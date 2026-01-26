//
//  YAML.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// YAML format utilities.
public enum YAML {

  public protocol Error: FormatError {}

  /// Errors related to data encountered during reading/writing.
  public enum DataError: Error {
    /// Input data was not valid for the required encoding.
    case invalidEncoding(String.Encoding)
  }

  /// Errors emitted by the YAML readers and writers.
  public enum ParseError: Error {

    /// Source relative location that generated an error.
    public struct Location: Sendable, Equatable {
      public let line: Int
      public let column: Int

      public init(line: Int, column: Int) {
        self.line = line
        self.column = column
      }
    }

    /// The YAML syntax was invalid for the current parsing context.
    case invalidSyntax(String, location: Location?)
    /// The indentation for a block could not be determined.
    case invalidIndentation(location: Location?)
    /// An alias referenced an anchor that was not defined.
    case unresolvedAlias(String)
    /// An anchor was defined more than once.
    case duplicateAnchor(String)
  }

  /// Errors emitted by YAML writers and emitters.
  public enum EmitError: Error {

    case invalidState(String)
    case invalidEvent(String)
  }

  /// YAML text format.
  public enum Format: SolidData.Format, Sendable {
    case instance

    public var kind: FormatKind { .text }

    public func supports(type: ValueType) -> Bool {
      true
    }
  }

  /// Shared format instance.
  public static let format = Format.instance
}


extension YAML.Error {

  public var format: YAML.Format { .instance }

}
