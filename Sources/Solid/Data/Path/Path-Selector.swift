//
//  Path-Selector.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/28/25.
//

extension Path {

  /// Selects values from the current value being processed.
  ///
  public enum Selector {

    /// Selects values by name from `object` values.
    case name(String, quote: Character? = nil)

    /// Selects all values from arrays or objects.
    case wildcard

    /// Selects a range of values from an array.
    case slice(Slice)

    /// Selects  that selects a specific value from an array.
    case index(Int)

    /// Selects a values that pass the filter expressions.
    case filter(Expression)
  }

}

extension Path.Selector: Sendable {}

extension Path.Selector: Hashable {

  /// Hashes the essential components of the selector.
  ///
  /// - Note: `quote` property for ``name(_:quote:)`` selectors are not considered.
  ///
  /// - Parameters:
  ///  - hasher: The hasher to use for hashing the selector.
  ///
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .name(let name, quote: _):
      hasher.combine(0)
      hasher.combine(name)
    case .wildcard:
      hasher.combine(1)
    case .slice(let slice):
      hasher.combine(2)
      hasher.combine(slice)
    case .index(let index):
      hasher.combine(3)
      hasher.combine(index)
    case .filter(let expression):
      hasher.combine(4)
      hasher.combine(expression)
    }
  }
}

extension Path.Selector: Equatable {

  /// Compares two selectors for equality.
  ///
  /// - Note: `quote` property for ``name(_:quote:)`` selectors are not considered.
  ///
  /// - Parameters:
  ///   - lhs: The left-hand side selector.
  ///   - rhs: The right-hand side selector.
  /// - Returns: `true` if the selectors are equal, `false` otherwise.
  ///
  public static func == (lhs: Path.Selector, rhs: Path.Selector) -> Bool {
    switch (lhs, rhs) {
    case (.name(let lhsName, quote: _), .name(let rhsName, quote: _)):
      return lhsName == rhsName
    case (.wildcard, .wildcard):
      return true
    case (.slice(let lhsSlice), .slice(let rhsSlice)):
      return lhsSlice == rhsSlice
    case (.index(let lhsIndex), .index(let rhsIndex)):
      return lhsIndex == rhsIndex
    case (.filter(let lhsExpression), .filter(let rhsExpression)):
      return lhsExpression == rhsExpression
    default:
      return false
    }
  }
}

extension Path.Selector: CustomStringConvertible {

  /// A description of the selector.
  ///
  public var description: String {
    switch self {
    case .name(let name, quote: let quote):
      return if let quote {
        "\(String(quote))\(name.escaped(quote))\(String(quote))"
      } else {
        name
      }
    case .wildcard:
      return "*"
    case .slice(let slice):
      return slice.description
    case .index(let index):
      return index.description
    case .filter(let expression):
      return "?\(expression.description)"
    }
  }
}

extension Array where Element == Path.Selector {

  internal var solidDescription: String {
    "\(self.map(\.description).joined(separator: ", "))"
  }

}

private nonisolated(unsafe) let singleQuoteRegex = #/'/#
private nonisolated(unsafe) let doubleQuoteRegex = #/"/#

extension String {

  internal func escaped(_ quote: Character) -> String {
    var string = self
    for match in string.matches(of: quote == "'" ? singleQuoteRegex : doubleQuoteRegex) {
      string.replaceSubrange(match.range, with: #"\\#(quote)"#)
    }
    return string
  }

}
