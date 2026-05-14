//
//  Format.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/10/26.
//

public protocol Format: Sendable {

  /// Kind of the format (`text` or `binary`).
  var kind: FormatKind { get }

  /// Does this format support the type without conversion.
  ///
  /// - Parameter type: Type of value to check support for.
  /// - Returns: `true` if the reader supports directly reading values of `type`.
  ///
  func supports(type: ValueType) -> Bool

}
