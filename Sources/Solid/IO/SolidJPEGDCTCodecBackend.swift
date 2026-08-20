import Foundation
import SolidJPEG

struct SolidJPEGDCTCodecBackend: DCTCodecBackend {

  func encode(_ data: Data, options: DCTEncodeOptions) throws -> Data {
    do {
      let encodingOptions = try makeEncodingOptions(options)
      var encoder = JPEGEncoder(options: encodingOptions)
      let result = try data.withUnsafeBytes { buffer in
        try encoder.process(
          Span(_unsafeElements: buffer.assumingMemoryBound(to: UInt8.self))
        )
      }
      return Data(result.bytes + (try encoder.finish()))
    } catch {
      throw Self.translate(error)
    }
  }

  func makeEncodingOptions(_ options: DCTEncodeOptions) throws -> JPEGEncodingOptions {
    let quantizationTables = try makeQuantizationTables(options)
    let huffman = try makeHuffmanTables(options.huffmanTables, colors: options.colors)
    let components = try makeComponents(
      colors: options.colors,
      horizontalSamples: options.horizontalSamples,
      verticalSamples: options.verticalSamples,
      quantizationTableCount: quantizationTables.count,
      usesDefaults: options.quantizationTables.isEmpty
    )
    let scans = try makeScans(components: components, assignments: huffman.assignments)
    return try JPEGEncodingOptions(
      width: options.columns,
      height: options.rows,
      components: components,
      quantizationTables: quantizationTables,
      huffmanTables: huffman.tables,
      scans: scans,
      colorTransform: try colorTransform(options.colorTransform)
    )
  }

