//
//  BaseEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//

import Foundation


/// Base encodings.
///
/// - ``base64``: Base64 encoding.
/// - ``base64Url``: Base64 URL encoding.
/// - ``base62``: Base62 encoding.
/// - ``base32``: Base32 encoding.
/// - ``base32Lower``: Base32 lowercase encoding.
/// - ``base32Crockford``: Base32 Crockford encoding.
/// - ``base32CrockfordLower``: Base32 Crockford lowercase encoding.
/// - ``base32Hex``: Base32 Hex encoding.
/// - ``base32HexLower``: Base32 Hex lowercase encoding.
/// - ``base16``: Base16 (hexadecimal) encoding.
/// - ``base16Lower``: Base16 (hexadecimal) lowercase encoding.
///
public struct BaseEncoding: Sendable {

  public enum DecodeError: Swift.Error, Sendable {
    case invalidPadding
    case invalidCharacter(Character)
    case invalidTrailingBits
  }

  /// Base 64 encoding.
  ///
  /// Base 64 encoding  with the standard alphabet and the following options:
  /// - Padding character: `=`
  /// - Strict padding: `true`
  /// - Case insensitive: `false`
  ///
  public static let base64 = Self(
    alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
    padding: "=",
    strictPadding: true,
    caseInsensitive: false
  )

  /// Base 64 URL encoding.
  ///
  /// Base 64 URL encoding with URL-safe alphabet and the following options:
  /// - Padding character: `=`
  /// - Strict padding: `false`
  /// - Case insensitive: `false`
  ///
  public static let base64Url = Self(
    alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_",
    padding: "=",
    strictPadding: false,
    caseInsensitive: false
  )

  /// Base 62 encoding.
  ///
  /// Base 62 encoding with alphabet `0-9A-Za-z` and the following options:
  /// - Padding character: `none`
  /// - Strict padding: `false`
  /// - Case insensitive: `false`
  ///
  public static let base62 = Self(
    alphabet: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
    padding: nil,
    strictPadding: false,
    caseInsensitive: false
  )

  /// Base 32 encoding.
  ///
  /// Base 32 encoding with the standard alphabet (`A-Z2-7`) and the following options:
  /// - Padding character: `=`
  /// - Strict padding: `true`
  /// - Case insensitive: `true`
  ///
  public static let base32 = Self(
    alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567",
    padding: "=",
    strictPadding: true,
    caseInsensitive: true
  )

  /// Base 32 encoding.
  ///
  /// Base 32 encoding with the standard alphabet (`a-z2-7`) and the following options:
  /// - Padding character: `=`
  /// - Strict padding: `true`
  /// - Case insensitive: `true`
  ///
  public static let base32Lower = Self(
    alphabet: "abcdefghijklmnopqrstuvwxyz234567",
    padding: "=",
    strictPadding: true,
    caseInsensitive: true
  )

  /// Base 32 Hex encoding.
  ///
  /// Base 32 Hex encoding with the extended hex alphabet (`0-9A-V`) and the following options:
  /// - Padding character: `=`
  /// - Strict padding: `true`
  /// - Case insensitive: `true`
  ///
  public static let base32Hex = Self(
    alphabet: "0123456789ABCDEFGHIJKLMNOPQRSTUV",
    padding: "=",
    strictPadding: true,
    caseInsensitive: true
  )

  /// Base 32 Hex encoding.
  ///
  /// Base 32 Hex encoding with the extended hex alphabet (`0-9A-V`) and the following options:
  /// - Padding character: `=`
  /// - Strict padding: `true`
  /// - Case insensitive: `true`
  ///
  public static let base32HexLower = Self(
    alphabet: "0123456789abcdefghijklmnopqrstuv",
    padding: "=",
    strictPadding: true,
    caseInsensitive: true
  )

  /// Base 32 Crockford encoding.
  ///
  /// Base 32 Crockford encoding with the Crockford alphabet and the following options:
  /// - Padding character: `None`
  /// - Strict padding: `false`
  /// - Case insensitive: `true`
  ///
  public static let base32Crockford = Self(
    alphabet: "0123456789ABCDEFGHJKMNPQRSTVWXYZ",
    padding: nil,
    strictPadding: false,
    caseInsensitive: true
  )

  /// Base 32 Crockford encoding.
  ///
  /// Base 32 Crockford encoding with the Crockford alphabet and the following options:
  /// - Padding character: `None`
  /// - Strict padding: `false`
  /// - Case insensitive: `true`
  ///
  public static let base32CrockfordLower = Self(
    alphabet: "0123456789abcdefghjkmnpqrstvwxyz",
    padding: nil,
    strictPadding: false,
    caseInsensitive: true
  )

  /// Base 16 (hexadecimal) encoding.
  ///
  /// Base 16 encoding with the standard alphabet (`0-9A-F`) and the following options:
  /// - Padding character: `none`
  /// - Strict padding: `false`
  /// - Case insensitive: `true`
  ///
  public static let base16 = Self(
    alphabet: "0123456789ABCDEF",
    padding: nil,
    strictPadding: false,
    caseInsensitive: true
  )

