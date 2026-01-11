//
//  Value-Number.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/28/25.
//

import SolidNumeric


extension Value {

  /// A protocol for numeric values that can be represented in Values.
  ///
  /// This protocol defines the requirements for numeric values that can be used in Values.
  /// It provides methods to convert between different numeric types and properties to
  /// query the characteristics of the number.
  public protocol Number: CustomStringConvertible, Sendable {
    /// The decimal representation of this number.
    var decimal: BigDecimal { get }
    /// Whether this number represents an integer value.
    var isInteger: Bool { get }
    /// Whether this number represents infinity.
    var isInfinity: Bool { get }
    /// Whether this number represents a not-a-number value.
    var isNaN: Bool { get }
    /// Whether this number is negative.
    var isNegative: Bool { get }
    /// The integer representation of this number, if it is an integer.
    var integer: BigInt? { get }
    /// The integer representation of this number, if it is an integer and can be represented as the
    /// Swift integer type ``T``.
    ///
    /// - Returns: The Swift integer representation of this number, or `nil` if the
    ///   number cannot be represented as a Swift integer of type ``T``.
    func int<T: FixedWidthInteger>(as type: T.Type) -> T?
    /// The floating-point representation of this number, if it is a floating-point number
    /// and can be represented as the Swift floating-point type ``F``.
    ///
    /// - Returns: The Swift floating-point representation of this number, or `nil` if the
    ///   number cannot be represented as a Swift floating-point of type ``F``.
    func float<F: BinaryFloatingPoint>(as type: F.Type) -> F?
  }

}

extension Value.Number {

  /// The integer representation of this number, if it is an integer and can be represented as the
  /// Swift integer type ``T``.
  ///
  /// - Returns: The Swift integer representation of this number, or `nil` if the
  ///   number cannot be represented as a Swift integer of type ``T``.
  public func int<T: FixedWidthInteger>(as type: T.Type = T.self) -> T? {
    return int(as: type)
  }

  /// The floating-point representation of this number, if it is a floating-point number
  /// and can be represented as the Swift floating-point type ``F``.
  ///
  /// - Returns: The Swift floating-point representation of this number, or `nil` if the
  ///   number cannot be represented as a Swift floating-point of type ``F``.
  public func float<F: BinaryFloatingPoint>(as type: F.Type) -> F? {
    return float(as: type)
  }

}
