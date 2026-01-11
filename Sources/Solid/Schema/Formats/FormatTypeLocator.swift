//
//  FormatTypeLocator.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/9/25.
//


/// Locator for ``FormatType`` instances.
///
public protocol FormatTypeLocator: Sendable {

  /// Locates a ``FormatType`` by its identifier.
  ///
  /// - Parameter id: The identifier of the format type to locate.
  /// - Returns: The located ``FormatType`` instance.
  /// - Throws: An error if the format type cannot be located.
  ///
  func locate(formatType id: String) throws -> Schema.FormatType

}
