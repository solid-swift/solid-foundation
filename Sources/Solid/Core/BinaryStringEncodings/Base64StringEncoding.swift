//
//  Base64StringEncoding.swift
//

/// A configurable Base64 encoder/decoder.
///
/// This implementation supports the standard and URL-safe alphabets, with optional
/// padding and strict padding validation. It can encode any collection of bytes and
/// decode padded or unpadded input according to the instance configuration.
///
/// Features
/// - Standard ("+/") and URL-safe ("-_") alphabets
/// - Optional padding ("=") emission and acceptance
/// - Strict padding rules when desired
/// - Zero-allocation decoding into an ``OutputSpan``
///
/// Example
/// ```swift
/// // Standard alphabet with padding (default)
/// let b64 = Base64Encoding()
/// let s = b64.encode([0x01, 0x02, 0x03]) // "AQID"
/// let roundtrip = try b64.decode(s)      // [1, 2, 3]
///
/// // URL-safe, no padding
/// let b64url = Base64Encoding(urlSafe: true, padding: false)
/// let s2 = b64url.encode([0xFF, 0xEF])   // "_-8" (no '=')
/// let rt2 = try b64url.decode(s2)        // [255, 239]
/// ```
///
public struct Base64StringEncoding: BinaryStringEncoding {

  public static let `default` = Self()
  public static let urlSafe = Self(urlSafe: true)

  /// Errors that can occur while decoding Base64 text.
  ///
  public enum Error: Swift.Error {
    /// The input length is invalid for the current configuration (for example,
    /// not a multiple of 4 when padding is required, or a single trailing character in
    /// unpadded mode).
    case invalidLength
    /// An input character is not part of the selected Base64 alphabet.
    case invalidCharacter(at: Int)
    /// Padding ("=") appears in an invalid position for the current configuration.
    case invalidPadding
  }

  // MARK: - Alphabets

  private static let standardAlphabet: [UInt8] =
    Array(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
    )
  private static let urlSafeAlphabet: [UInt8] =
    Array(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8
    )

  private static func makeReverseTable(for alphabet: [UInt8]) -> [Int8] {
    var table = Array(repeating: Int8(-1), count: 256)
    for (i, b) in alphabet.enumerated() {
      table[Int(b)] = Int8(i)
    }
    return table
  }

  // MARK: - Configuration

  /// The active Base64 alphabet for this instance.
  ///
  /// This is either the standard alphabet ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
  /// or the URL-safe alphabet ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").
  public let alphabet: [UInt8]
  private let reverse: [Int8]
  private let paddingChar: UInt8?
  private let strictPadding: Bool

  /// Creates a Base64 codec with configurable alphabet and padding behavior.
  ///
  /// - Parameters:
  ///   - urlSafe: When `true`, uses the URL-safe alphabet ("-_") instead of the standard ("+/").
  ///   - padding: When `true`, emits and accepts padding ("=") during encoding/decoding.
  ///   - strictPadding: When `true`, decoding enforces valid padding placement and input length
  ///     rules when padding is enabled.
  /// - Note: When `padding` is `false`, decoding accepts unpadded input whose length modulo 4 is 0, 2, or 3.
  public init(urlSafe: Bool = false, padding: Bool = false, strictPadding: Bool = false) {
    let alpha = urlSafe ? Self.urlSafeAlphabet : Self.standardAlphabet
    self.alphabet = alpha
    self.reverse = Self.makeReverseTable(for: alpha)
    self.paddingChar = padding ? UInt8(ascii: "=") : nil
    self.strictPadding = strictPadding
  }

  // MARK: - Encode

  /// Computes the required string capacity to encode the provided input buffer
  /// according to this instance's alphabet and padding configuration.
  ///
  /// - Parameter n: The number of bytes to be encoded.
  /// - Returns: The number of characters required to encode the input.
  public func encodedSize(ofCount n: Int) -> Int {
    let fullGroups = n / 3
    let rem = n % 3

    guard paddingChar == nil else {
      return (fullGroups + (rem > 0 ? 1 : 0)) * 4
    }

    return fullGroups * 4 + (rem == 1 ? 2 : (rem == 2 ? 3 : 0))
  }

