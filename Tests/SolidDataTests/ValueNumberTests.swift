//
//  ValueNumberTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/13/25.
//

@testable import SolidData
@testable import SolidNumeric
import Foundation
import Testing


@Suite("Value Number Tests")
struct ValueNumberTests {

  @Test(
    "Int from 0",
    arguments: [
      ("int8", Value.Number.binary(.int8(0))),
      ("int16", Value.Number.binary(.int16(0))),
      ("int32", Value.Number.binary(.int32(0))),
      ("int64", Value.Number.binary(.int64(0))),
      ("int128", Value.Number.binary(.int128(0))),
      ("uint8", Value.Number.binary(.uint8(0))),
      ("uint16", Value.Number.binary(.uint16(0))),
      ("uint32", Value.Number.binary(.uint32(0))),
      ("uint64", Value.Number.binary(.uint64(0))),
      ("uint128", Value.Number.binary(.uint128(0))),
      ("int", Value.Number.binary(.int(0))),
      ("float16", Value.Number.binary(.float16(0))),
      ("float32", Value.Number.binary(.float32(0))),
      ("float64", Value.Number.binary(.float64(0))),
      ("decimal", Value.Number.binary(.decimal(0))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "0"))),
    ] as [(String, Value.Number)]
  )
  func intFromIntegerZero(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 0)
  }

  @Test(
    "Int from positive integer",
    arguments: [
      ("int8", Value.Number.binary(.int8(123))),
      ("int16", Value.Number.binary(.int16(123))),
      ("int32", Value.Number.binary(.int32(123))),
      ("int64", Value.Number.binary(.int64(123))),
      ("int128", Value.Number.binary(.int128(123))),
      ("uint8", Value.Number.binary(.uint8(123))),
      ("uint16", Value.Number.binary(.uint16(123))),
      ("uint32", Value.Number.binary(.uint32(123))),
      ("uint64", Value.Number.binary(.uint64(123))),
      ("uint128", Value.Number.binary(.uint128(123))),
      ("int", Value.Number.binary(.int(123))),
      ("float16", Value.Number.binary(.float16(123))),
      ("float32", Value.Number.binary(.float32(123))),
      ("float64", Value.Number.binary(.float64(123))),
      ("decimal", Value.Number.binary(.decimal(123))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "123"))),
    ] as [(String, Value.Number)]
  )
  func intFromPositiveInteger(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 123)
  }

  @Test(
    "Int from negative integer",
    arguments: [
      ("int8", Value.Number.binary(.int8(-123))),
      ("int16", Value.Number.binary(.int16(-123))),
      ("int32", Value.Number.binary(.int32(-123))),
      ("int64", Value.Number.binary(.int64(-123))),
      ("int128", Value.Number.binary(.int128(-123))),
      ("int", Value.Number.binary(.int(BigInt(-123)))),
      ("float16", Value.Number.binary(.float16(-123))),
      ("float32", Value.Number.binary(.float32(-123))),
      ("float64", Value.Number.binary(.float64(-123))),
      ("decimal", Value.Number.binary(.decimal(-123))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "-123"))),
    ] as [(String, Value.Number)]
  )
  func intFromNegativeInteger(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: -123)
  }

  @Test(
    "Int from decimal zero (0.0)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("0.0").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("0.0").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("0.0").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("0.0")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "0.0"))),
    ] as [(String, Value.Number)]
  )
  func intFromDecimalZero(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 0)
  }

  @Test(
    "Int from decimal zero with extra precision (0.000)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("0.000").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("0.000").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("0.000").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("0.000")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "0.000"))),
    ] as [(String, Value.Number)]
  )
  func intFromDecimalZeroExtraPrecision(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 0)
  }

  @Test(
    "Int from decimal zero with extra digits (000.000)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("000.000").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("000.000").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("000.000").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("000.000")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "000.000"))),
    ] as [(String, Value.Number)]
  )
  func intFromDecimalZeroExtraDigits(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 0)
  }

  @Test(
    "Int from decimal integer (123.0)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("123.0").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("123.0").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("123.0").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("123.0")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "123.0"))),
    ] as [(String, Value.Number)]
  )
  func intFromDecimalInteger(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 123)
  }

  @Test(
    "Int from decimal integer with extra precision (123.000)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("123.000").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("123.000").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("123.000").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("123.000")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "123.000"))),
    ] as [(String, Value.Number)]
  )
  func intFromDecimalIntegerExtraPrecision(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 123)
  }

  @Test(
    "Int from decimal integer with extra digits (00123.000)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("00123.000").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("00123.000").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("00123.000").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("00123.000")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "00123.000"))),
    ] as [(String, Value.Number)]
  )
  func intFromDecimalIntegerExtraDigits(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: 123)
  }

  @Test(
    "Int from negative decimal integer (-123.0)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("-123.0").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("-123.0").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("-123.0").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("-123.0")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "-123.0"))),
    ] as [(String, Value.Number)]
  )
  func intFromNegativeDecimalInteger(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: -123)
  }

  @Test(
    "Int from negative decimal integer with extra precision (-123.000)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("-123.000").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("-123.000").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("-123.000").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("-123.000")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "-123.000"))),
    ] as [(String, Value.Number)]
  )
  func intFromNegativeDecimalIntegerExtraPrecision(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: -123)
  }

  @Test(
    "Int from negative decimal integer with extra digits (-00123.000)",
    arguments: [
      ("float16", Value.Number.binary(.float16(Float16("-00123.000").neverNil()))),
      ("float32", Value.Number.binary(.float32(Float32("-00123.000").neverNil()))),
      ("float64", Value.Number.binary(.float64(Float64("-00123.000").neverNil()))),
      ("decimal", Value.Number.binary(.decimal(BigDecimal("-00123.000")))),
      ("text", Value.Number.text(Value.TextNumber(decimal: "-00123.000"))),
    ] as [(String, Value.Number)]
  )
  func intFromNegativeDecimalIntegerExtraDigits(type: String, number: Value.Number) throws {
    checkInteger(number: number, expected: -123)
  }

  func checkInteger(number: Value.Number, expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(number.isNaN == false, sourceLocation: sourceLocation)
    #expect(number.isInfinity == false, sourceLocation: sourceLocation)
    #expect(number.isInteger == true, sourceLocation: sourceLocation)
    #expect(number.integer == BigInt(expected), sourceLocation: sourceLocation)
    let int8: Int8? = number.int()
    #expect(int8 == Int8(exactly: expected), sourceLocation: sourceLocation)
    let int16: Int16? = number.int()
    #expect(int16 == Int16(exactly: expected), sourceLocation: sourceLocation)
    let int32: Int32? = number.int()
    #expect(int32 == Int32(exactly: expected), sourceLocation: sourceLocation)
    let int64: Int64? = number.int()
    #expect(int64 == Int64(exactly: expected), sourceLocation: sourceLocation)
    let int128: Int128? = number.int()
    #expect(int128 == Int128(exactly: expected), sourceLocation: sourceLocation)
    let uint8: UInt8? = number.int()
    #expect(uint8 == UInt8(exactly: expected), sourceLocation: sourceLocation)
    let uint16: UInt16? = number.int()
    #expect(uint16 == UInt16(exactly: expected), sourceLocation: sourceLocation)
    let uint32: UInt32? = number.int()
    #expect(uint32 == UInt32(exactly: expected), sourceLocation: sourceLocation)
    let uint64: UInt64? = number.int()
    #expect(uint64 == UInt64(exactly: expected), sourceLocation: sourceLocation)
    let uint128: UInt128? = number.int()
    #expect(uint128 == UInt128(exactly: expected), sourceLocation: sourceLocation)
    let int: Int? = number.int()
    #expect(int == expected, sourceLocation: sourceLocation)
    let uint: UInt? = number.int()
    #expect(uint == UInt(exactly: expected), sourceLocation: sourceLocation)
  }

}
