//
//  FlateFilterTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidIO
import Testing

@Suite
struct FlateFilterTests {

  @Test(arguments: [-1, 0, 1, 5, 9])
  func roundTripEffortAndTrailingInput(_ effort: Int) throws {
    let source = Data((0..<8192).map { UInt8(($0 * 29) & 0xFF) })
    let options = try FlateOptions(effort: effort)
    let encoder = FlateEncoder(options: options)
    var encoded = try encoder.process(input: source).output
    encoded.append(try #require(try encoder.finish()))

    let decoder = FlateDecoder(options: options)
    let result = try decoder.process(input: encoded + Data("tail".utf8))
    #expect(result.output == source)
    #expect(result.consumedInput == encoded.count)
    #expect(result.progress == .finished)
  }

  @Test(arguments: [2, 10, 11, 12, 13, 14, 15])
  func predictorRoundTrip(_ predictor: Int) throws {
    let predictorOptions = try PredictorOptions(predictor: predictor, colors: 3, columns: 13)
    let options = try FlateOptions(predictor: predictorOptions)
    let source = Data((0..<(predictorOptions.rowBytes * 5)).map { UInt8(($0 * 7) & 0xFF) })
    let encoder = FlateEncoder(options: options)
    var encoded = try encoder.process(input: source).output
    encoded.append(try #require(try encoder.finish()))
    let decoder = FlateDecoder(options: options)
    #expect(try decoder.process(input: encoded).output == source)
  }

  @Test
  func rejectsCorruptionAndTruncation() throws {
    let decoder = FlateDecoder()
    #expect(throws: StreamCodecError.invalidData) {
      try decoder.process(input: Data("not zlib".utf8))
    }

    let truncated = FlateDecoder()
    _ = try truncated.process(input: Data([0x78, 0x9C]))
    #expect(throws: StreamCodecError.truncatedData) {
      try truncated.finish()
    }
  }

  @Test
  func predictorPreservesRowsAcrossIrregularChunks() throws {
    let predictor = try PredictorOptions(predictor: 15, colors: 3, columns: 17)
    let options = try FlateOptions(predictor: predictor)
    let source = Data((0..<(predictor.rowBytes * 19)).map { UInt8(($0 * 23) & 0xFF) })
    let encoder = FlateEncoder(options: options)
    var encoded = Data()
    var offset = 0
    for length in [1, 7, 31, 113, 509] where offset < source.count {
      let end = min(source.count, offset + length)
      encoded.append(try encoder.process(input: source[offset..<end]).output)
      offset = end
    }
    if offset < source.count { encoded.append(try encoder.process(input: source[offset...]).output) }
    encoded.append(try #require(try encoder.finish()))

    let decoder = FlateDecoder(options: options)
    var decoded = Data()
    for byte in encoded {
      decoded.append(try decoder.process(input: Data([byte])).output)
    }
    #expect(decoded == source)
  }

}
