import Foundation
@testable import SolidIO
import Testing

@Suite struct ZlibStreamEncoderTests {
  @Test(arguments: [-1, 0, 1, 5, 9])
  func streamsAcrossIrregularChunks(_ level: Int) throws {
    let source = Data((0..<131_071).map { UInt8(($0 * 31) & 0xFF) })
    let encoder = try ZlibStreamEncoder(compressionLevel: level)
    var encoded = Data()
    var offset = 0
    for size in [1, 7, 257, 4093, 65_537] where offset < source.count {
      let end = min(source.count, offset + size)
      encoded.append(try encoder.process(source[offset..<end]))
      offset = end
    }
    if offset < source.count {
      encoded.append(try encoder.process(source[offset...]))
    }
    encoded.append(try #require(try encoder.finish()))

    let decoder = FlateDecoder()
    #expect(try decoder.process(input: encoded).output == source)
    #expect(try encoder.finish() == nil)
  }

  @Test func flushDoesNotFinishStream() throws {
    let encoder = try ZlibStreamEncoder()
    var encoded = try encoder.process(Data("first".utf8))
    encoded.append(try encoder.flush())
    encoded.append(try encoder.process(Data("second".utf8)))
    encoded.append(try #require(try encoder.finish()))

    #expect(try FlateDecoder().process(input: encoded).output == Data("firstsecond".utf8))
  }

  @Test func validatesLevelAndFinishedState() throws {
    #expect(throws: StreamCodecError.invalidOption("compressionLevel")) {
      _ = try ZlibStreamEncoder(compressionLevel: 10)
    }
    let encoder = try ZlibStreamEncoder()
    _ = try encoder.finish()
    #expect(throws: StreamCodecError.invalidData) {
      try encoder.process(Data([1]))
    }
    #expect(try encoder.flush().isEmpty)
  }
}
