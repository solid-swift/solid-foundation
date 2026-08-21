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

}
