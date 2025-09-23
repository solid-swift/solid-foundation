//
//  BigIntTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/16/25.
//

@testable import SolidNumeric
import Foundation
import Testing


@Suite("BigInt Tests")
struct BigIntTests {

  static let testData = BigIntTestData.loadFromBundle(bundle: .module)

  func signum(_ int: some BinaryInteger) -> Int {
    Int(int.signum())
  }

  @Test("Default initialization")
  func defaultInitialization() {
    let zero = BigInt()
    #expect(zero.isZero)
    #expect(zero.magnitude.words == [0])
  }

  @Test(
    "Integer literal initialization",
    arguments: [
      // Positive numbers
      (0, [0], 0),
      (42, [42], 1),
      (0xFF, [0xFF], 1),
      (0xFFFF, [0xFFFF], 1),
      (0xFFFFFFFF, [0xFFFFFFFF], 1),
      (0xFFFFFFFFFFFFFFFF, [0xFFFFFFFFFFFFFFFF], 1),
      (0x123456789ABCDEF0, [0x123456789ABCDEF0], 1),
      (0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, [0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF], 1),
      (0x123456789ABCDEF0123456789ABCDEF0, [0x123456789ABCDEF0, 0x123456789ABCDEF0], 1),
      (
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        [0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF],
        1
      ),
      (
        0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0,
        [0x123456789ABCDEF0, 0x123456789ABCDEF0, 0x123456789ABCDEF0, 0x123456789ABCDEF0],
        1
      ),
      // Negative numbers
      (-1, [1], -1),
      (-42, [42], -1),
      (-0xFF, [0xFF], -1),
      (-0xFFFF, [0xFFFF], -1),
      (-0xFFFFFFFF, [0xFFFFFFFF], -1),
      (-0xFFFFFFFFFFFFFFFF, [0xFFFFFFFFFFFFFFFF], -1),
      (-0x123456789ABCDEF0, [0x123456789ABCDEF0], -1),
      (-0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, [0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF], -1),
      (-0x123456789ABCDEF0123456789ABCDEF0, [0x123456789ABCDEF0, 0x123456789ABCDEF0], -1),
      (
        -0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        [0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF],
        -1
      ),
      (
        -0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0,
        [0x123456789ABCDEF0, 0x123456789ABCDEF0, 0x123456789ABCDEF0, 0x123456789ABCDEF0],
        -1
      ),
    ] as [(StaticBigInt, [UInt], Int)]
  )
  func integerLiteralInitialization(_ value: StaticBigInt, _ expectedWords: [UInt], _ expectedSignum: Int) throws {
    let num: BigInt = BigInt(integerLiteral: value)
    #expect(num.magnitude.words == BigUInt.Words(expectedWords))
    #expect(num.signum() == expectedSignum)
  }

  @Test(
    "Binary integer initialization",
    arguments: [
      // Positive numbers
      // UInt8 tests
      (UInt8.max, [UInt(UInt8.max)]),
      (UInt8.max - 1, [UInt(UInt8.max - 1)]),
      (UInt8.min, [UInt(UInt8.min)]),

      // UInt16 tests
      (UInt16.max, [UInt(UInt16.max)]),
      (UInt16.max - 1, [UInt(UInt16.max - 1)]),
      (UInt16.min, [UInt(UInt16.min)]),

      // UInt32 tests
      (UInt32.max, [UInt(UInt32.max)]),
      (UInt32.max - 1, [UInt(UInt32.max - 1)]),
      (UInt32.min, [UInt(UInt32.min)]),

      // UInt64 tests
      (UInt64.max, [UInt(UInt64.max)]),
      (UInt64.max - 1, [UInt(UInt64.max - 1)]),
      (UInt64.min, [UInt(UInt64.min)]),

      // UInt tests
      (UInt.max, [UInt(UInt.max)]),
      (UInt.max - 1, [UInt(UInt.max - 1)]),
      (UInt.min, [UInt(UInt.min)]),

      // UInt128 tests
      (UInt128.max, [UInt.max, UInt.max]),
      (UInt128.max - 1, [UInt.max - 1, UInt.max]),
      (UInt128.min, [UInt(UInt128.min)]),

      // Negative numbers
      // Int8 tests
      (Int8.min, [UInt(Int8.max) + 1]),
      (Int8.max, [UInt(Int8.max)]),
      (-Int8.max, [UInt(Int8.max)]),

      // Int16 tests
      (Int16.min, [UInt(Int16.max) + 1]),
      (Int16.max, [UInt(Int16.max)]),
      (-Int16.max, [UInt(Int16.max)]),

      // Int32 tests
      (Int32.min, [UInt(Int32.max) + 1]),
      (Int32.max, [UInt(Int32.max)]),
      (-Int32.max, [UInt(Int32.max)]),

      // Int64 tests
      (Int64.min, [UInt(Int64.max) + 1]),
      (Int64.max, [UInt(Int64.max)]),
      (-Int64.max, [UInt(Int64.max)]),

      // Int tests
      (Int.min, [UInt.max / 2 + 1]),
      (Int.max, [UInt(Int.max)]),
      (-Int.max, [UInt(Int.max)]),

      // Int128 tests
      (Int128.min, [0, UInt.max / 2 + 1]),
      (Int128.max, [UInt.max, UInt.max / 2]),
      (-Int128.max, [UInt.max, UInt.max / 2]),
    ] as [(any BinaryInteger & Sendable, [UInt])]
  )
  func binaryIntegerInitialization(_ value: any BinaryInteger & Sendable, _ expectedWords: [UInt]) {
    let num = BigInt(value)
    #expect(num.magnitude.words == BigUInt.Words(expectedWords))
    #expect(num.signum() == signum(value))
  }

