//
//  PostScriptByteCodecTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidIO
import Testing

@Suite
struct PostScriptByteCodecTests {

  @Test
  func asciiHexKnownVectorAndTrailingInput() throws {
    let encoder = ASCIIHexEncoder()
    let body = try encoder.process(input: Data("Hello".utf8)).output
    let final = try encoder.finish()
    let encoded = body + (try #require(final))
    #expect(encoded == Data("48656c6c6f>".utf8))

    let decoder = ASCIIHexDecoder()
    let decoded = try decoder.process(input: encoded + Data("tail".utf8))
    #expect(decoded.output == Data("Hello".utf8))
    #expect(decoded.consumedInput == encoded.count)
    #expect(decoded.progress == .finished)
  }

  @Test
  func asciiHexOddNibbleAndWhitespace() throws {
    let decoder = ASCIIHexDecoder()
    let result = try decoder.process(input: Data("6 1 2>".utf8))
    #expect(result.output == Data([0x61, 0x20]))
  }

  @Test
  func ascii85KnownVectorAndChunking() throws {
    let encoder = ASCII85Encoder()
    var encoded = Data()
    for byte in Data("Hello, world!".utf8) {
      encoded.append(try encoder.process(input: Data([byte])).output)
    }
    let final = try encoder.finish()
    encoded.append(try #require(final))
    #expect(encoded == Data("87cURD_*#TDfTZ)+T~>".utf8))

    let decoder = ASCII85Decoder()
    var decoded = Data()
    for byte in encoded {
      decoded.append(try decoder.process(input: Data([byte])).output)
    }
    #expect(decoded == Data("Hello, world!".utf8))
  }

  @Test
  func ascii85ZeroAndPartialTuple() throws {
    let decoder = ASCII85Decoder()
    let result = try decoder.process(input: Data("z!!~>tail".utf8))
    #expect(result.output == Data([0, 0, 0, 0, 0]))
    #expect(result.consumedInput == 5)
  }

  @Test
  func runLengthKnownVectorAndTrailingInput() throws {
    let source = Data("AAAAABBBBCCCCCCCCXYZ".utf8)
    let encoder = try RunLengthEncoder(recordSize: 7)
    _ = try encoder.process(input: source)
    let final = try encoder.finish()
    let encoded = try #require(final)

    let decoder = RunLengthDecoder()
    let result = try decoder.process(input: encoded + Data([42]))
    #expect(result.output == source)
    #expect(result.consumedInput == encoded.count)
    #expect(result.progress == .finished)
  }

}
