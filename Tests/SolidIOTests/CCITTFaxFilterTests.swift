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

  @Test(arguments: [-1, 0])
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
    _ = try decoder.process(input: encoded)
    let decoded = try decoder.finish()
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
    _ = try decoder.process(input: encoded)
    #expect(try decoder.finish() == source)
  }

  @Test
  func encoderDerivesRowsFromCompleteInput() throws {
    let options = try CCITTFaxOptions(k: 0, columns: 16)
    let encoder = CCITTFaxEncoder(options: options)
    _ = try encoder.process(input: Data([0xAA, 0x55, 0xF0, 0x0F]))
    let encoded = try #require(try encoder.finish())
    #expect(encoded.isEmpty == false)
  }

}