  @Test(
    "Exact binary integer initialization",
    arguments: [
      // UInt8 tests
      (UInt8.max, [UInt(UInt8.max)]),
      (UInt8.max - 1, [UInt(UInt8.max - 1)]),
      (UInt8.min, [UInt(UInt8.min)]),

      // UInt16 tests
      (UInt16.max, [UInt(UInt16.max)]),
      (UInt16.max - 1, [UInt(UInt16.max - 1)]),
      (UInt16.min, [UInt(UInt16.min)]),

      // UInt32 tests
      (UInt32.max, [UInt(UInt32.max)]),
      (UInt32.max - 1, [UInt(UInt32.max - 1)]),
      (UInt32.min, [UInt(UInt32.min)]),

      // UInt64 tests
      (UInt64.max, [UInt(UInt64.max)]),
      (UInt64.max - 1, [UInt(UInt64.max - 1)]),
      (UInt64.min, [UInt(UInt64.min)]),

      // UInt tests
      (UInt.max, [UInt(UInt.max)]),
      (UInt.max - 1, [UInt(UInt.max - 1)]),
      (UInt.min, [UInt(UInt.min)]),

      // UInt128 tests
      (UInt128.max, [UInt.max, UInt.max]),
      (UInt128.max - 1, [UInt.max - 1, UInt.max]),
      (UInt128.min, [UInt(UInt128.min)]),

      // Int8 tests
      (Int8.max, [UInt(Int8.max)]),
      (Int8.max - 1, [UInt(Int8.max - 1)]),
      (Int8.min, [UInt(Int8.max) + 1]),

      // Int16 tests
      (Int16.max, [UInt(Int16.max)]),
      (Int16.max - 1, [UInt(Int16.max - 1)]),
      (Int16.min, [UInt(Int16.max) + 1]),

      // Int32 tests
      (Int32.max, [UInt(Int32.max)]),
      (Int32.max - 1, [UInt(Int32.max - 1)]),
      (Int32.min, [UInt(Int32.max) + 1]),

      // Int64 tests
      (Int64.max, [UInt(Int64.max)]),
      (Int64.max - 1, [UInt(Int64.max - 1)]),
      (Int64.min, [UInt(Int64.max) + 1]),

      // Int tests
      (Int.max, [UInt(Int.max)]),
      (Int.max - 1, [UInt(Int.max - 1)]),
      (Int.min, [UInt.max / 2 + 1]),

      // Int128 tests
      (Int128.max, [UInt.max, UInt(Int.max)]),
      (Int128.max - 1, [UInt.max - 1, UInt(Int.max)]),
      (Int128.min, [0, UInt.max / 2 + 1]),
    ] as [(any BinaryInteger & Sendable, [UInt])]
  )
  func exactBinaryIntegerInitialization(_ value: any BinaryInteger & Sendable, _ expectedWords: [UInt]) throws {
    switch value {
    case let uint as UInt:
      let num = try #require(BigInt(exactly: uint))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == uint.signum())
    case let uint8 as UInt8:
      let num = try #require(BigInt(exactly: uint8))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == uint8.signum())
    case let uint16 as UInt16:
      let num = try #require(BigInt(exactly: uint16))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == uint16.signum())
    case let uint32 as UInt32:
      let num = try #require(BigInt(exactly: uint32))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == uint32.signum())
    case let uint64 as UInt64:
      let num = try #require(BigInt(exactly: uint64))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == uint64.signum())
    case let uint128 as UInt128:
      let num = try #require(BigInt(exactly: uint128))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == uint128.signum())
    case let int8 as Int8:
      let num = try #require(BigInt(exactly: int8))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == int8.signum())
    case let int16 as Int16:
      let num = try #require(BigInt(exactly: int16))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == int16.signum())
    case let int32 as Int32:
      let num = try #require(BigInt(exactly: int32))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == int32.signum())
    case let int64 as Int64:
      let num = try #require(BigInt(exactly: int64))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == int64.signum())
    case let int as Int:
      let num = try #require(BigInt(exactly: int))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == int.signum())
    case let int128 as Int128:
      let num = try #require(BigInt(exactly: int128))
      #expect(num.magnitude.words == BigUInt.Words(expectedWords))
      #expect(num.signum() == int128.signum())
    default:
      fatalError("Unexpected type: \(type(of: value))")
    }
  }

  @Test(
    "Binary integer initialization with truncation",
    arguments: [
      // Positive numbers
      // UInt8/Int8 tests
      (UInt8.max, [UInt(UInt8.max)]),
      (UInt8.min, [UInt(UInt8.min)]),
      (Int8.min, [UInt(Int8.min.magnitude)]),
      (Int8.max, [UInt(Int8.max.magnitude)]),

      // UInt16/Int16 tests
      (UInt16.max, [UInt(UInt16.max)]),
      (UInt16.min, [UInt(UInt16.min)]),
      (Int16.min, [UInt(Int16.min.magnitude)]),
      (Int16.max, [UInt(Int16.max.magnitude)]),

      // UInt32/Int32 tests
      (UInt32.max, [UInt(UInt32.max)]),
      (UInt32.min, [UInt(UInt32.min)]),
      (Int32.min, [UInt(Int32.min.magnitude)]),
      (Int32.max, [UInt(Int32.max.magnitude)]),

      // UInt64/Int64 tests
      (UInt64.max, [UInt(UInt64.max)]),
      (UInt64.min, [UInt(UInt64.min)]),
      (Int64.min, [UInt(Int64.min.magnitude)]),
      (Int64.max, [UInt(Int64.max.magnitude)]),

      // UInt/Int tests
      (UInt.max, [UInt.max]),
      (UInt.min, [UInt.min]),
      (Int.min, [UInt(Int.min.magnitude)]),
      (Int.max, [UInt(Int.max.magnitude)]),

      // UInt128/Int128 tests
      (UInt128.max, [UInt.max, UInt.max]),
      (UInt128.min, [UInt.min]),
      (Int128.min, [0, UInt(Int.min.magnitude)]),
      (Int128.max, [UInt.max, UInt(Int.max.magnitude)]),
    ] as [(any BinaryInteger & Sendable, [UInt])]
  )
  func binaryIntegerInitializationWithTruncation(_ value: any BinaryInteger & Sendable, _ expectedWords: [UInt]) {
    let num = BigInt(truncatingIfNeeded: value)
    #expect(num.magnitude.words == BigUInt.Words(expectedWords))
    #expect(num.signum() == signum(value))
  }

