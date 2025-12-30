//
//  BaseEncodingTests.swift
//  SolidFoundation
//
//  Created by Agent on 12/29/25.
//

import Foundation
import SolidCore
import Testing

@Suite
struct BaseEncodingTests {

  struct EncodingCase: CustomStringConvertible, Sendable {
    let name: String
    let encoding: BaseEncoding
    var description: String { name }

    static let all: [EncodingCase] = [
      .init(name: "base64", encoding: .base64),
      .init(name: "base64Url", encoding: .base64Url),
      .init(name: "base62", encoding: .base62),
      .init(name: "base32", encoding: .base32),
      .init(name: "base32Lower", encoding: .base32Lower),
      .init(name: "base32Crockford", encoding: .base32Crockford),
      .init(name: "base32CrockfordLower", encoding: .base32CrockfordLower),
      .init(name: "base32Hex", encoding: .base32Hex),
      .init(name: "base32HexLower", encoding: .base32HexLower),
      .init(name: "base16", encoding: .base16),
      .init(name: "base16Lower", encoding: .base16Lower),
    ]
  }

  // Deterministic byte vectors used across tests
  static let vectors: [[UInt8]] = {
    let small: [UInt8] = [0x00, 0x01, 0x02, 0xFF, 0x10]
    let zeros: [UInt8] = Array(repeating: 0, count: 8)
    var seq: [UInt8] = []
    seq.reserveCapacity(64)
    for i in 0..<64 { seq.append(UInt8(truncatingIfNeeded: (i * 37) & 0xff)) }
    return [[], [0], small, zeros, seq]
  }()

  // Helper to decode via BaseEncoding into Data to surface decode errors precisely
  private func decodeToData(_ string: String, using enc: BaseEncoding) throws -> Data {
    let size = try enc.decodedSize(of: string)
    var data = Data(repeating: 0, count: size)
    try data.withUnsafeMutableBytes { rawBuf in
      let buf = rawBuf.bindMemory(to: UInt8.self)
      var out = OutputSpan<UInt8>(buffer: buf, initializedCount: 0)
      try enc.decode(string, into: &out)
      _ = out.finalize(for: buf)
    }
    return data
  }

  @Test(arguments: EncodingCase.all)
  func `round trip`(_ arg: EncodingCase) throws {
    for vec in Self.vectors {
      let encoded = Data(vec).baseEncoded(using: arg.encoding)
      let decoded = try decodeToData(encoded, using: arg.encoding)
      #expect(Array(decoded) == vec, "Round-trip mismatch for \(arg.name)")
    }
  }

  @Test(arguments: EncodingCase.all)
  func `decodedSize matches count`(_ arg: EncodingCase) throws {
    for vec in Self.vectors {
      let s = Data(vec).baseEncoded(using: arg.encoding)
      let size = try arg.encoding.decodedSize(of: s)
      #expect(size == vec.count, "decodedSize mismatch for \(arg.name)")
    }
  }

  @Test
  func `base62 leading zeros are preserved`() throws {
    // Leading zero bytes should map to leading first-alphabet characters ("0") in base62
    let cases: [[UInt8]] = [
      [0],
      [0, 0],
      [0, 0, 0],
      [0, 0, 1],
      [0, 0, 1, 2, 3],
    ]
    for vec in cases {
      let s = Data(vec).baseEncoded(using: .base62)
      let leadingZeros = vec.prefix { $0 == 0 }.count
      let leadingChars = s.prefix { $0 == "0" }.count
      #expect(leadingChars == leadingZeros, "base62 should preserve leading zeros as '0'")

      // And should round trip
      let dec = try decodeToData(s, using: .base62)
      #expect(Array(dec) == vec)
    }
  }

  @Test(arguments: EncodingCase.all)
  func `invalid characters throw errors`(_ arg: EncodingCase) {
    // Craft a string with an invalid character for each alphabet
    // Choose '!' which is not present in any of the supported alphabets
    let s = "!"

    #expect(throws: BaseEncoding.DecodeError.self) {
      _ = try decodeToData(s, using: arg.encoding)
    }
  }

  // MARK: - Padding and strictness

  @Test
  func `base64 strictPadding is enforced on missing padding`() {
    // "M" -> "TQ==" in standard base64
    let enc = BaseEncoding.base64    // strictPadding: true
    let encoded = Data([0x4d]).baseEncoded(using: enc)
    #expect(encoded.hasSuffix("=="))

    // Remove one padding char: length not multiple of 4 -> invalid in strict mode
    let trimmed = String(encoded.dropLast(1))
    #expect(throws: BaseEncoding.DecodeError.self) {
      _ = try decodeToData(trimmed, using: enc)
    }
  }

  @Test
  func `base64 lenient allows missing padding`() throws {
    // Use URL flavor which defaults to strictPadding=false but still uses '=' padding
    let enc = BaseEncoding.base64Url
    let data = Data([0x4d])    // "M"
    let encoded = data.baseEncoded(using: enc)    // will include '=' by default
    let unpadded = encoded.replacingOccurrences(of: "=", with: "")

    // Should decode fine in lenient mode
    let decoded = try decodeToData(unpadded, using: enc)
    #expect(Array(decoded) == [0x4d])
  }

  @Test
  func `base64 custom padding character is honored`() {
    let enc = BaseEncoding.base64.padded(character: "~", strict: true)
    let s1 = Data([0x4d]).baseEncoded(using: enc)
    #expect(s1.hasSuffix("~~"))

    let s2 = Data([0x4d, 0x61]).baseEncoded(using: enc)
    #expect(s2.hasSuffix("~"))
  }

  @Test
  func `base64 unpadded mode emits no padding and decodes`() throws {
    let enc = BaseEncoding.base64.unpadded()
    // 1 byte -> normally two '='; here none
    let s = Data([0x4d]).baseEncoded(using: enc)
    #expect(!s.contains("="))
    let d = try decodeToData(s, using: enc)
    #expect(Array(d) == [0x4d])
  }

  private func blockSize(bitsPerChar: Int) -> Int {
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    func lcm(_ a: Int, _ b: Int) -> Int { (a / gcd(a, b)) * b }
    let blockBits = lcm(8, bitsPerChar)
    return blockBits / bitsPerChar
  }

  @Test
  func `power-of-two encodings pad to block boundaries`() {
    let cases: [(enc: BaseEncoding, bits: Int)] = [
      (.base64, 6),
      (.base32, 5),
      (.base32Lower, 5),
      (.base32Hex, 5),
      (.base32HexLower, 5),
      (.base16, 4),
      (.base16Lower, 4),
    ]

    for (enc, bits) in cases {
      let blk = blockSize(bitsPerChar: bits)
      // Try payload sizes that exercise each remainder
      for n in 1...6 {
        let data = Data((0..<n).map { UInt8($0) })
        let s = data.baseEncoded(using: enc)
        #expect(s.count % blk == 0, "Encoded length must be multiple of block size for power-of-two alphabets")
        if let pad = enc.paddingCharacter {
          // Ensure the pad character appears only at the end (if at all)
          if let idx = s.firstIndex(of: pad) {
            #expect(s[idx...].allSatisfy { $0 == pad })
          }
        }
      }
    }
  }

  @Test
  func `base62 has no padding`() {
    let s = Data([0, 1, 2, 3]).baseEncoded(using: .base62)
    #expect(!s.contains("="))
  }
}
