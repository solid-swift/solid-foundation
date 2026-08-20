struct NativeJPEGStreamingDecoder {

  private enum Phase {
    case start
    case marker
    case segmentLength(UInt8)
    case segment(marker: UInt8, remaining: Int, captureLimit: Int, payload: [UInt8])
    case entropy
    case finished
  }

  private let options: JPEGDecodingOptions
  private var phase = Phase.start
  private var input: ContiguousArray<UInt8> = []
  private var offset = 0
  private var prefix: [UInt8] = []
  private var fallbackBytes: [UInt8]?
  private var width = 0
  private var height = 0
  private var components: [JPEGComponent] = []
  private var restartInterval = 0
  private var adobeTransform: Int?
  private var quantizationTables: [UInt8: JPEGQuantizationTable]
  private var huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable]
  private var scanDecoder: JPEGStreamingScanDecoder?
  private var decodedComponents = Set<UInt8>()
  private var scanCount = 0
  private var acceptedBytes = 0
  private var knownMetadata: JPEGMetadata?
  private var maximumScratchHighWaterMark = 0

  init(options: JPEGDecodingOptions) {
    self.options = options
    quantizationTables = Dictionary(
      uniqueKeysWithValues: options.quantizationTables.map { ($0.identifier, $0) }
    )
    huffmanTables = Dictionary(
      uniqueKeysWithValues: options.huffmanTables.map {
        (JPEGHuffmanKey(tableClass: $0.tableClass, identifier: $0.identifier), $0)
      }
    )
  }

  var scratchHighWaterMark: Int {
    max(maximumScratchHighWaterMark, input.capacity + (fallbackBytes?.capacity ?? prefix.capacity))
  }

  mutating func process(_ source: borrowing Span<UInt8>) throws -> JPEGDecodingResult {
    guard case .finished = phase else {
      guard source.count <= options.limits.maximumInputBytes - acceptedBytes else {
        throw JPEGError.limitExceeded
      }
      if fallbackBytes != nil {
        for index in 0..<source.count {
          fallbackBytes!.append(source[index])
        }
        let result = try processFallback(consumedBytes: source.count)
        acceptedBytes += result.consumedBytes
        return result
      }
      for index in 0..<source.count {
        let byte = source[index]
        input.append(byte)
        prefix.append(byte)
      }
      var rows: [JPEGDecodedRows] = []
      while true {
        let madeProgress = try advance(rows: &rows)
        if fallbackBytes != nil {
          let result = try processFallback(consumedBytes: source.count)
          acceptedBytes += result.consumedBytes
          return result
        }
        if case .finished = phase {
          let trailingCount = input.count - offset
          let trailingFromSource = min(source.count, trailingCount)
          let consumed = source.count - trailingFromSource
          acceptedBytes += consumed
          input.removeAll(keepingCapacity: false)
          return JPEGDecodingResult(
            metadata: knownMetadata,
            rows: rows,
            consumedBytes: consumed,
            progress: .finished
          )
        }
        if !madeProgress { break }
      }
      compactInput()
      acceptedBytes += source.count
      maximumScratchHighWaterMark = max(
        maximumScratchHighWaterMark,
        input.capacity + (scanDecoder?.scratchHighWaterMark ?? 0)
      )
      return JPEGDecodingResult(
        metadata: knownMetadata,
        rows: rows,
        consumedBytes: source.count,
        progress: .needsInput
      )
    }
    return JPEGDecodingResult(
      metadata: knownMetadata,
      rows: [],
      consumedBytes: 0,
      progress: .finished
    )
  }

  mutating func finish() throws -> JPEGDecodingResult {
    if fallbackBytes != nil {
      do {
        return try processFallback(consumedBytes: 0)
      } catch JPEGError.truncatedData {
        throw JPEGError.truncatedData
      }
    }
    guard case .finished = phase else { throw JPEGError.truncatedData }
    return JPEGDecodingResult(
      metadata: knownMetadata,
      rows: [],
      consumedBytes: 0,
      progress: .finished
    )
  }

  private mutating func advance(rows: inout [JPEGDecodedRows]) throws -> Bool {
    switch phase {
    case .start:
      guard available >= 2 else { return false }
      guard input[offset] == 0xFF, input[offset + 1] == 0xD8 else {
        throw JPEGError.invalidData
      }
      offset += 2
      phase = .marker
      return true
    case .marker:
      guard available >= 2 else { return false }
      guard input[offset] == 0xFF else { throw JPEGError.invalidData }
      while offset < input.count, input[offset] == 0xFF { offset += 1 }
      guard offset < input.count else {
        offset -= 1
        return false
      }
      let marker = input[offset]
      guard marker != 0 else { throw JPEGError.invalidData }
      offset += 1
      switch marker {
      case 0xD9:
        guard width > 0,
              height > 0,
              !components.isEmpty,
              scanCount > 0,
              decodedComponents == Set(components.map(\.identifier))
        else {
          throw JPEGError.invalidData
        }
        phase = .finished
      case 0xC1...0xCF where marker != 0xC4 && marker != 0xC8 && marker != 0xCC:
        throw JPEGError.unsupportedFeature("non-baseline frame")
      case 0x01, 0xD0...0xD8:
        throw JPEGError.invalidData
      default:
        phase = .segmentLength(marker)
      }
      return true
    case .segmentLength(let marker):
      guard available >= 2 else { return false }
      let length = Int(input[offset]) << 8 | Int(input[offset + 1])
      guard length >= 2 else { throw JPEGError.invalidData }
      offset += 2
      let captureLimit: Int
      switch marker {
      case 0xC0, 0xC4, 0xDB, 0xDD, 0xDC, 0xDA:
        captureLimit = length - 2
      case 0xEE:
        captureLimit = min(12, length - 2)
      default:
        captureLimit = 0
      }
      phase = .segment(
        marker: marker,
        remaining: length - 2,
        captureLimit: captureLimit,
        payload: []
      )
      return true
    case .segment(let marker, let remaining, let captureLimit, var payload):
      guard remaining > 0 else {
        try completeSegment(marker: marker, payload: payload)
        return true
      }
      guard available > 0 else { return false }
      let count = min(available, remaining)
      let captureCount = min(count, max(0, captureLimit - payload.count))
      if captureCount > 0 {
        payload.append(contentsOf: input[offset..<(offset + captureCount)])
      }
      offset += count
      phase = .segment(
        marker: marker,
        remaining: remaining - count,
        captureLimit: captureLimit,
        payload: payload
      )
      return true
    case .entropy:
      guard var scanDecoder else { throw JPEGError.invalidData }
      guard available > 0 else { return false }
      let produced = try scanDecoder.process(input[offset...])
      rows.append(contentsOf: produced)
      offset = input.count
      maximumScratchHighWaterMark = max(maximumScratchHighWaterMark, scanDecoder.scratchHighWaterMark)
      if scanDecoder.isFinished {
        let trailing = scanDecoder.finishScan()
        input = ContiguousArray(trailing)
        offset = 0
        decodedComponents.formUnion(scanDecoderComponentIdentifiers)
        self.scanDecoder = nil
        phase = .marker
      } else {
        self.scanDecoder = scanDecoder
      }
      return true
    case .finished:
      return false
    }
  }

  private var scanDecoderComponentIdentifiers: [UInt8] {
    currentScan?.components.map(\.identifier) ?? []
  }

  private var currentScan: JPEGScan?

  private mutating func completeSegment(marker: UInt8, payload: [UInt8]) throws {
    defer {
      if case .entropy = phase {} else { phase = .marker }
    }
    switch marker {
    case 0xC0:
      (width, height, components) = try JPEGParser.parseFrame(payload)
      if height == 0 {
        fallbackBytes = prefix
        input.removeAll(keepingCapacity: false)
        offset = 0
        return
      }
      try establishMetadata()
      prefix.removeAll(keepingCapacity: false)
    case 0xC4:
      for table in try JPEGParser.parseHuffmanTables(payload) {
        huffmanTables[JPEGHuffmanKey(tableClass: table.tableClass, identifier: table.identifier)] = table
      }
    case 0xDB:
      for table in try JPEGParser.parseQuantizationTables(payload) {
        quantizationTables[table.identifier] = table
      }
    case 0xDD:
      guard payload.count == 2 else { throw JPEGError.invalidData }
      restartInterval = Int(payload[0]) << 8 | Int(payload[1])
      if knownMetadata != nil { try establishMetadata() }
    case 0xDC:
      guard payload.count == 2 else { throw JPEGError.invalidData }
      let lineCount = Int(payload[0]) << 8 | Int(payload[1])
      guard height == 0, lineCount > 0 else { throw JPEGError.invalidData }
      height = lineCount
      try establishMetadata()
    case 0xDA:
      guard !components.isEmpty, height > 0 else { throw JPEGError.invalidData }
      let scan = try JPEGParser.parseScan(payload, frame: components)
      scanCount += 1
      guard scanCount <= options.limits.maximumScans else { throw JPEGError.limitExceeded }
      currentScan = scan
      scanDecoder = try JPEGStreamingScanDecoder(
        metadata: try requireMetadata(),
        options: options,
        scan: scan,
        restartInterval: restartInterval,
        quantizationTables: quantizationTables,
        huffmanTables: huffmanTables
      )
      phase = .entropy
    case 0xEE:
      if payload.count >= 12, Array(payload.prefix(5)) == Array("Adobe".utf8) {
        adobeTransform = Int(payload[11])
        if knownMetadata != nil { try establishMetadata() }
      }
    default:
      break
    }
  }

  private mutating func establishMetadata() throws {
    try JPEGParser.validateExpected(
      width: width,
      height: height,
      components: components,
      options: options
    )
    knownMetadata = JPEGMetadata(
      width: width,
      height: height,
      components: components,
      restartInterval: restartInterval,
      adobeColorTransform: adobeTransform
    )
  }

  private func requireMetadata() throws -> JPEGMetadata {
    guard let knownMetadata else { throw JPEGError.invalidData }
    return knownMetadata
  }

  private mutating func processFallback(consumedBytes: Int) throws -> JPEGDecodingResult {
    guard let fallbackBytes else { throw JPEGError.invalidData }
    do {
      let result = try NativeJPEGDecoder.decode(bytes: fallbackBytes, options: options)
      phase = .finished
      knownMetadata = result.metadata
      let trailing = fallbackBytes.count - result.consumedBytes
      return JPEGDecodingResult(
        metadata: result.metadata,
        rows: result.rows.map {
          JPEGDecodedRows(
            firstRow: $0.firstRow,
            rowCount: $0.rowCount,
            componentCount: $0.componentCount,
            samples: $0.samples,
            componentIdentifiers: result.metadata?.components.map(\.identifier) ?? []
          )
        },
        consumedBytes: max(0, consumedBytes - trailing),
        progress: .finished
      )
    } catch JPEGError.truncatedData {
      return JPEGDecodingResult(
        metadata: nil,
        rows: [],
        consumedBytes: consumedBytes,
        progress: .needsInput
      )
    }
  }

  private var available: Int { input.count - offset }

  private mutating func compactInput() {
    guard offset > 0 else { return }
    input.removeFirst(offset)
    offset = 0
  }

}
