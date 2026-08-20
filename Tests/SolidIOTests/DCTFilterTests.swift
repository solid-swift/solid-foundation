//
//  DCTFilterTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization
@testable import SolidIO
import Testing

@Suite
struct DCTFilterTests {

  @Test
  func rgbRoundTripAndTrailingInput() throws {
    let byteCount = 16 * 12 * 3
    let bytes: [UInt8] = (0..<byteCount).map { UInt8(($0 * 11) & 0xFF) }
    let source = Data(bytes)
    let encoder = DCTEncoder(
      options: try DCTEncodeOptions(
        columns: 16,
        rows: 12,
        colors: 3,
        horizontalSamples: [2, 1, 1],
        verticalSamples: [2, 1, 1]
      )
    )
    let encoded = try encoder.process(input: source)
    #expect(encoded.progress == .finished)
    let jpeg = encoded.output + (try #require(try encoder.finish()))
    #expect(jpeg.starts(with: [0xFF, 0xD8]))
    #expect(jpeg.suffix(2) == Data([0xFF, 0xD9]))
    let parsedMetadata = try JPEGMetadataParser.parse(jpeg)
    let metadata = try #require(parsedMetadata)
    #expect(metadata.components.map(\.horizontalSample) == [2, 1, 1])
    #expect(metadata.components.map(\.verticalSample) == [2, 1, 1])
    #expect(metadata.adobeColorTransform == 1)

    let decoder = DCTDecoder(options: try DCTDecodeOptions(columns: 16, rows: 12, colors: 3))
    let result = try decoder.process(input: jpeg + Data("tail".utf8))
    #expect(result.output.count == source.count)
    #expect(result.consumedInput == jpeg.count)
    #expect(result.progress == .finished)
  }

  @Test
  func portableBackendSupportsTwoComponents() throws {
    let options = try DCTEncodeOptions(columns: 1, rows: 1, colors: 2)
    let encoder = DCTEncoder(options: options)
    let result = try encoder.process(input: Data([0, 0]))
    #expect(result.progress == .finished)
    #expect(result.output.starts(with: [0xFF, 0xD8]))
  }

  @Test
  func encoderEnforcesExactSampleCount() throws {
    let options = try DCTEncodeOptions(columns: 2, rows: 1, colors: 1)
    let short = DCTEncoder(options: options)
    _ = try short.process(input: Data([0]))
    #expect(throws: StreamCodecError.truncatedData) {
      try short.finish()
    }

    let long = DCTEncoder(options: options)
    #expect(throws: StreamCodecError.invalidData) {
      try long.process(input: Data([0, 1, 2]))
    }
  }

  @Test
  func decodeOptionsAcceptAbbreviatedStreamTables() throws {
    let huffman = try DCTHuffmanTable(
      codeCounts: Data([1] + Array(repeating: 0, count: 15)),
      symbols: Data([0])
    )
    let options = try DCTDecodeOptions(
      colors: 1,
      horizontalSamples: [1],
      verticalSamples: [1],
      quantizationTables: [Data(repeating: 1, count: 64)],
      huffmanTables: [huffman]
    )
    #expect(options.horizontalSamples == [1])
    #expect(options.huffmanTables == [huffman])
  }

  @Test
  func encodeOptionsUsePLRMQualityAndSamplingRanges() throws {
    #expect(throws: Never.self) {
      try DCTEncodeOptions(
        columns: 1,
        rows: 1,
        colors: 3,
        horizontalSamples: [4, 2, 2],
        verticalSamples: [1, 1, 1],
        quantizationFactor: 0
      )
    }
    #expect(throws: StreamCodecError.self) {
      try DCTEncodeOptions(
        columns: 1,
        rows: 1,
        colors: 3,
        horizontalSamples: [4, 4, 4],
        verticalSamples: [1, 1, 1]
      )
    }
  }

  @Test(
    arguments: [
      ("grayscale", 1, [1], [1]),
      ("baseline-444", 3, [1, 1, 1], [1, 1, 1]),
      ("baseline-422", 3, [2, 1, 1], [1, 1, 1]),
      ("baseline-420", 3, [2, 1, 1], [2, 1, 1]),
      ("rgb-app14-0", 3, [1, 1, 1], [1, 1, 1]),
      ("restart", 3, [2, 1, 1], [2, 1, 1]),
    ]
  )
  func decodesCommonBaselineProfiles(
    sample: (fixture: String, components: Int, horizontal: [Int], vertical: [Int])
  ) throws {
    let jpeg = try fixture(named: sample.fixture)
    let parsedMetadata = try JPEGMetadataParser.parse(jpeg)
    let metadata = try #require(parsedMetadata)
    #expect(metadata.width == 16)
    #expect(metadata.height == 16)
    #expect(metadata.components.count == sample.components)
    #expect(metadata.components.map(\.horizontalSample) == sample.horizontal)
    #expect(metadata.components.map(\.verticalSample) == sample.vertical)
    #expect(metadata.endOffset == jpeg.count)

    let decoder = DCTDecoder(
      options: try DCTDecodeOptions(
        columns: 16,
        rows: 16,
        colors: sample.components,
        maximumDecodedBytes: 16 * 16 * sample.components
      )
    )
    let result = try decoder.process(input: jpeg + Data("tail".utf8))
    #expect(result.output.count == 16 * 16 * sample.components)
    #expect(result.consumedInput == jpeg.count)
    #expect(result.progress == .finished)
  }

  @Test
  func oneByteChunkingPreservesEODBoundary() throws {
    let jpeg = try fixture(named: "baseline-420")
    let decoder = DCTDecoder()
    var output = Data()
    var totalConsumed = 0
    for byte in jpeg {
      let result = try decoder.process(input: Data([byte]))
      output.append(result.output)
      totalConsumed += result.consumedInput
    }
    #expect(output.count == 16 * 16 * 3)
    #expect(totalConsumed == jpeg.count)
  }

  @Test
  func progressiveJPEGIsOutsidePostScriptProfile() throws {
    let jpeg = try fixture(named: "progressive")
    let decoder = DCTDecoder()
    #expect(throws: StreamCodecError.unsupportedOperation) {
      try decoder.process(input: jpeg)
    }
  }

  @Test
  func adobeTransformOverridesDecodeParameter() throws {
    let jpeg = try fixture(named: "rgb-app14-0")
    let decoder = DCTDecoder(options: try DCTDecodeOptions(colors: 3, colorTransform: 1))
    let output = try decoder.process(input: jpeg).output
    #expect(matches(Array(output.prefix(6)), [0, 0, 0, 16, 1, 8], tolerance: 1))
  }

  @Test
  func transformFreeStreamUsesRawComponents() throws {
    let jpeg = try fixture(named: "baseline-444")
    let decoder = DCTDecoder(options: try DCTDecodeOptions(colors: 3, colorTransform: 0))
    let result = try decoder.process(input: jpeg)
    #expect(result.output.count == 16 * 16 * 3)
  }

  @Test
  func separateBaselineScansAreDecoded() throws {
    let jpeg = try fixture(named: "separate-scans")
    let result = try DCTDecoder().process(input: jpeg)
    #expect(result.output.count == 16 * 16 * 3)
    #expect(result.progress == .finished)
  }

  @Test
  func twoComponentJPEGUsesPortableDecoder() throws {
    let result = try DCTDecoder().process(input: twoComponentJPEG())
    #expect(result.output.count == 2)
    #expect(result.progress == .finished)
  }

  @Test
  func truncatedJPEGRequiresPhysicalSourceFinish() throws {
    let jpeg = try fixture(named: "baseline-420")
    let decoder = DCTDecoder()
    let partial = try decoder.process(input: jpeg.dropLast(2))
    #expect(partial.progress == .needsInput)
    #expect(throws: StreamCodecError.truncatedData) {
      try decoder.finish()
    }
  }

  @Test
  func externalDecodeTablesAreAccepted() throws {
    let abbreviated = try abbreviatedGrayscaleJPEG(from: fixture(named: "grayscale"))
    let options = try DCTDecodeOptions(
      colors: 1,
      quantizationTables: [abbreviated.quantization],
      huffmanTables: [abbreviated.dc, abbreviated.ac]
    )
    let decoder = DCTDecoder(options: options)
    let result = try decoder.process(input: abbreviated.data + Data("tail".utf8))
    #expect(result.output.count == 16 * 16)
    #expect(result.consumedInput == abbreviated.data.count)
  }

  @Test
  func outputBudgetIsCheckedBeforeImageIODecode() throws {
    let jpeg = try fixture(named: "baseline-420")
    let decoder = DCTDecoder(
      options: try DCTDecodeOptions(colors: 3, maximumDecodedBytes: 16 * 16 * 3 - 1)
    )
    #expect(throws: StreamCodecError.limitExceeded) {
      try decoder.process(input: jpeg)
    }
  }

  @Test(arguments: [
    ("cmyk-app14-0", 0, [UInt8(32), 64, 96, 128], [UInt8(32), 64, 96, 128], 0),
    ("ycck-app14-2", 2, [UInt8(187), 182, 160, 217], [UInt8(16), 15, 11, 0], 2),
  ])
  func adobeFourComponentTransforms(
    sample: (
      fixture: String,
      transform: Int,
      expectedFirst: [UInt8],
      expectedLast: [UInt8],
      tolerance: Int
    )
  ) throws {
    let jpeg = try fixture(named: sample.fixture)
    let parsedMetadata = try JPEGMetadataParser.parse(jpeg)
    let metadata = try #require(parsedMetadata)
    #expect(metadata.components.count == 4)
    #expect(metadata.adobeColorTransform == sample.transform)

    let result = try DCTDecoder(options: try DCTDecodeOptions(colors: 4))
      .process(input: jpeg)
    #expect(result.output.count == 16 * 16 * 4)
    #expect(matches(Array(result.output.prefix(4)), sample.expectedFirst, tolerance: sample.tolerance))
    #expect(matches(Array(result.output.suffix(4)), sample.expectedLast, tolerance: sample.tolerance))
  }

  @Test
  func portableEncoderPreservesDefaultSampling() throws {
    let encoder = DCTEncoder(options: try DCTEncodeOptions(columns: 16, rows: 16, colors: 3))
    let result = try encoder.process(input: Data(repeating: 127, count: 16 * 16 * 3))
    let metadata = try #require(try JPEGMetadataParser.parse(result.output))
    #expect(metadata.components.map(\.horizontalSample) == [1, 1, 1])
    #expect(metadata.components.map(\.verticalSample) == [1, 1, 1])
  }

  @Test(.timeLimit(.minutes(1)))
  func backendCallsOccurOutsideCodecStateLocks() throws {
    let encoderBackend = ReentrantDCTBackend()
    let encoder = DCTEncoder(
      options: try DCTEncodeOptions(columns: 1, rows: 1, colors: 1, colorTransform: 0),
      backend: encoderBackend
    )
    encoderBackend.onEncode = {
      #expect(throws: StreamCodecError.invalidData) {
        try encoder.finish()
      }
    }
    let encoded = try encoder.process(input: Data([0]))
    #expect(encoded.output == Data([0xFF, 0xD8, 0xFF, 0xD9]))

    let jpeg = try fixture(named: "grayscale")
    let decoderBackend = ReentrantDCTBackend()
    let decoder = DCTDecoder(options: try DCTDecodeOptions(colors: 1), backend: decoderBackend)
    decoderBackend.onDecode = {
      #expect(throws: StreamCodecError.invalidData) {
        try decoder.finish()
      }
    }
    let decoded = try decoder.process(input: jpeg)
    #expect(decoded.output == Data(repeating: 0, count: 16 * 16))
  }

  private func fixture(named name: String) throws -> Data {
    let root = try #require(Bundle.module.resourceURL)
    return try Data(
      contentsOf: root
        .appending(path: "JPEG")
        .appending(path: "\(name).jpg")
    )
  }

  private func matches(_ actual: [UInt8], _ expected: [UInt8], tolerance: Int) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
      abs(Int($0) - Int($1)) <= tolerance
    }
  }

  private func twoComponentJPEG() -> Data {
    var data = Data([0xFF, 0xD8])
    data.append(contentsOf: [0xFF, 0xDB, 0x00, 0x43, 0x00])
    data.append(Data(repeating: 1, count: 64))
    data.append(contentsOf: [
      0xFF, 0xC0, 0x00, 0x0E,
      0x08, 0x00, 0x01, 0x00, 0x01, 0x02,
      0x01, 0x11, 0x00,
      0x02, 0x11, 0x00,
    ])
    data.append(contentsOf: [0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01])
    data.append(Data(repeating: 0, count: 15))
    data.append(0)
    data.append(contentsOf: [0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01])
    data.append(Data(repeating: 0, count: 15))
    data.append(0)
    data.append(contentsOf: [
      0xFF, 0xDA, 0x00, 0x0A,
      0x02, 0x01, 0x00, 0x02, 0x00,
      0x00, 0x3F, 0x00,
      0x00,
      0xFF, 0xD9,
    ])
    return data
  }

  private func abbreviatedGrayscaleJPEG(
    from source: Data
  ) throws -> (data: Data, quantization: Data, dc: DCTHuffmanTable, ac: DCTHuffmanTable) {
    var output = Data(source.prefix(2))
    var quantization: Data?
    var dc: DCTHuffmanTable?
    var ac: DCTHuffmanTable?
    var index = 2
    while index < source.count {
      guard source[index] == 0xFF, index + 3 < source.count else {
        throw StreamCodecError.invalidData
      }
      let marker = source[index + 1]
      if marker == 0xDA {
        output.append(source[index...])
        break
      }
      let length = Int(source[index + 2]) << 8 | Int(source[index + 3])
      guard length >= 2, index + 2 + length <= source.count else {
        throw StreamCodecError.invalidData
      }
      let payloadStart = index + 4
      let payloadEnd = index + 2 + length
      if marker == 0xDB {
        guard payloadEnd - payloadStart == 65, source[payloadStart] == 0 else {
          throw StreamCodecError.invalidData
        }
        quantization = Data(source[(payloadStart + 1)..<payloadEnd])
      } else if marker == 0xC4 {
        guard payloadEnd - payloadStart >= 17 else { throw StreamCodecError.invalidData }
        let tableClass = source[payloadStart] >> 4
        let counts = Data(source[(payloadStart + 1)..<(payloadStart + 17)])
        let symbolCount = counts.reduce(0) { $0 + Int($1) }
        guard payloadStart + 17 + symbolCount == payloadEnd else {
          throw StreamCodecError.invalidData
        }
        let table = try DCTHuffmanTable(
          codeCounts: counts,
          symbols: Data(source[(payloadStart + 17)..<payloadEnd])
        )
        if tableClass == 0 { dc = table } else { ac = table }
      } else {
        output.append(source[index..<payloadEnd])
      }
      index = payloadEnd
    }
    try #require(output.suffix(2) == Data([0xFF, 0xD9]))
    return try (output, #require(quantization), #require(dc), #require(ac))
  }

}

private final class ReentrantDCTBackend: DCTCodecBackend {

  private struct Callbacks: Sendable {
    var onEncode: (@Sendable () -> Void)?
    var onDecode: (@Sendable () -> Void)?
  }

  private let callbacks = Mutex(Callbacks())

  var onEncode: (@Sendable () -> Void)? {
    get { callbacks.withLock { $0.onEncode } }
    set { callbacks.withLock { $0.onEncode = newValue } }
  }

  var onDecode: (@Sendable () -> Void)? {
    get { callbacks.withLock { $0.onDecode } }
    set { callbacks.withLock { $0.onDecode = newValue } }
  }

  func encode(_ data: Data, options: DCTEncodeOptions) throws -> Data {
    let callback = callbacks.withLock { $0.onEncode }
    callback?()
    return Data([0xFF, 0xD8, 0xFF, 0xD9])
  }

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int
  ) throws -> Data {
    let callback = callbacks.withLock { $0.onDecode }
    callback?()
    return Data(repeating: 0, count: metadata.width * metadata.height * outputComponents)
  }

}
