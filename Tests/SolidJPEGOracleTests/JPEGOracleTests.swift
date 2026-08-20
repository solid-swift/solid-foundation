import JPEG
import SolidJPEG
import Testing

@Suite
struct JPEGOracleTests {

  @Test
  func oracleDependencyIsAvailableOnlyWhenRequested() {
    let _: JPEG.Common = .y8
  }

  @Test
  func swiftJPEGDecodesNativeBaselineOutput() throws {
    let width = 16
    let height = 16
    let samples = (0..<(width * height)).map { index in
      UInt8(truncatingIfNeeded: (index % width) * 11 + (index / width) * 5)
    }
    let options = try SolidJPEG.JPEGEncodingOptions(
      width: width,
      height: height,
      components: [SolidJPEG.JPEGComponent(identifier: 1)]
    )
    var encoder = SolidJPEG.JPEGEncoder(options: options)
    let result = try samples.withUnsafeBufferPointer {
      try encoder.process(Span(_unsafeElements: $0))
    }
    let encoded = result.bytes + (try encoder.finish())

    var source = ByteSource(bytes: encoded)
    let oracle: JPEG.Data.Rectangular<JPEG.Common> = try .decompress(stream: &source)
    let oraclePixels = oracle.unpack(as: JPEG.RGB.self)

    #expect(oracle.size.x == width)
    #expect(oracle.size.y == height)
    #expect(oraclePixels.count == samples.count)
    let maximumDifference = try #require(zip(oraclePixels, samples).map { pixel, sample in
      abs(Int(pixel.r) - Int(sample))
    }.max())
    #expect(maximumDifference <= 4)
  }

}

private struct ByteSource: JPEG.Bytestream.Source {

  let bytes: [UInt8]
  private var offset = 0

  init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  mutating func read(count: Int) -> [UInt8]? {
    guard count >= 0, count <= bytes.count - offset else { return nil }
    defer { offset += count }
    return Array(bytes[offset..<(offset + count)])
  }

}
