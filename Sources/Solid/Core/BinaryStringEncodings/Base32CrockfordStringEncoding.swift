//
//  Base32CrockfordStringEncoding.swift
//
//
//  Created by Automated on 2025-12-20.
//

import Foundation

/// Base32 Crockford encoding/decoding implementation.
///
/// Uses the alphabet: "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
/// (digits 0-9, letters A-Z excluding I, L, O, U).
/// Unpadded uppercase encoding.
/// Decoding accepts case-insensitive input with normalization:
/// 'O'/'o' → '0', 'I'/'i'/'L'/'l' → '1', '-' ignored as group separator.
/// Throws for invalid length or invalid characters.
///
public struct Base32CrockfordStringEncoding: BinaryStringEncoding {

  public static let `default` = Self()

  public enum Error: Swift.Error {
    case invalidLength
    case invalidCharacter(at: Int)
    case invalidString
  }

  private static let uppercaseAlphabet: [UInt8] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
  private static let lowercaseAlphabet: [UInt8] = Array("0123456789abcdefghjkmnpqrstvwxyz".utf8)

  /// Reverse table: maps ASCII code to alphabet index or -1 if invalid.
  /// Normalization table: maps ASCII code to normalized alphabet index, or -1 invalid, or -2 skip ('-').
  private static func normalizationTable(alphabet: [UInt8]) -> [Int8] {
    var table = [Int8](repeating: -1, count: 256)

    // Map alphabet characters (upper & lower) to index
    for (idx, byte) in alphabet.enumerated() {
      table[Int(byte)] = Int8(idx)
      // lowercase ascii letters to same index
      if byte >= 65 && byte <= 90 {    // 'A'..'Z'
        table[Int(byte + 32)] = Int8(idx)
      }
    }

    // Ambiguous chars normalization:
    // 'O', 'o' → '0' (index 0)
    table[Int(UInt8(ascii: "O"))] = 0
    table[Int(UInt8(ascii: "o"))] = 0
    // 'I','i','L','l' → '1' (index 1)
    let ones: [UInt8] = [UInt8(ascii: "I"), UInt8(ascii: "i"), UInt8(ascii: "L"), UInt8(ascii: "l")]
    for ch in ones {
      table[Int(ch)] = 1
    }

    // Ignore hyphen '-'
    table[Int(UInt8(ascii: "-"))] = -2

    return table
  }

  private let alphabet: [UInt8]
  private let normalizationTable: [Int8]

  public init(lowercase: Bool = false) {
    self.alphabet = lowercase ? Self.lowercaseAlphabet : Self.uppercaseAlphabet
    self.normalizationTable = Self.normalizationTable(alphabet: self.alphabet)
  }

  public func encode(_ bytes: some Collection<UInt8>) -> String {
    let input = bytes
    let length = input.count
    if length == 0 {
      return ""
    }

    // Calculate output length: ceil(bits/5)
    let bitCount = length * 8
    let charCount = (bitCount + 4) / 5

    return String(unsafeUninitializedCapacity: charCount) { buffer in
      var bitBuffer: UInt = 0
      var bitsLeft: Int = 0
      var outputIndex = 0

      for byte in input {
        bitBuffer = (bitBuffer << 8) | UInt(byte)
        bitsLeft += 8
        while bitsLeft >= 5 {
          bitsLeft -= 5
          let index = Int((bitBuffer >> bitsLeft) & 0x1F)
          buffer[outputIndex] = alphabet[index]
          outputIndex += 1
        }
      }
      if bitsLeft > 0 {
        let index = Int((bitBuffer << (5 - bitsLeft)) & 0x1F)
        buffer[outputIndex] = alphabet[index]
        outputIndex += 1
      }
      return outputIndex
    }
  }

  public func decodedSize(of encoded: String) throws -> Int {
    var symbolCount = 0

    for (idx, scalar) in encoded.unicodeScalars.enumerated() {
      let v: Int8
      if scalar.value < 256 {
        v = normalizationTable[Int(scalar.value)]
      } else {
        v = -1
      }

      if v == -2 {
        // Hyphen: ignored for sizing
        continue
      }

      guard v >= 0 else {
        throw Error.invalidCharacter(at: idx)
      }

      symbolCount += 1
    }

    // Each symbol contributes 5 bits
    let totalBits = symbolCount * 5
    let fullBytes = totalBits / 8
    let leftoverBits = totalBits % 8

    // Canonical Crockford Base32 requires leftover bits to be zero
    // Valid leftover bits: 0, 2, 4, 5, 7 symbols → 0, 2, 4, 5, 7 * 5 % 8
    switch leftoverBits {
    case 0:
      break
    default:
      // Decode() will later verify the bits are zero,
      // but a non-zero remainder here is structurally invalid.
      throw Error.invalidLength
    }

    return fullBytes
  }

  public func decode(_ string: String, into out: inout OutputSpan<UInt8>) throws {
    var buffer: UInt = 0
    var bitsLeft = 0

    // Position among non-hyphen characters (for error reporting)
    var pos = 0

    for (idx, scalar) in string.unicodeScalars.enumerated() {
      let v: Int8
      if scalar.value < 256 {
        v = normalizationTable[Int(scalar.value)]
      } else {
        v = -1
      }

      if v == -2 {
        // Skip hyphen (does not advance pos)
        continue
      }

      // Advance logical position for every non-hyphen character
      pos += 1

      guard v >= 0 else {
        throw Error.invalidCharacter(at: idx)
      }

      buffer = (buffer << 5) | UInt(v)
      bitsLeft += 5

      while bitsLeft >= 8 {
        if out.isFull {
          throw Error.invalidString
        }

        bitsLeft -= 8
        let byte = UInt8((buffer >> bitsLeft) & 0xFF)
        out.append(byte)

        // Keep only the remaining bits
        if bitsLeft == 0 {
          buffer = 0
        } else {
          buffer &= (UInt(1) << bitsLeft) - 1
        }
      }
    }

    guard out.count == 16 else { throw Error.invalidString }

    // Leftover bits must be zero (canonical Crockford Base32)
    if bitsLeft > 0 {
      let mask = (UInt(1) << bitsLeft) - 1
      if (buffer & mask) != 0 {
        throw Error.invalidLength
      }
    }
  }
}
