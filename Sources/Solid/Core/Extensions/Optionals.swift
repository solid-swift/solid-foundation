//
//  Optionals.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/8/25.
//

/// An error produced when an optional value cannot be unwrapped.
public enum OptionalError: Error {

  /// Indicates that an optional expected to contain a value was `nil`.
  case nilUnwrapped(message: String)
}

extension Optional {

  /// Returns the wrapped value or throws an ``OptionalError`` when this optional is `nil`.
  ///
  /// - Parameter message: Message included in the error when this optional is `nil`.
  /// - Returns: The wrapped value.
  /// - Throws: ``OptionalError/nilUnwrapped(message:)`` when this optional is `nil`.
  @inlinable
  public func unwrap(_ message: String? = nil) throws -> Wrapped {
    try unwrap(or: OptionalError.nilUnwrapped(message: message ?? "Attempt to unwrap nil"))
  }

  /// Returns the wrapped value or throws the supplied error when this optional is `nil`.
  ///
  /// - Parameter error: Error produced only when this optional is `nil`.
  /// - Returns: The wrapped value.
  /// - Throws: The supplied error when this optional is `nil`.
  @inlinable
  public func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
    guard let value = self else {
      throw error()
    }
    return value
  }

  /// Returns the wrapped value, terminating when this optional is unexpectedly `nil`.
  ///
  /// Use this only when a program invariant guarantees a value. Prefer ``unwrap(or:)``
  /// when failure can be handled by the caller.
  ///
  /// - Parameters:
  ///   - message: Message reported when the invariant fails.
  ///   - file: Source file containing the assertion.
  ///   - line: Source line containing the assertion.
  /// - Returns: The wrapped value.
  public func neverNil(
    _ message: String = "Unwrap of optional declared as never nil",
    file: StaticString = #file,
    line: UInt = #line
  ) -> Wrapped {
    guard let value = self else {
      fatalError(message, file: file, line: line)
    }
    return value
  }

}

package protocol OptionalConvertible {
  associatedtype Wrapped
  var toOptional: Optional<Wrapped> { get }
}

extension Optional: OptionalConvertible {
  package var toOptional: Optional<Wrapped> { self }
}