  /// Encodes the provided bytes using this instance's alphabet and padding configuration.
  ///
  /// - Parameter bytes: The input bytes to encode.
  /// - Returns: The Base64-encoded string.
  /// - Complexity: O(n), where n is `bytes.count`.
  public func encode(_ bytes: some Collection<UInt8>) -> String {
    let capacity = encodedSize(ofCount: bytes.count)
    return String(unsafeUninitializedCapacity: capacity) { out in
      var outIndex = 0

      // Fast path: try contiguous storage
      if let buf = bytes.withContiguousStorageIfAvailable({ $0 }) {
        var i = 0
        let count = buf.count
        // Process full groups
        while i + 2 < count {
          let b0 = UInt32(buf[i])
          let b1 = UInt32(buf[i + 1])
          let b2 = UInt32(buf[i + 2])
          i += 3
          let v = (b0 << 16) | (b1 << 8) | b2
          out.initializeElement(at: outIndex + 0, to: alphabet[Int((v >> 18) & 0x3F)])
          out.initializeElement(at: outIndex + 1, to: alphabet[Int((v >> 12) & 0x3F)])
          out.initializeElement(at: outIndex + 2, to: alphabet[Int((v >> 6) & 0x3F)])
          out.initializeElement(at: outIndex + 3, to: alphabet[Int(v & 0x3F)])
          outIndex += 4
        }
        let remaining = count - i
        if remaining == 1 {
          let b0 = UInt32(buf[i])
          let v = b0 << 16
          out.initializeElement(at: outIndex + 0, to: alphabet[Int((v >> 18) & 0x3F)])
          out.initializeElement(at: outIndex + 1, to: alphabet[Int((v >> 12) & 0x3F)])
          if let pad = paddingChar {
            out.initializeElement(at: outIndex + 2, to: pad)
            out.initializeElement(at: outIndex + 3, to: pad)
            outIndex += 4
          } else {
            outIndex += 2
          }
        } else if remaining == 2 {
          let b0 = UInt32(buf[i])
          let b1 = UInt32(buf[i + 1])
          let v = (b0 << 16) | (b1 << 8)
          out.initializeElement(at: outIndex + 0, to: alphabet[Int((v >> 18) & 0x3F)])
          out.initializeElement(at: outIndex + 1, to: alphabet[Int((v >> 12) & 0x3F)])
          out.initializeElement(at: outIndex + 2, to: alphabet[Int((v >> 6) & 0x3F)])
          if let pad = paddingChar {
            out.initializeElement(at: outIndex + 3, to: pad)
            outIndex += 4
          } else {
            outIndex += 3
          }
        }
      } else {
        // Generic iterator path
        var it = bytes.makeIterator()
        // Process full groups
        while true {
          guard let b0_ = it.next() else { break }
          guard let b1_ = it.next() else {
            // 1 trailing
            let v = UInt32(b0_) << 16
            out.initializeElement(at: outIndex + 0, to: alphabet[Int((v >> 18) & 0x3F)])
            out.initializeElement(at: outIndex + 1, to: alphabet[Int((v >> 12) & 0x3F)])
            if let pad = paddingChar {
              out.initializeElement(at: outIndex + 2, to: pad)
              out.initializeElement(at: outIndex + 3, to: pad)
              outIndex += 4
            } else {
              outIndex += 2
            }
            return outIndex
          }
          guard let b2_ = it.next() else {
            // 2 trailing
            let v = (UInt32(b0_) << 16) | (UInt32(b1_) << 8)
            out.initializeElement(at: outIndex + 0, to: alphabet[Int((v >> 18) & 0x3F)])
            out.initializeElement(at: outIndex + 1, to: alphabet[Int((v >> 12) & 0x3F)])
            out.initializeElement(at: outIndex + 2, to: alphabet[Int((v >> 6) & 0x3F)])
            if let pad = paddingChar {
              out.initializeElement(at: outIndex + 3, to: pad)
              outIndex += 4
            } else {
              outIndex += 3
            }
            return outIndex
          }
          let v = (UInt32(b0_) << 16) | (UInt32(b1_) << 8) | UInt32(b2_)
          out.initializeElement(at: outIndex + 0, to: alphabet[Int((v >> 18) & 0x3F)])
          out.initializeElement(at: outIndex + 1, to: alphabet[Int((v >> 12) & 0x3F)])
          out.initializeElement(at: outIndex + 2, to: alphabet[Int((v >> 6) & 0x3F)])
          out.initializeElement(at: outIndex + 3, to: alphabet[Int(v & 0x3F)])
          outIndex += 4
        }
      }
      return outIndex
    }
  }

