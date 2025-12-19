//
//  Datas.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/3/25.
//

import Foundation

extension Data {

  /// Decodes a base encoded string accordiing to specified encoding.
  ///
  /// - Parameters:
  ///   - string: The base encoded string to decode.
  ///   - encoding: The base encoding to use for decoding.
  ///
  public init?(baseEncodedString string: String, encoding: BaseEncoding) {
    guard let data = encoding.decode(string: string) else {
      return nil
    }
    self = data
  }

  /// Encodes the data using the specified base encoding.
  ///
  /// - Parameter encoding: The base encoding to use for encoding.
  /// - Returns: The base encoded string.
  ///
  public func baseEncoded(using encoding: BaseEncoding) -> String {
    return encoding.encode(data: self)
  }

  /// Base encodings.
  ///
  /// - ``base64``: Base64 encoding.
  /// - ``base64Url``: Base64 URL encoding.
  /// - ``base62``: Base62 encoding.
  /// - ``base32``: Base32 encoding.
  /// - ``base32Hex``: Base32 Hex encoding.
  /// - ``base16``: Base16 (hexadecimal) encoding.
  ///
  public struct BaseEncoding: Sendable {

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
    public func encode(data: Data) -> String {
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

    /// Decodes the given base encoded string using this base encoding.
    ///
    /// - Parameter string: The base encoded string to decode.
    /// - Returns: The decoded data, or `nil` if the decoding fails.
    ///
    public func decode(string: String) -> Data? {
      let unpaddedInput = string.filter { $0 != paddingCharacter }

      // Padding check
      if strictPadding, let padChar = paddingCharacter {
        let paddingCount = string.reversed().prefix { $0 == padChar }.count
        let totalChars = string.count
        let expectedPaddedLength = ((totalChars + (8 / bitsPerChar) - 1) / (8 / bitsPerChar)) * (8 / bitsPerChar)

        if totalChars != expectedPaddedLength {
          return nil    // Padding doesn't match expected length
        }
        if (unpaddedInput.count * bitsPerChar) % 8 != 0 {
          return nil    // Not a full byte
        }
        if paddingCount > (8 / bitsPerChar) {
          return nil    // Too much padding
        }
      }

      var buffer: UInt32 = 0
      var bufferBits = 0
      var output: [UInt8] = []

      for char in unpaddedInput {
        guard let value = reverseLookup[char] else {
          return nil    // Invalid character
        }

        buffer = (buffer << bitsPerChar) | UInt32(value)
        bufferBits += bitsPerChar

        while bufferBits >= 8 {
          bufferBits -= 8
          let byte = UInt8((buffer >> bufferBits) & 0xFF)
          output.append(byte)
        }
      }

      if bufferBits > 0 {
        let leftover = buffer & ((1 << bufferBits) - 1)
        if leftover != 0 {
          return nil    // Invalid trailing bits
        }
      }

      return Data(output)
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
}
