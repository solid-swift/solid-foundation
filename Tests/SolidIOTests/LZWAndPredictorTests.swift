//
//  LZWAndPredictorTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidIO
import Testing

@Suite
struct LZWAndPredictorTests {

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

  @Test(arguments: [1, 2, 4, 8])
  func tiffPredictorRoundTrip(_ bits: Int) throws {
    let options = try PredictorOptions(
      predictor: 2,
      colors: 3,
      bitsPerComponent: bits,
      columns: 8
    )
    let source = Data((0..<(options.rowBytes * 3)).map { UInt8(($0 * 17) & 0xFF) })
    let encoded = try PredictorCodec.encode(source, options: options)
    #expect(try PredictorCodec.decode(encoded, options: options) == source)
  }

  @Test(arguments: Array(10...15))
  func pngPredictorRoundTrip(_ predictor: Int) throws {
    let options = try PredictorOptions(predictor: predictor, colors: 3, columns: 9)
    let source = Data((0..<(options.rowBytes * 4)).map { UInt8(($0 * 43) & 0xFF) })
    let encoded = try PredictorCodec.encode(source, options: options)
    #expect(try PredictorCodec.decode(encoded, options: options) == source)
  }

}
