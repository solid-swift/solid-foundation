//
//  Pointer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/31/25.
//

import Synchronization

/// A JSON Pointer that can be used to reference a specific location in a JSON document.
///
/// JSON Pointers are defined in RFC 6901 and are used to identify a specific value
/// within a JSON document. They are represented as a sequence of reference tokens
/// that navigate through the document's structure.
///
public struct Pointer {

  /// Whether to enforce strict parsing rules globally.
  ///
  /// When true, the parser will enforce strict rules for reference tokens,
  /// including proper escaping of special characters.
  ///
  /// Currently applies to:
  ///   - `~` escaping rules (strict mode fails when `~` is not followed by 0 or 1)
  ///
  /// - Important: This is a global setting that affects all pointer parsing. It is not
  ///   meant to be used as a per-pointer setting, use `Pointer(validating:strict:)`,
  ///   passing `strict` as true or false as needed.
  ///
  public static var strict: Bool {
    get { lockedStrict.withLock { $0 } }
    set { lockedStrict.withLock { $0 = newValue } }
  }

  private static let lockedStrict = Mutex<Bool>(true)

  /// The type of a sequence of reference tokens.
  ///
  public typealias ReferenceTokens = Array<ReferenceToken>

  /// The sequence of reference tokens that make up this pointer.
  ///
  public let tokens: ReferenceTokens

  /// Creates a new pointer from a sequence of reference tokens.
  ///
  /// - Parameter tokens: The sequence of reference tokens
  ///
  public init<S: Sequence>(tokens: S) where S.Element == ReferenceToken {
    self.tokens = Array(tokens)
  }

  /// Creates a new pointer from a variadic list of reference tokens.
  ///
  /// - Parameter tokens: The reference tokens
  ///
  public init(tokens: ReferenceToken...) {
    self.tokens = tokens
  }

  /// The parent pointer of this pointer.
  ///
  /// This is equivalent to dropping the last token from the pointer.
  ///
  public var parent: Pointer {
    dropping(count: 1)
  }

  /// Creates a new pointer by dropping the specified number of tokens from the end.
  ///
  /// - Parameter count: The number of tokens to drop
  /// - Returns: A new pointer with the specified tokens removed
  public func dropping(count: Int) -> Pointer {
    Pointer(tokens: Array(tokens.dropLast(count)))
  }

  /// Creates a new pointer by appending a sequence of tokens.
  ///
  /// - Parameter tokens: The tokens to append
  /// - Returns: A new pointer with the tokens appended
  public func appending(tokens: ReferenceTokens) -> Pointer {
    Pointer(tokens: self.tokens + tokens)
  }

  /// Creates a new pointer by appending a variadic list of tokens.
  ///
  /// - Parameter tokens: The tokens to append
  /// - Returns: A new pointer with the tokens appended
  public func appending(tokens: ReferenceToken...) -> Pointer {
    appending(tokens: tokens)
  }

  /// Creates a new pointer by appending another pointer.
  ///
  /// - Parameter pointer: The pointer to append
  /// - Returns: A new pointer with the tokens from the other pointer appended
  public func appending(pointer: Pointer) -> Pointer {
    appending(tokens: pointer.tokens)
  }

  /// Creates a new pointer by appending a string representation of a pointer.
  ///
  /// - Parameter string: The string representation of the pointer to append
  /// - Returns: A new pointer with the tokens from the string appended
  /// - Throws: An error if the string is not a valid pointer representation
  public func appending(string: String) throws -> Pointer {
    appending(pointer: try Pointer(validating: string))
  }

  /// Returns the first token and a pointer to the remaining tokens.
  ///
  /// - Returns: A tuple containing the first token and a pointer to the remaining tokens,
  ///            or nil if there are no tokens
  public func descend() -> (ReferenceToken, Pointer)? {
    guard let token = tokens.first else {
      return nil
    }
    return (token, Pointer(tokens: tokens.dropFirst()))
  }

  /// The root pointer, which has no tokens.
  public static let root = Pointer(tokens: [])

}

extension Pointer: Sendable {}

extension Pointer: Hashable {}

extension Pointer: Equatable {}

extension Pointer: CustomStringConvertible, CustomDebugStringConvertible {

  /// A string representation of this pointer.
  ///
  /// This is the encoded form of the pointer, which can be used to create a new pointer.
  public var description: String {
    tokens.map { "/\($0.description)" }.joined(separator: "")
  }

  /// A debug string representation of this pointer.
  ///
  /// This shows the pointer as a sequence of tokens, with each token prefixed by a slash.
  public var debugDescription: String {
    "\(tokens.map { "/\($0.debugDescription)" }.joined(separator: ""))"
  }

}

extension Pointer {

  /// Creates a pointer from its encoded string representation.
  ///
  /// - Parameters:
  ///   - string: The encoded string representation of the pointer
  ///   - strict: Whether to enforce strict parsing rules
  ///     Currrently affects:
  ///       - `~` escaping rules (strict mode fails when `~` is not followed by 0 or 1)
  ///
  public init?(encoded string: some StringProtocol, strict: Bool = Pointer.strict) {
    do {
      self = try Pointer(validating: string, strict: strict)
    } catch {
      return nil
    }
  }

  /// The encoded string representation of this pointer.
  ///
  /// This is the string form that can be used to create a new pointer.
  public var encoded: String {
    "\(tokens.map { "/\($0.encoded)" }.joined(separator: ""))"
  }

}

extension Pointer {