  func makeDecodingOptions(
    _ options: DCTDecodeOptions,
    metadata: JPEGMetadata,
    outputComponents: Int
  ) throws -> JPEGDecodingOptions {
    let quantization = try makeQuantizationTables(options.quantizationTables)
    let huffman = try makeHuffmanTables(options.huffmanTables, colors: outputComponents).tables
    let expectedComponents = try decodeComponents(options, metadata: metadata)
    return try JPEGDecodingOptions(
      expectedWidth: metadata.width,
      expectedHeight: metadata.height,
      expectedComponents: outputComponents,
      components: expectedComponents,
      quantizationTables: quantization,
      huffmanTables: huffman,
      colorTransform: try options.colorTransform.map(colorTransform),
      limits: try JPEGLimits(maximumOutputBytes: options.maximumDecodedBytes)
    )
  }

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int
  ) throws -> Data {
    try decode(data, metadata: metadata, outputComponents: outputComponents, options: nil)
  }

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int,
    options: DCTDecodeOptions?
  ) throws -> Data {
    do {
      let quantization = try options.map { try makeQuantizationTables($0.quantizationTables) } ?? []
      let huffman = try options.map {
        try makeHuffmanTables($0.huffmanTables, colors: outputComponents).tables
      } ?? []
      let expectedComponents = try options.map { try decodeComponents($0, metadata: metadata) } ?? []
      let decodingOptions = try JPEGDecodingOptions(
        expectedWidth: metadata.width,
        expectedHeight: metadata.height,
        expectedComponents: outputComponents,
        components: expectedComponents,
        quantizationTables: quantization,
        huffmanTables: huffman,
        colorTransform: try options?.colorTransform.map(colorTransform),
        limits: try JPEGLimits(maximumOutputBytes: options?.maximumDecodedBytes ?? .max)
      )
      var decoder = JPEGDecoder(options: decodingOptions)
      let result = try data.withUnsafeBytes { buffer in
        try decoder.process(
          Span(_unsafeElements: buffer.assumingMemoryBound(to: UInt8.self))
        )
      }
      guard result.progress == .finished else { throw StreamCodecError.truncatedData }
      return Data(result.rows.flatMap(\.samples))
    } catch {
      throw Self.translate(error)
    }
  }

  private func makeComponents(
    colors: Int,
    horizontalSamples: [Int],
    verticalSamples: [Int],
    quantizationTableCount: Int,
    usesDefaults: Bool
  ) throws -> [JPEGComponent] {
    try (0..<colors).map { index in
      let table: UInt8
      if usesDefaults {
        table = index == 0 ? 0 : 1
      } else if quantizationTableCount <= 1 {
        table = 0
      } else {
        guard index < quantizationTableCount else {
          throw StreamCodecError.invalidOption("quantizationTables")
        }
        table = UInt8(index)
      }
      return try JPEGComponent(
        identifier: UInt8(index + 1),
        sampling: JPEGSampling(
          horizontal: horizontalSamples[index],
          vertical: verticalSamples[index]
        ),
        quantizationTable: table
      )
    }
  }

  private func decodeComponents(
    _ options: DCTDecodeOptions,
    metadata: JPEGMetadata
  ) throws -> [JPEGComponent] {
    guard !options.horizontalSamples.isEmpty || !options.verticalSamples.isEmpty else { return [] }
    let horizontal = options.horizontalSamples.isEmpty
      ? metadata.components.map(\.horizontalSample)
      : options.horizontalSamples
    let vertical = options.verticalSamples.isEmpty
      ? metadata.components.map(\.verticalSample)
      : options.verticalSamples
    guard horizontal.count == metadata.components.count, vertical.count == metadata.components.count else {
      throw StreamCodecError.invalidOption("samples")
    }
    return try metadata.components.enumerated().map { index, component in
      try JPEGComponent(
        identifier: component.identifier,
        sampling: JPEGSampling(horizontal: horizontal[index], vertical: vertical[index]),
        quantizationTable: UInt8(component.quantizationTable)
      )
    }
  }

  private func makeQuantizationTables(_ options: DCTEncodeOptions) throws -> [JPEGQuantizationTable] {
    let source = options.quantizationTables.isEmpty
      ? [JPEGQuantizationTable.standardLuminance, .standardChrominance]
      : try makeQuantizationTables(options.quantizationTables)
    return try source.enumerated().map { index, table in
      try JPEGQuantizationTable(
        identifier: UInt8(index),
        values: table.values.map { value in
          UInt16(min(255, max(1, Int((Double(value) * options.quantizationFactor).rounded()))))
        }
      )
    }
  }

  private func makeQuantizationTables(_ tables: [Data]) throws -> [JPEGQuantizationTable] {
    try tables.enumerated().map { index, table in
      try JPEGQuantizationTable(identifier: UInt8(index), values: table.map(UInt16.init))
    }
  }

  private func makeHuffmanTables(
    _ tables: [DCTHuffmanTable],
    colors: Int
  ) throws -> (tables: [JPEGHuffmanTable], assignments: [(dc: UInt8, ac: UInt8)]) {
    guard !tables.isEmpty else {
      return ([], (0..<colors).map { ($0 == 0 ? 0 : 1, $0 == 0 ? 0 : 1) })
    }
    guard tables.count == colors * 2 else {
      throw StreamCodecError.invalidOption("huffmanTables")
    }
    var dcTables: [DCTHuffmanTable] = []
    var acTables: [DCTHuffmanTable] = []
    var assignments: [(UInt8, UInt8)] = []
    for index in 0..<colors {
      let dc = tables[index * 2]
      let ac = tables[index * 2 + 1]
      let dcIndex = try tableIdentifier(dc, in: &dcTables)
      let acIndex = try tableIdentifier(ac, in: &acTables)
      assignments.append((dcIndex, acIndex))
    }
    guard dcTables.count <= 2, acTables.count <= 2 else {
      throw StreamCodecError.invalidOption("huffmanTables")
    }
    var converted: [JPEGHuffmanTable] = []
    for (index, table) in dcTables.enumerated() {
      converted.append(
        try JPEGHuffmanTable(
          tableClass: .dc,
          identifier: UInt8(index),
          codeCounts: Array(table.codeCounts),
          symbols: Array(table.symbols)
        )
      )
    }
    for (index, table) in acTables.enumerated() {
      converted.append(
        try JPEGHuffmanTable(
          tableClass: .ac,
          identifier: UInt8(index),
          codeCounts: Array(table.codeCounts),
          symbols: Array(table.symbols)
        )
      )
    }
    return (converted, assignments)
  }

  private func tableIdentifier(
    _ table: DCTHuffmanTable,
    in tables: inout [DCTHuffmanTable]
  ) throws -> UInt8 {
    if let index = tables.firstIndex(of: table) { return UInt8(index) }
    guard tables.count < 2 else { throw StreamCodecError.invalidOption("huffmanTables") }
    tables.append(table)
    return UInt8(tables.count - 1)
  }

  private func makeScans(
    components: [JPEGComponent],
    assignments: [(dc: UInt8, ac: UInt8)]
  ) throws -> [JPEGScan] {
    guard assignments.count == components.count else { throw StreamCodecError.invalidOption("huffmanTables") }
    return [
      try JPEGScan(
        components: try zip(components, assignments).map { component, assignment in
          try JPEGScanComponent(
            identifier: component.identifier,
            dcTable: assignment.dc,
            acTable: assignment.ac
          )
        }
      )
    ]
  }

  private func colorTransform(_ value: Int) throws -> JPEGColorTransform {
    guard let transform = JPEGColorTransform(rawValue: value) else {
      throw StreamCodecError.invalidOption("colorTransform")
    }
    return transform
  }

  static func translate(_ error: any Error) -> StreamCodecError {
    guard let error = error as? JPEGError else { return .invalidData }
    switch error {
    case .truncatedData: return .truncatedData
    case .invalidConfiguration(let option): return .invalidOption(option)
    case .limitExceeded: return .limitExceeded
    case .unsupportedFeature: return .unsupportedOperation
    case .invalidData, .abandoned, .finished: return .invalidData
    }
  }

}
