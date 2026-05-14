//
//  JSON.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//

import SolidData

public enum JSON {

  /// Errors throws during serialization and deserialization.
  ///
  /// + Note: These are informational only, all errors are
  /// fatal and represent corrupted data; no recovery is
  /// possible
  public enum Error: FormatError {
    /// End of data stream unexpectedly encountered during deserialization
    case unexpectedEndOfStream
    /// An invalid UTF-8 `string` sequence was encountered during deserialization
    case invalidUTF8String
    /// Invalid tag was encountered during serialization
    ///
    /// JSON tags must be a string. Passing any other value
    /// will result in this error.
    case invalidTagType
    /// An invalid token was encountered during parsing
    case invalidToken
    /// An invalid string was encountered (e.g., unescaped control character)
    case invalidString
    /// An invalid number was encountered during parsing
    case invalidNumber
    /// An invalid escape sequence was encountered in a string
    case invalidEscapeSequence
    /// A structural error in the JSON (e.g., mismatched brackets, extra data)
    case invalidStructure(String)
  }

  public enum Format: SolidData.Format, Sendable {
    case instance

    public var kind: FormatKind { .text }

    public func supports(type: ValueType) -> Bool {
      type != .bytes
    }
  }

  public static let format = Format.instance

}


extension JSON.Error {

  public var format: JSON.Format { .instance }

}
