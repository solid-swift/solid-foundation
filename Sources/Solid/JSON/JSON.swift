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
  public enum Error: Swift.Error {
    /// End of data stream unexpectedly encounteredd during deserialization
    case unexpectedEndOfStream
    /// An invalid UTF-8 `string` sequence was encountered during deserialization
    case invalidUTF8String
    /// Invalid tag was encountered during serialization
    ///
    /// JSON tags must be a string. Passing any other value
    /// will result in this error.
    case invalidTagType
  }

  public enum Format: SolidData.Format, Sendable {
    case instance

    public var kind: FormatKind { .binary }

    public func supports(type: ValueType) -> Bool {
      guard case .bytes = type else { return true }
      return true
    }
  }

  public static let format = Format.instance

}
