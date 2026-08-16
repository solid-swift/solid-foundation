//
//  DCTFilterTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidIO
import Testing

@Suite
struct DCTFilterTests {

  @Test
  func rgbRoundTripAndTrailingInput() throws {
    let byteCount = 16 * 12 * 3
    let bytes: [UInt8] = (0..<byteCount).map { UInt8(($0 * 11) & 0xFF) }
    let source = Data(bytes)
    let encoder = DCTEncoder(options: try DCTEncodeOptions(columns: 16, rows: 12, colors: 3))
    let encoded = try encoder.process(input: source)
    #expect(encoded.progress == .finished)
    let jpeg = encoded.output
    #expect(jpeg.starts(with: [0xFF, 0xD8]))
    #expect(jpeg.suffix(2) == Data([0xFF, 0xD9]))

    let decoder = DCTDecoder(options: try DCTDecodeOptions(columns: 16, rows: 12, colors: 3))
    let result = try decoder.process(input: jpeg + Data("tail".utf8))
    #expect(result.output.count == source.count)
    #expect(result.consumedInput == jpeg.count)
    #expect(result.progress == .finished)
  }

  @Test
  func unavailableImageIOModesFailExplicitly() throws {
    let options = try DCTEncodeOptions(columns: 1, rows: 1, colors: 2)
    let encoder = DCTEncoder(options: options)
    #expect(throws: StreamCodecError.unsupportedOperation) {
      try encoder.process(input: Data([0, 0]))
    }
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

}