  @Test(
    "Binary integer initialization with clamping",
    arguments: [
      // Positive numbers
      // UInt8/Int8 tests
      (UInt8.max, [UInt(UInt8.max)]),
      (UInt8.min, [UInt(UInt8.min)]),
      (Int8.min, [UInt(Int8.min.magnitude)]),
      (Int8.max, [UInt(Int8.max.magnitude)]),

      // UInt16/Int16 tests
      (UInt16.max, [UInt(UInt16.max)]),
      (UInt16.min, [UInt(UInt16.min)]),
      (Int16.min, [UInt(Int16.min.magnitude)]),
      (Int16.max, [UInt(Int16.max.magnitude)]),

      // UInt32/Int32 tests
      (UInt32.max, [UInt(UInt32.max)]),
      (UInt32.min, [UInt(UInt32.min)]),
      (Int32.min, [UInt(Int32.min.magnitude)]),
      (Int32.max, [UInt(Int32.max.magnitude)]),

      // UInt64/Int64 tests
      (UInt64.max, [UInt(UInt64.max)]),
      (UInt64.min, [UInt(UInt64.min)]),
      (Int64.min, [UInt(Int64.min.magnitude)]),
      (Int64.max, [UInt(Int64.max.magnitude)]),

      // UInt/Int tests
      (UInt.max, [UInt.max]),
      (UInt.min, [UInt.min]),
      (Int.min, [UInt(Int.min.magnitude)]),
      (Int.max, [UInt(Int.max.magnitude)]),

      // UInt128/Int128 tests
      (UInt128.max, [UInt.max, UInt.max]),
      (UInt128.min, [UInt.min]),
      (Int128.min, [0, UInt(Int.min.magnitude)]),
      (Int128.max, [UInt.max, UInt(Int.max.magnitude)]),
    ] as [(any BinaryInteger & Sendable, [UInt])]
  )
  func binaryIntegerInitializationWithClamping(_ value: any BinaryInteger & Sendable, _ expectedWords: [UInt]) {
    let num = BigInt(clamping: value)
    #expect(num.magnitude.words == BigUInt.Words(expectedWords))
    #expect(num.signum() == signum(value))
  }

  @Test(
    "String initialization",
    arguments: testData.stringInitialization.map { ($0.input, $0.expectedWords) }
  )
  func stringInitialization(_ input: String, _ expectedWords: [UInt]?) throws {
    let num = BigInt(input)
    #expect(num?.magnitude.words == expectedWords.map { $0.signFlagWords.words })
    #expect(num?.signum() == expectedWords.map { $0.signFlagWords.signum })
  }

  @Test(
    "String conversion",
    arguments: testData.stringInitialization.compactMap { test in test.expectedWords.map { ($0, test.input) } }
  )
  func stringConversion(_ words: [UInt], _ expectedString: String) {
    let number = BigInt(wordsWithSignFlag: words)
    let stringFromNumber = String(number)
    let stringFromDescription = number.description
    let stringFromDebugDescription = number.debugDescription
    #expect(stringFromNumber == expectedString)
    #expect(stringFromDescription == expectedString)
    #expect(stringFromDebugDescription == "BigInt(\(expectedString))")
  }

  @Test(
    "Formatted strings",
    arguments: [
      (
        1234567890, "1,234,567,890",
        IntegerFormatStyle<BigInt>.number.locale(Locale(identifier: "en_US"))
      ),
      (
        -1234567890, "-1,234,567,890",
        IntegerFormatStyle<BigInt>.number.locale(Locale(identifier: "en_US"))
      ),
      (
        1000000000000000000, "1,000,000,000,000,000,000",
        IntegerFormatStyle<BigInt>.number.locale(Locale(identifier: "en_US"))
      ),
      (
        -1000000000000000000, "-1,000,000,000,000,000,000",
        IntegerFormatStyle<BigInt>.number.locale(Locale(identifier: "en_US"))
      ),
      (
        0xFFFFFFFFFFFFFFFF, "+18,446,744,073,709,551,615",
        IntegerFormatStyle<BigInt>.number.grouping(.automatic).sign(strategy: .always(includingZero: true))
      ),
      (
        -0xFFFFFFFFFFFFFFFF, "-18,446,744,073,709,551,615",
        IntegerFormatStyle<BigInt>.number.grouping(.automatic).sign(strategy: .always(includingZero: true))
      ),
    ] as [(StaticBigInt, String, IntegerFormatStyle<BigInt>)]
  )
  func formattedStrings(_ value: StaticBigInt, _ expected: String, _ style: IntegerFormatStyle<BigInt>) {
    let num = BigInt(integerLiteral: value)
    let formatted = num.formatted(style)
    #expect(formatted == expected)
  }