  // MARK: - Decoded size

  /// Computes the number of bytes that would result from decoding the given Base64 string.
  ///
  /// This validates length and padding according to the instance configuration, and throws
  /// if the input cannot be decoded.
  ///
  /// - Parameter string: The Base64 input string.
  /// - Returns: The exact number of decoded bytes on success.
  /// - Throws: ``Base64Encoding/Error/invalidLength`` if the length is incompatible with the configuration.
  ///
  public func decodedSize(of string: String) throws(Error) -> Int {
    let len = string.utf8.count
    guard let pad = paddingChar else {
      // Unpadded length: rem of 1 is invalid
      let rem = len % 4
      guard rem != 1 else { throw .invalidLength }
      return (len / 4) * 3 + (rem == 2 ? 1 : (rem == 3 ? 2 : 0))
    }
    // Length must be a multiple of 4 when padding is enabled
    guard len % 4 == 0 else { throw .invalidLength }
    // Count trailing '=' up to 2
    var padCount = 0
    let utf8 = string.utf8
    var idx = utf8.endIndex
    if idx > utf8.startIndex {
      idx = utf8.index(before: idx)
      if utf8[idx] == pad { padCount += 1 }
      if padCount == 1 && idx > utf8.startIndex {
        let idx2 = utf8.index(before: idx)
        if utf8[idx2] == pad { padCount += 1 }
      }
    }
    return (len / 4) * 3 - padCount
  }

  // MARK: - Decode

