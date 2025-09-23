//
//  BigDecimalTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/16/25.
//

@testable import SolidNumeric
import Foundation
import Testing


@Suite("BigDecimal Tests")
struct BigDecimalTests {

  static let testData = BigDecimalTestData.loadFromBundle(bundle: .module)

  // MARK: - Initialization Tests

  @Test("Default initialization")
  func defaultInitialization() throws {
    let zero = BigDecimal(mantissa: 0, scale: 0)
    #expect(zero.isZero)
    #expect(zero.mantissa == 0)
    #expect(zero.scale == 0)
    #expect(!zero.isNaN)
    #expect(!zero.isInfinite)
    #expect(zero.isFinite)
  }

  @Test(
    "Mantissa and scale initialization",
    arguments: [
      // Zero values
      (0, 0, "0"),
      (0, 1, "0.0"),
      (0, 2, "0.00"),
      (0, -1, "0E+1"),

      // Positive integers
      (1, 0, "1"),
      (42, 0, "42"),
      (100, 0, "100"),
      (1234567890, 0, "1234567890"),

      // Negative integers
      (-1, 0, "-1"),
      (-42, 0, "-42"),
      (-100, 0, "-100"),
      (-1234567890, 0, "-1234567890"),

      // Positive decimals
      (10, 1, "1.0"),
      (100, 2, "1.00"),
      (123, 2, "1.23"),
      (123456, 3, "123.456"),
      (1, 1, "0.1"),
      (1, 2, "0.01"),
      (1, 3, "0.001"),

      // Negative decimals
      (-10, 1, "-1.0"),
      (-100, 2, "-1.00"),
      (-123, 2, "-1.23"),
      (-123456, 3, "-123.456"),
      (-1, 1, "-0.1"),
      (-1, 2, "-0.01"),
      (-1, 3, "-0.001"),

      // Large scale
      (1, 10, "0.0000000001"),
      (-1, 10, "-0.0000000001"),
      (1234567890, 9, "1.234567890"),
      (-1234567890, 9, "-1.234567890"),

      // Negative scale
      (1, -1, "10"),
      (1, -2, "100"),
      (42, -1, "420"),
      (-1, -1, "-10"),
      (-1, -2, "-100"),
      (-42, -1, "-420"),
    ] as [(BigInt, Int, String)]
  )
  func mantissaAndScaleInitialization(_ mantissa: BigInt, _ scale: Int, _ expected: String) throws {
    let num = BigDecimal(mantissa: mantissa, scale: scale)
    #expect(num.mantissa == mantissa)
    #expect(num.scale == scale)
    #expect(num.description == expected)
  }

  @Test(
    "String initialization",
    arguments: [
      // Zero
      ("0", 0, 0),
      ("0.0", 0, 1),
      ("0.00", 0, 2),
      ("000.000", 0, 3),

      // Positive integers
      ("1", 1, 0),
      ("42", 42, 0),
      ("100", 100, 0),
      ("1234567890", 1234567890, 0),

      // Positive decimals
      ("1.0", 10, 1),
      ("1.00", 100, 2),
      ("1.23", 123, 2),
      ("123.456", 123456, 3),
      ("0.1", 1, 1),
      ("0.01", 1, 2),
      ("0.001", 1, 3),

      // Negative integers
      ("-1", -1, 0),
      ("-42", -42, 0),
      ("-100", -100, 0),
      ("-1234567890", -1234567890, 0),

      // Negative decimals
      ("-1.0", -10, 1),
      ("-1.00", -100, 2),
      ("-1.23", -123, 2),
      ("-123.456", -123456, 3),
      ("-0.1", -1, 1),
      ("-0.01", -1, 2),
      ("-0.001", -1, 3),

      // Scientific notation
      ("1e0", 1, 0),
      ("1e1", 10, 0),
      ("1e2", 100, 0),
      ("1e-1", 1, 1),
      ("1e-2", 1, 2),
      ("1.23e2", 123, 0),
      ("1.23e-2", 123, 4),
      ("-1.23e2", -123, 0),
      ("-1.23e-2", -123, 4),

      // Special values
      ("inf", 0, 0),
      ("+inf", 0, 0),
      ("-inf", 0, 0),
      ("nan", 0, 0),
    ] as [(String, Int, Int)]
  )
  func stringInitialization(_ string: String, _ expectedMantissa: Int, _ expectedScale: Int) throws {
    let num = try #require(BigDecimal(string), "Failed to create BigDecimal from string: \(string)")

    if string.lowercased() == "nan" {
      #expect(num.isNaN)
    } else if string.lowercased().contains("inf") {
      #expect(num.isInfinite)
      #expect(num.isNegative == string.hasPrefix("-"))
    } else {
      #expect(num.mantissa == expectedMantissa)
      #expect(num.scale == expectedScale)
    }
  }

  @Test(
    "Integer initialization",
    arguments: [
      // Small numbers
      (0, "0"),
      (1, "1"),
      (-1, "-1"),
      (42, "42"),
      (-42, "-42"),

      // Large numbers
      (1234567890, "1234567890"),
      (-1234567890, "-1234567890"),
      (Int.max, String(Int.max)),
      (Int.min, String(Int.min)),
    ] as [(Int, String)]
  )
  func integerInitialization(_ value: Int, _ expected: String) throws {
    let num = BigDecimal(value)
    #expect(num.description == expected)
    #expect(num.scale == 0)
  }

  @Test(
    "Exact integer initialization",
    arguments: [
      // Small numbers
      (0, true),
      (1, true),
      (-1, true),
      (42, true),
      (-42, true),

      // Large numbers
      (1234567890, true),
      (-1234567890, true),
      (Int.max, true),
      (Int.min, true),
    ] as [(Int, Bool)]
  )
  func exactIntegerInitialization(_ value: Int, _ shouldSucceed: Bool) throws {
    let num = try #require(BigDecimal(exactly: value), "Failed to create BigDecimal from integer: \(value)")
    #expect(num.description == String(value))
    #expect(num.scale == 0)
  }

  @Test(
    "Floating point initialization",
    arguments: [
      6.25,
      // Zero
      0.0,
      -0.0,

      // Small numbers
      1.0,
      -1.0,
      0.5,
      -0.5,
      3.14159,
      -3.14159,
      0.005,
      -0.005,

      // Powers of 10
      10.0,
      100.0,
      0.1,
      0.01,
      0.001,

      // Powers of 2
      2.0,
      4.0,
      8.0,
      0.25,
      0.125,

      // Special values
      Double.infinity,
      -Double.infinity,
      Double.nan,
    ] as [Double]
  )
  func floatingPointInitialization(_ value: Double) throws {
    let expected = (value.sign == .minus && value.isZero ? -value : value).description.replacing(/\.0$/, with: "")
    let expectedFractionalDigits = expected.split(separator: ".").last?.count ?? 0
    let num = BigDecimal(value).rounded(.toNearestOrAwayFromZero, places: expectedFractionalDigits)
    #expect(num.description == expected)
    if !value.isNaN {
      #expect(BigDecimal(exactly: value)?.rounded(.toNearestOrAwayFromZero, places: expectedFractionalDigits) == num)
    } else {
      #expect(BigDecimal(exactly: value) == nil)
    }
  }

  @Test("Special FloatingPoint Initializers")
  func specialFloatingPointInitializers() throws {
    let source = BigDecimal(1234)
    // Exponent is the negative of the scale in FloatingPoint/IEEE754 protocol terms.
    #expect(BigDecimal(sign: .plus, exponent: 3, significand: source).description == "1234000")
    #expect(BigDecimal(sign: .minus, exponent: 3, significand: source).description == "-1234000")
    #expect(BigDecimal(sign: .plus, exponent: -3, significand: source).description == "1.234")
    #expect(BigDecimal(sign: .minus, exponent: -3, significand: source).description == "-1.234")
    #expect(BigDecimal(sign: .plus, exponent: 0, significand: .nan).isNaN)
    #expect(BigDecimal(sign: .plus, exponent: 0, significand: -.infinity) == .infinity)
    #expect(BigDecimal(sign: .minus, exponent: 0, significand: .infinity) == -.infinity)

    let source2 = BigDecimal(-1)
    #expect(BigDecimal(signOf: source, magnitudeOf: source2).description == "1")
    #expect(BigDecimal(signOf: source2, magnitudeOf: source).description == "-1234")
    #expect(BigDecimal(signOf: source, magnitudeOf: .nan).isNaN)
    #expect(BigDecimal(signOf: source, magnitudeOf: -.infinity) == .infinity)
    #expect(BigDecimal(signOf: source2, magnitudeOf: .infinity) == -.infinity)
  }