  @Test(
    "Addition",
    arguments: testData.addition.map { ($0.lWords, $0.rWords, $0.expectedWords) }
  )
  func addition(_ lWords: [UInt], _ rWords: [UInt], _ expectedWords: [UInt]) {
    let lNum = BigInt(wordsWithSignFlag: lWords)
    let rNum = BigInt(wordsWithSignFlag: rWords)
    let sum = lNum + rNum
    var sumAssign = lNum
    sumAssign += rNum
    #expect(sum.magnitude.words == expectedWords.signFlagWords.words)
    #expect(sum.signum() == expectedWords.signFlagWords.signum)
    #expect(sumAssign.magnitude.words == expectedWords.signFlagWords.words)
    #expect(sumAssign.signum() == expectedWords.signFlagWords.signum)
  }

  @Test(
    "Subtraction",
    arguments: testData.subtraction.map { ($0.lWords, $0.rWords, $0.expectedWords) }
  )
  func subtraction(_ lWords: [UInt], _ rWords: [UInt], _ expectedWords: [UInt]) {
    let lNum = BigInt(wordsWithSignFlag: lWords)
    let rNum = BigInt(wordsWithSignFlag: rWords)
    let diff = lNum - rNum
    var diffAssign = lNum
    diffAssign -= rNum
    #expect(diff.magnitude.words == expectedWords.signFlagWords.words)
    #expect(diff.signum() == expectedWords.signFlagWords.signum)
    #expect(diffAssign.magnitude.words == expectedWords.signFlagWords.words)
    #expect(diffAssign.signum() == expectedWords.signFlagWords.signum)
  }

  @Test(
    "Multiplication",
    arguments: testData.multiplication.map { ($0.lWords, $0.rWords, $0.expectedWords) }
  )
  func multiplication(_ lWords: [UInt], _ rWords: [UInt], _ expectedWords: [UInt]) {
    let lNum = BigInt(wordsWithSignFlag: lWords)
    let rNum = BigInt(wordsWithSignFlag: rWords)
    let product = lNum * rNum
    var productAssign = lNum
    productAssign *= rNum
    #expect(product.magnitude.words == expectedWords.signFlagWords.words)
    #expect(product.signum() == expectedWords.signFlagWords.signum)
    #expect(productAssign.magnitude.words == expectedWords.signFlagWords.words)
    #expect(productAssign.signum() == expectedWords.signFlagWords.signum)
  }

