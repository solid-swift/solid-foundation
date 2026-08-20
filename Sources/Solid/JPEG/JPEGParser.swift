struct JPEGParsedScan {
  let scan: JPEGScan
  let entropyBytes: [UInt8]
  let restartInterval: Int
}

struct JPEGParsedImage {
  let metadata: JPEGMetadata
  let quantizationTables: [UInt8: JPEGQuantizationTable]
  let huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable]
  let scans: [JPEGParsedScan]
  let diagnostics: [JPEGDiagnostic]
  let consumedBytes: Int
}

enum JPEGParser {

  static func parse(bytes: [UInt8], options: JPEGDecodingOptions) throws -> JPEGParsedImage {
    guard bytes.count <= options.limits.maximumInputBytes else { throw JPEGError.limitExceeded }
    guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
      throw JPEGError.invalidData
    }
    var offset = 2
    var width = 0
    var height = 0
    var components: [JPEGComponent] = []
    var restartInterval = 0
    var adobeTransform: Int?
    var quantization = Dictionary(
      uniqueKeysWithValues: options.quantizationTables.map { ($0.identifier, $0) }
    )
    var huffman = Dictionary(
      uniqueKeysWithValues: options.huffmanTables.map {
        (JPEGHuffmanKey(tableClass: $0.tableClass, identifier: $0.identifier), $0)
      }
    )
    var scans: [JPEGParsedScan] = []
    var diagnostics: [JPEGDiagnostic] = []