  /// Decodes a Base64 string into the supplied output span.
  ///
  /// The behavior depends on the configuration provided at initialization (alphabet, padding,
  /// and strict padding rules). On success, exactly ``decodedSize(of:)`` bytes are appended to
  /// the destination span.
  ///
  /// - Parameters:
  ///   - string: The Base64 input string to decode.
  ///   - outBytes: The destination span that receives the decoded bytes. It must have capacity
  ///     for ``decodedSize(of:)`` bytes.
  /// - Throws: ``Base64Encoding/Error`` if the input contains invalid characters, invalid length,
  ///   or invalid padding for the current configuration.
  /// - Complexity: O(n).
  ///
  public func decode(_ string: String, into outBytes: inout OutputSpan<UInt8>) throws(Error) {
    @inline(__always) func val(_ c: UInt8) -> UInt8? {
      let v = reverse[Int(c)]
      return v >= 0 ? UInt8(bitPattern: v) : nil
    }

    let expected = try decodedSize(of: string)
    if outBytes.capacity < expected {
      throw Error.invalidLength
    }

    let utf8 = string.utf8
    var i = utf8.startIndex
    let end = utf8.endIndex

    func take() -> UInt8? {
      guard i < end else { return nil }
      let c = utf8[i]
      i = utf8.index(after: i)
      return c
    }

    if let pad = paddingChar {
      // Padded decoding: process quanta of 4
      while i < end {
        let c0i = utf8.distance(from: utf8.startIndex, to: i)
        guard let c0 = take(), let a = val(c0) else { throw .invalidCharacter(at: c0i) }

        let c1i = utf8.distance(from: utf8.startIndex, to: i)
        guard let c1 = take(), let b = val(c1) else { throw .invalidCharacter(at: c1i) }

        let c2i = utf8.distance(from: utf8.startIndex, to: i)
        guard let c2 = take() else { throw .invalidLength }
        if c2 == pad {
          // Expect exactly one more pad and then end-of-input or next group
          let byte0 = (a << 2) | (b >> 4)
          outBytes.append(byte0)

          guard let c3 = take(), c3 == pad else { throw .invalidPadding }
          // Continue to next group (or end). No more content should follow that changes size expectations.
          continue
        }
        guard let c = val(c2) else { throw .invalidCharacter(at: c2i) }

        let c3i = utf8.distance(from: utf8.startIndex, to: i)
        guard let c3 = take() else { throw .invalidLength }
        if c3 == pad {
          let byte0 = (a << 2) | (b >> 4)
          let byte1 = ((b & 0x0F) << 4) | (c >> 2)
          outBytes.append(byte0)
          outBytes.append(byte1)
          continue
        }
        guard let d = val(c3) else { throw .invalidCharacter(at: c3i) }

        let byte0 = (a << 2) | (b >> 4)
        let byte1 = ((b & 0x0F) << 4) | (c >> 2)
        let byte2 = ((c & 0x03) << 6) | d
        outBytes.append(byte0)
        outBytes.append(byte1)
        outBytes.append(byte2)
      }
    } else {
      // Unpadded decoding
      while i < end {
        let remaining = utf8.distance(from: i, to: end)
        if remaining >= 4 {
          let c0i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c0 = take(), let a = val(c0) else { throw .invalidCharacter(at: c0i) }

          let c1i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c1 = take(), let b = val(c1) else { throw .invalidCharacter(at: c1i) }

          let c2i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c2 = take(), let c = val(c2) else { throw .invalidCharacter(at: c2i) }

          let c3i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c3 = take(), let d = val(c3) else { throw .invalidCharacter(at: c3i) }

          let byte0 = (a << 2) | (b >> 4)
          let byte1 = ((b & 0x0F) << 4) | (c >> 2)
          let byte2 = ((c & 0x03) << 6) | d
          outBytes.append(byte0)
          outBytes.append(byte1)
          outBytes.append(byte2)
        } else if remaining == 2 {
          let c0i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c0 = take(), let a = val(c0) else { throw .invalidCharacter(at: c0i) }

          let c1i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c1 = take(), let b = val(c1) else { throw .invalidCharacter(at: c1i) }

          let byte0 = (a << 2) | (b >> 4)
          outBytes.append(byte0)
        } else if remaining == 3 {
          let c0i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c0 = take(), let a = val(c0) else { throw .invalidCharacter(at: c0i) }

          let c1i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c1 = take(), let b = val(c1) else { throw .invalidCharacter(at: c1i) }

          let c2i = utf8.distance(from: utf8.startIndex, to: i)
          guard let c2 = take(), let c = val(c2) else { throw .invalidCharacter(at: c2i) }

          let byte0 = (a << 2) | (b >> 4)
          let byte1 = ((b & 0x0F) << 4) | (c >> 2)
          outBytes.append(byte0)
          outBytes.append(byte1)
        } else {
          // remaining == 1 is invalid for unpadded
          throw Error.invalidLength
        }
      }
    }

    // Optional strict checks: if strictPadding is enabled and padding was configured,
    // ensure no stray characters followed a padding group. The size pre-check already
    // guards most issues; here we only enforce placement if requested.
    if strictPadding, let pad = paddingChar {
      // If any '=' present, they must only appear in final quartet positions.
      // We do a quick scan to ensure that '=' doesn't appear except as the last 1-2 chars of a quartet.
      var idx = utf8.startIndex
      var quartetPos = 0
      while idx < end {
        let c = utf8[idx]
        if c == pad {
          // Only allowed at positions 2 or 3 of a quartet, and only if no subsequent non-pad chars before quartet end.
          if quartetPos < 2 { throw Error.invalidPadding }
        }
        quartetPos += 1
        if quartetPos == 4 { quartetPos = 0 }
        idx = utf8.index(after: idx)
      }
    }
  }
}
