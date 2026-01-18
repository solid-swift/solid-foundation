//
//  Cast.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/4/25.
//

/// Explicit, and purposefully verbose, force casts value of type ``V`` to type ``T``.
///
/// This is a more verbose version of the `as!` operator, for situations where the
/// case is known to be valid, but the compiler cannot prove it. In addition to being
/// more verbose, it allows providing a more specific error message which defaults
/// to a detailed message including the attempted cast.
///
/// This is especially usefull for codebases that have banned  general use of `as!`.
///
package func knownSafeCast<T, V>(
  _ value: V,
  to type: T.Type = T.self,
  message: String? = nil,
  _ file: StaticString = #file,
  _ line: UInt = #line
) -> T {
  guard let castedValue = value as? T else {
    fatalError(message ?? "Cast marked known to be safe failed, casting \(value) to \(T.self)", file: file, line: line)
  }
  return castedValue
}
