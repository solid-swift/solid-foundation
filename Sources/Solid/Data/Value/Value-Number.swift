//
//  Value-Number.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/28/25.
//

import SolidNumeric


extension Value {

  /// A numeric value that can be represented in Values.
  ///
  /// This enum wraps either a text-based or binary numeric representation,
  /// providing a unified interface for numeric operations.
  public enum Number: Hashable, Sendable {
    case text(TextNumber)
    case binary(BinaryNumber)

    /// The decimal representation of this number.
    public var decimal: BigDecimal {
      switch self {
      case .text(let t): t.decimal
      case .binary(let b): b.decimal
      }
    }

    /// Whether this number represents an integer value.
    public var isInteger: Bool {
      switch self {
      case .text(let t): t.isInteger
      case .binary(let b): b.isInteger
      }
    }

    /// Whether this number represents infinity.
    public var isInfinity: Bool {
      switch self {
      case .text(let t): t.isInfinity
      case .binary(let b): b.isInfinity
      }
    }

    /// Whether this number represents a not-a-number value.
    public var isNaN: Bool {
      switch self {
      case .text(let t): t.isNaN
      case .binary(let b): b.isNaN
      }
    }

    /// Whether this number is negative.
    public var isNegative: Bool {
      switch self {
      case .text(let t): t.isNegative
      case .binary(let b): b.isNegative
      }
    }

    /// The integer representation of this number, if it is an integer.
    public var integer: BigInt? {
      switch self {
      case .text(let t): t.integer
      case .binary(let b): b.integer
      }
    }

    /// The integer representation of this number, if it is an integer and can be represented as the
    /// Swift integer type ``T``.
    ///
    /// - Returns: The Swift integer representation of this number, or `nil` if the
    ///   number cannot be represented as a Swift integer of type ``T``.
    public func int<T: FixedWidthInteger>(as type: T.Type = T.self) -> T? {
      switch self {
      case .text(let t): t.int(as: type)
      case .binary(let b): b.int(as: type)
      }
    }

    /// The floating-point representation of this number, if it is a floating-point number
    /// and can be represented as the Swift floating-point type ``F``.
    ///
    /// - Returns: The Swift floating-point representation of this number, or `nil` if the
    ///   number cannot be represented as a Swift floating-point of type ``F``.
    public func float<F: BinaryFloatingPoint>(as type: F.Type) -> F? {
      switch self {
      case .text(let t): t.float(as: type)
      case .binary(let b): b.float(as: type)
      }
    }
  }

}

extension Value.Number: CustomStringConvertible {

  public var description: String {
    switch self {
    case .text(let t): t.description
    case .binary(let b): b.description
    }
  }

}
