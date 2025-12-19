/// A binary-to-text encoding supporting both encoding to and decoding from strings.
///
/// Types that conform to `BinaryStringEncoding` transform raw bytes into a textual
/// representation (for example, Base64 or hexadecimal) and can decode that
/// representation back to the original bytes without loss.
///
/// Implementations provide:
/// - An encoder, ``encode(_:)``
/// - A preflight size calculator, ``decodedSize(of:)``
/// - A zero-allocation decoder that writes into an ``OutputSpan`` via ``decode(_:into:)``
///
/// This protocol also supplies a default convenience ``decode(_:)`` that allocates and returns
/// a new `[UInt8]` array.
///
public protocol BinaryStringEncoding: Sendable {

  /// Encodes an arbitrary collection of bytes into a textual representation.
  ///
  /// - Parameter bytes: The input bytes to encode.
  /// - Returns: The encoded string.
  /// - Complexity: O(n), where n is `bytes.count`.
  func encode(_ bytes: some Collection<UInt8>) -> String

  /// Decodes a textual representation back into its original bytes, allocating
  /// storage for the result.
  ///
  /// - Parameter string: The encoded input string.
  /// - Returns: A newly allocated array containing the decoded bytes.
  /// - Throws: Implementation-defined errors if the input is malformed.
  /// - Complexity: O(n).
  func decode(_ string: String) throws -> [UInt8]

  /// Computes the number of decoded bytes that would result from decoding the
  /// given string, without allocating output storage.
  ///
  /// Implementations may validate input length and padding constraints here and
  /// throw if the input cannot be decoded.
  ///
  /// - Parameter string: The encoded input string.
  /// - Returns: The exact number of bytes that decoding will produce.
  /// - Throws: Implementation-defined errors if the input length or padding is invalid.
  func decodedSize(of string: String) throws -> Int

  /// Decodes the string into the supplied output span.
  ///
  /// Implementations must append exactly ``decodedSize(of:)`` bytes to the span on success.
  ///
  /// - Parameters:
  ///   - string: The encoded input string.
  ///   - into: The destination span that receives the decoded bytes. It must
  ///     have capacity for ``decodedSize(of:)`` bytes.
  /// - Throws: Implementation-defined errors if the input is malformed.
  /// - Complexity: O(n).
  func decode(_ string: String, into: inout OutputSpan<UInt8>) throws
}

extension BinaryStringEncoding {

  /// Default implementation that decodes into a newly allocated `[UInt8]` by
  /// precomputing the output size and delegating to ``decode(_:into:)``.
  ///
  /// - Parameter string: The encoded input string.
  /// - Returns: A newly allocated array containing the decoded bytes.
  /// - Throws: Rethrows any error from the concrete implementation of ``decodedSize(of:)``
  ///   or ``decode(_:into:)``.
  /// - Complexity: O(n).
  public func decode(_ string: String) throws -> [UInt8] {
    let size = try self.decodedSize(of: string)
    return try Array<UInt8>(unsafeUninitializedCapacity: size) { ptr, count in
      var outputSpan = OutputSpan(buffer: ptr, initializedCount: 0)
      try self.decode(string, into: &outputSpan)
      count = outputSpan.finalize(for: ptr)
    }
  }

}