  /// Base 16 (hexadecimal) lowercase encoding.
  ///
  /// Base 16 encoding with the standard alphabet (`0-9A-F`) and the following options:
  /// - Padding character: `none`
  /// - Strict padding: `false`
  /// - Case insensitive: `true`
  ///
  public static let base16Lower = Self(
    alphabet: "0123456789abcdef",
    padding: nil,
    strictPadding: false,
    caseInsensitive: true
  )

  /// The alphabet used for encoding.
  public let alphabet: [Character]

  /// The number of bits per character in the alphabet.
  public let bitsPerChar: Int

  /// The padding character used, if any.
  public let paddingCharacter: Character?

  /// If decoding should fail on invalid padding.
  public let strictPadding: Bool

  /// If the decoding is case insensitive.
  public let caseInsensitive: Bool

  /// Internal lookup table for encoding.
  fileprivate let lookup: [UInt8: Character]

  /// Internal reverse lookup table for decoding.
  fileprivate let reverseLookup: [Character: UInt8]

  /// Initialized a new base encoding.
  ///
  /// - Parameters:
  ///  - alphabet: The alphabet used for encoding.
  ///  - padding: The padding character used, if any.
  ///  - strictPadding: If decoding should fail on invalid padding.
  ///  - caseInsensitive: If the decoding is case insensitive.
  /// - Returns: A new base encoding instance.
  public init(
    alphabet: String,
    padding: Character?,
    strictPadding: Bool,
    caseInsensitive: Bool
  ) {
    self.init(
      alphabet: Array(alphabet),
      padding: padding,
      strictPadding: strictPadding,
      caseInsensitive: caseInsensitive
    )
  }

  /// Initialized a new base encoding.
  ///
  /// - Parameters:
  ///  - alphabet: The alphabet used for encoding.
  ///  - padding: The padding character used, if any.
  ///  - strictPadding: If decoding should fail on invalid padding.
  ///  - caseInsensitive: If the decoding is case insensitive.
  /// - Returns: A new base encoding instance.
  public init(
    alphabet: [Character],
    padding: Character?,
    strictPadding: Bool,
    caseInsensitive: Bool
  ) {
    let bitsPerChar = Int(log2(Double(alphabet.count)))
    precondition(1 << bitsPerChar == alphabet.count, "Alphabet length must be a power of 2")
    self.alphabet = alphabet
    self.bitsPerChar = bitsPerChar
    self.paddingCharacter = padding
    self.strictPadding = strictPadding
    self.caseInsensitive = caseInsensitive
    self.lookup = Self.buildLookup(for: alphabet)
    self.reverseLookup = Self.buildReverseLookup(for: alphabet, caseInsensitive: caseInsensitive)
  }

  /// Creates a new base encoding witout padding.
  ///
  /// Copies this encoding without padding and disables `strict` mode, unless otherwise specified.
  ///
  /// - Parameter strict: Enable or disable strict mode. Defaults to `false`.
  /// - Returns: A new base encoding instance without padding and the specified strict mode.
  public func unpadded(strict: Bool = false) -> Self {
    return Self(alphabet: alphabet, padding: nil, strictPadding: strict, caseInsensitive: caseInsensitive)
  }

  /// Creates a new base encoding with padding.
  ///
  /// Copies this encoding updating the padding to use the character specified (defaults to `=`). Optionally, strict
  /// padding decoding can be enabled or disabled as well.
  ///
  /// - Parameters:
  ///   - character: The padding character to use. Defaults to `=`.
  ///   - strict: Enable or disable strict padding. Defaults to not altering the current setting.
  /// - Returns: A new base encoding instance with the specified padding and strict mode.
  ///
  public func padded(character: Character = "=", strict: Bool? = nil) -> Self {
    return Self(
      alphabet: alphabet,
      padding: character,
      strictPadding: strict ?? strictPadding,
      caseInsensitive: caseInsensitive
    )
  }

  /// Creates a new base encoding with the specified strict padding mode.
  ///
  /// - Parameter enabled: Enable or disable strict padding. Defaults to `true`.
  /// - Returns: A new base encoding instance with the specified strict padding mode.
  ///
  public func strictPadding(_ enabled: Bool = true) -> Self {
    return Self(
      alphabet: alphabet,
      padding: paddingCharacter,
      strictPadding: enabled,
      caseInsensitive: caseInsensitive
    )
  }

  /// Creates a new base encoding with lenient padding decoding.
  ///
  /// - Parameter enabled: Enable or disable lenient padding. Defaults to `true`.
  /// - Returns: A new base encoding instance with lenient padding decoding.
  ///
  public func lenientPadding(_ enabled: Bool = true) -> Self {
    return Self(
      alphabet: alphabet,
      padding: paddingCharacter,
      strictPadding: !enabled,
      caseInsensitive: caseInsensitive
    )
  }

  /// Creates a new base encoding with the specified case insensitive mode.
  ///
  /// - Parameter enabled: Enable or disable case insensitive decoding. Defaults to `true`.
  /// - Returns: A new base encoding instance with the specified case insensitive mode.
  ///
  public func caseInsensitive(_ enabled: Bool = true) -> Self {
    return Self(alphabet: alphabet, padding: paddingCharacter, strictPadding: strictPadding, caseInsensitive: enabled)
  }

