//
//  CCITTFaxFilterTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidIO
import Testing

@Suite
struct CCITTFaxFilterTests {

  @Test(arguments: [-1, 0, 2])
  func groupThreeAndFourRoundTrip(_ k: Int) throws {
    let columns = 64
    let rows = 16
    let source = Data((0..<(columns / 8 * rows)).map { UInt8(($0 * 37) & 0xFF) })
    let options = try CCITTFaxOptions(k: k, columns: columns, rows: rows)
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: source)
    let final = try encoder.finish()
    let encoded = try #require(final)
    #expect(!encoded.isEmpty)

    let decoder = CCITTFaxDecoder(options: options)
    let result = try decoder.process(input: encoded)
    let decoded = result.progress == .finished ? result.output : try decoder.finish()
    #expect(decoded == source)
  }

  @Test
  func blackPolarityRoundTrip() throws {
    let options = try CCITTFaxOptions(k: -1, columns: 16, rows: 2, blackIs1: true)
    let source = Data([0xAA, 0x55, 0xF0, 0x0F])
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: source)
    let final = try encoder.finish()
    let encoded = try #require(final)
    let decoder = CCITTFaxDecoder(options: options)
    let result = try decoder.process(input: encoded)
    let decoded = result.progress == .finished ? result.output : try decoder.finish()
    #expect(decoded == source)
  }

  @Test
  func encoderDerivesRowsFromCompleteInput() throws {
    let options = try CCITTFaxOptions(k: 0, columns: 16)
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: Data([0xAA, 0x55, 0xF0, 0x0F]))
    let encoded = try #require(try encoder.finish())
    #expect(encoded.isEmpty == false)
  }

  @Test(arguments: [-1, 0])
  func decoderStopsAtEndOfBlockBeforeTrailingInput(_ k: Int) throws {
    let options = try CCITTFaxOptions(k: k, columns: 16, rows: 2)
    let source = Data([0xAA, 0x55, 0xF0, 0x0F])
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: source)
    let encoded = try #require(try encoder.finish())

    let decoder = CCITTFaxDecoder(options: options)
    let result = try decoder.process(input: encoded + Data("tail".utf8))
    #expect(result.output == source)
    #expect(result.consumedInput == encoded.count)
    #expect(result.progress == .finished)
  }

  @Test(arguments: [0, 2])
  func endOfLineAndByteAlignmentRoundTrip(_ k: Int) throws {
    let options = try CCITTFaxOptions(
      k: k,
      endOfLine: true,
      encodedByteAlign: true,
      columns: 40,
      rows: 5
    )
    let source = Data((0..<25).map { UInt8(($0 * 73) & 0xFF) })
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: source)
    let encoded = try #require(try encoder.finish())
    let decoder = CCITTFaxDecoder(options: options)
    let decoded = try decoder.process(input: encoded)
    #expect(decoded.output == source)
  }

  @Test
  func longMakeupRunsRoundTrip() throws {
    let options = try CCITTFaxOptions(k: -1, columns: 4096, rows: 2, blackIs1: true)
    let source = Data(repeating: 0, count: 1024)
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: source)
    let encoded = try #require(try encoder.finish())
    let decoder = CCITTFaxDecoder(options: options)
    #expect(try decoder.process(input: encoded).output == source)
  }

}
