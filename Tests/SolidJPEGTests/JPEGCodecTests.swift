import Foundation
@testable import SolidJPEG
import Testing

@Suite
struct JPEGCodecTests {

  @Test
  func grayscaleRoundTripAndTrailingInput() throws {
    let source = [UInt8](repeating: 96, count: 16 * 8)
    let components = try [JPEGComponent(identifier: 1)]
    let encoded = try encode(
      source,
      options: JPEGEncodingOptions(width: 16, height: 8, components: components)
    )
    #expect(encoded.starts(with: [0xFF, 0xD8]))
    #expect(encoded.suffix(2) == [0xFF, 0xD9])

    let trailing = encoded + Array("tail".utf8)
    var decoder = JPEGDecoder(
      options: try JPEGDecodingOptions(
        expectedWidth: 16,
        expectedHeight: 8,
        expectedComponents: 1
      )
    )
    let result = try trailing.withUnsafeBufferPointer {
      try decoder.process(Span(_unsafeElements: $0))
    }
    #expect(result.progress == .finished)
    #expect(result.consumedBytes == encoded.count)
    #expect(result.rows.flatMap(\.samples).allSatisfy { abs(Int($0) - 96) <= 1 })
  }

  @Test
  func rgbSubsampledRoundTrip() throws {
    var source: [UInt8] = []
    for y in 0..<16 {
      for x in 0..<16 {
        source.append(UInt8(x * 8))
        source.append(UInt8(y * 8))
        source.append(UInt8((x + y) * 4))
      }
    }
    let components = try [
      JPEGComponent(
        identifier: 1,
        sampling: JPEGSampling(horizontal: 2, vertical: 2),
        quantizationTable: 0
      ),
      JPEGComponent(identifier: 2, quantizationTable: 1),
      JPEGComponent(identifier: 3, quantizationTable: 1),
    ]
    let encoded = try encode(
      source,
      options: JPEGEncodingOptions(
        width: 16,
        height: 16,
        components: components,
        restartInterval: 1,
        colorTransform: .yCbCr
      )
    )
    let result = try decode(encoded)
    let decoded = result.rows.flatMap(\.samples)
    #expect(decoded.count == source.count)
    let averageError = zip(source, decoded).reduce(0) { partial, pair in
      partial + abs(Int(pair.0) - Int(pair.1))
    } / source.count
    #expect(averageError < 8)
  }

  @Test
  func supportsTwoRawComponentsAndSeparateScans() throws {
    let source = (0..<(9 * 7 * 2)).map { UInt8(($0 * 13) & 0xFF) }
    let components = try [
      JPEGComponent(identifier: 1),
      JPEGComponent(identifier: 2),
    ]
    let scans = try [
      JPEGScan(components: [JPEGScanComponent(identifier: 1)]),
      JPEGScan(components: [JPEGScanComponent(identifier: 2)]),
    ]
    let encoded = try encode(
      source,
      options: JPEGEncodingOptions(
        width: 9,
        height: 7,
        components: components,
        scans: scans
      )
    )
    let result = try decode(encoded, expectedComponents: 2)
    #expect(result.rows.flatMap(\.samples).count == source.count)
    #expect(result.rows.map(\.componentIdentifiers) == [[1], [2]])
  }

  @Test
  func encoderEmitsCompletedBandsBeforeFinish() throws {
    let width = 16
    let height = 24
    let source = (0..<(width * height)).map { UInt8(truncatingIfNeeded: $0 * 17) }
    let options = try JPEGEncodingOptions(
      width: width,
      height: height,
      components: [JPEGComponent(identifier: 7)]
    )
    var encoder = JPEGEncoder(options: options)
    var encoded: [UInt8] = []
    for range in [0..<(width * 8), (width * 8)..<(width * height)] {
      let result = try source[range].withUnsafeBufferPointer {
        try encoder.process(Span(_unsafeElements: $0))
      }
      #expect(!result.bytes.isEmpty)
      encoded.append(contentsOf: result.bytes)
    }
    #expect(!encoded.suffix(2).elementsEqual([0xFF, 0xD9]))
    encoded.append(contentsOf: try encoder.finish())
    #expect(encoded.suffix(2) == [0xFF, 0xD9])
    let decoded = try decode(encoded, expectedComponents: 1)
    #expect(decoded.rows.count == 3)
    #expect(decoded.rows.allSatisfy { $0.componentIdentifiers == [7] })
  }

  @Test
  func decoderEmitsBandsBeforeEOIWithOneByteChunks() throws {
    let width = 16
    let height = 32
    let source = (0..<(width * height)).map { UInt8(truncatingIfNeeded: $0 * 29) }
    let encoded = try encode(
      source,
      options: JPEGEncodingOptions(
        width: width,
        height: height,
        components: [JPEGComponent(identifier: 3)]
      )
    )
    var decoder = JPEGDecoder(options: try JPEGDecodingOptions(expectedComponents: 1))
    var rows: [JPEGDecodedRows] = []
    var firstEmissionOffset: Int?
    var totalConsumed = 0
    for (offset, byte) in encoded.enumerated() {
      let result = try [byte].withUnsafeBufferPointer {
        try decoder.process(Span(_unsafeElements: $0))
      }
      if firstEmissionOffset == nil, !result.rows.isEmpty { firstEmissionOffset = offset }
      rows.append(contentsOf: result.rows)
      totalConsumed += result.consumedBytes
    }
    #expect(try #require(firstEmissionOffset) < encoded.count - 2)
    #expect(rows.map(\.firstRow) == [0, 8, 16, 24])
    #expect(rows.allSatisfy { $0.componentIdentifiers == [3] })
    #expect(totalConsumed == encoded.count)
  }

