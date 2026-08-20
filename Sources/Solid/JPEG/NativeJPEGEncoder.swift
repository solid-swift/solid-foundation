enum NativeJPEGEncoder {

  struct StreamingState {

    private struct ScanState {
      let scan: JPEGScan
      let codingTables: [UInt8: JPEGBlockCodingTables]
      let totalMCUs: Int
      var writer: JPEGEntropyBitWriter
      var predictors: [Int]
      var mcuIndex = 0
      var restartIndex: UInt8 = 0
    }

    private let options: JPEGEncodingOptions
    private let quantizationTables: [UInt8: JPEGQuantizationTable]
    private let huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable]
    private let scans: [JPEGScan]
    private let maximumHorizontal: Int
    private let maximumVertical: Int
    private let mcuColumns: Int
    private let mcuRows: Int
    private let rowStride: Int
    private let rowsPerBand: Int
    private var scanStates: [ScanState]
    private var rowRing: ContiguousArray<UInt8> = []
    private var sourceBlock = [UInt8](repeating: 0, count: 64)
    private var coefficients = [Int](repeating: 0, count: 64)
    private var samplesReceived = 0
    private var bandsEncoded = 0
    private var headerEmitted = false
    private var outputBytes = 0

    init(options: JPEGEncodingOptions) throws {
      self.options = options
      quantizationTables = try resolvedQuantizationTables(options)
      huffmanTables = try resolvedHuffmanTables(options)
      scans = try resolvedScans(options)
      try validateReferences(
        options: options,
        quantizationTables: quantizationTables,
        huffmanTables: huffmanTables,
        scans: scans
      )
      maximumHorizontal = options.components.map(\.sampling.horizontal).max() ?? 1
      maximumVertical = options.components.map(\.sampling.vertical).max() ?? 1
      mcuColumns = JPEGCodecUtilities.ceilDivide(options.width, by: maximumHorizontal * 8)
      mcuRows = JPEGCodecUtilities.ceilDivide(options.height, by: maximumVertical * 8)
      rowStride = options.width * options.components.count
      rowsPerBand = maximumVertical * 8
      let ringCapacity = rowStride * min(rowsPerBand, options.height)
      guard ringCapacity <= options.limits.maximumScratchBytes else {
        throw JPEGError.limitExceeded
      }
      rowRing.reserveCapacity(ringCapacity)

      scanStates = []
      for scan in scans {
        let codingTables = try Dictionary(
          uniqueKeysWithValues: scan.components.map { scanComponent in
            let frameIndex = try componentIndex(scanComponent.identifier, in: options.components)
            return (
              scanComponent.identifier,
              try blockCodingTables(
                scanComponent: scanComponent,
                frameComponent: options.components[frameIndex],
                quantizationTables: quantizationTables,
                huffmanTables: huffmanTables
              )
            )
          }
        )
        let totalMCUs: Int
        if scan.components.count == 1 {
          let frameIndex = try componentIndex(scan.components[0].identifier, in: options.components)
          let component = options.components[frameIndex]
          let blockColumns = JPEGCodecUtilities.ceilDivide(
            options.width * component.sampling.horizontal,
            by: maximumHorizontal * 8
          )
          let blockRows = JPEGCodecUtilities.ceilDivide(
            options.height * component.sampling.vertical,
            by: maximumVertical * 8
          )
          totalMCUs = blockColumns * blockRows
        } else {
          totalMCUs = mcuColumns * mcuRows
        }
        scanStates.append(ScanState(
          scan: scan,
          codingTables: codingTables,
          totalMCUs: totalMCUs,
          writer: JPEGEntropyBitWriter(maximumBytes: options.limits.maximumOutputBytes),
          predictors: [Int](repeating: 0, count: options.components.count)
        ))
      }
    }

    var consumedSamples: Int { samplesReceived }

    var scratchHighWaterMark: Int {
      rowRing.capacity + sourceBlock.capacity + coefficients.capacity * MemoryLayout<Int>.stride
    }

    mutating func process(_ input: borrowing Span<UInt8>) throws -> [UInt8] {
      guard input.count <= options.sampleCount - samplesReceived else {
        throw JPEGError.invalidData
      }
      var output = try emitHeaderIfNeeded()
      var inputIndex = 0
      while inputIndex < input.count {
        let firstRow = bandsEncoded * rowsPerBand
        let bandRows = min(rowsPerBand, options.height - firstRow)
        let requiredSamples = bandRows * rowStride
        let count = min(input.count - inputIndex, requiredSamples - rowRing.count)
        rowRing.reserveCapacity(requiredSamples)
        for index in 0..<count { rowRing.append(input[inputIndex + index]) }
        inputIndex += count
        samplesReceived += count
        if rowRing.count == requiredSamples {
          try encodeBand(firstRow: firstRow, rowCount: bandRows)
          rowRing.removeAll(keepingCapacity: true)
          bandsEncoded += 1
          output.append(contentsOf: scanStates[0].writer.drainBytes())
        }
      }
      try recordOutput(output.count)
      return output
    }

    mutating func finish() throws -> [UInt8] {
      guard samplesReceived == options.sampleCount, rowRing.isEmpty, bandsEncoded == mcuRows else {
        throw JPEGError.truncatedData
      }
      var output = try emitHeaderIfNeeded()
      output.append(contentsOf: try scanStates[0].writer.finish())
      if scanStates.count > 1 {
        for index in 1..<scanStates.count {
          var markerWriter = try CheckedByteWriter(maximumBytes: options.limits.maximumOutputBytes)
          try scanMarker(scans[index], to: &markerWriter)
          output.append(contentsOf: markerWriter.bytes)
          output.append(contentsOf: try scanStates[index].writer.finish())
        }
      }
      output.append(contentsOf: [0xFF, 0xD9])
      try recordOutput(output.count)
      return output
    }

    private mutating func emitHeaderIfNeeded() throws -> [UInt8] {
      guard !headerEmitted else { return [] }
      var writer = try CheckedByteWriter(maximumBytes: options.limits.maximumOutputBytes)
      try marker(0xD8, to: &writer)
      if options.components.count > 1 {
        try adobeMarker(transform: options.colorTransform.rawValue, to: &writer)
      }
      try quantizationMarker(quantizationTables, to: &writer)
      try frameMarker(options: options, to: &writer)
      try huffmanMarker(huffmanTables, to: &writer)
      if options.restartInterval > 0 {
        try segment(marker: 0xDD, payload: [
          UInt8(options.restartInterval >> 8),
          UInt8(options.restartInterval & 0xFF),
        ], to: &writer)
      }
      try scanMarker(scans[0], to: &writer)
      headerEmitted = true
      return writer.bytes
    }

    private mutating func encodeBand(firstRow: Int, rowCount: Int) throws {
      for scanIndex in scanStates.indices {
        if scanStates[scanIndex].scan.components.count == 1 {
          try encodeSeparateBand(scanIndex: scanIndex, firstRow: firstRow, rowCount: rowCount)
        } else {
          try encodeInterleavedBand(scanIndex: scanIndex, firstRow: firstRow, rowCount: rowCount)
        }
      }
    }

    private mutating func encodeInterleavedBand(
      scanIndex: Int,
      firstRow: Int,
      rowCount: Int
    ) throws {
      let mcuY = firstRow / rowsPerBand
      let scan = scanStates[scanIndex].scan
      for mcuX in 0..<mcuColumns {
        for scanComponent in scan.components {
          let frameIndex = try componentIndex(scanComponent.identifier, in: options.components)
          let component = options.components[frameIndex]
          for vertical in 0..<component.sampling.vertical {
            for horizontal in 0..<component.sampling.horizontal {
              try fillStreamingBlock(
                componentIndex: frameIndex,
                blockX: mcuX * component.sampling.horizontal + horizontal,
                blockY: mcuY * component.sampling.vertical + vertical,
                firstRow: firstRow,
                rowCount: rowCount
              )
              try encodeStreamingBlock(scanIndex: scanIndex, frameIndex: frameIndex, scanComponent: scanComponent)
            }
          }
        }
        try completeMCU(scanIndex: scanIndex)
      }
    }

    private mutating func encodeSeparateBand(
      scanIndex: Int,
      firstRow: Int,
      rowCount: Int
    ) throws {
      let scanComponent = scanStates[scanIndex].scan.components[0]
      let frameIndex = try componentIndex(scanComponent.identifier, in: options.components)
      let component = options.components[frameIndex]
      let blockColumns = JPEGCodecUtilities.ceilDivide(
        options.width * component.sampling.horizontal,
        by: maximumHorizontal * 8
      )
      let blockRows = JPEGCodecUtilities.ceilDivide(
        options.height * component.sampling.vertical,
        by: maximumVertical * 8
      )
      let firstBlockRow = firstRow / rowsPerBand * component.sampling.vertical
      let lastBlockRow = min(firstBlockRow + component.sampling.vertical, blockRows)
      for blockY in firstBlockRow..<lastBlockRow {
        for blockX in 0..<blockColumns {
          try fillStreamingBlock(
            componentIndex: frameIndex,
            blockX: blockX,
            blockY: blockY,
            firstRow: firstRow,
            rowCount: rowCount
          )
          try encodeStreamingBlock(scanIndex: scanIndex, frameIndex: frameIndex, scanComponent: scanComponent)
          try completeMCU(scanIndex: scanIndex)
        }
      }
    }

    private mutating func fillStreamingBlock(
      componentIndex: Int,
      blockX: Int,
      blockY: Int,
      firstRow: Int,
      rowCount: Int
    ) throws {
      let component = options.components[componentIndex]
      for y in 0..<8 {
        for x in 0..<8 {
          let componentX = blockX * 8 + x
          let componentY = blockY * 8 + y
          let startX = componentX * maximumHorizontal / component.sampling.horizontal
          let startY = componentY * maximumVertical / component.sampling.vertical
          let nextX = max(startX + 1, (componentX + 1) * maximumHorizontal / component.sampling.horizontal)
          let nextY = max(startY + 1, (componentY + 1) * maximumVertical / component.sampling.vertical)
          var total = 0
          var count = 0
          for sourceY in startY..<nextY {
            for sourceX in startX..<nextX {
              let imageX = min(options.width - 1, sourceX)
              let imageY = min(options.height - 1, sourceY)
              guard imageY >= firstRow, imageY < firstRow + rowCount else {
                throw JPEGError.invalidData
              }
              total += transformedStreamingSample(
                x: imageX,
                y: imageY - firstRow,
                componentIndex: componentIndex
              )
              count += 1
            }
          }
          guard count > 0 else { throw JPEGError.invalidData }
          sourceBlock[y * 8 + x] = UInt8(clamping: (total + count / 2) / count)
        }
      }
    }

    private func transformedStreamingSample(x: Int, y: Int, componentIndex: Int) -> Int {
      let base = (y * options.width + x) * options.components.count
      guard options.colorTransform == .yCbCr,
            options.components.count >= 3,
            componentIndex < 3
      else {
        return Int(rowRing[base + componentIndex])
      }
      let red = Double(rowRing[base])
      let green = Double(rowRing[base + 1])
      let blue = Double(rowRing[base + 2])
      switch componentIndex {
      case 0: return Int((0.299 * red + 0.587 * green + 0.114 * blue).rounded())
      case 1: return Int((-0.168736 * red - 0.331264 * green + 0.5 * blue + 128).rounded())
      default: return Int((0.5 * red - 0.418688 * green - 0.081312 * blue + 128).rounded())
      }
    }

    private mutating func encodeStreamingBlock(
      scanIndex: Int,
      frameIndex: Int,
      scanComponent: JPEGScanComponent
    ) throws {
      let tables = scanStates[scanIndex].codingTables[scanComponent.identifier]!
      JPEGDCT.forward(samples: sourceBlock, coefficients: &coefficients)
      for index in 0..<64 {
        coefficients[index] = Int((Double(coefficients[index]) / Double(tables.quantization[index])).rounded())
      }
      let difference = coefficients[0] - scanStates[scanIndex].predictors[frameIndex]
      scanStates[scanIndex].predictors[frameIndex] = coefficients[0]
      let dcCategory = JPEGCodecUtilities.magnitudeCategory(difference)
      try tables.dc.encode(symbol: UInt8(dcCategory), to: &scanStates[scanIndex].writer)
      if dcCategory > 0 {
        try scanStates[scanIndex].writer.append(
          value: JPEGCodecUtilities.encodedMagnitude(difference, category: dcCategory),
          count: dcCategory
        )
      }
      var zeroRun = 0
      for zigzagIndex in 1..<64 {
        let value = coefficients[JPEGConstants.zigzag[zigzagIndex]]
        if value == 0 {
          zeroRun += 1
          continue
        }
        while zeroRun >= 16 {
          try tables.ac.encode(symbol: 0xF0, to: &scanStates[scanIndex].writer)
          zeroRun -= 16
        }
        let category = JPEGCodecUtilities.magnitudeCategory(value)
        guard category <= 10 else { throw JPEGError.invalidData }
        try tables.ac.encode(symbol: UInt8(zeroRun << 4 | category), to: &scanStates[scanIndex].writer)
        try scanStates[scanIndex].writer.append(
          value: JPEGCodecUtilities.encodedMagnitude(value, category: category),
          count: category
        )
        zeroRun = 0
      }
      if zeroRun > 0 { try tables.ac.encode(symbol: 0, to: &scanStates[scanIndex].writer) }
    }

    private mutating func completeMCU(scanIndex: Int) throws {
      scanStates[scanIndex].mcuIndex += 1
      let state = scanStates[scanIndex]
      guard options.restartInterval > 0,
            state.mcuIndex < state.totalMCUs,
            state.mcuIndex.isMultiple(of: options.restartInterval)
      else {
        return
      }
      try scanStates[scanIndex].writer.emitRestart(scanStates[scanIndex].restartIndex)
      scanStates[scanIndex].restartIndex = (scanStates[scanIndex].restartIndex + 1) & 7
      for index in scanStates[scanIndex].predictors.indices {
        scanStates[scanIndex].predictors[index] = 0
      }
    }

    private mutating func recordOutput(_ count: Int) throws {
      guard count <= options.limits.maximumOutputBytes - outputBytes else {
        throw JPEGError.limitExceeded
      }
      outputBytes += count
    }

  }

  static func encode(samples: [UInt8], options: JPEGEncodingOptions) throws -> [UInt8] {
    guard samples.count == options.sampleCount else { throw JPEGError.truncatedData }
    let quantizationTables = try resolvedQuantizationTables(options)
    let huffmanTables = try resolvedHuffmanTables(options)
    let scans = try resolvedScans(options)
    try validateReferences(
      options: options,
      quantizationTables: quantizationTables,
      huffmanTables: huffmanTables,
      scans: scans
    )

    var writer = try CheckedByteWriter(maximumBytes: options.limits.maximumOutputBytes)
    try marker(0xD8, to: &writer)
    if options.components.count > 1 {
      try adobeMarker(transform: options.colorTransform.rawValue, to: &writer)
    }
    try quantizationMarker(quantizationTables, to: &writer)
    try frameMarker(options: options, to: &writer)
    try huffmanMarker(huffmanTables, to: &writer)
    if options.restartInterval > 0 {
      try segment(marker: 0xDD, payload: [
        UInt8(options.restartInterval >> 8),
        UInt8(options.restartInterval & 0xFF),
      ], to: &writer)
    }

    for scan in scans {
      try scanMarker(scan, to: &writer)
      let entropy = try encodeScan(
        samples: samples,
        options: options,
        scan: scan,
        quantizationTables: quantizationTables,
        huffmanTables: huffmanTables
      )
      try writer.append(contentsOf: entropy)
    }
    try marker(0xD9, to: &writer)
    return writer.bytes
  }

  private static func encodeScan(
    samples: [UInt8],
    options: JPEGEncodingOptions,
    scan: JPEGScan,
    quantizationTables: [UInt8: JPEGQuantizationTable],
    huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable]
  ) throws -> [UInt8] {
    let maximumHorizontal = options.components.map(\.sampling.horizontal).max() ?? 1
    let maximumVertical = options.components.map(\.sampling.vertical).max() ?? 1
    let mcuColumns = JPEGCodecUtilities.ceilDivide(options.width, by: maximumHorizontal * 8)
    let mcuRows = JPEGCodecUtilities.ceilDivide(options.height, by: maximumVertical * 8)
    var writer = JPEGEntropyBitWriter(maximumBytes: options.limits.maximumOutputBytes)
    var predictors = [Int](repeating: 0, count: options.components.count)
    var sourceBlock = [UInt8](repeating: 0, count: 64)
    var coefficients = [Int](repeating: 0, count: 64)
    var mcuIndex = 0
    var restartIndex: UInt8 = 0
    let codingTables = try Dictionary(
      uniqueKeysWithValues: scan.components.map { scanComponent in
        let frameIndex = try componentIndex(scanComponent.identifier, in: options.components)
        return (
          scanComponent.identifier,
          try blockCodingTables(
            scanComponent: scanComponent,
            frameComponent: options.components[frameIndex],
            quantizationTables: quantizationTables,
            huffmanTables: huffmanTables
          )
        )
      }
    )

    let totalMCUs: Int
    if scan.components.count == 1 {
      let frameIndex = try componentIndex(scan.components[0].identifier, in: options.components)
      let component = options.components[frameIndex]
      let blockColumns = JPEGCodecUtilities.ceilDivide(
        options.width * component.sampling.horizontal,
        by: maximumHorizontal * 8
      )
      let blockRows = JPEGCodecUtilities.ceilDivide(
        options.height * component.sampling.vertical,
        by: maximumVertical * 8
      )
      totalMCUs = blockColumns * blockRows
      for blockY in 0..<blockRows {
        for blockX in 0..<blockColumns {
          try fillBlock(
            samples: samples,
            options: options,
            componentIndex: frameIndex,
            blockX: blockX,
            blockY: blockY,
            maximumHorizontal: maximumHorizontal,
            maximumVertical: maximumVertical,
            destination: &sourceBlock
          )
          try encodeBlock(
            samples: sourceBlock,
            componentIndex: frameIndex,
            scanComponent: scan.components[0],
            codingTables: codingTables[scan.components[0].identifier]!,
            predictors: &predictors,
            coefficients: &coefficients,
            writer: &writer
          )
          mcuIndex += 1
          try emitRestartIfNeeded(
            mcuIndex: mcuIndex,
            totalMCUs: totalMCUs,
            interval: options.restartInterval,
            restartIndex: &restartIndex,
            predictors: &predictors,
            writer: &writer
          )
        }
      }
    } else {
      totalMCUs = mcuColumns * mcuRows
      for mcuY in 0..<mcuRows {
        for mcuX in 0..<mcuColumns {
          for scanComponent in scan.components {
            let frameIndex = try componentIndex(scanComponent.identifier, in: options.components)
            let component = options.components[frameIndex]
            for vertical in 0..<component.sampling.vertical {
              for horizontal in 0..<component.sampling.horizontal {
                try fillBlock(
                  samples: samples,
                  options: options,
                  componentIndex: frameIndex,
                  blockX: mcuX * component.sampling.horizontal + horizontal,
                  blockY: mcuY * component.sampling.vertical + vertical,
                  maximumHorizontal: maximumHorizontal,
                  maximumVertical: maximumVertical,
                  destination: &sourceBlock
                )
                try encodeBlock(
                  samples: sourceBlock,
                  componentIndex: frameIndex,
                  scanComponent: scanComponent,
                  codingTables: codingTables[scanComponent.identifier]!,
                  predictors: &predictors,
                  coefficients: &coefficients,
                  writer: &writer
                )
              }
            }
          }
          mcuIndex += 1
          try emitRestartIfNeeded(
            mcuIndex: mcuIndex,
            totalMCUs: totalMCUs,
            interval: options.restartInterval,
            restartIndex: &restartIndex,
            predictors: &predictors,
            writer: &writer
          )
        }
      }
    }
    return try writer.finish()
  }

  private static func fillBlock(
    samples: [UInt8],
    options: JPEGEncodingOptions,
    componentIndex: Int,
    blockX: Int,
    blockY: Int,
    maximumHorizontal: Int,
    maximumVertical: Int,
    destination: inout [UInt8]
  ) throws {
    let component = options.components[componentIndex]
    for y in 0..<8 {
      for x in 0..<8 {
        let componentX = blockX * 8 + x
        let componentY = blockY * 8 + y
        let startX = componentX * maximumHorizontal / component.sampling.horizontal
        let startY = componentY * maximumVertical / component.sampling.vertical
        let nextX = max(
          startX + 1,
          (componentX + 1) * maximumHorizontal / component.sampling.horizontal
        )
        let nextY = max(
          startY + 1,
          (componentY + 1) * maximumVertical / component.sampling.vertical
        )
        var total = 0
        var count = 0
        for sourceY in startY..<nextY {
          for sourceX in startX..<nextX {
            total += transformedSample(
              samples: samples,
              options: options,
              x: min(options.width - 1, sourceX),
              y: min(options.height - 1, sourceY),
              componentIndex: componentIndex
            )
            count += 1
          }
        }
        guard count > 0 else { throw JPEGError.invalidData }
        destination[y * 8 + x] = UInt8(clamping: (total + count / 2) / count)
      }
    }
  }

  private static func transformedSample(
    samples: [UInt8],
    options: JPEGEncodingOptions,
    x: Int,
    y: Int,
    componentIndex: Int
  ) -> Int {
    let base = (y * options.width + x) * options.components.count
    guard options.colorTransform == .yCbCr,
          options.components.count >= 3,
          componentIndex < 3
    else {
      return Int(samples[base + componentIndex])
    }
    let red = Double(samples[base])
    let green = Double(samples[base + 1])
    let blue = Double(samples[base + 2])
    switch componentIndex {
    case 0: return Int((0.299 * red + 0.587 * green + 0.114 * blue).rounded())
    case 1: return Int((-0.168736 * red - 0.331264 * green + 0.5 * blue + 128).rounded())
    default: return Int((0.5 * red - 0.418688 * green - 0.081312 * blue + 128).rounded())
    }
  }

  private static func encodeBlock(
    samples: [UInt8],
    componentIndex: Int,
    scanComponent: JPEGScanComponent,
    codingTables: JPEGBlockCodingTables,
    predictors: inout [Int],
    coefficients: inout [Int],
    writer: inout JPEGEntropyBitWriter
  ) throws {
    JPEGDCT.forward(samples: samples, coefficients: &coefficients)
    for index in 0..<64 {
      coefficients[index] = Int(
        (Double(coefficients[index]) / Double(codingTables.quantization[index])).rounded()
      )
    }
    let difference = coefficients[0] - predictors[componentIndex]
    predictors[componentIndex] = coefficients[0]
    let dcCategory = JPEGCodecUtilities.magnitudeCategory(difference)
    try codingTables.dc.encode(symbol: UInt8(dcCategory), to: &writer)
    if dcCategory > 0 {
      try writer.append(
        value: JPEGCodecUtilities.encodedMagnitude(difference, category: dcCategory),
        count: dcCategory
      )
    }

    var zeroRun = 0
    for zigzagIndex in 1..<64 {
      let value = coefficients[JPEGConstants.zigzag[zigzagIndex]]
      if value == 0 {
        zeroRun += 1
        continue
      }
      while zeroRun >= 16 {
        try codingTables.ac.encode(symbol: 0xF0, to: &writer)
        zeroRun -= 16
      }
      let category = JPEGCodecUtilities.magnitudeCategory(value)
      guard category <= 10 else { throw JPEGError.invalidData }
      try codingTables.ac.encode(symbol: UInt8(zeroRun << 4 | category), to: &writer)
      try writer.append(
        value: JPEGCodecUtilities.encodedMagnitude(value, category: category),
        count: category
      )
      zeroRun = 0
    }
    if zeroRun > 0 { try codingTables.ac.encode(symbol: 0, to: &writer) }
  }

  private static func blockCodingTables(
    scanComponent: JPEGScanComponent,
    frameComponent: JPEGComponent,
    quantizationTables: [UInt8: JPEGQuantizationTable],
    huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable]
  ) throws -> JPEGBlockCodingTables {
    guard let quantization = quantizationTables[frameComponent.quantizationTable],
          let dcTable = huffmanTables[
            JPEGHuffmanKey(tableClass: .dc, identifier: scanComponent.dcTable)
          ],
          let acTable = huffmanTables[
            JPEGHuffmanKey(tableClass: .ac, identifier: scanComponent.acTable)
          ]
    else {
      throw JPEGError.invalidData
    }
    return try JPEGBlockCodingTables(
      quantization: JPEGCodecUtilities.naturalQuantization(quantization),
      dc: JPEGHuffmanCodec(table: dcTable),
      ac: JPEGHuffmanCodec(table: acTable)
    )
  }

  private static func emitRestartIfNeeded(
    mcuIndex: Int,
    totalMCUs: Int,
    interval: Int,
    restartIndex: inout UInt8,
    predictors: inout [Int],
    writer: inout JPEGEntropyBitWriter
  ) throws {
    guard interval > 0, mcuIndex < totalMCUs, mcuIndex.isMultiple(of: interval) else { return }
    try writer.emitRestart(restartIndex)
    restartIndex = (restartIndex + 1) & 7
    predictors = [Int](repeating: 0, count: predictors.count)
  }

  private static func resolvedQuantizationTables(
    _ options: JPEGEncodingOptions
  ) throws -> [UInt8: JPEGQuantizationTable] {
    let tables = options.quantizationTables.isEmpty
      ? try JPEGConstants.defaultQuantizationTables()
      : options.quantizationTables
    return Dictionary(uniqueKeysWithValues: tables.map { ($0.identifier, $0) })
  }

  private static func resolvedHuffmanTables(
    _ options: JPEGEncodingOptions
  ) throws -> [JPEGHuffmanKey: JPEGHuffmanTable] {
    let tables = options.huffmanTables.isEmpty
      ? try JPEGConstants.defaultHuffmanTables()
      : options.huffmanTables
    return Dictionary(
      uniqueKeysWithValues: tables.map {
        (JPEGHuffmanKey(tableClass: $0.tableClass, identifier: $0.identifier), $0)
      }
    )
  }

  private static func resolvedScans(_ options: JPEGEncodingOptions) throws -> [JPEGScan] {
    if !options.scans.isEmpty { return options.scans }
    let components = try options.components.enumerated().map { index, component in
      try JPEGScanComponent(
        identifier: component.identifier,
        dcTable: index == 0 ? 0 : 1,
        acTable: index == 0 ? 0 : 1
      )
    }
    return [try JPEGScan(components: components)]
  }

  private static func validateReferences(
    options: JPEGEncodingOptions,
    quantizationTables: [UInt8: JPEGQuantizationTable],
    huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable],
    scans: [JPEGScan]
  ) throws {
    guard options.components.allSatisfy({ quantizationTables[$0.quantizationTable] != nil }) else {
      throw JPEGError.invalidConfiguration("quantizationTable")
    }
    let scanned = scans.flatMap(\.components).map(\.identifier)
    guard scanned.count == options.components.count,
          Set(scanned) == Set(options.components.map(\.identifier))
    else {
      throw JPEGError.invalidConfiguration("scans")
    }
    for component in scans.flatMap(\.components) {
      guard huffmanTables[JPEGHuffmanKey(tableClass: .dc, identifier: component.dcTable)] != nil,
            huffmanTables[JPEGHuffmanKey(tableClass: .ac, identifier: component.acTable)] != nil
      else {
        throw JPEGError.invalidConfiguration("huffmanTable")
      }
    }
  }

  private static func quantizationMarker(
    _ tables: [UInt8: JPEGQuantizationTable],
    to writer: inout CheckedByteWriter
  ) throws {
    var payload: [UInt8] = []
    for table in tables.values.sorted(by: { $0.identifier < $1.identifier }) {
      guard table.values.allSatisfy({ $0 <= 255 }) else {
        throw JPEGError.unsupportedFeature("16-bit quantization")
      }
      payload.append(table.identifier)
      payload.append(contentsOf: table.values.map(UInt8.init))
    }
    try segment(marker: 0xDB, payload: payload, to: &writer)
  }

  private static func frameMarker(
    options: JPEGEncodingOptions,
    to writer: inout CheckedByteWriter
  ) throws {
    var payload: [UInt8] = [
      8,
      UInt8(options.height >> 8), UInt8(options.height & 0xFF),
      UInt8(options.width >> 8), UInt8(options.width & 0xFF),
      UInt8(options.components.count),
    ]
    for component in options.components {
      payload.append(component.identifier)
      payload.append(UInt8(component.sampling.horizontal << 4 | component.sampling.vertical))
      payload.append(component.quantizationTable)
    }
    try segment(marker: 0xC0, payload: payload, to: &writer)
  }

  private static func huffmanMarker(
    _ tables: [JPEGHuffmanKey: JPEGHuffmanTable],
    to writer: inout CheckedByteWriter
  ) throws {
    var payload: [UInt8] = []
    let sorted = tables.values.sorted {
      ($0.tableClass.rawValue, $0.identifier) < ($1.tableClass.rawValue, $1.identifier)
    }
    for table in sorted {
      payload.append(table.tableClass.rawValue << 4 | table.identifier)
      payload.append(contentsOf: table.codeCounts)
      payload.append(contentsOf: table.symbols)
    }
    try segment(marker: 0xC4, payload: payload, to: &writer)
  }

  private static func scanMarker(_ scan: JPEGScan, to writer: inout CheckedByteWriter) throws {
    var payload: [UInt8] = [UInt8(scan.components.count)]
    for component in scan.components {
      payload.append(component.identifier)
      payload.append(component.dcTable << 4 | component.acTable)
    }
    payload.append(contentsOf: [0, 63, 0])
    try segment(marker: 0xDA, payload: payload, to: &writer)
  }

  private static func adobeMarker(transform: Int, to writer: inout CheckedByteWriter) throws {
    var payload = Array("Adobe".utf8)
    payload.append(contentsOf: [0, 100, 0, 0, 0, 0, UInt8(transform)])
    try segment(marker: 0xEE, payload: payload, to: &writer)
  }

  private static func segment(
    marker markerValue: UInt8,
    payload: [UInt8],
    to writer: inout CheckedByteWriter
  ) throws {
    guard payload.count <= Int(UInt16.max) - 2 else { throw JPEGError.limitExceeded }
    try marker(markerValue, to: &writer)
    try writer.appendUInt16(UInt16(payload.count + 2))
    try writer.append(contentsOf: payload)
  }

  private static func marker(_ value: UInt8, to writer: inout CheckedByteWriter) throws {
    try writer.append(0xFF)
    try writer.append(value)
  }

  private static func componentIndex(_ identifier: UInt8, in components: [JPEGComponent]) throws -> Int {
    guard let index = components.firstIndex(where: { $0.identifier == identifier }) else {
      throw JPEGError.invalidData
    }
    return index
  }

}