  // MARK: - Property Tests

  @Test(
    "Special value properties",
    arguments: [
      // Normal values
      ("0", false, false, true, true, false),
      ("1", false, false, true, false, false),
      ("-1", false, false, true, false, true),
      ("0.5", false, false, true, false, false),
      ("-0.5", false, false, true, false, true),

      // Special values
      ("nan", true, false, false, false, false),
      ("inf", false, true, false, false, false),
      ("-inf", false, true, false, false, true),
    ] as [(String, Bool, Bool, Bool, Bool, Bool)]
  )
  func specialValueProperties(
    _ value: String,
    _ isNaN: Bool,
    _ isInfinite: Bool,
    _ isFinite: Bool,
    _ isZero: Bool,
    _ isNegative: Bool
  ) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from string: \(value)")
    #expect(num.isNaN == isNaN)
    #expect(num.isInfinite == isInfinite)
    #expect(num.isFinite == isFinite)
    #expect(num.isZero == isZero)
    #expect(num.isNegative == isNegative)
  }

  @Test(
    "Integer property",
    arguments: [
      // Integers
      ("0", 0),
      ("1", 1),
      ("-1", -1),
      ("42", 42),
      ("-42", -42),
      ("1234567890", 1234567890),
      ("-1234567890", -1234567890),

      // Non-integers
      ("0.5", nil),
      ("-0.5", nil),
      ("1.23", nil),
      ("-1.23", nil),
      ("0.001", nil),
      ("-0.001", nil),

      // Special values
      ("nan", nil),
      ("inf", nil),
      ("-inf", nil),
    ] as [(String, Int?)]
  )
  func integerProperty(_ value: String, _ expected: Int?) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from string: \(value)")
    if let expected {
      let integer = try #require(num.integer, "Expected integer value for: \(value)")
      #expect(integer == expected)
    } else {
      #expect(num.integer == nil)
    }
  }

  @Test(
    "Magnitude property",
    arguments: [
      // Zero
      ("0", "0"),
      ("0.0", "0.0"),

      // Positive numbers
      ("1", "1"),
      ("42", "42"),
      ("1.23", "1.23"),
      ("0.001", "0.001"),

      // Negative numbers
      ("-1", "1"),
      ("-42", "42"),
      ("-1.23", "1.23"),
      ("-0.001", "0.001"),

      // Special values
      ("nan", "nan"),
      ("inf", "inf"),
      ("-inf", "inf"),
    ] as [(String, String)]
  )
  func magnitudeProperty(_ value: String, _ expected: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from string: \(value)")
    let magnitude = num.magnitude
    #expect(magnitude.description == expected)
  }

  @Test(
    "Signum function",
    arguments: [
      // Zero
      ("0", 0),
      ("0.0", 0),

      // Positive numbers
      ("1", 1),
      ("42", 1),
      ("0.1", 1),
      ("0.001", 1),

      // Negative numbers
      ("-1", -1),
      ("-42", -1),
      ("-0.1", -1),
      ("-0.001", -1),

      // Special values
      ("nan", 0),
      ("inf", 1),
      ("-inf", -1),
    ] as [(String, Int)]
  )
  func signumFunction(_ value: String, _ expected: Int) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from string: \(value)")
    #expect(num.signum() == expected)
  }

  @Test(
    "isInteger property",
    arguments: [
      // Integers
      ("0", true),
      ("1", true),
      ("-1", true),
      ("42", true),
      ("-42", true),
      ("1000", true),
      ("-1000", true),
      ("1.0", true),
      ("-1.0", true),
      ("0.0", true),
      ("-0.0", true),
      ("0.00", true),
      ("-0.00", true),
      ("0.000", true),
      ("0000.000", true),

      // Non-integers
      ("0.1", false),
      ("-0.1", false),
      ("1.23", false),
      ("-1.23", false),
      ("0.001", false),
      ("-0.001", false),

      // Special values
      ("nan", false),
      ("inf", false),
      ("-inf", false),
    ] as [(String, Bool)]
  )
  func isIntegerProperty(_ value: String, _ expected: Bool) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from string: \(value)")
    #expect(num.isInteger == expected)
  }

  @Test("Rescale")
  func rescale() throws {
    let num = BigDecimal("123.456")
    #expect(num.scaled(to: 2).description == "123.46")
    #expect(num.scaled(to: 2, rounding: .towardZero).description == "123.45")
    #expect(num.scaled(to: 5).description == "123.45600")
    #expect(num.scaled(to: 0).description == "123")
    #expect(num.scaled(to: 1).scaled(to: 5).description == "123.50000")
    #expect(num.scaled(to: 1, rounding: .down).scaled(to: 5).description == "123.40000")
    var num2 = num
    num2.scale(to: 2, rounding: .towardZero)
    #expect(num2.description == "123.45")
    var num3 = num
    num3.scale(to: 2, rounding: .awayFromZero)
    #expect(num3.description == "123.46")
    var num4 = num
    num4.scale(to: 2, rounding: .toNearestOrAwayFromZero)
    #expect(num4.description == "123.46")
  }

  @Test(
    "Absolute value",
    arguments: [
      // Small numbers
      ("0", "0", 0),
      ("1", "1", 0),
      ("-1", "1", 0),
      ("42", "42", 0),
      ("-42", "42", 0),

      // Decimals
      ("0.1", "0.1", 1),
      ("-0.1", "0.1", 1),
      ("0.01", "0.01", 2),
      ("-0.01", "0.01", 2),

      // Large numbers
      ("100000000", "100000000", 0),
      ("-100000000", "100000000", 0),
      ("0.00000001", "0.00000001", 8),
      ("-0.00000001", "0.00000001", 8),

      // Special values
      ("inf", "Inf", 0),
      ("-inf", "Inf", 0),
      ("nan", "NaN", 0),
    ] as [(String, String, Int)]
  )
  func abs(_ value: String, _ expected: String, _ expectedScale: Int) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let result = num.abs
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    #expect(result.mantissa == expectedNum.mantissa)
    #expect(result.scale == expectedScale)
  }

  // MARK: - Arithmetic Operation Tests

  @Test(
    "Addition",
    arguments: testData.addition.map { ($0.lhs, $0.rhs, $0.expected) }
  )
  func addition(_ a: String, _ b: String, _ expected: BigDecimalTestData.BigDecimalComponents) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    if !numA.isFinite || !numB.isFinite {
    } else {
      let expectedNum = BigDecimal(components: expected)
      let result = (numA + numB).scaled(to: expectedNum.scale)
      #expect(result.description == expectedNum.description)
    }
  }

  @Test("Addition with special values")
  func additionWithSpecialValues() throws {
    // NaN + NaN = NaN
    #expect((BigDecimal.nan + .nan).isNaN)
    // NaN + Any = NaN
    #expect((BigDecimal.nan + .zero).isNaN)
    #expect((BigDecimal.nan + .one).isNaN)
    #expect((BigDecimal.nan + (-.one)).isNaN)
    #expect((BigDecimal.nan + .infinity).isNaN)
    #expect((BigDecimal.nan + (-.infinity)).isNaN)
    // Any + NaN = NaN
    #expect((BigDecimal.zero + .nan).isNaN)
    #expect((BigDecimal.one + .nan).isNaN)
    #expect(((-BigDecimal.one) + .nan).isNaN)
    #expect((BigDecimal.infinity + .nan).isNaN)
    #expect(((-BigDecimal.infinity) + .nan).isNaN)
    // Infinity + X
    #expect(BigDecimal.infinity + .zero == .infinity)
    #expect(BigDecimal.infinity + .one == .infinity)
    #expect(BigDecimal.infinity + (-.one) == .infinity)
    #expect(BigDecimal.infinity + .infinity == .infinity)
    #expect((BigDecimal.infinity + (-.infinity)).isNaN)
    // -Infinity + X
    #expect((-BigDecimal.infinity) + .zero == (-.infinity))
    #expect((-BigDecimal.infinity) + .one == (-.infinity))
    #expect((-BigDecimal.infinity) + (-.one) == (-.infinity))
    #expect((-BigDecimal.infinity) + (-.infinity) == (-.infinity))
    #expect(((-BigDecimal.infinity) + .infinity).isNaN)
    // X + Infinity
    #expect(BigDecimal.zero + .infinity == .infinity)
    #expect(BigDecimal.one + .infinity == .infinity)
    #expect((-BigDecimal.one) + .infinity == .infinity)
    // X - -Infinity
    #expect(BigDecimal.zero + (-.infinity) == -.infinity)
    #expect(BigDecimal.one + (-.infinity) == -.infinity)
    #expect((-BigDecimal.one) + (-.infinity) == -.infinity)
  }

  @Test(
    "Subtraction",
    arguments: testData.subtraction.map { ($0.lhs, $0.rhs, $0.expected) }
  )
  func subtraction(_ a: String, _ b: String, _ expected: BigDecimalTestData.BigDecimalComponents) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    let expectedNum = BigDecimal(components: expected)
    let result = (numA - numB).scaled(to: expectedNum.scale)
    #expect(result.description == expectedNum.description)
  }

  @Test("Subtraction with special values")
  func subtractionWithSpecialValues() throws {
    // NaN - NaN = NaN
    #expect((BigDecimal.nan - .nan).isNaN)
    // NaN - Any = NaN
    #expect((BigDecimal.nan - .zero).isNaN)
    #expect((BigDecimal.nan - .one).isNaN)
    #expect((BigDecimal.nan - (-.one)).isNaN)
    #expect((BigDecimal.nan - .infinity).isNaN)
    #expect((BigDecimal.nan - (-.infinity)).isNaN)
    // Any - NaN = NaN
    #expect((BigDecimal.zero - .nan).isNaN)
    #expect((BigDecimal.one - .nan).isNaN)
    #expect(((-BigDecimal.one) - .nan).isNaN)
    #expect((BigDecimal.infinity - .nan).isNaN)
    #expect(((-BigDecimal.infinity) - .nan).isNaN)
    // Infinity - X
    #expect(BigDecimal.infinity - .zero == .infinity)
    #expect(BigDecimal.infinity - .one == .infinity)
    #expect(BigDecimal.infinity - (-.one) == .infinity)
    #expect(BigDecimal.infinity - (-.infinity) == .infinity)
    #expect((BigDecimal.infinity - .infinity).isNaN)
    // -Infinity - X
    #expect((-BigDecimal.infinity) - .zero == (-.infinity))
    #expect((-BigDecimal.infinity) - .one == (-.infinity))
    #expect((-BigDecimal.infinity) - (-.one) == (-.infinity))
    #expect((-BigDecimal.infinity) - .infinity == (-.infinity))
    #expect(((-BigDecimal.infinity) - (-.infinity)).isNaN)
    // X - Infinity
    #expect(BigDecimal.zero - .infinity == (-.infinity))
    #expect(BigDecimal.one - .infinity == (-.infinity))
    #expect((-BigDecimal.one) - .infinity == (-.infinity))
    // X - -Infinity
    #expect(BigDecimal.zero - (-.infinity) == .infinity)
    #expect(BigDecimal.one - (-.infinity) == .infinity)
    #expect((-BigDecimal.one) - (-.infinity) == .infinity)
  }

  @Test(
    "Multiplication",
    arguments: testData.multiplication.map { ($0.lhs, $0.rhs, $0.expected) }
  )
  func multiplication(_ a: String, _ b: String, _ expected: BigDecimalTestData.BigDecimalComponents) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    let expectedNum = BigDecimal(components: expected)
    let result = (numA * numB).scaled(to: expectedNum.scale)
    var resultAssign = numA
    resultAssign *= numB
    resultAssign.scale(to: expectedNum.scale)
    #expect(result.description == expectedNum.description)
    #expect(resultAssign.description == expectedNum.description)
  }

  @Test("Multiplication with special values")
  func multiplicationWithSpecialValues() throws {
    // NaN * NaN = NaN
    #expect((BigDecimal.nan * .nan).isNaN)
    // NaN * Any = NaN
    #expect((BigDecimal.nan * .zero).isNaN)
    #expect((BigDecimal.nan * .one).isNaN)
    #expect((BigDecimal.nan * (-.one)).isNaN)
    #expect((BigDecimal.nan * .infinity).isNaN)
    #expect((BigDecimal.nan * (-.infinity)).isNaN)
    // Any * NaN = NaN
    #expect((BigDecimal.zero * .nan).isNaN)
    #expect((BigDecimal.one * .nan).isNaN)
    #expect(((-BigDecimal.one) * .nan).isNaN)
    #expect((BigDecimal.infinity * .nan).isNaN)
    #expect(((-BigDecimal.infinity) * .nan).isNaN)
    // Infinity * X
    #expect((BigDecimal.infinity * .zero).isNaN)
    #expect(BigDecimal.infinity * .one == .infinity)
    #expect(BigDecimal.infinity * (-.one) == (-.infinity))
    #expect(BigDecimal.infinity * (-.infinity) == (-.infinity))
    #expect(BigDecimal.infinity * .infinity == .infinity)
    // -Infinity * X
    #expect((-BigDecimal.infinity * .zero).isNaN)
    #expect((-BigDecimal.infinity) * .one == (-.infinity))
    #expect((-BigDecimal.infinity) * (-.one) == .infinity)
    #expect((-BigDecimal.infinity) * .infinity == (-.infinity))
    #expect((-BigDecimal.infinity) * (-.infinity) == .infinity)
    // X - Infinity
    #expect((BigDecimal.zero * .infinity).isNaN)
    #expect(BigDecimal.one * .infinity == .infinity)
    #expect((-BigDecimal.one) * .infinity == (-.infinity))
    // X - -Infinity
    #expect((BigDecimal.zero * (-.infinity)).isNaN)
    #expect(BigDecimal.one * (-.infinity) == (-.infinity))
    #expect((-BigDecimal.one) * (-.infinity) == .infinity)
  }

  @Test(
    "Division",
    arguments: testData.division.map { ($0.lhs, $0.rhs, $0.expected) }
  )
  func division(_ a: String, _ b: String, _ expected: BigDecimalTestData.BigDecimalComponents) throws {
    let expectedNum = BigDecimal(components: expected)
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    let result = (numA / numB).scaled(to: expectedNum.scale)
    var resultAssign = numA
    resultAssign /= numB
    resultAssign.scale(to: expectedNum.scale)
    #expect(result.description == expectedNum.description)
    #expect(resultAssign.description == expectedNum.description)
  }

  @Test("Division with special values")
  func divisionWithSpecialValues() throws {
    #expect((BigDecimal.zero / .zero).isNaN)
    #expect(BigDecimal.one / .zero == .infinity)
    #expect((-BigDecimal.one) / .zero == (-.infinity))

    // NaN / NaN = NaN
    #expect((BigDecimal.nan / .nan).isNaN)
    // NaN / Any = NaN
    #expect((BigDecimal.nan / .zero).isNaN)
    #expect((BigDecimal.nan / .one).isNaN)
    #expect((BigDecimal.nan / (-.one)).isNaN)
    #expect((BigDecimal.nan / .infinity).isNaN)
    #expect((BigDecimal.nan / (-.infinity)).isNaN)
    // Any / NaN = NaN
    #expect((BigDecimal.zero / .nan).isNaN)
    #expect((BigDecimal.one / .nan).isNaN)
    #expect(((-BigDecimal.one) / .nan).isNaN)
    #expect((BigDecimal.infinity / .nan).isNaN)
    #expect(((-BigDecimal.infinity) / .nan).isNaN)
    // Infinity / X
    #expect(BigDecimal.infinity / .zero == .infinity)
    #expect(BigDecimal.infinity / .one == .infinity)
    #expect(BigDecimal.infinity / (-.one) == (-.infinity))
    #expect((BigDecimal.infinity / (-.infinity)).isNaN)
    #expect((BigDecimal.infinity / .infinity).isNaN)
    // -Infinity / X
    #expect((-BigDecimal.infinity) / .zero == (-.infinity))
    #expect((-BigDecimal.infinity) / .one == (-.infinity))
    #expect((-BigDecimal.infinity) / (-.one) == .infinity)
    #expect(((-BigDecimal.infinity) / .infinity).isNaN)
    #expect(((-BigDecimal.infinity) / (-.infinity)).isNaN)
    // X / Infinity
    #expect(BigDecimal.zero / .infinity == .zero)
    #expect(BigDecimal.one / .infinity == .zero)
    #expect((-BigDecimal.one) / .infinity == -.zero)
    // X / -Infinity
    #expect(BigDecimal.zero / (-.infinity) == -.zero)
    #expect(BigDecimal.one / (-.infinity) == -.zero)
    #expect((-BigDecimal.one) / (-.infinity) == .zero)
  }

  @Test(
    "Remainder",
    arguments: testData.remainder.map { ($0.lhs, $0.rhs, $0.expected, $0.expectedTruncating) }
  )
  func remainder(
    _ a: String,
    _ b: String,
    _ expected: BigDecimalTestData.BigDecimalComponents,
    _ expectedTruncating: BigDecimalTestData.BigDecimalComponents
  ) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    let expectedNum = BigDecimal(components: expected)
    let expectedTruncatingNum = BigDecimal(components: expectedTruncating)
    let result = numA.remainder(dividingBy: numB).scaled(to: expectedNum.scale)
    var formResult = numA
    formResult.formRemainder(dividingBy: numB)
    formResult.scale(to: expectedNum.scale)
    let truncatedResult = numA.truncatingRemainder(dividingBy: numB).scaled(to: expectedTruncatingNum.scale)
    var formTruncatedResult = numA
    formTruncatedResult.formTruncatingRemainder(dividingBy: numB)
    formTruncatedResult.scale(to: expectedTruncatingNum.scale)
    #expect(result.description == expectedNum.description)
    #expect(truncatedResult.description == expectedTruncatingNum.description)
    #expect(formResult.description == expectedNum.description)
    #expect(formTruncatedResult.description == expectedTruncatingNum.description)
  }

  @Test("Remainder with special values")
  func remainderWithSpecialValues() throws {
    // NaN % NaN = NaN
    #expect(BigDecimal.nan.remainder(dividingBy: .nan).isNaN)
    #expect(BigDecimal.nan.truncatingRemainder(dividingBy: .nan).isNaN)
    // NaN % Any = NaN
    #expect(BigDecimal.nan.remainder(dividingBy: .zero).isNaN)
    #expect(BigDecimal.nan.truncatingRemainder(dividingBy: .zero).isNaN)
    #expect(BigDecimal.nan.remainder(dividingBy: .one).isNaN)
    #expect(BigDecimal.nan.truncatingRemainder(dividingBy: .one).isNaN)
    #expect(BigDecimal.nan.remainder(dividingBy: (-.one)).isNaN)
    #expect(BigDecimal.nan.truncatingRemainder(dividingBy: (-.one)).isNaN)
    #expect(BigDecimal.nan.remainder(dividingBy: .infinity).isNaN)
    #expect(BigDecimal.nan.truncatingRemainder(dividingBy: .infinity).isNaN)
    #expect(BigDecimal.nan.remainder(dividingBy: (-.infinity)).isNaN)
    #expect(BigDecimal.nan.truncatingRemainder(dividingBy: (-.infinity)).isNaN)
    // Any % NaN = NaN
    #expect(BigDecimal.zero.remainder(dividingBy: .nan).isNaN)
    #expect(BigDecimal.zero.truncatingRemainder(dividingBy: .nan).isNaN)
    #expect(BigDecimal.one.remainder(dividingBy: .nan).isNaN)
    #expect(BigDecimal.one.truncatingRemainder(dividingBy: .nan).isNaN)
    #expect((-BigDecimal.one).remainder(dividingBy: .nan).isNaN)
    #expect((-BigDecimal.one).truncatingRemainder(dividingBy: .nan).isNaN)
    #expect(BigDecimal.infinity.remainder(dividingBy: .nan).isNaN)
    #expect(BigDecimal.infinity.truncatingRemainder(dividingBy: .nan).isNaN)
    #expect((-BigDecimal.infinity).remainder(dividingBy: .nan).isNaN)
    #expect((-BigDecimal.infinity).truncatingRemainder(dividingBy: .nan).isNaN)
    // Infinity % X
    #expect(BigDecimal.infinity.remainder(dividingBy: .zero).isNaN)
    #expect(BigDecimal.infinity.truncatingRemainder(dividingBy: .zero).isNaN)
    #expect(BigDecimal.infinity.remainder(dividingBy: .one).isNaN)
    #expect(BigDecimal.infinity.truncatingRemainder(dividingBy: .one).isNaN)
    #expect(BigDecimal.infinity.remainder(dividingBy: (-.one)).isNaN)
    #expect(BigDecimal.infinity.truncatingRemainder(dividingBy: (-.one)).isNaN)
    #expect(BigDecimal.infinity.remainder(dividingBy: (-.infinity)).isNaN)
    #expect(BigDecimal.infinity.truncatingRemainder(dividingBy: (-.infinity)).isNaN)
    #expect(BigDecimal.infinity.remainder(dividingBy: .infinity).isNaN)
    #expect(BigDecimal.infinity.truncatingRemainder(dividingBy: .infinity).isNaN)
    // -Infinity % X
    #expect((-BigDecimal.infinity).remainder(dividingBy: .zero).isNaN)
    #expect((-BigDecimal.infinity).truncatingRemainder(dividingBy: .zero).isNaN)
    #expect((-BigDecimal.infinity).remainder(dividingBy: .one).isNaN)
    #expect((-BigDecimal.infinity).truncatingRemainder(dividingBy: .one).isNaN)
    #expect((-BigDecimal.infinity).remainder(dividingBy: (-.one)).isNaN)
    #expect((-BigDecimal.infinity).truncatingRemainder(dividingBy: (-.one)).isNaN)
    #expect((-BigDecimal.infinity).remainder(dividingBy: (-.infinity)).isNaN)
    #expect((-BigDecimal.infinity).truncatingRemainder(dividingBy: (-.infinity)).isNaN)
    #expect((-BigDecimal.infinity).remainder(dividingBy: .infinity).isNaN)
    #expect((-BigDecimal.infinity).truncatingRemainder(dividingBy: .infinity).isNaN)
    // X % Infinity
    #expect(BigDecimal.zero.remainder(dividingBy: .infinity) == .zero)
    #expect(BigDecimal.zero.truncatingRemainder(dividingBy: .infinity) == .zero)
    #expect(BigDecimal.one.remainder(dividingBy: .infinity) == .one)
    #expect(BigDecimal.one.truncatingRemainder(dividingBy: .infinity) == .one)
    #expect((-BigDecimal.one).remainder(dividingBy: .infinity) == (-.one))
    #expect((-BigDecimal.one).truncatingRemainder(dividingBy: .infinity) == (-.one))
    // X % -Infinity
    #expect(BigDecimal.zero.remainder(dividingBy: (-.infinity)) == .zero)
    #expect(BigDecimal.zero.truncatingRemainder(dividingBy: (-.infinity)) == -.zero)
    #expect(BigDecimal.one.remainder(dividingBy: (-.infinity)) == .one)
    #expect(BigDecimal.one.truncatingRemainder(dividingBy: (-.infinity)) == .one)
    #expect((-BigDecimal.one).remainder(dividingBy: (-.infinity)) == -.one)
    #expect((-BigDecimal.one).truncatingRemainder(dividingBy: (-.infinity)) == -.one)
  }

  @Test(
    "Negation",
    arguments: [
      // Zero
      ("0", "0"),
      ("0.0", "0.0"),

      // Positive numbers
      ("1", "-1"),
      ("42", "-42"),
      ("0.1", "-0.1"),
      ("1.23", "-1.23"),

      // Negative numbers
      ("-1", "1"),
      ("-42", "42"),
      ("-0.1", "0.1"),
      ("-1.23", "1.23"),

      // Special values
      ("inf", "-Inf"),
      ("-inf", "Inf"),
      ("nan", "NaN"),
    ] as [(String, String)]
  )
  func negation(_ value: String, _ expected: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from string: \(value)")
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from string: \(expected)")
    let result = -num
    #expect(result.description == expectedNum.description)
  }

  @Test(
    "Raising to integer exponent",
    arguments: testData.integerPower.map { ($0.base, $0.exponent, $0.expected) }
  )
  func raisedToIntegerPower(_ base: String, _ exponent: Int, _ expected: BigDecimalTestData.BigDecimalComponents) throws
  {
    let num = try #require(BigDecimal(base), "Failed to create BigDecimal from base: \(base)")
    let expectedNum = BigDecimal(components: expected).normalized()
    let result = num.raised(to: exponent).scaled(to: expectedNum.scale)
    #expect(result.description == expectedNum.description)
  }

  @Test("Raising special values to integer power")
  func raisedToIntegerPowerSpecialValues() {
    #expect(BigDecimal.nan.raised(to: 1).isNaN)
    #expect(BigDecimal.infinity.raised(to: -1) == .zero)
    #expect((-BigDecimal.infinity).raised(to: -1) == .zero)
    #expect(BigDecimal.infinity.raised(to: 1) == .infinity)
    #expect((-BigDecimal.infinity).raised(to: 1) == (-.infinity))
    #expect(BigDecimal.infinity.raised(to: 2) == .infinity)
    #expect((-BigDecimal.infinity).raised(to: 2) == .infinity)
    #expect(BigDecimal.zero.raised(to: -1) == .infinity)
    #expect(BigDecimal.zero.raised(to: 1) == .zero)
  }

  @Test(
    "Square root",
    arguments: [
      // Small numbers
      ("0", "0", 0),
      ("1", "1", 0),
      ("4", "2", 0),
      ("9", "3", 0),
      ("16", "4", 0),
      ("25", "5", 0),

      // Decimals
      ("0.25", "0.5", 1),
      ("0.01", "0.1", 1),
      ("0.0001", "0.01", 2),
      ("0.000001", "0.001", 3),

      // Large numbers
      ("100000000", "10000", 0),
      ("0.00000001", "0.0001", 4),

      // Special cases
      ("-1", "nan", 0),
      ("-0.25", "nan", 0),
      ("inf", "nan", 0),
      ("-inf", "nan", 0),
      ("nan", "nan", 0),
    ] as [(String, String, Int)]
  )
  func squareRoot(_ value: String, _ expected: String, _ expectedScale: Int) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    let result = num.squareRoot().scaled(to: expectedNum.scale)
    var formResult = num
    formResult.formSquareRoot()
    formResult.scale(to: expectedScale)
    #expect(result.description == expectedNum.description)
    #expect(formResult.description == expectedNum.description)
  }

  @Test(
    "Greatest common divisor",
    arguments: [
      // Small numbers
      ("0", "0", "0", 0),
      ("0", "1", "1", 0),
      ("1", "0", "1", 0),
      ("1", "1", "1", 0),
      ("2", "4", "2", 0),
      ("4", "2", "2", 0),
      ("6", "9", "3", 0),
      ("9", "6", "3", 0),
      ("-2", "4", "2", 0),
      ("2", "-4", "2", 0),
      ("-2", "-4", "2", 0),

      // Decimals
      ("0.1", "0.2", "0.1", 1),
      ("0.2", "0.4", "0.2", 1),
      ("0.3", "0.6", "0.3", 1),
      ("-0.1", "0.2", "0.1", 1),
      ("0.1", "-0.2", "0.1", 1),
      ("-0.1", "-0.2", "0.1", 1),

      // Large numbers
      ("100000000", "200000000", "100000000", 0),
      ("-100000000", "200000000", "100000000", 0),
      ("100000000", "-200000000", "100000000", 0),
      ("-100000000", "-200000000", "100000000", 0),
    ] as [(String, String, String, Int)]
  )
  func greatestCommonDivisor(_ a: String, _ b: String, _ expected: String, _ expectedScale: Int) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from a: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from b: \(b)")
    let result = numA.greatestCommonDivisor(numB)
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    #expect(result.mantissa == expectedNum.mantissa)
    #expect(result.scale == expectedScale)
  }

  @Test(
    "Lowest common multiple",
    arguments: [
      // Small numbers
      ("0", "0", "0", 0),
      ("0", "1", "0", 0),
      ("1", "0", "0", 0),
      ("1", "1", "1", 0),
      ("2", "4", "4", 0),
      ("4", "2", "4", 0),
      ("6", "9", "18", 0),
      ("9", "6", "18", 0),
      ("-2", "4", "4", 0),
      ("2", "-4", "4", 0),
      ("-2", "-4", "4", 0),

      // Decimals
      ("0.1", "0.2", "0.2", 1),
      ("0.2", "0.4", "0.4", 1),
      ("0.3", "0.6", "0.6", 1),
      ("-0.1", "0.2", "0.2", 1),
      ("0.1", "-0.2", "0.2", 1),
      ("-0.1", "-0.2", "0.2", 1),

      // Large numbers
      ("100000000", "200000000", "200000000", 0),
      ("-100000000", "200000000", "200000000", 0),
      ("100000000", "-200000000", "200000000", 0),
      ("-100000000", "-200000000", "200000000", 0),
    ] as [(String, String, String, Int)]
  )
  func lowestCommonMultiple(_ a: String, _ b: String, _ expected: String, _ expectedScale: Int) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from a: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from b: \(b)")
    let result = numA.lowestCommonMultiple(numB)
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    #expect(result.mantissa == expectedNum.mantissa)
    #expect(result.scale == expectedScale)
  }

  // MARK: - Rounding Tests

  @Test(
    "Rounding to decimal places",
    arguments: [
      (String(format: "%.60f", 0.005), 2, .toNearestOrAwayFromZero, "0.01"),
      // Zero
      ("0", 0, .towardZero, "0"),
      ("0.0", 0, .towardZero, "0"),
      ("0.00", 0, .towardZero, "0"),

      // Positive numbers
      ("0.00123", 3, .towardZero, "0.001"),
      ("0.00123", 3, .up, "0.002"),
      ("0.00123", 3, .down, "0.001"),
      ("0.00123", 3, .awayFromZero, "0.002"),
      ("0.00123", 3, .toNearestOrAwayFromZero, "0.001"),
      ("0.00150", 3, .toNearestOrAwayFromZero, "0.002"),
      ("0.00123", 3, .toNearestOrEven, "0.001"),
      ("0.00150", 3, .toNearestOrEven, "0.002"),
      ("0.00250", 3, .toNearestOrEven, "0.002"),
      ("0.123", 1, .towardZero, "0.1"),
      ("0.123", 1, .up, "0.2"),
      ("0.123", 1, .down, "0.1"),
      ("0.123", 1, .awayFromZero, "0.2"),
      ("0.123", 1, .toNearestOrAwayFromZero, "0.1"),
      ("0.150", 1, .toNearestOrAwayFromZero, "0.2"),
      ("0.123", 1, .toNearestOrEven, "0.1"),
      ("0.150", 1, .toNearestOrEven, "0.2"),
      ("0.250", 1, .toNearestOrEven, "0.2"),
      ("1.23", 0, .towardZero, "1"),
      ("1.23", 0, .up, "2"),
      ("1.73", 0, .down, "1"),
      ("1.23", 0, .awayFromZero, "2"),
      ("1.23", 0, .toNearestOrAwayFromZero, "1"),
      ("1.50", 0, .toNearestOrAwayFromZero, "2"),
      ("1.23", 0, .toNearestOrEven, "1"),
      ("1.50", 0, .toNearestOrEven, "2"),
      ("2.50", 0, .toNearestOrEven, "2"),

      // Negative numbers
      ("-0.00123", 3, .towardZero, "-0.001"),
      ("-0.00123", 3, .up, "-0.001"),
      ("-0.00123", 3, .down, "-0.002"),
      ("-0.00123", 3, .awayFromZero, "-0.002"),
      ("-0.00123", 3, .toNearestOrAwayFromZero, "-0.001"),
      ("-0.00150", 3, .toNearestOrAwayFromZero, "-0.002"),
      ("-0.00123", 3, .toNearestOrEven, "-0.001"),
      ("-0.00150", 3, .toNearestOrEven, "-0.002"),
      ("-0.00250", 3, .toNearestOrEven, "-0.002"),
      ("-0.123", 1, .towardZero, "-0.1"),
      ("-0.123", 1, .up, "-0.1"),
      ("-0.123", 1, .down, "-0.2"),
      ("-0.123", 1, .awayFromZero, "-0.2"),
      ("-0.123", 1, .toNearestOrAwayFromZero, "-0.1"),
      ("-0.150", 1, .toNearestOrAwayFromZero, "-0.2"),
      ("-0.123", 1, .toNearestOrEven, "-0.1"),
      ("-0.150", 1, .toNearestOrEven, "-0.2"),
      ("-0.250", 1, .toNearestOrEven, "-0.2"),
      ("-1.23", 0, .towardZero, "-1"),
      ("-1.23", 0, .up, "-1"),
      ("-1.23", 0, .down, "-2"),
      ("-1.23", 0, .awayFromZero, "-2"),
      ("-1.23", 0, .toNearestOrAwayFromZero, "-1"),
      ("-1.50", 0, .toNearestOrAwayFromZero, "-2"),
      ("-1.23", 0, .toNearestOrEven, "-1"),
      ("-1.50", 0, .toNearestOrEven, "-2"),
      ("-2.50", 0, .toNearestOrEven, "-2"),

      // Special values
      ("inf", 2, .towardZero, "inf"),
      ("-inf", 2, .towardZero, "-inf"),
      ("nan", 2, .towardZero, "nan"),
    ] as [(String, Int, FloatingPointRoundingRule, String)]
  )
  func roundingToDecimalPlaces(
    _ value: String,
    _ places: Int,
    _ rule: FloatingPointRoundingRule,
    _ expected: String
  ) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    let result = num.rounded(rule, places: places)
    #expect(result.description == expectedNum.description)
    if places == 0 {
      let roundToZeroResult = num.rounded(rule)
      #expect(roundToZeroResult.description == expectedNum.description)
    }
  }

  @Test(
    "Rounding to integer",
    arguments: [
      // Zero
      ("0", .towardZero, "0"),
      ("0.0", .towardZero, "0"),
      ("0.00", .towardZero, "0"),

      // Positive numbers
      ("1.23", .towardZero, "1"),
      ("1.23", .up, "2"),
      ("1.73", .down, "1"),
      ("1.23", .awayFromZero, "2"),
      ("1.23", .toNearestOrAwayFromZero, "1"),
      ("1.50", .toNearestOrAwayFromZero, "2"),
      ("1.23", .toNearestOrEven, "1"),
      ("1.50", .toNearestOrEven, "2"),
      ("2.50", .toNearestOrEven, "2"),

      // Negative numbers
      ("-1.23", .towardZero, "-1"),
      ("-1.23", .up, "-1"),
      ("-1.23", .down, "-2"),
      ("-1.23", .awayFromZero, "-2"),
      ("-1.23", .toNearestOrAwayFromZero, "-1"),
      ("-1.50", .toNearestOrAwayFromZero, "-2"),
      ("-1.23", .toNearestOrEven, "-1"),
      ("-1.50", .toNearestOrEven, "-2"),
      ("-2.50", .toNearestOrEven, "-2"),

      // Special values
      ("inf", .towardZero, "0"),
      ("-inf", .towardZero, "0"),
      ("nan", .towardZero, "0"),
    ] as [(String, FloatingPointRoundingRule, String)]
  )
  func roundingToInteger(_ value: String, _ rule: FloatingPointRoundingRule, _ expected: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let result = num.integer(rounding: rule)
    let expectedNum = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    #expect(result == expectedNum.mantissa)
  }

  // MARK: - Comparison Tests

  @Test(
    "Equality",
    arguments: [
      // Same numbers
      ("0", "0", true),
      ("1", "1", true),
      ("-1", "-1", true),
      ("0.1", "0.1", true),
      ("-0.1", "-0.1", true),

      // Different representations of same value
      ("1.0", "1", true),
      ("1.00", "1", true),
      ("1.0", "1.00", true),
      ("-1.0", "-1", true),
      ("-1.00", "-1", true),

      // Different numbers
      ("0", "1", false),
      ("1", "-1", false),
      ("0.1", "0.2", false),
      ("-0.1", "-0.2", false),

      // Special values
      ("nan", "nan", false),    // NaN is not equal to anything, including itself
      ("inf", "inf", true),
      ("-inf", "-inf", true),
      ("inf", "-inf", false),
      ("nan", "0", false),
      ("inf", "0", false),
      ("-inf", "0", false),
    ] as [(String, String, Bool)]
  )
  func equality(_ a: String, _ b: String, _ expected: Bool) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    #expect((numA == numB) == expected)
  }

  @Test(
    "Comparison",
    arguments: [
      // Equal numbers
      ("0", "0", true, false, true, false, true),
      ("1", "1", true, false, true, false, true),
      ("-1", "-1", true, false, true, false, true),
      ("0.1", "0.1", true, false, true, false, true),
      ("-0.1", "-0.1", true, false, true, false, true),

      // Less than
      ("0", "1", false, true, true, false, false),
      ("1", "2", false, true, true, false, false),
      ("-2", "-1", false, true, true, false, false),
      ("0.1", "0.2", false, true, true, false, false),
      ("-0.2", "-0.1", false, true, true, false, false),

      // Greater than
      ("1", "0", false, false, false, true, true),
      ("2", "1", false, false, false, true, true),
      ("-1", "-2", false, false, false, true, true),
      ("0.2", "0.1", false, false, false, true, true),
      ("-0.1", "-0.2", false, false, false, true, true),

      // Special values
      ("nan", "nan", false, false, false, false, false),
      ("inf", "inf", true, false, true, false, true),
      ("-inf", "-inf", true, false, true, false, true),
      ("-inf", "inf", false, true, true, false, false),
      ("inf", "-inf", false, false, false, true, true),
      ("nan", "0", false, false, false, false, false),
      ("0", "inf", false, true, true, false, false),
      ("0", "-inf", false, false, false, true, true),
    ] as [(String, String, Bool, Bool, Bool, Bool, Bool)]
  )
  func comparison(
    _ a: String,
    _ b: String,
    _ isEqual: Bool,
    _ isLess: Bool,
    _ isLessOrEqual: Bool,
    _ isGreater: Bool,
    _ isGreaterOrEqual: Bool
  ) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    let equal = numA == numB
    let less = numA < numB
    let greater = numA > numB
    let lessEqual = numA <= numB
    let greaterEqual = numA >= numB
    #expect(equal == isEqual)
    #expect(less == isLess)
    #expect(lessEqual == isLessOrEqual)
    #expect(greater == isGreater)
    #expect(greaterEqual == isGreaterOrEqual)
  }

  @Test(
    "Hashing",
    arguments: [
      ("42", "42", "100"),
      ("1.5", "1.5", "1.6"),
      ("0.001", "0.001", "0.002"),
      ("-42", "-42", "-100"),
      ("-1.5", "-1.5", "-1.6"),
      ("-0.001", "-0.001", "-0.002"),
      ("-42", "-42", "42"),
      ("42", "42", "-42"),
      ("1.5", "1.5", "-1.5"),
      ("-1.5", "-1.5", "1.5"),
      ("0.001", "0.001", "-0.001"),
      ("-0.001", "-0.001", "0.001"),
    ] as [(String, String, String)]
  )
  func hashing(_ a: String, _ b: String, _ c: String) throws {
    let numA = try #require(BigDecimal(a), "Failed to create BigDecimal from string: \(a)")
    let numB = try #require(BigDecimal(b), "Failed to create BigDecimal from string: \(b)")
    let numC = try #require(BigDecimal(c), "Failed to create BigDecimal from string: \(c)")

    #expect(numA.hashValue == numB.hashValue)
    #expect(numA.hashValue != numC.hashValue)
  }

  @Test("Strideable conformance")
  func strideableConformance() throws {
    let start = BigDecimal("1.5")
    let end = BigDecimal("3.0")
    let step = BigDecimal("0.5")

    // Test distance
    let distance = start.distance(to: end)
    #expect(distance == BigDecimal("1.5"))

    // Test advancing
    let advanced = start.advanced(by: step)
    #expect(advanced == BigDecimal("2.0"))

    // Test negative distance
    let negDistance = end.distance(to: start)
    #expect(negDistance == BigDecimal("-1.5"))

    // Test advancing by negative amount
    let negAdvanced = end.advanced(by: negDistance)
    #expect(negAdvanced == start)

    // Test zero distance
    let zeroDistance = start.distance(to: start)
    #expect(zeroDistance == .zero)
  }

  // MARK: - Conversion Tests

  @Test(
    "String conversion",
    arguments: [
      // Zero
      ("0", "0"),
      ("0.0", "0.0"),
      ("0.00", "0.00"),

      // Positive numbers
      ("1", "1"),
      ("42", "42"),
      ("1.0", "1.0"),
      ("1.23", "1.23"),
      ("0.1", "0.1"),
      ("0.01", "0.01"),

      // Negative numbers
      ("-1", "-1"),
      ("-42", "-42"),
      ("-1.0", "-1.0"),
      ("-1.23", "-1.23"),
      ("-0.1", "-0.1"),
      ("-0.01", "-0.01"),

      // Special values
      ("inf", "inf"),
      ("-inf", "-inf"),
      ("nan", "nan"),
    ] as [(String, String)]
  )
  func stringConversion(_ value: String, _ expected: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    #expect(num.description == expected)
    #expect(num.debugDescription == "BigDecimal(\(expected))")
    #expect(String(num) == expected)
    #expect(String(describing: num) == expected)

    // Test round-trip conversion
    let roundTrip = try #require(BigDecimal(expected), "Failed to create BigDecimal from expected: \(expected)")
    if !num.isNaN {    // NaN is not equal to itself
      #expect(roundTrip == num)
    }
  }

  @Test(
    "Formatted strings",
    arguments: [
      (
        BigDecimal("1234567.890"), "1,234,567.890",
        DecimalFormatStyle.number.locale(Locale(identifier: "en_US"))
      ),
      (
        BigDecimal("-1234567.890"), "-1,234,567.890",
        DecimalFormatStyle.number.locale(Locale(identifier: "en_US"))
      ),
      (
        BigDecimal("100000000000000.0000"), "100000000000000.0000",
        DecimalFormatStyle.number.locale(Locale(identifier: "en_US")).grouping(.never)
      ),
      (
        BigDecimal("-100000000000000.0000"), "-100000000000000.0000",
        DecimalFormatStyle.number.locale(Locale(identifier: "en_US")).grouping(.never)
      ),
      (
        BigDecimal("184467440737.09551615"), "+184,467,440,737.095516",
        DecimalFormatStyle.number.grouping(.automatic).sign(strategy: .always)
      ),
      (
        BigDecimal("-184467440737.09551615"), "-184,467,440,737.095516",
        DecimalFormatStyle.number.grouping(.automatic).sign(strategy: .always)
      ),
      (
        BigDecimal("184467440737.09551615"), "184,467,440,737.1",
        DecimalFormatStyle.number.precision(.fractionLength(0...2))
      ),
      (
        BigDecimal("184467440737.09551615"), "184,467,440,737.10",
        DecimalFormatStyle.number.precision(.fractionLength(2))
      ),
    ] as [(BigDecimal, String, DecimalFormatStyle)]
  )
  func formattedStrings(_ value: BigDecimal, _ expected: String, _ style: DecimalFormatStyle) {
    let formatted = value.formatted(style)
    #expect(formatted == expected)
  }

  @Test(
    "Integer conversion",
    arguments: [
      // Zero
      ("0", 0),
      ("0.0", 0),
      ("0.00", 0),

      // Positive numbers
      ("1", 1),
      ("42", 42),
      ("1.0", 1),
      ("100.0", 100),

      // Negative numbers
      ("-1", -1),
      ("-42", -42),
      ("-1.0", -1),
      ("-100.0", -100),

      // Non-integer values
      ("1.23", nil),
      ("-1.23", nil),
      ("0.1", nil),
      ("-0.1", nil),

      // Special values
      ("inf", nil),
      ("-inf", nil),
      ("nan", nil),
    ] as [(String, Int?)]
  )
  func integerConversion(_ value: String, _ expected: Int?) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")

    // Test Int(exactly:)
    #expect(Int(exactly: num) == expected)

    // Test Int(_:)
    if let expected {
      #expect(Int(num) == expected)
    }
  }

  @Test(
    "Floating point conversion",
    arguments: [
      // Zero
      ("0", 0.0),
      ("0.0", 0.0),
      ("0.00", 0.0),

      // Positive numbers
      ("1", 1.0),
      ("42", 42.0),
      ("1.0", 1.0),
      ("1.23", 1.23),
      ("0.1", 0.1),
      ("0.01", 0.01),

      // Negative numbers
      ("-1", -1.0),
      ("-42", -42.0),
      ("-1.0", -1.0),
      ("-1.23", -1.23),
      ("-0.1", -0.1),
      ("-0.01", -0.01),

      // Special values
      ("inf", Double.infinity),
      ("-inf", -Double.infinity),
      ("nan", Double.nan),
    ] as [(String, Double)]
  )
  func floatingPointConversion(_ value: String, _ expected: Double) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let result = Double(num)

    if num.isNaN {
      #expect(result.isNaN)
    } else {
      #expect(result == expected)
    }
  }

  @Test("Exact floating point conversion")
  func exactFloatingPointConversion() throws {
    let num = BigDecimal(1.0)
    #expect(Float16(exactly: num) == 1.0)
    #expect(Float32(exactly: num) == 1.0)
    #expect(Float64(exactly: num) == 1.0)

    let largeMantissa = BigInt(isNegative: false, words: Array(repeating: 0xDEADBEEFDEADBE, count: 1))
    let num2 = BigDecimal(mantissa: largeMantissa, scale: 0)
    #expect(Float16(exactly: num2) == nil)
    #expect(Float32(exactly: num2) == nil)
    #expect(Float64(exactly: num2) == nil)
  }

  @Test(
    "Normalize",
    arguments: [
      ("1.200", "1.2"),
      ("1.0", "1"),
      ("1.00", "1"),
      ("1.000", "1"),
      ("1.0000", "1"),
      ("1.00000", "1"),
      ("01.00", "1"),
      ("1234.56700", "1234.567"),
    ] as [(String, String)]
  )
  func normalize(_ value: String, _ expected: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    #expect(num.normalized().description == expected)
  }

  @Test(
    "BigInt Accessor",
    arguments: [
      (BigDecimal("0.0"), 0),
      (BigDecimal("0.00"), 0),
      (BigDecimal("1.0"), 1),
      (BigDecimal("1.00"), 1),
      (BigDecimal("1.000"), 1),
      (BigDecimal("10.0"), 10),
      (BigDecimal("10.00"), 10),
      (BigDecimal("10.000"), 10),
      (BigDecimal("200.000"), 200),
      (BigDecimal("200.0000"), 200),
      (BigDecimal("3000.00000"), 3000),
      (BigDecimal("1234567890"), 1234567890),
      (BigDecimal("-1234567890"), -1234567890),
      (BigDecimal("-10.00"), -10),
      (BigDecimal(mantissa: .one, scale: -4), 10000),
      (BigDecimal(mantissa: .minusOne, scale: -10), -10000000000),
      (BigDecimal("1.23"), nil),
      (BigDecimal("-1.1"), nil),
      (BigDecimal("inf"), nil),
      (BigDecimal("-inf"), nil),
      (BigDecimal("nan"), nil),
    ] as [(BigDecimal, Int?)]
  )
  func bigIntAccessor(_ value: BigDecimal, _ expected: Int?) throws {
    if let expected {
      let bigInt = try #require(value.integer, "Failed to get integer from value: \(value)")
      #expect(bigInt == expected)
    } else {
      #expect(value.integer == nil)
    }
  }

  @Test(
    "Mantissa Accessor",
    arguments: [
      ("1.23"),
      ("-1.23"),
      ("1.023"),
      ("-1.023"),
      ("0.0"),
      ("inf"),
      ("-inf"),
      ("nan"),
    ] as [String]
  )
  func mantissaAccessor(_ value: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let mantissa = num.mantissa
    if num.isFinite {
      #expect(mantissa == num.mantissa)
      #expect(mantissa.description == num.description.replacing(/(\.0+$)|\./, with: ""))
    } else {
      #expect(mantissa == .zero)
    }
  }

  @Test(
    "Magnitude Accessor",
    arguments: [
      ("1.23"),
      ("-1.23"),
      ("0.0"),
      ("inf"),
      ("-inf"),
      ("nan"),
    ] as [String]
  )
  func magnitudeAccessor(_ value: String) throws {
    let num = try #require(BigDecimal(value), "Failed to create BigDecimal from value: \(value)")
    let magnitude = num.magnitude
    if num.isNegative {
      #expect(magnitude == -num)
      #expect(magnitude.description == (-num).description)
    } else if !num.isNaN {
      #expect(magnitude == num)
      #expect(magnitude.description == num.description)
    } else {
      #expect(magnitude.isNaN)
      #expect(magnitude.description == num.description)
    }
  }

  @Test(
    "Normalize",
    arguments: [
      (BigDecimal("0.0"), "0"),
      (BigDecimal("0.00"), "0"),
      (BigDecimal("1.0"), "1"),
      (BigDecimal("1.00"), "1"),
      (BigDecimal("1.000"), "1"),
      (BigDecimal("10.0"), "10"),
      (BigDecimal("10.00"), "10"),
      (BigDecimal("-0.0"), "0"),
      (BigDecimal("-0.00"), "0"),
      (BigDecimal("-1.0"), "-1"),
      (BigDecimal("-1.00"), "-1"),
      (BigDecimal("-1.000"), "-1"),
      (BigDecimal("-10.0"), "-10"),
      (BigDecimal("-10.00"), "-10"),
      (.nan, "nan"),
      (.infinity, "inf"),
      (-.infinity, "-inf"),
    ] as [(BigDecimal, String)]
  )
  func properties(_ value: BigDecimal, _ expectedNormalized: String) throws {
    var normalizeValue = value
    normalizeValue.normalize()
    let normalizedValue = value.normalized()
    let removedTrailingZerosValue = value.removingTrailingZeros()
    #expect(normalizeValue.description == expectedNormalized)
    #expect(normalizedValue.description == expectedNormalized)
    #expect(removedTrailingZerosValue.description == expectedNormalized)
    if !value.isNaN {
      #expect(normalizeValue == normalizedValue)
      #expect(normalizedValue == removedTrailingZerosValue)
    } else {
      #expect(normalizeValue.isNaN)
      #expect(normalizedValue.isNaN)
      #expect(removedTrailingZerosValue.isNaN)
    }
  }

  @Test("FloatingPoint Protocol")
  func floatingPointProtocol() throws {
    #expect(BigDecimal.radix == 10)
    #expect(BigDecimal.nan.isNaN)
    #expect(BigDecimal.signalingNaN.isNaN)
    #expect(BigDecimal.signalingNaN.isSignalingNaN == false)
    #expect(BigDecimal.greatestFiniteMagnitude == BigDecimal(mantissa: .one << 1024, scale: 0))
    #expect(BigDecimal.leastNormalMagnitude == BigDecimal(mantissa: .one, scale: 0))
    #expect(BigDecimal.leastNonzeroMagnitude == BigDecimal(mantissa: .one, scale: Int.max))
    #expect(BigDecimal.zero.ulp == .one)
    #expect(BigDecimal("0.99999").ulp == BigDecimal("0.00001"))
    #expect(BigDecimal.nan.ulp.isNaN)
    #expect(BigDecimal.infinity.ulp.isNaN)
    #expect(BigDecimal.zero.nextUp == .one)
    #expect(BigDecimal("0.99999").nextUp == .one)
    #expect(BigDecimal.nan.nextUp.isNaN)
    #expect(BigDecimal.infinity.nextUp == .infinity)
    #expect((-BigDecimal.infinity).nextUp == (-.infinity))
    #expect(BigDecimal.zero.nextDown == -.one)
    #expect(BigDecimal("0.00001").nextDown == .zero)
    #expect(BigDecimal.nan.nextDown.isNaN)
    #expect(BigDecimal.infinity.nextDown == .infinity)
    #expect((-BigDecimal.infinity).nextDown == (-.infinity))
    #expect(BigDecimal.zero.exponent == 0)
    #expect(BigDecimal("0.00001").exponent == -5)    // Exponent = -scale
    #expect(BigDecimal.nan.exponent == 0)
    #expect(BigDecimal.infinity.exponent == 0)
    #expect(BigDecimal.zero.significandWidth == 1)
    #expect(BigDecimal("0.00001").significandWidth == 2)

    var x = BigDecimal.one
    x.addProduct(.one, .two)
    #expect(x == BigDecimal(3))

    #expect(BigDecimal.two.isEqual(to: .two))
    #expect(BigDecimal.one.isLess(than: .two))
    #expect(BigDecimal.two.isLessThanOrEqualTo(.two))
    #expect(BigDecimal.two.isTotallyOrdered(belowOrEqualTo: .two))
    #expect(BigDecimal.nan.isTotallyOrdered(belowOrEqualTo: .nan) == false)
    #expect(BigDecimal.zero.floatingPointClass == .positiveZero)
    #expect((-BigDecimal.zero).floatingPointClass == .positiveZero)
    #expect(BigDecimal.nan.floatingPointClass == .quietNaN)
    #expect(BigDecimal.infinity.floatingPointClass == .positiveInfinity)
    #expect((-BigDecimal.infinity).floatingPointClass == .negativeInfinity)
    #expect(BigDecimal.one.floatingPointClass == .positiveNormal)
    #expect((-BigDecimal.one).floatingPointClass == .negativeNormal)
    #expect(BigDecimal.nan.isCanonical)
    #expect(BigDecimal.one.isNormal)
    #expect(BigDecimal.zero.isNormal == false)
    #expect(BigDecimal.nan.isNormal == false)
    #expect(BigDecimal.infinity.isNormal == false)
    #expect(BigDecimal.zero.isSubnormal == false)
    #expect(BigDecimal.one.isSubnormal == false)
    #expect(BigDecimal.nan.isSubnormal == false)
    #expect(BigDecimal.infinity.isSubnormal == false)
    #expect(BigDecimal.zero.isSignalingNaN == false)
    #expect(BigDecimal.nan.isSignalingNaN == false)
    #expect(BigDecimal.infinity.isSignalingNaN == false)
    #expect(BigDecimal.zero.isSignaling == false)
    #expect(BigDecimal.nan.isSignaling == false)
    #expect(BigDecimal.infinity.isSignaling == false)
    #expect((BigDecimal.one).sign == .plus)
    #expect((-BigDecimal.one).sign == .minus)
    #expect(BigDecimal.zero.sign == .plus)
    #expect((-BigDecimal.zero).sign == .plus)
    #expect(BigDecimal.nan.sign == .plus)
    #expect(BigDecimal.infinity.sign == .plus)
    #expect((-BigDecimal.infinity).sign == .minus)
    #expect(BigDecimal(mantissa: .one, scale: 10).significand == .one)
    #expect(BigDecimal.nan.significand.isNaN)
    #expect(BigDecimal.infinity.significand == .infinity)
    #expect((-BigDecimal.infinity).significand == -.infinity)
  }
}
