//
//  RelativePointer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/4/25.
//

import Foundation
import RegexBuilder

/// A relative JSON pointer that references a location relative to a current JSON pointer.
///
/// Implements relative JSON pointers as defined in draft-handrews-relative-json-pointer-01.
/// A relative pointer is of the form:
///     non-negative-integer ( ("#") / ( "/" json-pointer ) )
/// For example:
///     "0#"    -> means 0 levels up and return the key/index of the current node.
///     "1/foo" -> means go up one level, then follow the JSON pointer "/foo".
///
/// The syntax is defined in draft-handrews-relative-json-pointer-01 as:
///
///     relative-json-pointer = non-negative-integer ( ("#") / ( "/" json-pointer ) )
///
/// This struct uses the existing `Pointer` type (defined in Pointer.swift) to represent the JSON pointer portion.
public struct RelativePointer {

  /// The tail of a relative pointer, which is either a key indicator ("#")
  /// or a JSON pointer.
  public enum Tail {
    /// Indicates that the relative pointer ends with "#". This form is used to
    /// return the key (or index) of the current location in its parent.
    case keyIndicator

    /// A JSON pointer (as defined in RFC 6901) that follows the relative pointer
    /// upward traversal.
    case pointer(Pointer)
  }

  /// The number of levels to go up from the current location.
  public let up: Int?

  /// The tail part of the relative pointer.
  public let tail: Tail?

  /// Returns the encoded relative pointer string.
  public var encoded: String {
    guard let tail else {
      guard let up else {
        fatalError("Invalid relative pointer: \(self)")
      }
      return "\(up)"
    }
    let upString = up.map(String.init) ?? ""
    switch tail {
    case .keyIndicator:
      return "\(upString)#"
    case .pointer(let pointer):
      return "\(upString)\(pointer.encoded)"
    }
  }

  /// Initializes a RelativePointer from an encoded relative pointer string.
  ///
  /// The relative pointer must follow the syntax:
  ///
  ///     relative-json-pointer = non-negative-integer ( ("#") / ( "/" json-pointer ) )
  ///
  /// For example:
  ///
  ///     "0#"    represents 0 levels up with a key indicator.
  ///     "1/foo" represents 1 level up followed by the JSON pointer "/foo".
  ///
  /// - Parameter string: The encoded relative pointer string.
  public init?(encoded string: some StringProtocol) {

    var up: Int? = nil
    var tail: Tail? = nil

    let startIndex = string.startIndex
    let endIndex = string.endIndex
    guard startIndex < endIndex else {
      return nil
    }

    var index = startIndex
    parseLoop: while index < endIndex {
      switch string[index] {
      case "0" where up == nil && index == startIndex:
        up = 0
        index = string.index(after: index)
      case "1"..."9" where up == nil && index == startIndex:
        index = string.index(after: index)
        intUpLoop: while index < endIndex {
          switch string[index] {
          case "0"..."9":
            index = string.index(after: index)
          case "/", "#":
            break intUpLoop
          default:
            return nil
          }
        }
        guard let count = Int(string[startIndex..<index]) else {
          return nil
        }
        up = count
      case "#" where up != nil && tail == nil:
        tail = .keyIndicator
        index = string.index(after: index)
      case "/" where up != nil && tail == nil:
        guard let pointer = Pointer(encoded: string[index...]) else {
          return nil
        }
        tail = .pointer(pointer)
        break parseLoop
      default:
        return nil
      }
    }
    self.up = up
    self.tail = tail
  }

  /// Applies this pointer to the given pointer to produce a new absolute pointer.
  ///
  /// - Parameter pointer: The pointer to which this relative pointer is applied.
  /// - Returns: A new Pointer that represents the absolute location.
  ///
  public func relative(to pointer: Pointer) -> Pointer? {
    var pointer: Pointer = pointer
    for _ in 0..<(up ?? 0) {
      pointer = pointer.parent
      if pointer.tokens.isEmpty {
        break
      }
    }
    guard let tail else {
      return pointer
    }
    switch tail {
    case .keyIndicator:
      return pointer
    case .pointer(let tailPointer):
      return pointer / tailPointer
    }
  }
}

extension RelativePointer: Equatable {}

extension RelativePointer: Hashable {}

extension RelativePointer: Sendable {}

extension RelativePointer: CustomStringConvertible {

  public var description: String { encoded }

}

extension RelativePointer.Tail: Equatable {}

extension RelativePointer.Tail: Hashable {}

extension RelativePointer.Tail: Sendable {}
