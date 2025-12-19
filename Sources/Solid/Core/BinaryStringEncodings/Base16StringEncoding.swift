//
//  Base16StringEncoding.swift
//

/// A base-16 (hexadecimal) binary-to-text codec.
///
/// Base-16 (hex) encoding represents each input byte as two ASCII digits using the
/// alphabet 0–9 and A–F/a–f. This implementation:
/// - Supports lowercase or uppercase digits via ``init(lowercase:)``
/// - Produces and accepts strings with even length only
/// - Throws on any non-hex character
///
/// Example
/// ```swift
/// let base16 = Base16Encoding(lowercase: true)
/// let encoded = base16.encode([0xDE, 0xAD, 0xBE, 0xEF])
/// // "deadbeef"
/// let decoded: [UInt8] = try base16.decode(encoded)
/// // decoded == [0xDE, 0xAD, 0xBE, 0xEF]
/// ```
public struct Base16StringEncoding: BinaryStringEncoding {

  public static let `default` = Self()

  /// Errors that can occur while decoding hexadecimal strings.
  ///
  public enum Error: Swift.Error {
    /// The input contains an odd number of characters.
    case invalidLength
    /// The input contains a non-hex digit at the given character index.
    case invalidCharacter(at: Int)
  }

  private let digits: [UInt8]

  /// Creates a base-16 (hexadecimal) encoder/decoder.
  ///
  /// - Parameter lowercase: When `true`, uses lowercase digits ("abcdef"). When `false`,
  ///   uses uppercase digits ("ABCDEF").
  /// - Important: Decoding expects the same case as configured here. For example, an
  ///   instance initialized with `lowercase: true` will reject uppercase hex letters.
  public init(lowercase: Bool = true) {
    self.digits = lowercase ? Self.lowecaseDigits : Self.uppercaseDigits
  }

  /// Encodes the provided bytes as a base-16 (hexadecimal) string using this instance's digit case.
  ///
  /// - Parameter bytes: The input bytes to encode.
  /// - Returns: A string containing two hex digits per input byte.
  /// - Complexity: O(n), where n is `bytes.count`.
  public func encode(_ bytes: some Collection<UInt8>) -> String {
    String(unsafeUninitializedCapacity: bytes.count * 2) { buffer in
      for (byteIdx, byte) in bytes.enumerated() {
        let bufferIdx = byteIdx * 2
        buffer.initializeElement(at: bufferIdx, to: digits[Int(byte >> 4)])
        buffer.initializeElement(at: bufferIdx + 1, to: digits[Int(byte & 0x0F)])
      }
      return bytes.count * 2
    }
  }

  /// Computes the number of bytes that would result from decoding the given base-16 (hex) string.
  ///
  /// - Parameter string: The hex string to examine.
  /// - Returns: `string.count / 2` when the input has even length.
  /// - Throws: ``HexEncoding/Error/invalidLegth`` if the input length is odd.
  public func decodedSize(of string: String) throws(Error) -> Int {
    if !string.count.isMultiple(of: 2) {
      throw .invalidLength
    }
    return string.count / 2
  }

  /// Decodes a base-16 (hexadecimal) string into the supplied output span.
  ///
  /// The input must have even length, and every character must be a valid hex digit
  /// in this instance's configured case (lowercase or uppercase).
  ///
  /// - Parameters:
  ///   - string: The hex string to decode.
  ///   - bytes: The destination span that receives the decoded bytes. It must have
  ///     capacity for ``decodedSize(of:)`` bytes.
  /// - Throws: ``HexEncoding/Error/invalidLegth`` if the input length is odd, or
  ///   ``HexEncoding/Error/invalidCharacter(at:)`` if a non-hex character is encountered.
  /// - Complexity: O(n).
  public func decode(_ string: String, into bytes: inout OutputSpan<UInt8>) throws(Error) {

    func digitValue(_ char: UInt8) -> UInt8? {
      if char >= digits[0] && char <= digits[9] {
        return char - digits[0]
      } else if char >= digits[10] && char <= digits[15] {
        return char - digits[10] + 10
      } else {
        return nil
      }
    }

    let decodedSize = try self.decodedSize(of: string)
    if bytes.capacity < decodedSize {
      throw Error.invalidLength
    }

    let utf8 = string.utf8
    let end = utf8.endIndex
    var index = utf8.startIndex

    while index < end {

      guard let firstDigitValue = digitValue(utf8[index]) else {
        throw .invalidCharacter(at: string.distance(from: utf8.startIndex, to: index))
      }
      index = utf8.index(after: index)

      guard let secondDigitValue = digitValue(utf8[index]) else {
        throw .invalidCharacter(at: string.distance(from: utf8.startIndex, to: index))
      }
      index = utf8.index(after: index)

      bytes.append((firstDigitValue << 4) | secondDigitValue)
    }
  }

  private static let lowecaseDigits = Array("0123456789abcdef".utf8)
  private static let uppercaseDigits = Array("0123456789ABCDEF".utf8)
}
