//
//  JSONToken.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/24.
//

import SolidData
import Foundation

enum JSONToken: Equatable {

  public enum Scalar: Equatable {

    public enum Kind: Equatable {
      case string
      case number
      case bool
      case null
    }

    public struct Number: Equatable, Hashable, Codable {

      public var value: String
      public var isInteger: Bool
      public var isNegative: Bool

      public init(_ value: String, isInteger: Bool, isNegative: Bool) {
        self.value = value
        self.isInteger = isInteger
        self.isNegative = isNegative
      }

      public init(_ value: String) {
        self.init(value, isInteger: value.allSatisfy { $0.isNumber || $0 == "-" }, isNegative: value.hasPrefix("-"))
      }

      public init(_ value: Value.Number) {
        self.init(value.description, isInteger: value.isInteger, isNegative: value.isNegative)
      }

      public init<T: FloatingPoint>(_ value: T) {
        self.value = String(describing: value)
        isInteger = false
        isNegative = value < 0
      }

      public init<T: SignedInteger>(_ value: T) {
        self.value = String(value)
        isInteger = true
        isNegative = value < 0
      }

      public init<T: UnsignedInteger>(_ value: T) {
        self.value = String(value)
        isInteger = true
        isNegative = false
      }

    }

    case string(String)
    case number(Number)
    case bool(Bool)
    case null

    public var kind: Kind {
      switch self {
      case .string: .string
      case .number: .number
      case .bool: .bool
      case .null: .null
      }
    }
  }

  public enum Kind: Equatable {
    case scalar
    case beginArray
    case endArray
    case beginObject
    case endObject
    case pairSeparator
    case elementSeparator
  }

  case scalar(Scalar)
  case beginArray
  case endArray
  case beginObject
  case endObject
  case pairSeparator
  case elementSeparator

  public var kind: Kind {
    switch self {
    case .scalar: .scalar
    case .beginArray: .beginArray
    case .endArray: .endArray
    case .beginObject: .beginObject
    case .endObject: .endObject
    case .pairSeparator: .pairSeparator
    case .elementSeparator: .elementSeparator
    }
  }

}

extension JSONToken.Scalar.Number {

  /// Convert a JSON number token to a Value, using a fast integer path
  /// to avoid BigDecimal construction for simple integers.
  func toValue() -> Value {
    let text = value
    // Fast path: simple integers bypass BigDecimal entirely by parsing directly to Int64/UInt64
    if isInteger {
      let utf8 = text.utf8
      var idx = utf8.startIndex
      let isNeg = utf8[idx] == UInt8(ascii: "-")
      if isNeg { utf8.formIndex(after: &idx) }

      // Parse as UInt64 to avoid overflow on large positive values
      var magnitude: UInt64 = 0
      var overflow = false
      while idx < utf8.endIndex {
        let digit = utf8[idx] &- UInt8(ascii: "0")
        let (m1, o1) = magnitude.multipliedReportingOverflow(by: 10)
        let (m2, o2) = m1.addingReportingOverflow(UInt64(digit))
        if o1 || o2 { overflow = true; break }
        magnitude = m2
        utf8.formIndex(after: &idx)
      }

      if !overflow {
        if isNeg {
          if magnitude <= UInt64(Int64.max) + 1 {
            return .number(.binary(.int64(Int64(bitPattern: 0 &- magnitude))))
          }
        } else {
          if magnitude <= UInt64(Int64.max) {
            return .number(.binary(.int64(Int64(magnitude))))
          } else {
            return .number(.binary(.uint64(magnitude)))
          }
        }
      }
    }

    // Fallback: use TextNumber which constructs BigDecimal
    guard let textNumber = Value.TextNumber(text: text) else {
      return .number(text)
    }
    return .number(.text(textNumber))
  }

}
