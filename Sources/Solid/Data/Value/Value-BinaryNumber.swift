//
//  Value-BinaryNumber.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/28/25.
//

import SolidNumeric
import Foundation


extension Value {

  public enum BinaryNumber {
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case int128(Int128)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case uint128(UInt128)
    case int(BigInt)
    case uint(BigUInt)
    case float16(Float16)
    case float32(Float32)
    case float64(Float64)
    case decimal(BigDecimal)
  }

}

extension Value.BinaryNumber: Sendable {}

extension Value.BinaryNumber: Value.Number {

  public var decimal: BigDecimal {
    switch self {
    case .int8(let value): BigDecimal(value)
    case .int16(let value): BigDecimal(value)
    case .int32(let value): BigDecimal(value)
    case .int64(let value): BigDecimal(value)
    case .int128(let value): BigDecimal(value)
    case .uint8(let value): BigDecimal(value)
    case .uint16(let value): BigDecimal(value)
    case .uint32(let value): BigDecimal(value)
    case .uint64(let value): BigDecimal(value)
    case .uint128(let value): BigDecimal(value)
    case .int(let value): BigDecimal(value)
    case .uint(let value): BigDecimal(value)
    case .float16(let value): BigDecimal(Float64(value))
    case .float32(let value): BigDecimal(Float64(value))
    case .float64(let value): BigDecimal(value)
    case .decimal(let value): value
    }
  }

  public var isInteger: Bool {
    switch self {
    case .int, .uint,
      .int8, .int16, .int32, .int64, .int128,
      .uint8, .uint16, .uint32, .uint64, .uint128:
      return true
    case .decimal:
      return decimal.isInteger
    case .float16(let value):
      return value.rounded(.towardZero) == value
    case .float32(let value):
      return value.rounded(.towardZero) == value
    case .float64(let value):
      return value.rounded(.towardZero) == value
    }
  }

  public var isNaN: Bool {
    switch self {
    case .float16(let value): value.isNaN
    case .float32(let value): value.isNaN
    case .float64(let value): value.isNaN
    case .decimal(let value): value.isNaN
    default: false
    }
  }

  public var isInfinity: Bool {
    switch self {
    case .float16(let value): value.isInfinite
    case .float32(let value): value.isInfinite
    case .float64(let value): value.isInfinite
    case .decimal(let value): value.isInfinite
    default: false
    }
  }

  public var isNegative: Bool {
    switch self {
    case .int8(let value): value < 0
    case .int16(let value): value < 0
    case .int32(let value): value < 0
    case .int64(let value): value < 0
    case .int128(let value): value < 0
    case .int(let value): value.isNegative
    case .uint8, .uint16, .uint32, .uint64, .uint128, .uint: false
    case .float16(let value): value < 0
    case .float32(let value): value < 0
    case .float64(let value): value < 0
    case .decimal(let value): value.isNegative
    }
  }

  public var integer: BigInt? {
    switch self {
    case .int8(let value): BigInt(value)
    case .int16(let value): BigInt(value)
    case .int32(let value): BigInt(value)
    case .int64(let value): BigInt(value)
    case .int128(let value): BigInt(value)
    case .uint8(let value): BigInt(value)
    case .uint16(let value): BigInt(value)
    case .uint32(let value): BigInt(value)
    case .uint64(let value): BigInt(value)
    case .uint128(let value): BigInt(value)
    case .int(let value): value
    case .uint(let value): BigInt(value)
    case .float16(let value): BigInt(value)
    case .float32(let value): BigInt(value)
    case .float64(let value): BigInt(value)
    case .decimal(let value): value.integer
    }
  }

  public func int<T: FixedWidthInteger>(as type: T.Type) -> T? {
    switch self {
    case .int8(let value): type.init(exactly: value)
    case .int16(let value): type.init(exactly: value)
    case .int32(let value): type.init(exactly: value)
    case .int64(let value): type.init(exactly: value)
    case .int128(let value): type.init(exactly: value)
    case .uint8(let value): type.init(exactly: value)
    case .uint16(let value): type.init(exactly: value)
    case .uint32(let value): type.init(exactly: value)
    case .uint64(let value): type.init(exactly: value)
    case .uint128(let value): type.init(exactly: value)
    case .int(let value): type.init(exactly: value)
    case .uint(let value): type.init(exactly: value)
    case .decimal(let value): type.init(exactly: value)
    case .float16(let value): type.init(exactly: value)
    case .float32(let value): type.init(exactly: value)
    case .float64(let value): type.init(exactly: value)
    }
  }

  public func float<F>(as type: F.Type) -> F? where F: BinaryFloatingPoint {
    switch self {
    case .int8(let value): type.init(exactly: value)
    case .int16(let value): type.init(exactly: value)
    case .int32(let value): type.init(exactly: value)
    case .int64(let value): type.init(exactly: value)
    case .int128(let value): type.init(exactly: value)
    case .uint8(let value): type.init(exactly: value)
    case .uint16(let value): type.init(exactly: value)
    case .uint32(let value): type.init(exactly: value)
    case .uint64(let value): type.init(exactly: value)
    case .uint128(let value): type.init(exactly: value)
    case .int(let value): type.init(exactly: value)
    case .uint(let value): type.init(exactly: value)
    case .float16(let value):
      if value.isNaN {
        F.nan
      } else if value.isInfinite {
        value.sign == .plus ? F.infinity : -F.infinity
      } else {
        type.init(exactly: value)
      }
    case .float32(let value):
      if value.isNaN {
        F.nan
      } else if value.isInfinite {
        value.sign == .plus ? F.infinity : -F.infinity
      } else {
        type.init(exactly: value)
      }
    case .float64(let value):
      if value.isNaN {
        F.nan
      } else if value.isInfinite {
        value.sign == .plus ? F.infinity : -F.infinity
      } else {
        type.init(exactly: value)
      }
    case .decimal(let value):
      if value.isNaN {
        F.nan
      } else if value.isInfinite {
        value.sign == .plus ? F.infinity : -F.infinity
      } else {
        type.init(exactly: value)
      }
    }
  }

}

