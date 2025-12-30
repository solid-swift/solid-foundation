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
  /// - Padding character: None
  /// - Strict padding: `false`
  /// - Case insensitive: `false`
  ///
  public static let base64Url = Self(
    alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_",
    padding: nil,
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

  /// True when the alphabet size is a power of two (2, 4, 8, 16, 32, 64, ...).
  ///
  /// When true, a faster bit-packing algorithm is used; otherwise a generic base-N conversion is used.
  //
  public let isPowerOfTwoAlphabet: Bool

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

  @inline(__always)
  private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

  @inline(__always)
  private static func lcm(_ a: Int, _ b: Int) -> Int { (a / gcd(a, b)) * b }

  /// Number of output characters in a fully padded block for power-of-two alphabets.
  /// Example: base64 -> 4, base32 -> 8, base16 -> 2
  @inline(__always)
  private static func blockSize(for bitsPerChar: Int) -> Int {
    let blockBits = lcm(8, bitsPerChar)
    return blockBits / bitsPerChar
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
    let count = alphabet.count
    let bitsPerChar = Int(log2(Double(count)))
    self.alphabet = alphabet
    self.bitsPerChar = bitsPerChar
    self.isPowerOfTwoAlphabet = (count & (count &- 1)) == 0 && count > 0
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
    var output = ""

    if isPowerOfTwoAlphabet {

      let mask = UInt32((1 << bitsPerChar) - 1)

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
        let block = Self.blockSize(for: bitsPerChar)
        let paddedLength = ((totalChars + block - 1) / block) * block
        output.append(String(repeating: paddingChar, count: paddedLength - output.count))
      }

    } else {
      // Generic base-N conversion (e.g., base62). Implements conversion from base-256 (bytes)
      // to base-N using repeated division. Preserves leading zero bytes by mapping to the first
      // alphabet character.
      let radix = alphabet.count
      if radix <= 1 || data.isEmpty { return String(repeating: alphabet.first ?? "?", count: data.isEmpty ? 0 : 1) }

      // Copy data into a working buffer (big-endian base-256 digits)
      var digits = Array(data)

      // Count and preserve leading zeros
      let leadingZeroCount = digits.prefix { $0 == 0 }.count
      digits.removeFirst(leadingZeroCount)

      if digits.isEmpty {
        return String(repeating: alphabet[0], count: leadingZeroCount)
      }

      var encodedChars: [Character] = []
      // Repeated division algorithm
      while !digits.isEmpty {
        var quotient: [UInt8] = []
        quotient.reserveCapacity(digits.count)
        var remainder = 0
        var started = false
        for byte in digits {
          let accumulator = remainder * 256 + Int(byte)
          let q = accumulator / radix
          remainder = accumulator % radix
          if started || q != 0 {
            quotient.append(UInt8(truncatingIfNeeded: q))
            started = true
          }
        }
        encodedChars.append(alphabet[remainder])
        digits = quotient
      }

      // Add a character for each leading zero byte
      for _ in 0..<leadingZeroCount { encodedChars.append(alphabet[0]) }

      output = String(encodedChars.reversed())
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

    let size: Int

    if isPowerOfTwoAlphabet {

      // Remove padding characters for sizing; character validity checked during decode
      let padChar = paddingCharacter
      let unpaddedCount = padChar == nil ? string.count : string.reduce(0) { $1 == padChar ? $0 : $0 + 1 }

      if strictPadding, paddingCharacter != nil {
        let totalChars = string.count
        let block = Self.blockSize(for: bitsPerChar)
        let expectedPaddedLength = ((totalChars + block - 1) / block) * block
        if totalChars != expectedPaddedLength { throw DecodeError.invalidPadding }
        // Character validity and trailing zero-bit checks are enforced during decode.
      }

      let bits = unpaddedCount * bitsPerChar
      size = bits / 8

    } else {
      // For non power-of-two alphabets (e.g., base62), compute size by simulating the decode
      // using base-N -> base-256 conversion but counting bytes only.
      let padChar = paddingCharacter
      let input = padChar == nil ? string : string.filter { $0 != padChar }

      // Validate characters and build digit array
      var digits: [Int] = []
      digits.reserveCapacity(input.count)
      for ch in input {
        guard let v = reverseLookup[ch] else { throw DecodeError.invalidCharacter(ch) }
        digits.append(Int(v))
      }
      if digits.isEmpty { return 0 }

      let radix = alphabet.count
      // Count leading zero digits to preserve
      let leadingZeroDigits = input.prefix { $0 == alphabet[0] }.count

      // Simulate multiply-add to count bytes
      var bytes: [UInt8] = []
      for value in digits {
        var carry = value
        for i in 0..<bytes.count {
          let val = Int(bytes[i]) * radix + carry
          bytes[i] = UInt8(truncatingIfNeeded: val & 0xff)
          carry = val >> 8
        }
        while carry > 0 {
          bytes.append(UInt8(truncatingIfNeeded: carry & 0xff))
          carry >>= 8
        }
      }

      size = bytes.count + leadingZeroDigits
    }

    return size
  }

  /// Decodes the given base encoded string using this base encoding into the provided output span.
  /// - Parameters:
  ///   - string: The base encoded string to decode.
  ///   - out: The destination span to receive decoded bytes. Must have at least `decodedSize(of:)` capacity.
  /// - Throws: ``DecodeError`` if decoding fails.
  public func decode(_ string: String, into out: inout OutputSpan<UInt8>) throws {
    let padChar = paddingCharacter
    // Filter out padding for iteration
    let rawInput = padChar == nil ? string : string.filter { $0 != padChar }

    if isPowerOfTwoAlphabet {
      var buffer: UInt32 = 0
      var bufferBits = 0

      for char in rawInput {
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
    } else {
      // Generic base-N -> base-256 conversion (e.g., base62)
      if rawInput.isEmpty { return }

      let radix = alphabet.count

      // Build digits (values) and validate characters
      var values: [Int] = []
      values.reserveCapacity(rawInput.count)
      for ch in rawInput {
        guard let v = reverseLookup[ch] else { throw DecodeError.invalidCharacter(ch) }
        values.append(Int(v))
      }

      // Count leading zero digits (map to zero bytes)
      let leadingZeroDigits = rawInput.prefix { $0 == alphabet[0] }.count

      // Convert using multiply-add in base 256
      var bytes: [UInt8] = []    // little-endian accumulation
      for v in values {
        var carry = v
        for i in 0..<bytes.count {
          let val = Int(bytes[i]) * radix + carry
          bytes[i] = UInt8(truncatingIfNeeded: val & 0xff)
          carry = val >> 8
        }
        while carry > 0 {
          bytes.append(UInt8(truncatingIfNeeded: carry & 0xff))
          carry >>= 8
        }
      }

      // Append leading zero bytes
      for _ in 0..<leadingZeroDigits { out.append(0) }
      // Output bytes in big-endian order
      for b in bytes.reversed() { out.append(b) }
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
