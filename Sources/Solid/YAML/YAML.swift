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

  /// Errors emitted by the YAML readers and writers.
  public enum Error: Swift.Error, Sendable {
    /// Input data was not valid UTF-8.
    case invalidUTF8
    /// The YAML syntax was invalid for the current parsing context.
    case invalidSyntax(String)
    /// The indentation for a block could not be determined.
    case invalidIndentation
    /// An alias referenced an anchor that was not defined.
    case unresolvedAlias(String)
    /// An anchor was defined more than once.
    case duplicateAnchor(String)
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