extension Value.BinaryNumber: CustomStringConvertible {

  private static let numLocale = Locale(identifier: "C")
  private static let int8Style = IntegerFormatStyle<Int8>.number.locale(Self.numLocale)
  private static let int16Style = IntegerFormatStyle<Int16>.number.locale(Self.numLocale)
  private static let int32Style = IntegerFormatStyle<Int32>.number.locale(Self.numLocale)
  private static let int64Style = IntegerFormatStyle<Int64>.number.locale(Self.numLocale)
  private static let intStyle = IntegerFormatStyle<BigInt>.number.locale(Self.numLocale)
  private static let uint8Style = IntegerFormatStyle<UInt8>.number.locale(Self.numLocale)
  private static let uint16Style = IntegerFormatStyle<UInt16>.number.locale(Self.numLocale)
  private static let uint32Style = IntegerFormatStyle<UInt32>.number.locale(Self.numLocale)
  private static let uint64Style = IntegerFormatStyle<UInt64>.number.locale(Self.numLocale)
  private static let uintStyle = IntegerFormatStyle<BigUInt>.number.locale(Self.numLocale)
  private static let float16Style = FloatingPointFormatStyle<Float16>.number.locale(Self.numLocale)
  private static let float32Style = FloatingPointFormatStyle<Float32>.number.locale(Self.numLocale)
  private static let float64Style = FloatingPointFormatStyle<Float64>.number.locale(Self.numLocale)

  public var description: String {
    return switch self {
    case .int8(let value): value.formatted(Self.int8Style)
    case .int16(let value): value.formatted(Self.int16Style)
    case .int32(let value): value.formatted(Self.int32Style)
    case .int64(let value): value.formatted(Self.int64Style)
    case .int128(let value): value.formatted()
    case .uint8(let value): value.formatted(Self.uint8Style)
    case .uint16(let value): value.formatted(Self.uint16Style)
    case .uint32(let value): value.formatted(Self.uint32Style)
    case .uint64(let value): value.formatted(Self.uint64Style)
    case .uint128(let value): value.formatted()
    case .int(let value): value.formatted(Self.intStyle)
    case .uint(let value): value.formatted(Self.uintStyle)
    case .float16(let value): value.formatted(Self.float16Style)
    case .float32(let value): value.formatted(Self.float32Style)
    case .float64(let value): value.formatted(Self.float64Style)
    case .decimal(let value): value.description
    }
  }
}

extension Value.BinaryNumber: Hashable {

  public func hash(into hasher: inout Hasher) {
    switch self {
    case .int8(let value):
      hasher.combine(value)
    case .int16(let value):
      hasher.combine(value)
    case .int32(let value):
      hasher.combine(value)
    case .int64(let value):
      hasher.combine(value)
    case .int128(let value):
      hasher.combine(value)
    case .uint8(let value):
      hasher.combine(value)
    case .uint16(let value):
      hasher.combine(value)
    case .uint32(let value):
      hasher.combine(value)
    case .uint64(let value):
      hasher.combine(value)
    case .uint128(let value):
      hasher.combine(value)
    case .int(let value):
      hasher.combine(value)
    case .uint(let value):
      hasher.combine(value)
    case .float16(let value):
      hasher.combine(value)
    case .float32(let value):
      hasher.combine(value)
    case .float64(let value):
      hasher.combine(value)
    case .decimal(let value):
      hasher.combine(value)
    }
  }

}

extension Value.BinaryNumber: Equatable {

  public static func == (lhs: Value.BinaryNumber, rhs: Value.BinaryNumber) -> Bool {
    switch (lhs, rhs) {
    case (.int8(let l), .int8(let r)):
      return l == r
    case (.int16(let l), .int16(let r)):
      return l == r
    case (.int32(let l), .int32(let r)):
      return l == r
    case (.int64(let l), .int64(let r)):
      return l == r
    case (.int128(let l), .int128(let r)):
      return l == r
    case (.int(let l), .int(let r)):
      return l == r
    case (.uint8(let l), .uint8(let r)):
      return l == r
    case (.uint16(let l), .uint16(let r)):
      return l == r
    case (.uint32(let l), .uint32(let r)):
      return l == r
    case (.uint64(let l), .uint64(let r)):
      return l == r
    case (.uint128(let l), .uint128(let r)):
      return l == r
    case (.uint(let l), .uint(let r)):
      return l == r
    case (.float16(let l), .float16(let r)):
      return l == r
    case (.float32(let l), .float32(let r)):
      return l == r
    case (.float64(let l), .float64(let r)):
      return l == r
    default:
      return false
    }
  }
}