  /// Creates a pointer from its string representation, throwing an error if invalid.
  ///
  /// - Parameters:
  ///   - string: The string representation of the pointer
  ///   - strict: Whether to enforce strict parsing rules
  ///     Currrently affects:
  ///     - `~` escaping rules (strict mode fails when `~` is not followed by 0 or 1)
  /// - Throws: An error if the string is not a valid pointer representation
  ///
  public init(validating string: some StringProtocol, strict: Bool = Pointer.strict) throws {
    var tokens: [ReferenceToken] = []
    guard !string.isEmpty else {
      self.tokens = []
      return
    }
    var segmentStart = string.startIndex
    let endIndex = string.endIndex

    func fail(_ details: String) throws -> Never {
      throw Pointer.Error.invalidPointer(
        String(string),
        position: string.distance(from: string.startIndex, to: segmentStart),
        details: details
      )
    }

    while segmentStart < endIndex {
      guard string.first == "/" else {
        try fail("Expected '/')")
      }
      guard let tokenStart = string.index(segmentStart, offsetBy: 1, limitedBy: endIndex) else {
        try fail("Expected token after '/'")
      }
      let remaining = string[tokenStart...]
      let tokenEnd = remaining.firstIndex(of: "/") ?? remaining.endIndex
      let token = remaining[..<tokenEnd]
      do {
        let token = try ReferenceToken(validating: String(token), strict: strict)
        tokens.append(token)
      } catch let error as Pointer.Error {
        // Rewrite errors to include token start position
        guard case .invalidReferenceToken(let invalidToken, let position, let details) = error else {
          throw error
        }
        throw Pointer.Error.invalidReferenceToken(
          invalidToken,
          position: string.distance(from: string.startIndex, to: tokenStart) + position,
          details: details
        )
      }
      segmentStart = tokenEnd
    }
    self.tokens = tokens
  }

  /// Creates a pointer from a valid pointer string; halts if invalid.
  ///
  /// - Parameter:
  ///   - string: The string representation of the pointer
  /// - Precondition: The string must be a valid pointer representation
  ///
  public init(valid string: String, strict: Bool = Pointer.strict) {
    do {
      self = try Pointer(validating: string, strict: strict)
    } catch {
      fatalError("Invalid pointer: \(error.localizedDescription)")
    }
  }

}

extension Pointer: ExpressibleByStringLiteral {

  /// Creates a pointer from a string literal.
  ///
  /// If the string starts with a slash, it is treated as an encoded pointer.
  /// Otherwise, it is treated as a single name token.
  ///
  /// - Parameter value: The string literal
  /// - Precondition: If the string contains slashes, it must be a valid encoded pointer
  public init(stringLiteral value: String) {
    if value.first == "/" {
      do {
        self = try Pointer(validating: value)
      } catch {
        fatalError("Invalid literal Pointer: \(error.localizedDescription)")
      }
    } else {
      self = Pointer(tokens: [.name(value)])
    }
  }

}

extension Pointer: ExpressibleByIntegerLiteral {

  /// Creates a pointer from an integer literal.
  ///
  /// This creates a pointer with a single index token.
  ///
  /// - Parameter value: The integer literal
  public init(integerLiteral value: Int) {
    self = Pointer(tokens: [.index(value)])
  }

}

extension Pointer: Sequence {

  /// Returns an iterator over the reference tokens in this pointer.
  ///
  /// - Returns: An iterator over the reference tokens
  public func makeIterator() -> ReferenceTokens.Iterator {
    tokens.makeIterator()
  }

}

/// Creates a new pointer by appending one pointer to another.
///
/// - Parameters:
///   - lhs: The first pointer
///   - rhs: The second pointer
/// - Returns: A new pointer with the tokens from both pointers
public func / (lhs: Pointer, rhs: Pointer) -> Pointer {
  Pointer(tokens: lhs.tokens + rhs.tokens)
}

/// Appends one pointer to another in place.
///
/// - Parameters:
///   - lhs: The pointer to modify
///   - rhs: The pointer to append
public func /= (lhs: inout Pointer, rhs: Pointer) {
  lhs = Pointer(tokens: lhs.tokens + rhs.tokens)
}

/// Creates a new pointer by appending a reference token to a pointer.
///
/// - Parameters:
///   - lhs: The pointer
///   - rhs: The reference token
/// - Returns: A new pointer with the token appended
public func / (lhs: Pointer, rhs: Pointer.ReferenceToken) -> Pointer {
  Pointer(tokens: lhs.tokens + [rhs])
}

/// Appends a reference token to a pointer in place.
///
/// - Parameters:
///   - lhs: The pointer to modify
///   - rhs: The reference token to append
public func /= (lhs: inout Pointer, rhs: Pointer.ReferenceToken) {
  lhs = Pointer(tokens: lhs.tokens + [rhs])
}

/// Creates a new pointer by prepending a reference token to a pointer.
///
/// - Parameters:
///   - lhs: The reference token
///   - rhs: The pointer
/// - Returns: A new pointer with the token prepended
public func / (lhs: Pointer.ReferenceToken, rhs: Pointer) -> Pointer {
  Pointer(tokens: [lhs] + rhs.tokens)
}

/// Creates a new pointer from two reference tokens.
///
/// - Parameters:
///   - lhs: The first reference token
///   - rhs: The second reference token
/// - Returns: A new pointer with both tokens
public func / (lhs: Pointer.ReferenceToken, rhs: Pointer.ReferenceToken) -> Pointer {
  Pointer(tokens: [lhs, rhs])
}
