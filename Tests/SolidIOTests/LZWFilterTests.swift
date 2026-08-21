//
//  LZWFilterTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidIO
import Testing

@Suite
struct LZWFilterTests {

  @Test(arguments: [0, 1])
  func lzwRoundTripEarlyChange(_ earlyChange: Int) throws {
    let source = Data((0..<4096).map { UInt8(($0 * 31) & 0xFF) })
    let options = try LZWOptions(earlyChange: earlyChange)
    let encoder = LZWEncoder(options: options)
    var encoded = try encoder.process(input: source).output
    encoded.append(try #require(try encoder.finish()))

    let decoder = LZWDecoder(options: options)
    let result = try decoder.process(input: encoded + Data([0xAA]))
    #expect(result.output == source)
    #expect(result.consumedInput == encoded.count)
    #expect(result.progress == .finished)
  }

  @Test
  func lzwLowBitFirstUnitsRoundTrip() throws {
    let source = Data([0b1101_0010, 0b0110_1011, 0b1010_0000])
    let options = try LZWOptions(earlyChange: 0, unitLength: 4, lowBitFirst: true)
    let encoder = LZWEncoder(options: options)
    var encoded = try encoder.process(input: source).output
    encoded.append(try #require(try encoder.finish()))
    let decoder = LZWDecoder(options: options)
    let result = try decoder.process(input: encoded)
    #expect(result.output == source)
  }

  @Test
  func lzwEncoderStreamsAcrossInputChunks() throws {
    let source = Data((0..<16_384).map { UInt8(($0 * 19) & 0xFF) })
    let encoder = LZWEncoder()
    var encoded = Data()
    var offset = 0
    for length in [1, 17, 509, 4096, 8192] where offset < source.count {
      let end = min(source.count, offset + length)
      encoded.append(try encoder.process(input: source[offset..<end]).output)
      offset = end
    }
    if offset < source.count { encoded.append(try encoder.process(input: source[offset...]).output) }
    encoded.append(try #require(try encoder.finish()))
    #expect(try LZWDecoder().process(input: encoded).output == source)
  }

  @Test(arguments: [0, 1])
  func lzwDecoderStreamsAcrossOneByteChunks(_ earlyChange: Int) throws {
    let source = Data((0..<65_536).map { UInt8((($0 * 1_103_515_245 + 12_345) >> 16) & 0xFF) })
    let options = try LZWOptions(earlyChange: earlyChange)
    let encoded = try Self.encode(source, options: options)
    let decoder = LZWDecoder(options: options)
    var decoded = Data()
    var emittedBeforeEnd = false

    for byte in encoded {
      let result = try decoder.process(input: Data([byte]))
      #expect(result.consumedInput == 1)
      if result.progress == .needsInput && !result.output.isEmpty {
        emittedBeforeEnd = true
      }
      decoded.append(result.output)
    }

    #expect(emittedBeforeEnd)
    #expect(decoded == source)
    #expect(try decoder.finish() == nil)
  }

  @Test
  func lzwDecoderPreservesTrailingInputAfterPartialCode() throws {
    let source = Data((0..<8192).map { UInt8(($0 * 43) & 0xFF) })
    let options = try LZWOptions(earlyChange: 0, unitLength: 4, lowBitFirst: true)
    let encoded = try Self.encode(source, options: options)
    let split = encoded.count / 2
    let decoder = LZWDecoder(options: options)
    let first = try decoder.process(input: encoded.prefix(split))
    let trailer = Data("trailing".utf8)
    let secondInput = Data(encoded.dropFirst(split)) + trailer
    let second = try decoder.process(input: secondInput)

    #expect(first.progress == .needsInput)
    #expect(second.progress == .finished)
    #expect(second.consumedInput == encoded.count - split)
    #expect(first.output + second.output == source)
  }

  @Test
  func lzwDecoderRejectsPhysicalEndBeforeEndCode() throws {
    let source = Data((0..<1024).map { UInt8(($0 * 7) & 0xFF) })
    let encoded = try Self.encode(source)
    let decoder = LZWDecoder()

    _ = try decoder.process(input: encoded.dropLast())
    #expect(throws: StreamCodecError.truncatedData) {
      try decoder.finish()
    }
  }

  private static func encode(
    _ source: Data,
    options: LZWOptions = try! LZWOptions()
  ) throws -> Data {
    let encoder = LZWEncoder(options: options)
    var encoded = try encoder.process(input: source).output
    encoded.append(try #require(try encoder.finish()))
    return encoded
  }

}
