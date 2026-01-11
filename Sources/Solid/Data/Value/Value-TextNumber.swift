//
//  Value-TextNumber.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/28/25.
//

import SolidNumeric
import Foundation


extension Value {

  public struct TextNumber {

    public let text: String
    public let isInteger: Bool
    public let decimal: BigDecimal

    internal init(text: String, decimal: BigDecimal) {
      self.text = text
      self.decimal = decimal
      self.isInteger = !decimal.isNaN && !decimal.isInfinite && decimal.isInteger
    }

    public init?(text: String) {
      guard let decimal = BigDecimal(text) else { return nil }
      self = Self(text: text, decimal: decimal)
    }

    public init(decimal: BigDecimal) {
      self = Self(text: decimal.description, decimal: decimal)
    }
  }

}

extension Value.TextNumber: Sendable {}

extension Value.TextNumber: Value.Number {

  public var integer: BigInt? {
    return decimal.integer()
  }

  public func int<T: BinaryInteger>(as type: T.Type) -> T? {
    return type.init(exactly: decimal.rounded(.towardZero))
  }

  public func float<T: BinaryFloatingPoint>(as type: T.Type) -> T? {
    return type.init(exactly: decimal)
  }

  public var isNaN: Bool {
    return decimal.isNaN
  }

  public var isInfinity: Bool {
    return decimal.isInfinite
  }

  public var isNegative: Bool {
    return decimal.sign == .minus
  }

}

extension Value.TextNumber: CustomStringConvertible {

  public var description: String { text }

}

extension Value.TextNumber: Hashable {

  public func hash(into hasher: inout Hasher) {
    hasher.combine(decimal)
  }

}

extension Value.TextNumber: Equatable {

  public static func == (lhs: Value.TextNumber, rhs: Value.TextNumber) -> Bool {
    lhs.decimal == rhs.decimal
  }

}
