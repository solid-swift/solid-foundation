@testable import SolidJPEG
import Testing

@Suite
struct JPEGFoundationTests {

  @Test
  func validatesSamplingAndComponentVolume() throws {
    #expect(throws: JPEGError.self) { try JPEGSampling(horizontal: 0) }
    let components = try [
      JPEGComponent(identifier: 1, sampling: JPEGSampling(horizontal: 4, vertical: 1)),
      JPEGComponent(identifier: 2, sampling: JPEGSampling(horizontal: 2, vertical: 1)),
      JPEGComponent(identifier: 3, sampling: JPEGSampling(horizontal: 2, vertical: 1)),
    ]
    #expect(throws: Never.self) {
      try JPEGEncodingOptions(width: 16, height: 16, components: components)
    }
  }

  @Test
  func rejectsOversubscribedHuffmanTable() throws {
    #expect(throws: JPEGError.self) {
      try JPEGHuffmanTable(
        tableClass: .dc,
        identifier: 0,
        codeCounts: [3] + Array(repeating: 0, count: 15),
        symbols: [0, 1, 2]
      )
    }
  }

  @Test
  func checkedByteStorageHonorsLimits() throws {
    var writer = try CheckedByteWriter(maximumBytes: 2)
    try writer.appendUInt16(0x1234)
    #expect(writer.bytes == [0x12, 0x34])
    #expect(throws: JPEGError.limitExceeded) { try writer.append(0) }

    var reader = try CheckedByteReader(bytes: writer.bytes)
    #expect(try reader.readUInt16() == 0x1234)
    #expect(throws: JPEGError.truncatedData) { try reader.readByte() }
  }

  @Test
  func bitStorageUsesMostSignificantBitOrder() throws {
    var writer = BitWriter(maximumBytes: 1)
    try writer.append(value: 0b101, count: 3)
    #expect(try writer.finish(paddingBit: 0) == [0b1010_0000])

    var reader = BitReader(bytes: [0b1010_0000])
    #expect(try reader.readBits(count: 3) == 0b101)
  }

  @Test
  func encoderEnforcesExactInputAndCanBeAbandoned() throws {
    let component = try JPEGComponent(identifier: 1)
    let options = try JPEGEncodingOptions(width: 2, height: 1, components: [component])
    var encoder = JPEGEncoder(options: options)
    let samples = [UInt8](repeating: 0, count: 1)
    let result = try samples.withUnsafeBufferPointer {
      try encoder.process(Span(_unsafeElements: $0))
    }
    #expect(result.consumedSamples == 1)
    encoder.abandon()
    #expect(throws: JPEGError.abandoned) {
      _ = try samples.withUnsafeBufferPointer {
        try encoder.process(Span(_unsafeElements: $0))
      }
    }
  }

  @Test
  func limitsRejectOverflowingSampleBudget() throws {
    let limits = try JPEGLimits(maximumInputBytes: 3)
    let components = try [
      JPEGComponent(identifier: 1),
      JPEGComponent(identifier: 2),
      JPEGComponent(identifier: 3),
    ]
    #expect(throws: JPEGError.limitExceeded) {
      try JPEGEncodingOptions(width: 2, height: 1, components: components, limits: limits)
    }
  }

}