  /// Creates a new base encoding with the specified case sensitive mode.
  ///
  /// - Parameter enabled: Enable or disable case sensitive decoding. Defaults to `true`.
  /// - Returns: A new base encoding instance with the specified case sensitive mode.
  ///
  public func caseSensitive(_ enabled: Bool = true) -> Self {
    return Self(
      alphabet: alphabet,
      padding: paddingCharacter,
      strictPadding: strictPadding,
      caseInsensitive: !enabled
    )
  }

  /// Encodes the given data using this base encoding.
  ///
  /// - Parameter data: The data to encode.
  /// - Returns: A string encoded according to this base encoding.
  ///
  public func encode<S: Collection<UInt8>>(data: S) -> String {
    let mask = UInt32((1 << bitsPerChar) - 1)

    var output = ""
    var buffer: UInt32 = 0
    var bufferBits = 0

    for byte in data {
      buffer = (buffer << 8) | UInt32(byte)
      bufferBits += 8

      while bufferBits >= bitsPerChar {
        bufferBits -= bitsPerChar
        let index = UInt8((buffer >> bufferBits) & mask)
        if let char = lookup[index] {
          output.append(char)
        }
      }
    }

    if bufferBits > 0 {
      buffer <<= UInt32(bitsPerChar - bufferBits)
      let index = UInt8(buffer & mask)
      if let char = lookup[index] {
        output.append(char)
      }
    }

    if let paddingChar = paddingCharacter {
      let totalChars = ((data.count * 8) + bitsPerChar - 1) / bitsPerChar
      let paddedLength = ((totalChars + (8 / bitsPerChar) - 1) / (8 / bitsPerChar)) * (8 / bitsPerChar)
      output.append(String(repeating: paddingChar, count: paddedLength - output.count))
    }

    return output
  }

  /// Returns the number of decoded bytes for the given base-encoded string without allocating.
  ///
  /// This performs padding validation when `strictPadding` is enabled, but does not validate characters.
  /// - Parameter string: The base encoded string to size.
  /// - Returns: The number of decoded bytes if decodable; otherwise throws.
  /// - Throws: `DecodeError` if the string or padding does not match requirements of the encoding.
  ///
  public func decodedSize(of string: String) throws -> Int {
    // Remove padding characters for sizing; character validity checked during decode
    let padChar = paddingCharacter
    let unpaddedCount = padChar == nil ? string.count : string.reduce(0) { $1 == padChar ? $0 : $0 + 1 }

    if strictPadding, let padChar {
      let totalChars = string.count
      let block = 8 / bitsPerChar
      let expectedPaddedLength = ((totalChars + block - 1) / block) * block
      if totalChars != expectedPaddedLength { throw DecodeError.invalidPadding }
      if (unpaddedCount * bitsPerChar) % 8 != 0 { throw DecodeError.invalidPadding }
      // also reject too much padding
      let paddingCount = string.reversed().prefix { $0 == padChar }.count
      if paddingCount > block { throw DecodeError.invalidPadding }
    }

    let bits = unpaddedCount * bitsPerChar
    return bits / 8
  }

  /// Decodes the given base encoded string using this base encoding into the provided output span.
  /// - Parameters:
  ///   - string: The base encoded string to decode.
  ///   - out: The destination span to receive decoded bytes. Must have at least `decodedSize(of:)` capacity.
  /// - Throws: ``DecodeError`` if decoding fails.
  public func decode(_ string: String, into out: inout OutputSpan<UInt8>) throws {
    let padChar = paddingCharacter
    // Filter out padding for iteration
    let input = padChar == nil ? string : string.filter { $0 != padChar }

    var buffer: UInt32 = 0
    var bufferBits = 0

    for char in input {
      guard let value = reverseLookup[char] else {
        throw DecodeError.invalidCharacter(char)
      }

      buffer = (buffer << UInt32(bitsPerChar)) | UInt32(value)
      bufferBits += bitsPerChar

      while bufferBits >= 8 {
        bufferBits -= 8
        let byte = UInt8((buffer >> bufferBits) & 0xFF)
        out.append(byte)
      }
    }

    if bufferBits > 0 {
      let leftover = buffer & ((1 << bufferBits) - 1)
      if leftover != 0 { throw DecodeError.invalidTrailingBits }
    }
  }

  private static func buildLookup(for chars: [Character]) -> [UInt8: Character] {
    Dictionary(uniqueKeysWithValues: chars.enumerated().map { (UInt8($0.offset), $0.element) })
  }

  private static func buildReverseLookup(for chars: [Character], caseInsensitive: Bool) -> [Character: UInt8] {
    var reverseLookup: [Character: UInt8] = [:]
    for (i, char) in chars.enumerated() {
      reverseLookup[char] = UInt8(i)
      if caseInsensitive {
        reverseLookup[Character(char.lowercased())] = UInt8(i)
        reverseLookup[Character(char.uppercased())] = UInt8(i)
      }
    }
    return reverseLookup
  }
}
