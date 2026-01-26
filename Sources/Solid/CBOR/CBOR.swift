//
//  CBOR.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//

import SolidData

public enum CBOR {

  /// Errors throws during serialization and deserialization.
  ///
  /// + Note: These are informational only, all errors are
  /// fatal and represent corrupted data; no recovery is
  /// possible
  public enum Error: FormatError {
    /// End of data stream unexpectedly encounteredd during deserialization
    case unexpectedEndOfStream
    /// Invalid item type was encountered during deserialization
    case invalidItemType
    /// Invalid indefinite sequence item was encountered during deserialization
    /// + Important: `string` and `byte-string` that are indefinitely encoded
    /// must only contains items of their corresponding type. E.g. An indefinite
    /// `string` must only contain other `strings`
    case invalidIndefiniteElement
    /// Invalid `break` item encountered during deserialization
    case invalidBreak
    /// A sequence with more than `Int32.max` items was encountered during
    /// deserialization
    case sequenceTooLong
    /// An invalid UTF-8 `string` sequence was encountered during deserialization
    case invalidUTF8String
    /// Invalid integer size indicator
    case invalidIntegerSize
    /// An undefined item was encountered during deserialization
    ///
    /// - Note: This can be suppressed by setting ``CBORReader/Options/undefined``
    /// to ``CBORReader/Options/Undefined/convertToNull``.
    ///
    case undefinedItem
    /// Invalid tag was encountered during serialization
    ///
    /// CBOR tags must be an unsigned integer. Passing any other value
    /// will result in this error.
    case invalidTagType
    /// The CBOR value is unsupported
    case unsupportedValue
  }

  /// A CBOR value with an optional tag.
  public typealias Value = (value: SolidData.Value, tag: UInt64?)

  public enum Format: SolidData.Format, Sendable {
    case instance

    public var kind: FormatKind { .binary }

    public func supports(type: ValueType) -> Bool {
      return true
    }
  }

  public static let format = Format.instance

}


extension CBOR.Error {

  public var format: CBOR.Format { .instance }

}
