//
//  Pointer-ReferenceToken.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/31/25.
//

extension Pointer {

  /// A reference token in a JSON Pointer.
  ///
  /// Reference tokens are used to navigate through a JSON document's structure.
  /// They can represent object property names, array indices, or the append operation.
  public enum ReferenceToken {
    /// A reference to an object property by name
    case name(String)
    /// A reference to an array element by index
    case index(Int)
    /// A reference to the append position in an array
    case append
  }

}

extension Pointer.ReferenceToken: Sendable {}

extension Pointer.ReferenceToken: Hashable {}

extension Pointer.ReferenceToken: Equatable {}

extension Pointer.ReferenceToken: CustomStringConvertible {

  /// A textual representation of this reference token.
  ///
  /// - For `.name` tokens, returns the name, quoted if it contains special characters
  /// - For `.index` tokens, returns the index as a string
  /// - For `.append` tokens, returns "-"
  public var description: String {
    switch self {
    case .name(let name):
      return if name.contains(#/[/~]/#) {
        "\"\(name)\""
      } else {
        name
      }
    case .index(let index):
      return index.description
    case .append:
      return "-"
    }
  }
}

extension Pointer.ReferenceToken: CustomDebugStringConvertible {

  public var debugDescription: String {
    switch self {
    case .name(let name):
      return name.debugPointerEncoded
    case .index(let index):
      return index.description
    case .append:
      return "-"
    }
  }
}

extension Pointer.ReferenceToken {

  /// Creates a reference token from its encoded string representation, or `nil` if the string is invalid.
  ///
  /// - Parameters:
  ///   - string: The encoded string representation
  ///   - strict: Whether to enforce strict parsing rules
  ///     Currrently affects:
  ///     - `~` escaping rules (strict mode fails when `~` is not followed by 0 or 1)
  ///
  public init?(encoded string: String, strict: Bool = Pointer.strict) {
    do {
      try self.init(validating: string, strict: strict)
    } catch {
      return nil
    }
  }

  private static nonisolated(unsafe) let replaceRegex = #/[~/]/#

  /// The encoded string representation of this reference token.
  ///
  /// - For `.name` tokens, returns the name with special characters escaped
  /// - For `.index` tokens, returns the index as a string
  /// - For `.append` tokens, returns "-"
  public var encoded: String {
    switch self {
    case .name(let name):
      return name.pointerEncoded
    case .index(let index):
      return index.description
    case .append:
      return "-"
    }
  }
}

extension Pointer.ReferenceToken {

  /// Creates a reference token from its string representation, throwing an error if invalid.
  ///
  /// - Parameters:
  ///   - string: The string representation of the reference token
  ///   - strict: Whether to enforce strict parsing rules
  ///     Currrently affects:
  ///     - `~` escaping rules (strict mode fails when `~` is not followed by 0 or 1)
  /// - Throws: An error if the string is not a valid reference token representation
  ///
  public init(validating string: String, strict: Bool = Pointer.strict) throws {
    if string.isEmpty {
      self = .name("")
      return
    } else if string == "-" {
      self = .append
    } else if string == "0" || string.first != "0", let index = Int(string, radix: 10) {
      self = .index(index)
    } else {
      var value = ""
      var index = string.startIndex
      let lastIndex = string.index(before: string.endIndex)

      func fail(_ details: String, offset: Int = 0) throws -> Never {
        throw Pointer.Error.invalidReferenceToken(
          string,
          position: string.distance(from: string.startIndex, to: index) + offset,
          details: details
        )
      }

      while index < string.endIndex {
        switch string[index] {
        case "~":
          if index >= lastIndex {
            // ~ escaping "nothing" is not well defined...
            guard !strict else {
              try fail("~ at end of string is not well defined by RFC 6901. Disallowed in strict mode.")
            }
            // Treat as literal ~
            value += "~"
          } else {
            let nextIndex = string.index(after: index)
            switch string[nextIndex] {
            case "0":
              value += "~"
            case "1":
              value += "/"
            case let nextChar:
              // ~ escaping anything but 0 or 1 is not well defined...
              guard !strict else {
                try fail(
                  "~ escaping anything but 0 or 1 is not well defined by RFC 6901. Disallowed in strict mode.",
                  offset: 1
                )
              }
              // Treat as literal ~ (aligns with Jackson 2.19+ behavior)
              value += "~"
              value += String(nextChar)
            }
            index = nextIndex
          }

        case "\u{0000}"..."\u{002E}", "\u{0030}"..."\u{007D}", "\u{007F}"..."\u{10FFFF}":
          value.append(string[index])
        default:
          try fail("Invalid character in reference token: \(string[index])")
        }
        index = string.index(after: index)
      }
      self = .name(value)
    }
  }

}

extension Pointer.ReferenceToken: ExpressibleByStringLiteral {

  fileprivate nonisolated(unsafe) static let encodedRegex = #/~[01]/#

  /// Creates a reference token from a string literal.
  ///
  /// If the string contains `~0` or `~1`, it is treated as an encoded reference token.
  /// Otherwise, it is treated as a literal reference token by encoding `~` and `/`
  /// before validating.
  ///
  /// - Parameter value: The string literal
  /// - Precondition: The string must be a valid reference token representation
  ///
  public init(stringLiteral value: String) {
    let encoded =
      if value.contains(Self.encodedRegex) {
        value
      } else {
        value.pointerEncoded
      }
    do {
      try self.init(validating: encoded)
    } catch {
      fatalError("Invalid literal Pointer Reference Token: \(error.localizedDescription)")
    }
  }
}

extension Pointer.ReferenceToken: ExpressibleByIntegerLiteral {

  /// Creates a reference token from an integer literal.
  ///
  /// This creates an index token with the given value.
  ///
  /// - Parameter value: The integer literal
  public init(integerLiteral value: Int) {
    self = .index(value)
  }
}

private nonisolated(unsafe) let encodingRegex = #/[~/]/#

extension String {

  fileprivate var pointerEncoded: String {
    return self.replacing(
      encodingRegex,
      with: { match in
        return switch match.output {
        case "~": "~0"
        case "/": "~1"
        default: String(match.output)
        }
      }
    )
  }

  /// Returns a debug representation of the string with characters that
  /// need escaping in JSON Pointers underlined using Unicode combining characters.
  ///
  /// Tokens requiring escaping are underlined using Unicode combining characters.
  ///
  public var debugPointerEncoded: String {
    guard self.contains(encodingRegex) else {
      return self
    }
    return map { "\($0)\u{0332}" }.joined(separator: "")
  }
}