  @Test(
    "Division/Modulus",
    arguments: testData.divisionModulus.map { ($0.dividendWords, $0.divisorWords, $0.quotientWords, $0.remainderWords) }
  )
  func division(
    _ dividendWords: [UInt],
    _ divisorWords: [UInt],
    _ expectedQuotientWords: [UInt],
    _ expectedRemainderWords: [UInt]
  ) {
    let dividend = BigInt(wordsWithSignFlag: dividendWords)
    let divisor = BigInt(wordsWithSignFlag: divisorWords)
    let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: divisor)
    let quotient2 = dividend / divisor
    let remainder2 = dividend % divisor
    var quotient3 = dividend
    quotient3 /= divisor
    var remainder3 = dividend
    remainder3 %= divisor
    #expect(quotient.magnitude.words == expectedQuotientWords.signFlagWords.words)
    #expect(quotient.signum() == expectedQuotientWords.signFlagWords.signum)
    #expect(remainder.magnitude.words == expectedRemainderWords.signFlagWords.words)
    #expect(remainder.signum() == expectedRemainderWords.signFlagWords.signum)
    #expect(quotient2.magnitude.words == expectedQuotientWords.signFlagWords.words)
    #expect(quotient2.signum() == expectedQuotientWords.signFlagWords.signum)
    #expect(remainder2.magnitude.words == expectedRemainderWords.signFlagWords.words)
    #expect(remainder2.signum() == expectedRemainderWords.signFlagWords.signum)
    #expect(quotient3.magnitude.words == expectedQuotientWords.signFlagWords.words)
    #expect(quotient3.signum() == expectedQuotientWords.signFlagWords.signum)
    #expect(remainder3.magnitude.words == expectedRemainderWords.signFlagWords.words)
    #expect(remainder3.signum() == expectedRemainderWords.signFlagWords.signum)
  }

  @Test(
    "Raise to power",
    arguments: testData.power.map { ($0.baseWords, $0.exponent, $0.expectedWords) }
  )
  func raisedToPower(_ baseWords: [UInt], _ exponent: Int, _ expectedWords: [UInt]) {
    let base = BigInt(wordsWithSignFlag: baseWords)
    let result = base.raised(to: exponent)
    #expect(result.magnitude.words == expectedWords.signFlagWords.words)
    #expect(result.signum() == expectedWords.signFlagWords.signum)
  }

  @Test(
    "Greatest common divisor",
    arguments: testData.gcdLcm.map { ($0.lWords, $0.rWords, $0.expectedGcdWords) }
  )
  func greatestCommonDivisor(_ lWords: [UInt], _ rWords: [UInt], _ expectedGcdWords: [UInt]) {
    let a = BigInt(wordsWithSignFlag: lWords)
    let b = BigInt(wordsWithSignFlag: rWords)
    let result = a.greatestCommonDivisor(b)
    #expect(result.magnitude.words == expectedGcdWords.signFlagWords.words)
    #expect(result.signum() == expectedGcdWords.signFlagWords.signum)
  }

  @Test(
    "Lowest common multiple",
    arguments: testData.gcdLcm.map { ($0.lWords, $0.rWords, $0.expectedLcmWords) }
  )
  func lowestCommonMultiple(_ lWords: [UInt], _ rWords: [UInt], _ expectedLcmWords: [UInt]) {
    let a = BigInt(wordsWithSignFlag: lWords)
    let b = BigInt(wordsWithSignFlag: rWords)
    let result = a.lowestCommonMultiple(b)
    #expect(result.magnitude.words == expectedLcmWords.signFlagWords.words)
    #expect(result.signum() == expectedLcmWords.signFlagWords.signum)
  }

  @Test(
    "Bit width",
    arguments: testData.bitWidth.map { ($0.words, $0.bitWidth, $0.leadingZeroBitCount, $0.trailingZeroBitCount) }
  )
  func bitWidth(_ words: [UInt], _ expectedBitWidth: Int, _ expectedLeadingZeros: Int, _ expectedTrailingZeros: Int) {
    let num = BigInt(wordsWithSignFlag: words)
    #expect(num.bitWidth == expectedBitWidth)
    #expect(num.trailingZeroBitCount == expectedTrailingZeros)
    #expect(num.leadingZeroBitCount == expectedLeadingZeros)
  }

  @Test(
    "Bitwise operations",
    arguments: testData.bitwiseOps.map {
      (
        $0.lWords, $0.rWords,
        $0.expectedAndWords,
        $0.expectedOrWords,
        $0.expectedXorWords,
        $0.expectedNotLWords,
        $0.expectedNotRWords
      )
    }
  )
  func bitwiseOperations(
    _ lWords: [UInt],
    _ rWords: [UInt],
    _ expectedAndWords: [UInt],
    _ expectedOrWords: [UInt],
    _ expectedXorWords: [UInt],
    _ expectedNotLWords: [UInt],
    _ expectedNotRWords: [UInt]
  ) {
    let lNum = BigInt(wordsWithSignFlag: lWords)
    let rNum = BigInt(wordsWithSignFlag: rWords)
    let and = lNum & rNum
    var andAssign = lNum
    andAssign &= rNum
    let or = lNum | rNum
    var orAssign = lNum
    orAssign |= rNum
    let xor = lNum ^ rNum
    var xorAssign = lNum
    xorAssign ^= rNum
    let notL = ~lNum
    let notR = ~rNum
    #expect(and.magnitude.words == expectedAndWords.signFlagWords.words)
    #expect(andAssign.magnitude.words == expectedAndWords.signFlagWords.words)
    #expect(or.magnitude.words == expectedOrWords.signFlagWords.words)
    #expect(orAssign.magnitude.words == expectedOrWords.signFlagWords.words)
    #expect(xor.magnitude.words == expectedXorWords.signFlagWords.words)
    #expect(xorAssign.magnitude.words == expectedXorWords.signFlagWords.words)
    #expect(notL.magnitude.words == expectedNotLWords.signFlagWords.words)
    #expect(notR.magnitude.words == expectedNotRWords.signFlagWords.words)
  }

  @Test(
    "Bit shifts",
    arguments: testData.bitwiseShift.map { ($0.words, $0.shift, $0.expectedLeftWords, $0.expectedRightWords) }
  )
  func bitShifts(_ words: [UInt], _ shift: Int, _ expectedLeftWords: [UInt], _ expectedRightWords: [UInt]) {
    let numA = BigInt(wordsWithSignFlag: words)
    let leftShift = numA << shift
    var leftShiftAssign = numA
    leftShiftAssign <<= shift
    let rightShift = numA >> shift
    var rightShiftAssign = numA
    rightShiftAssign >>= shift
    #expect(leftShift.magnitude.words == expectedLeftWords.signFlagWords.words)
    #expect(leftShift.signum() == expectedLeftWords.signFlagWords.signum)
    #expect(rightShift.magnitude.words == expectedRightWords.signFlagWords.words)
    #expect(rightShift.signum() == expectedRightWords.signFlagWords.signum)
    #expect(leftShiftAssign.magnitude.words == expectedLeftWords.signFlagWords.words)
    #expect(leftShiftAssign.signum() == expectedLeftWords.signFlagWords.signum)
    #expect(rightShiftAssign.magnitude.words == expectedRightWords.signFlagWords.words)
    #expect(rightShiftAssign.signum() == expectedRightWords.signFlagWords.signum)
  }

  @Test(
    "Comparison operations",
    arguments: testData.comparison.map {
      ($0.lWords, $0.rWords, $0.expectedEq, $0.expectedLt, $0.expectedLtEq, $0.expectedGt, $0.expectedGtEq)
    }
  )
  func comparisonOperations(
    _ lWords: [UInt],
    _ rWords: [UInt],
    _ expectedEq: Bool,
    _ expectedLt: Bool,
    _ expectedLtEq: Bool,
    _ expectedGt: Bool,
    _ expectedGtEq: Bool
  ) {
    let numA = BigInt(wordsWithSignFlag: lWords)
    let numB = BigInt(wordsWithSignFlag: rWords)
    #expect((numA < numB) == expectedLt)
    #expect((numA > numB) == expectedGt)
    #expect((numA == numB) == expectedEq)
    #expect((numA <= numB) == expectedLtEq)
    #expect((numA >= numB) == expectedGtEq)
  }

  @Test(
    "Hashing",
    arguments: [
      (42, 42, 100),
      (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x10000000000000000),
      (0x10000000000000000, 0x10000000000000000, 0x20000000000000000),
      (0x1234567890ABCDEF1234567890ABCDEF, 0x1234567890ABCDEF1234567890ABCDEF, 0x1234567890ABCDEF1234567890ABCDE0),
      (-42, -42, -100),
      (-0xFFFFFFFFFFFFFFFF, -0xFFFFFFFFFFFFFFFF, -0x10000000000000000),
      (-0x10000000000000000, -0x10000000000000000, -0x20000000000000000),
      (-0x1234567890ABCDEF1234567890ABCDEF, -0x1234567890ABCDEF1234567890ABCDEF, -0x1234567890ABCDEF1234567890ABCDE0),
      (-42, -42, 42),
      (42, 42, -42),
      (-0xFFFFFFFFFFFFFFFF, -0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF),
      (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, -0xFFFFFFFFFFFFFFFF),
      (-0x10000000000000000, -0x10000000000000000, 0x10000000000000000),
      (0x10000000000000000, 0x10000000000000000, -0x10000000000000000),
    ] as [(StaticBigInt, StaticBigInt, StaticBigInt)]
  )
  func hashing(_ a: StaticBigInt, _ b: StaticBigInt, _ c: StaticBigInt) {
    let numA = BigInt(integerLiteral: a)
    let numB = BigInt(integerLiteral: b)
    let numC = BigInt(integerLiteral: c)

    #expect(numA.hashValue == numB.hashValue)
    #expect(numA.hashValue != numC.hashValue)
  }

  @Test("Zero handling")
  func zeroHandling() {
    let zero = BigInt()
    let one: BigInt = 1
    let minusOne: BigInt = -1

    #expect(zero + zero == zero)
    #expect(zero * one == zero)
    #expect(zero / one == zero)
    #expect(zero % one == zero)
    #expect(zero << 1 == zero)
    #expect(zero >> 1 == zero)
    #expect(zero * minusOne == zero)
  }

  @Test(
    "Integer conversion from BigInt",
    arguments: testData.integerConversion.map {
      (
        $0.sourceWords,
        $0.expectedInt8, $0.expectedUInt8,
        $0.expectedInt16, $0.expectedUInt16,
        $0.expectedInt32, $0.expectedUInt32,
        $0.expectedInt64, $0.expectedUInt64,
        $0.expectedInt128, $0.expectedUInt128,
        $0.expectedInt, $0.expectedUInt
      )
    }
  )
  func integerConversionFromBigInt(
    _ sourceWords: [UInt],
    _ expectedInt8: Int8?,
    _ expectedUInt8: UInt8?,
    _ expectedInt16: Int16?,
    _ expectedUInt16: UInt16?,
    _ expectedInt32: Int32?,
    _ expectedUInt32: UInt32?,
    _ expectedInt64: Int64?,
    _ expectedUInt64: UInt64?,
    _ expectedInt128: Int128?,
    _ expectedUInt128: UInt128?,
    _ expectedInt: Int?,
    _ expectedUInt: UInt?
  ) {
    let num = BigInt(wordsWithSignFlag: sourceWords)
    let int8 = Int8(exactly: num)
    let uint8 = UInt8(exactly: num)
    let int16 = Int16(exactly: num)
    let uint16 = UInt16(exactly: num)
    let int32 = Int32(exactly: num)
    let uint32 = UInt32(exactly: num)
    let int64 = Int64(exactly: num)
    let uint64 = UInt64(exactly: num)
    let int128 = Int128(exactly: num)
    let uint128 = UInt128(exactly: num)
    let int = Int(exactly: num)
    let uint = UInt(exactly: num)

    // Int8/UInt8
    #expect(int8 == expectedInt8)
    #expect(uint8 == expectedUInt8)

    // Int16/UInt16
    #expect(int16 == expectedInt16)
    #expect(uint16 == expectedUInt16)

    // Int32/UInt32
    #expect(int32 == expectedInt32)
    #expect(uint32 == expectedUInt32)

    // Int64/UInt64
    #expect(int64 == expectedInt64)
    #expect(uint64 == expectedUInt64)

    // Int/UInt
    #expect(int == expectedInt)
    #expect(uint == expectedUInt)

    // Int128/UInt128
    #expect(int128 == expectedInt128)
    #expect(uint128 == expectedUInt128)
  }

  @Test(
    "Floating point initialization",
    arguments: testData.floatInitialization.map { ($0.floatValue, $0.precision, $0.expectedWords) }
  )
  func floatingPointInitialization(
    _ floatValue: Double,
    _ precision: Int,
    _ expectedWords: [UInt]
  ) throws {
    // Define maximum exactly representable integers for each precision
    let float16ExactMax: Double = 2048.0    // 2^11
    let float32ExactMax: Double = 16777216.0    // 2^24
    let float64ExactMax: Double = 9007199254740992.0    // 2^53

    switch precision {
    case 16:
      let num = BigInt(Float16(floatValue))
      #expect(num.magnitude.words == expectedWords.signFlagWords.words)
      #expect(num.signum() == expectedWords.signFlagWords.signum)
      // Only test Int128 equality for values within exact precision range
      if floatValue <= float16ExactMax {
        let int = Int128(floatValue)
        #expect(num == BigInt(int))
        if Int128(exactly: floatValue) != nil {
          let exact = try #require(BigInt(exactly: floatValue))
          #expect(exact.magnitude.words == expectedWords.signFlagWords.words)
          #expect(exact.signum() == expectedWords.signFlagWords.signum)
        }
      }
    case 32:
      let num = BigInt(Float32(floatValue))
      #expect(num.magnitude.words == expectedWords.signFlagWords.words)
      #expect(num.signum() == expectedWords.signFlagWords.signum)
      // Only test Int128 equality for values within exact precision range
      if floatValue <= float32ExactMax {
        let int = Int128(floatValue)
        #expect(num == BigInt(int))
        if Int128(exactly: floatValue) != nil {
          let exact = try #require(BigInt(exactly: floatValue))
          #expect(exact.magnitude.words == expectedWords.signFlagWords.words)
          #expect(exact.signum() == expectedWords.signFlagWords.signum)
        }
      }
    case 64:
      let num = BigInt(floatValue)
      #expect(num.magnitude.words == expectedWords.signFlagWords.words)
      // Only test Int128 equality for values within exact precision range
      if floatValue <= float64ExactMax {
        let int = Int128(floatValue)
        #expect(num == BigInt(int))
        if Int128(exactly: floatValue) != nil {
          let exact = try #require(BigInt(exactly: floatValue))
          #expect(exact.magnitude.words == expectedWords.signFlagWords.words)
          #expect(exact.signum() == expectedWords.signFlagWords.signum)
        }
      }
    default:
      fatalError("Unexpected precision: \(precision)")
    }
  }

  @Test("Floating point initialization special cases")
  func floatingPointInitializationSpecialCases() {
    #expect(BigInt(exactly: Double.nan) == nil)
    #expect(BigInt(exactly: +Double.infinity) == nil)
    #expect(BigInt(exactly: -Double.infinity) == nil)
  }

  @Test(
    "Two's complement initialization",
    arguments: testData.twosComplementInit.map { ($0.twosComplementWords, $0.expectedWords) }
  )
  func twosComplementInitialization(_ twosComplementWords: [UInt], _ expectedWords: [UInt]) {
    let num = BigInt(twosComplementWords: twosComplementWords)
    let expected = BigInt(wordsWithSignFlag: expectedWords)
    #expect(num == expected)
    #expect(num.magnitude.words == expected.magnitude.words)
    #expect(num.signum() == expected.signum())
  }

  @Test(
    "Two's complement round trip",
    arguments: testData.twosComplementInit.map { ($0.expectedWords, $0.twosComplementWords) }
  )
  func twosComplementRoundTrip(_ words: [UInt], _ expectedTwosComplementWords: [UInt]) {

    func normalize(_ tcWords: [UInt]) -> [UInt] {
      guard tcWords.count > 1 else {
        return tcWords
      }
      if tcWords[tcWords.count - 2] == 0 && tcWords.last == 0 {
        return normalize(Array(tcWords.dropLast()))
      }
      return tcWords
    }

    let num = BigInt(wordsWithSignFlag: words)
    let twosComplementWords = Array(num.words)
    #expect(twosComplementWords == normalize(expectedTwosComplementWords))
    let roundTrip = BigInt(twosComplementWords: twosComplementWords)
    #expect(roundTrip == num)
  }

  @Test(
    "Encode/decode bytes",
    arguments: testData.encoding.map { ($0.words, $0.encodedBytes, $0.inputBytes) }
  )
  func encodeDecodeBytes(_ words: [UInt], _ expectedBytes: [UInt8], _ inputBytes: [UInt8]?) {
    let number = BigInt(wordsWithSignFlag: words)

    // Test encoding
    let encoded = number.encode()
    #expect(encoded == expectedBytes)

    // Test decoding
    let decoded = BigInt(encoded: encoded)
    #expect(decoded == number)

    if let inputBytes {
      let decoded2 = BigInt(encoded: inputBytes)
      #expect(decoded2 == number)
    }
  }

  @Test("isMultiple implementation")
  func isMultipleImplementation() {
    // Setup test values
    let zero = BigInt.zero
    let one = BigInt.one
    let two = BigInt.two
    let ten = BigInt.ten
    let hundred = BigInt(100)
    let largeNumber = BigInt("123456789123456789123456789")!
    let divisibleLargeNumber = largeNumber * BigInt(42)

    // Negative values
    let minusOne = BigInt.minusOne
    let minusTwo = BigInt(-2)
    let minusTen = BigInt(-10)
    let minusHundred = BigInt(-100)
    let minusLargeNumber = BigInt("-123456789123456789123456789")!
    let minusDivisibleLargeNumber = minusLargeNumber * BigInt(42)

    // Zero is multiple of everything except zero
    #expect(zero.isMultiple(of: one))
    #expect(zero.isMultiple(of: two))
    #expect(zero.isMultiple(of: ten))
    #expect(zero.isMultiple(of: hundred))
    #expect(zero.isMultiple(of: largeNumber))

    // Zero is multiple of negative numbers too
    #expect(zero.isMultiple(of: minusOne))
    #expect(zero.isMultiple(of: minusTwo))
    #expect(zero.isMultiple(of: minusTen))

    // One is multiple of only one (positive or negative)
    #expect(one.isMultiple(of: one))
    #expect(one.isMultiple(of: minusOne))
    #expect(!one.isMultiple(of: two))
    #expect(!one.isMultiple(of: ten))
    #expect(!one.isMultiple(of: hundred))
    #expect(!one.isMultiple(of: largeNumber))

    // Negative one is multiple of one (positive or negative)
    #expect(minusOne.isMultiple(of: one))
    #expect(minusOne.isMultiple(of: minusOne))
    #expect(!minusOne.isMultiple(of: two))
    #expect(!minusOne.isMultiple(of: ten))

    // Basic multiples (positive divisors)
    #expect(ten.isMultiple(of: one))
    #expect(ten.isMultiple(of: two))
    #expect(ten.isMultiple(of: BigInt(5)))
    #expect(!ten.isMultiple(of: BigInt(3)))
    #expect(!ten.isMultiple(of: hundred))

    // Basic multiples (negative divisors)
    #expect(ten.isMultiple(of: minusOne))
    #expect(ten.isMultiple(of: minusTwo))
    #expect(ten.isMultiple(of: BigInt(-5)))
    #expect(!ten.isMultiple(of: BigInt(-3)))

    // Negative multiples with positive divisors
    #expect(minusTen.isMultiple(of: one))
    #expect(minusTen.isMultiple(of: two))
    #expect(minusTen.isMultiple(of: BigInt(5)))
    #expect(!minusTen.isMultiple(of: BigInt(3)))

    // Negative multiples with negative divisors
    #expect(minusTen.isMultiple(of: minusOne))
    #expect(minusTen.isMultiple(of: minusTwo))
    #expect(minusTen.isMultiple(of: BigInt(-5)))
    #expect(!minusTen.isMultiple(of: BigInt(-3)))

    // Self is always multiple of self (positive and negative)
    #expect(hundred.isMultiple(of: hundred))
    #expect(minusHundred.isMultiple(of: minusHundred))
    #expect(largeNumber.isMultiple(of: largeNumber))
    #expect(minusLargeNumber.isMultiple(of: minusLargeNumber))

    // A number is multiple of both positive and negative versions of its divisors
    #expect(hundred.isMultiple(of: BigInt(10)))
    #expect(hundred.isMultiple(of: BigInt(-10)))
    #expect(minusHundred.isMultiple(of: BigInt(10)))
    #expect(minusHundred.isMultiple(of: BigInt(-10)))

    // Large numbers (positive)
    #expect(divisibleLargeNumber.isMultiple(of: largeNumber))
    #expect(divisibleLargeNumber.isMultiple(of: BigInt(42)))
    #expect(divisibleLargeNumber.isMultiple(of: BigInt(6)))
    #expect(divisibleLargeNumber.isMultiple(of: BigInt(7)))
    #expect(!divisibleLargeNumber.isMultiple(of: BigInt(11)))

    // Large numbers (negative)
    #expect(divisibleLargeNumber.isMultiple(of: minusLargeNumber))
    #expect(divisibleLargeNumber.isMultiple(of: BigInt(-42)))
    #expect(minusDivisibleLargeNumber.isMultiple(of: largeNumber))
    #expect(minusDivisibleLargeNumber.isMultiple(of: minusLargeNumber))
    #expect(minusDivisibleLargeNumber.isMultiple(of: BigInt(42)))
    #expect(minusDivisibleLargeNumber.isMultiple(of: BigInt(-42)))

    // Powers of 2 - testing trailing zeros optimization
    let powerOf2 = BigInt(1) << 64
    let multiplePowerOf2 = powerOf2 * BigInt(42)
    let negativePowerOf2 = BigInt(-1) << 64
    let negativeMultiplePowerOf2 = negativePowerOf2 * BigInt(42)

    #expect(powerOf2.isMultiple(of: BigInt(1) << 32))
    #expect(powerOf2.isMultiple(of: BigInt(1) << 16))
    #expect(powerOf2.isMultiple(of: BigInt(1) << 8))
    #expect(powerOf2.isMultiple(of: BigInt(1) << 4))
    #expect(powerOf2.isMultiple(of: BigInt(1) << 2))
    #expect(powerOf2.isMultiple(of: BigInt(1) << 1))
    #expect(!powerOf2.isMultiple(of: BigInt(1) << 128))

    #expect(negativePowerOf2.isMultiple(of: BigInt(1) << 32))
    #expect(negativePowerOf2.isMultiple(of: BigInt(-1) << 32))
    #expect(negativePowerOf2.isMultiple(of: BigInt(1) << 16))
    #expect(negativePowerOf2.isMultiple(of: BigInt(-1) << 16))

    #expect(multiplePowerOf2.isMultiple(of: BigInt(1) << 32))
    #expect(multiplePowerOf2.isMultiple(of: BigInt(1) << 16))
    #expect(multiplePowerOf2.isMultiple(of: BigInt(1) << 8))
    #expect(multiplePowerOf2.isMultiple(of: BigInt(1) << 4))
    #expect(multiplePowerOf2.isMultiple(of: BigInt(1) << 2))
    #expect(multiplePowerOf2.isMultiple(of: BigInt(1) << 1))
    #expect(!multiplePowerOf2.isMultiple(of: BigInt(1) << 128))

    #expect(negativeMultiplePowerOf2.isMultiple(of: BigInt(1) << 32))
    #expect(negativeMultiplePowerOf2.isMultiple(of: BigInt(-1) << 32))
    #expect(negativeMultiplePowerOf2.isMultiple(of: BigInt(1) << 16))
    #expect(negativeMultiplePowerOf2.isMultiple(of: BigInt(-1) << 16))

    // Test two-word divisors (GCD method)
    let twoWordDivisor = BigInt(UInt.max) + BigInt(1)
    let multipleTwoWordDivisor = twoWordDivisor * BigInt(123)
    let negativeTwoWordDivisor = BigInt(0) - twoWordDivisor
    let negativeMultipleTwoWordDivisor = negativeTwoWordDivisor * BigInt(123)

    #expect(multipleTwoWordDivisor.isMultiple(of: twoWordDivisor))
    #expect(multipleTwoWordDivisor.isMultiple(of: negativeTwoWordDivisor))
    #expect(!multipleTwoWordDivisor.isMultiple(of: twoWordDivisor + BigInt(1)))

    #expect(negativeMultipleTwoWordDivisor.isMultiple(of: twoWordDivisor))
    #expect(negativeMultipleTwoWordDivisor.isMultiple(of: negativeTwoWordDivisor))
    #expect(!negativeMultipleTwoWordDivisor.isMultiple(of: twoWordDivisor + BigInt(1)))

    // Test large divisors (fallback method)
    let largeWordDivisor = BigInt(UInt.max) + BigInt(1)
    let veryLargeDivisor = largeWordDivisor * largeWordDivisor * largeWordDivisor
    let multipleVeryLargeDivisor = veryLargeDivisor * BigInt(456)
    let negativeVeryLargeDivisor = BigInt(0) - veryLargeDivisor
    let negativeMultipleVeryLargeDivisor = negativeVeryLargeDivisor * BigInt(456)

    #expect(multipleVeryLargeDivisor.isMultiple(of: veryLargeDivisor))
    #expect(multipleVeryLargeDivisor.isMultiple(of: negativeVeryLargeDivisor))
    #expect(!multipleVeryLargeDivisor.isMultiple(of: veryLargeDivisor + BigInt(1)))

    #expect(negativeMultipleVeryLargeDivisor.isMultiple(of: veryLargeDivisor))
    #expect(negativeMultipleVeryLargeDivisor.isMultiple(of: negativeVeryLargeDivisor))
    #expect(!negativeMultipleVeryLargeDivisor.isMultiple(of: veryLargeDivisor + BigInt(1)))
  }
}