    while offset < bytes.count {
      let marker = try nextMarker(bytes: bytes, offset: &offset)
      switch marker {
      case 0xD9:
        guard width > 0, height > 0, !components.isEmpty, !scans.isEmpty else {
          throw JPEGError.invalidData
        }
        try validateExpected(
          width: width,
          height: height,
          components: components,
          options: options
        )
        return JPEGParsedImage(
          metadata: JPEGMetadata(
            width: width,
            height: height,
            components: components,
            restartInterval: restartInterval,
            adobeColorTransform: adobeTransform
          ),
          quantizationTables: quantization,
          huffmanTables: huffman,
          scans: scans,
          diagnostics: diagnostics,
          consumedBytes: offset
        )
      case 0xC0:
        let payload = try segmentPayload(bytes: bytes, offset: &offset)
        (width, height, components) = try parseFrame(payload)
      case 0xC4:
        for table in try parseHuffmanTables(segmentPayload(bytes: bytes, offset: &offset)) {
          huffman[JPEGHuffmanKey(tableClass: table.tableClass, identifier: table.identifier)] = table
        }
      case 0xDB:
        for table in try parseQuantizationTables(segmentPayload(bytes: bytes, offset: &offset)) {
          quantization[table.identifier] = table
        }
      case 0xDD:
        let payload = try segmentPayload(bytes: bytes, offset: &offset)
        guard payload.count == 2 else { throw JPEGError.invalidData }
        restartInterval = Int(payload[0]) << 8 | Int(payload[1])
      case 0xDC:
        let payload = try segmentPayload(bytes: bytes, offset: &offset)
        guard payload.count == 2 else { throw JPEGError.invalidData }
        let lineCount = Int(payload[0]) << 8 | Int(payload[1])
        guard height == 0, lineCount > 0 else { throw JPEGError.invalidData }
        height = lineCount
      case 0xDA:
        guard !components.isEmpty else { throw JPEGError.invalidData }
        let scan = try parseScan(segmentPayload(bytes: bytes, offset: &offset), frame: components)
        let entropyEnd = try findEntropyEnd(bytes: bytes, offset: offset)
        scans.append(
          JPEGParsedScan(
            scan: scan,
            entropyBytes: Array(bytes[offset..<entropyEnd]),
            restartInterval: restartInterval
          )
        )
        guard scans.count <= options.limits.maximumScans else { throw JPEGError.limitExceeded }
        offset = entropyEnd
      case 0xEE:
        let payload = try segmentPayload(bytes: bytes, offset: &offset)
        if payload.count >= 12, Array(payload.prefix(5)) == Array("Adobe".utf8) {
          adobeTransform = Int(payload[11])
        }
        diagnostics.append(.ignoredApplicationMarker(marker))
      case 0xE0...0xEF:
        _ = try segmentPayload(bytes: bytes, offset: &offset)
        diagnostics.append(.ignoredApplicationMarker(marker))
      case 0xFE:
        _ = try segmentPayload(bytes: bytes, offset: &offset)
        diagnostics.append(.ignoredComment)
      case 0xC1...0xCF where marker != 0xC4 && marker != 0xC8 && marker != 0xCC:
        throw JPEGError.unsupportedFeature("non-baseline frame")
      case 0x01, 0xD0...0xD8:
        throw JPEGError.invalidData
      default:
        _ = try segmentPayload(bytes: bytes, offset: &offset)
      }
    }
    throw JPEGError.truncatedData
  }

  private static func nextMarker(bytes: [UInt8], offset: inout Int) throws -> UInt8 {
    guard offset < bytes.count, bytes[offset] == 0xFF else { throw JPEGError.invalidData }
    while offset < bytes.count, bytes[offset] == 0xFF { offset += 1 }
    guard offset < bytes.count, bytes[offset] != 0 else { throw JPEGError.invalidData }
    defer { offset += 1 }
    return bytes[offset]
  }

  private static func segmentPayload(bytes: [UInt8], offset: inout Int) throws -> [UInt8] {
    guard offset + 2 <= bytes.count else { throw JPEGError.truncatedData }
    let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    guard length >= 2, length <= bytes.count - offset else { throw JPEGError.truncatedData }
    let start = offset + 2
    offset += length
    return Array(bytes[start..<offset])
  }

  static func parseFrame(_ payload: [UInt8]) throws -> (Int, Int, [JPEGComponent]) {
    guard payload.count >= 6, payload[0] == 8 else {
      throw JPEGError.unsupportedFeature("sample precision")
    }
    let height = Int(payload[1]) << 8 | Int(payload[2])
    let width = Int(payload[3]) << 8 | Int(payload[4])
    let count = Int(payload[5])
    guard width > 0, (1...4).contains(count), payload.count == 6 + count * 3 else {
      throw JPEGError.invalidData
    }
    var components: [JPEGComponent] = []
    for index in 0..<count {
      let start = 6 + index * 3
      let sampling = try JPEGSampling(
        horizontal: Int(payload[start + 1] >> 4),
        vertical: Int(payload[start + 1] & 0x0F)
      )
      components.append(
        try JPEGComponent(
          identifier: payload[start],
          sampling: sampling,
          quantizationTable: payload[start + 2]
        )
      )
    }
    guard Set(components.map(\.identifier)).count == components.count,
          components.reduce(0, { $0 + $1.sampling.horizontal * $1.sampling.vertical }) <= 10
    else {
      throw JPEGError.invalidData
    }
    return (width, height, components)
  }

  static func parseQuantizationTables(_ payload: [UInt8]) throws -> [JPEGQuantizationTable] {
    var offset = 0
    var tables: [JPEGQuantizationTable] = []
    while offset < payload.count {
      let descriptor = payload[offset]
      offset += 1
      let precision = descriptor >> 4
      let identifier = descriptor & 0x0F
      guard precision <= 1 else { throw JPEGError.invalidData }
      let byteCount = precision == 0 ? 64 : 128
      guard byteCount <= payload.count - offset else { throw JPEGError.truncatedData }
      var values: [UInt16] = []
      values.reserveCapacity(64)
      for _ in 0..<64 {
        if precision == 0 {
          values.append(UInt16(payload[offset]))
          offset += 1
        } else {
          values.append(UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1]))
          offset += 2
        }
      }
      tables.append(try JPEGQuantizationTable(identifier: identifier, values: values))
    }
    return tables
  }

  static func parseHuffmanTables(_ payload: [UInt8]) throws -> [JPEGHuffmanTable] {
    var offset = 0
    var tables: [JPEGHuffmanTable] = []
    while offset < payload.count {
      guard 17 <= payload.count - offset else { throw JPEGError.truncatedData }
      let descriptor = payload[offset]
      offset += 1
      guard let tableClass = JPEGHuffmanTableClass(rawValue: descriptor >> 4) else {
        throw JPEGError.invalidData
      }
      let counts = Array(payload[offset..<(offset + 16)])
      offset += 16
      let symbolCount = counts.reduce(0, { $0 + Int($1) })
      guard symbolCount <= payload.count - offset else { throw JPEGError.truncatedData }
      let symbols = Array(payload[offset..<(offset + symbolCount)])
      offset += symbolCount
      tables.append(
        try JPEGHuffmanTable(
          tableClass: tableClass,
          identifier: descriptor & 0x0F,
          codeCounts: counts,
          symbols: symbols
        )
      )
    }
    return tables
  }

  static func parseScan(_ payload: [UInt8], frame: [JPEGComponent]) throws -> JPEGScan {
    guard let countByte = payload.first else { throw JPEGError.invalidData }
    let count = Int(countByte)
    guard (1...4).contains(count), payload.count == 1 + count * 2 + 3 else {
      throw JPEGError.invalidData
    }
    var components: [JPEGScanComponent] = []
    for index in 0..<count {
      let start = 1 + index * 2
      guard frame.contains(where: { $0.identifier == payload[start] }) else {
        throw JPEGError.invalidData
      }
      components.append(
        try JPEGScanComponent(
          identifier: payload[start],
          dcTable: payload[start + 1] >> 4,
          acTable: payload[start + 1] & 0x0F
        )
      )
    }
    guard Array(payload.suffix(3)) == [0, 63, 0] else {
      throw JPEGError.unsupportedFeature("non-sequential scan")
    }
    return try JPEGScan(components: components)
  }

  private static func findEntropyEnd(bytes: [UInt8], offset: Int) throws -> Int {
    var cursor = offset
    while cursor < bytes.count {
      guard bytes[cursor] == 0xFF else {
        cursor += 1
        continue
      }
      let markerOffset = cursor
      while cursor < bytes.count, bytes[cursor] == 0xFF { cursor += 1 }
      guard cursor < bytes.count else { throw JPEGError.truncatedData }
      let code = bytes[cursor]
      if code == 0 || (0xD0...0xD7).contains(code) {
        cursor += 1
        continue
      }
      return markerOffset
    }
    throw JPEGError.truncatedData
  }

  static func validateExpected(
    width: Int,
    height: Int,
    components: [JPEGComponent],
    options: JPEGDecodingOptions
  ) throws {
    guard width <= options.limits.maximumWidth,
          height <= options.limits.maximumHeight,
          components.count <= options.limits.maximumComponents,
          options.expectedWidth == 0 || options.expectedWidth == width,
          options.expectedHeight == 0 || options.expectedHeight == height,
          options.expectedComponents == 0 || options.expectedComponents == components.count,
          options.components.isEmpty || options.components == components
    else {
      throw JPEGError.invalidData
    }
    let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (outputBytes, outputOverflow) = pixels.multipliedReportingOverflow(by: components.count)
    guard !pixelOverflow, !outputOverflow, outputBytes <= options.limits.maximumOutputBytes else {
      throw JPEGError.limitExceeded
    }
  }

}