  @Test
  func randomizedChunkingMatchesOneShotDecode() throws {
    let width = 31
    let height = 35
    let source = (0..<(width * height * 3)).map { UInt8(truncatingIfNeeded: $0 * 11) }
    let encoded = try encode(
      source,
      options: JPEGEncodingOptions(
        width: width,
        height: height,
        components: [
          JPEGComponent(identifier: 1, sampling: JPEGSampling(horizontal: 2, vertical: 2)),
          JPEGComponent(identifier: 2, quantizationTable: 1),
          JPEGComponent(identifier: 3, quantizationTable: 1),
        ],
        restartInterval: 3,
        colorTransform: .yCbCr
      )
    )
    let expected = try decode(encoded).rows.flatMap(\.samples)
    var decoder = JPEGDecoder(options: try JPEGDecodingOptions(expectedComponents: 3))
    var actual: [UInt8] = []
    var offset = 0
    var random: UInt64 = 0x4A50_4547
    while offset < encoded.count {
      random = random &* 6_364_136_223_846_793_005 &+ 1
      let count = min(encoded.count - offset, Int(random % 37) + 1)
      let result = try encoded[offset..<(offset + count)].withUnsafeBufferPointer {
        try decoder.process(Span(_unsafeElements: $0))
      }
      actual.append(contentsOf: result.rows.flatMap(\.samples))
      offset += result.consumedBytes
    }
    #expect(actual == expected)
  }

  @Test
  func knownHeightScratchDoesNotScaleWithImageHeight() throws {
    func highWaterMark(height: Int) throws -> Int {
      let width = 32
      let source = [UInt8](repeating: 127, count: width * height)
      var encoder = JPEGEncoder(
        options: try JPEGEncodingOptions(
          width: width,
          height: height,
          components: [JPEGComponent(identifier: 1)]
        )
      )
      _ = try source.withUnsafeBufferPointer {
        try encoder.process(Span(_unsafeElements: $0))
      }
      return encoder.scratchHighWaterMark
    }
    #expect(try highWaterMark(height: 16) == highWaterMark(height: 4_096))
  }

  @Test
  func rejectsProgressiveFrames() throws {
    let progressive = [UInt8](arrayLiteral:
      0xFF, 0xD8,
      0xFF, 0xC2, 0x00, 0x0B,
      0x08, 0x00, 0x01, 0x00, 0x01, 0x01,
      0x01, 0x11, 0x00,
      0xFF, 0xD9
    )
    var decoder = JPEGDecoder()
    #expect(throws: JPEGError.unsupportedFeature("non-baseline frame")) {
      _ = try progressive.withUnsafeBufferPointer {
        try decoder.process(Span(_unsafeElements: $0))
      }
    }
  }

  @Test(
    arguments: [
      ("cmyk-app14-0", 0, [32, 64, 96, 128], [32, 64, 96, 128], 0),
      ("ycck-app14-2", 2, [187, 182, 160, 217], [16, 15, 11, 0], 2),
    ]
  )
  func adobeFourComponentPolarity(
    sample: (
      fixture: String,
      transform: Int,
      expectedFirst: [UInt8],
      expectedLast: [UInt8],
      tolerance: Int
    )
  ) throws {
    let result = try decode(try fixture(named: sample.fixture), expectedComponents: 4)
    #expect(result.metadata?.adobeColorTransform == sample.transform)
    let samples = result.rows.flatMap(\.samples)
    #expect(matches(Array(samples.prefix(4)), sample.expectedFirst, tolerance: sample.tolerance))
    #expect(matches(Array(samples.suffix(4)), sample.expectedLast, tolerance: sample.tolerance))
  }

  private func encode(_ samples: [UInt8], options: JPEGEncodingOptions) throws -> [UInt8] {
    var encoder = JPEGEncoder(options: options)
    let result = try samples.withUnsafeBufferPointer {
      try encoder.process(Span(_unsafeElements: $0))
    }
    return result.bytes + (try encoder.finish())
  }

  private func decode(
    _ bytes: [UInt8],
    expectedComponents: Int = 3
  ) throws -> JPEGDecodingResult {
    var decoder = JPEGDecoder(
      options: try JPEGDecodingOptions(expectedComponents: expectedComponents)
    )
    return try bytes.withUnsafeBufferPointer {
      try decoder.process(Span(_unsafeElements: $0))
    }
  }

  private func fixture(named name: String) throws -> [UInt8] {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let url = testDirectory
      .deletingLastPathComponent()
      .appending(path: "SolidIOTests/Resources/JPEG/\(name).jpg")
    return Array(try Data(contentsOf: url))
  }

  private func matches(_ actual: [UInt8], _ expected: [UInt8], tolerance: Int) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy {
      abs(Int($0) - Int($1)) <= tolerance
    }
  }

}
