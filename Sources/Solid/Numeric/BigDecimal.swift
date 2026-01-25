//
//  BigDecimal.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/16/25.
//

import Foundation

/// Arbitrary‑precision decimal number.
///
/// Implements an arbitrary-precision, radix-10 decimal number
/// in Swift's numeric protocols.
///
/// The value is stored as a ``BigInt`` mantissa and an
/// ``Int`` scale, where the actual value is mantissa * 10^-scale.
///
public struct BigDecimal {

  public static let precisionBuffer: Int = 10

  private enum Storage: Equatable, Hashable, Sendable {
    case mantissa(BigInt, scale: Int)
    case infinity(sign: FloatingPointSign)
    case nan
  }

  private var storage: Storage

  private init(storage: Storage) {
    self.storage = storage
  }

  /// The mantissa (or coefficient) of the decimal number.
  public var mantissa: BigInt {
    guard case .mantissa(let m, _) = storage else {
      return .zero
    }
    return m
  }

  /// The scale (or exponent) of the decimal number.
  /// The actual value is mantissa * 10^-scale
  public var scale: Int {
    if case .mantissa(_, let s) = storage {
      return s
    }
    return 0
  }

  /// Creates a new BigDecimal with the given mantissa and scale.
  public init(mantissa: BigInt, scale: Int) {
    self.storage = .mantissa(mantissa, scale: scale)
  }

  /// Creates a new BigDecimal from an integer value.
  public init(_ value: BigInt) {
    self.init(mantissa: value, scale: 0)
  }

  /// Creates a new BigDecimal from a floating-point value.
  ///
  public init<Source>(_ value: Source) where Source: BinaryFloatingPoint {

    guard !value.isNaN else {
      self.storage = .nan
      return
    }
    guard !value.isInfinite else {
      self.storage = .infinity(sign: value.sign)
      return
    }
    guard !value.isZero else {
      self.storage = .mantissa(0, scale: 0)
      return
    }

    let (significand, exponent) = value.components
    let (mantissa, scale) = Source.decimalComponents(binarySignificand: significand, exponent: exponent)

    self.storage = .mantissa(mantissa, scale: scale)
    self.normalize()
  }

  /// Creates a new BigDecimal from a floating-point value if it can be
  /// represented exactly.
  ///
  /// - Note: Due to arbitrary-precision representation of BigDecimal, all
  ///   floating-point values can be represented exactly; this initializer
  ///   will return nil only if the value is NaN. Disallowing NaN replicates
  ///   the behavior of `Double` and `Float`.
  ///
  /// - Parameter source: The floating-point value to convert.
  ///
  public init?<Source>(exactly source: Source) where Source: BinaryFloatingPoint {
    guard !source.isNaN else {
      return nil
    }
    self.init(source)
  }

  /// Creates a new decimal number from its string representation.
  ///
  /// The string can be in one of these formats:
  /// ```swift
  /// // Plain decimal
  /// BigDecimal("123.456")     // 123.456
  /// BigDecimal("-123.456")    // -123.456
  /// BigDecimal("0.000123")    // 0.000123
  ///
  /// // Scientific notation
  /// BigDecimal("1.23e2")      // 123.0
  /// BigDecimal("1.23e-2")     // 0.0123
  /// BigDecimal("-1.23e-2")    // -0.0123
  ///
  /// // Special values
  /// BigDecimal("NaN")         // Not a Number
  /// BigDecimal("Inf")         // Positive infinity
  /// BigDecimal("-Inf")        // Negative infinity
  /// ```
  ///
  /// The initializer accepts strings with these components:
  /// - An optional sign (`+` or `-`)
  /// - A sequence of decimal digits with optional leading zeros
  /// - An optional decimal point (`.`) followed by decimal digits
  /// - An optional exponent indicated by `e` or `E`, followed by an optional
  ///   sign and digits.
  ///
  /// - Parameter string: A string representation of a decimal number. Fails
  ///   if the string cannot be parsed as a decimal number.
  ///
  public init?(_ string: some StringProtocol) {
    // Handle special values with case-insensitive comparison
    switch string.lowercased() {
    case "nan":
      self.storage = .nan
      return
    case "inf", "+inf":
      self.storage = .infinity(sign: .plus)
      return
    case "-inf":
      self.storage = .infinity(sign: .minus)
      return
    default:
      break
    }

    // Extract sign
    var str = Substring(string)
    let isNegative =
      str.first.map { c in
        if c == "-" || c == "+" {
          str = str.dropFirst()
          return c == "-"
        }
        return false
      } ?? false

    // Split into number and exponent
    let parts = str.split(maxSplits: 1) { $0 == "e" || $0 == "E" }
    guard parts.count > 0 && parts.count <= 2 else { return nil }

    // Parse mantissa parts
    let numberParts = parts[0].split(separator: ".", maxSplits: 1)
    guard numberParts.count > 0 && numberParts.count <= 2,
      !numberParts[0].isEmpty || numberParts.count > 1
    else { return nil }

    // Get integer and fractional parts, trimming whitespace
    let integerStr = numberParts[0].trimmingCharacters(in: .whitespaces)
    let fractionalStr = numberParts.count > 1 ? numberParts[1].trimmingCharacters(in: .whitespaces) : ""

    // Parse integer part (stripping leading zeros)
    let cleanIntegerStr = integerStr.drop(while: { $0 == "0" })
    guard let integerValue = BigInt(cleanIntegerStr.isEmpty ? "0" : String(cleanIntegerStr))
    else { return nil }

    // Combine integer and fractional parts
    var mantissa = integerValue
    var scale = 0

    if !fractionalStr.isEmpty {
      guard let fractionalValue = BigInt(fractionalStr) else { return nil }
      scale = fractionalStr.count
      mantissa = mantissa * .ten.raised(to: scale) + fractionalValue
    }

    // Apply exponent if present
    if parts.count == 2 {
      guard let exponent = Int(parts[1].trimmingCharacters(in: .whitespaces))
      else { return nil }

      scale -= exponent
      if scale < 0 {
        mantissa *= .ten.raised(to: -scale)
        scale = 0
      }
    }

    self.storage = .mantissa(isNegative ? -mantissa : mantissa, scale: scale)
  }

  /// Returns true if the decimal is NaN.
  public var isNaN: Bool {
    if case .nan = storage {
      return true
    }
    return false
  }

  /// Returns true if the decimal is infinity.
  public var isInfinite: Bool {
    if case .infinity = storage {
      return true
    }
    return false
  }

  /// Returns true if the decimal is finite (not NaN or infinity).
  public var isFinite: Bool {
    if case .mantissa = storage {
      return true
    }
    return false
  }

  /// Returns true if the decimal is zero.
  public var isZero: Bool {
    if case .mantissa(let m, _) = storage {
      return m.isZero
    }
    return false
  }

  /// Returns the integer value if this decimal can be exactly represented as an integer.
  /// - Returns: The integer value or nil if it cannot be represented as an integer.
  public var integer: BigInt? {
    if !isFinite {
      return nil
    }
    if scale == 0 {
      return mantissa
    }
    if scale < 0 {
      // For negative scales, we can multiply by 10^-scale
      return mantissa * .ten.raised(to: -scale)
    }
    // For positive scales, check if the mantissa is divisible by 10^scale
    let divisor = BigInt.ten.raised(to: scale)
    let (quotient, remainder) = mantissa.quotientAndRemainder(dividingBy: divisor)
    if remainder.isZero {
      return quotient
    }
    return nil
  }

  /// Returns the absolute value of the decimal.
  public var magnitude: Self {
    switch storage {
    case .nan:
      return .nan
    case .infinity:
      return .infinity
    case .mantissa(let m, let s):
      return Self(mantissa: BigInt(m.magnitude), scale: s)
    }
  }

  /// Returns true if the decimal is negative.
  public var isNegative: Bool {
    switch storage {
    case .nan:
      return false
    case .infinity(let sign):
      return sign == .minus
    case .mantissa(let m, _):
      return m.isNegative
    }
  }

  /// Returns the sign of the decimal (-1 for negative, 0 for zero, 1 for positive).
  public func signum() -> BigInt {
    switch storage {
    case .nan:
      return .zero
    case .infinity(let sign):
      return sign == .plus ? .one : -.one
    case .mantissa(let m, _):
      return m.signum()
    }
  }

  /// Normalizes the decimal by removing trailing zeros.
  ///
  /// For example, `1.200` becomes `1.2`, and `1.0` becomes `1`.
  ///
  public mutating func normalize() {
    guard case .mantissa(var mantissa, var scale) = storage else {
      return
    }

    guard !mantissa.isZero else {
      storage = .mantissa(0, scale: 0)
      return
    }

    while mantissa.divide(byMultipleOf: .ten) {
      scale -= 1
    }

    self.storage = .mantissa(mantissa, scale: scale)
  }

  /// Returns a normalized version of this decimal, with trailing zeros removed.
  ///
  /// For example, `1.200` becomes `1.2`, and `1.0` becomes `1`.
  ///
  /// - Returns: A normalized decimal with the same value but no trailing zeros.
  public func normalized() -> Self {
    var result = self
    result.normalize()
    return result
  }

  /// Normalizes this decimal by removing trailing zeros.
  ///
  /// For example, `1.200` becomes `1.2`, and `1.0` becomes `1`.
  public mutating func removeTrailingZeros() {
    normalize()
  }

  /// Normalizes this decimal by removing trailing zeros.
  ///
  /// For example, `1.200` becomes `1.2`, and `1.0` becomes `1`.
  public func removingTrailingZeros() -> Self {
    var result = self
    result.removeTrailingZeros()
    return result
  }

  /// Rounds the decimal to the specified number of decimal places, returning a new instance.
  ///
  /// - Parameters:
  ///  - rule: The rounding rule to apply. Defaults to `.toNearestOrAwayFromZero`.
  ///  - places: The number of decimal places to round to. Defaults to `0`.
  /// - Returns: A new `BigDecimal` instance with the rounded value.
  ///
  public func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero, places: Int = 0) -> Self {
    guard case .mantissa(let mantissa, let scale) = storage else {
      // Non-finite numbers round to themselves
      return self
    }

    let diff = scale - places
    guard diff > 0 else {
      // Already at or beyond desired precision
      return self
    }

    let divisor = BigInt.ten.raised(to: diff)
    let (quotient, remainder) = mantissa.quotientAndRemainder(dividingBy: divisor)

    // Check if rounding adjustment is needed
    let isZeroRemainder = remainder.isZero
    if isZeroRemainder {
      // No fractional part, no rounding needed
      return Self(mantissa: quotient, scale: places)
    }

    let isPositive = !mantissa.isNegative
    let absRemainder = remainder.magnitude
    let absDivisor = divisor    // Divisor is always positive (10^diff)

    // Determine if the remainder is exactly half or more than half
    let doubledAbsRemainder = absRemainder + absRemainder
    let isExactlyHalf = doubledAbsRemainder == absDivisor
    let isMoreThanHalf = doubledAbsRemainder > absDivisor

    var adjustment = BigInt.zero

    switch rule {
    case .up:    // Toward +infinity
      if isPositive { adjustment = 1 }
    // Negative numbers only adjust if exactly zero (handled above)

    case .down:    // Toward -infinity
      if !isPositive { adjustment = -1 }
    // Positive numbers only adjust if exactly zero (handled above)

    case .towardZero:    // Truncate
      adjustment = 0

    case .awayFromZero:
      adjustment = isPositive ? 1 : -1

    case .toNearestOrAwayFromZero:
      if isMoreThanHalf || isExactlyHalf {
        adjustment = isPositive ? 1 : -1
      }

    case .toNearestOrEven:
      if isMoreThanHalf {
        adjustment = isPositive ? 1 : -1
      } else if isExactlyHalf {
        // Tie-breaking: Round to nearest even quotient
        if !quotient.isMultiple(of: 2) {    // If quotient is odd, round away from zero
          adjustment = isPositive ? 1 : -1
        }
      }
    // If less than half, adjustment remains 0

    @unknown default:
      // Treat unknown cases as towardZero
      adjustment = 0
    }

    // Apply the adjustment to the quotient
    let newMantissa = quotient + adjustment

    // Create the final rounded value
    var result = Self(mantissa: newMantissa, scale: places)
    // Normalization might be needed if rounding results in trailing zeros (e.g., 1.99 rounded to 1 place -> 2.0)
    result.normalize()
    return result
  }

  public func scaled(to scale: Int, rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Self {

    guard case .mantissa(let mantissa, _) = storage, scale != self.scale else {
      return self
    }

    guard !isZero else {
      // Zero can have any scale
      return Self(mantissa: mantissa, scale: scale)
    }

    guard scale > self.scale else {

      return rounded(rule, places: scale)
    }

    let raise = scale - self.scale
    let multiplier = BigInt.ten.raised(to: raise)
    let newMantissa = mantissa * multiplier
    return Self(mantissa: newMantissa, scale: scale)
  }

  public mutating func scale(to scale: Int, rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) {
    self = scaled(to: scale, rounding: rule)
  }

  /// Returns this decimal rounded to a ``BigInt`` using the specified rounding rule.
  /// - Parameter rule: The rounding rule to apply
  /// - Returns: The rounded BigInt value
  ///
  public func integer(rounding rule: FloatingPointRoundingRule = .towardZero) -> BigInt {
    return rounded(rule, places: 0).integer ?? .zero
  }

  /// Tests if this decimal is an integer.
  ///
  /// - Returns true if this decimal can be exactly represented as an integer
  ///
  public var isInteger: Bool {
    guard case .mantissa(let m, let s) = storage else {
      return false
    }

    if s <= 0 {
      return true
    }
    // For positive scales, check if mantissa is divisible by 10^scale
    let divisor = BigInt.ten.raised(to: s)
    return m % divisor == 0
  }

}

// MARK: - Arithmetic Operations

extension BigDecimal {

  public static func + (lhs: Self, rhs: Self) -> Self {
    // Handle special values
    if lhs.isNaN || rhs.isNaN {
      return .nan
    }
    if lhs.isInfinite {
      if rhs.isInfinite {
        return lhs.isNegative == rhs.isNegative ? lhs : .nan
      }
      return lhs
    }
    if rhs.isInfinite {
      return rhs
    }

    let (lhs, rhs) = alignScales(lhs, rhs)
    return Self(mantissa: lhs.mantissa + rhs.mantissa, scale: lhs.scale)
  }

  public static func - (lhs: Self, rhs: Self) -> Self {
    // Handle special values
    if lhs.isNaN || rhs.isNaN {
      return .nan
    }
    if lhs.isInfinite {
      if rhs.isInfinite {
        return lhs.isNegative == rhs.isNegative ? .nan : lhs
      }
      return lhs
    }
    if rhs.isInfinite {
      return -rhs
    }

    let (lhs, rhs) = alignScales(lhs, rhs)
    return Self(mantissa: lhs.mantissa - rhs.mantissa, scale: lhs.scale)
  }

  public static func * (lhs: Self, rhs: Self) -> Self {
    // Handle special values
    if lhs.isNaN || rhs.isNaN {
      return .nan
    }
    if lhs.isInfinite || rhs.isInfinite {
      if lhs.isZero || rhs.isZero {
        return .nan
      }
      let isNegative = lhs.isNegative != rhs.isNegative
      return isNegative ? -.infinity : .infinity
    }

    return Self(
      mantissa: lhs.mantissa * rhs.mantissa,
      scale: lhs.scale + rhs.scale
    )
  }

  public static func *= (lhs: inout Self, rhs: Self) {
    lhs = lhs * rhs
  }

  public static func / (lhs: Self, rhs: Self) -> Self {
    // Handle special values
    if lhs.isNaN || rhs.isNaN {
      return .nan
    }
    if lhs.isInfinite {
      if rhs.isInfinite {
        return .nan
      }
      return rhs.isNegative ? -lhs : lhs
    }
    if rhs.isInfinite {
      return .zero
    }
    if rhs.isZero {
      if lhs.isZero {
        return .nan
      }
      return lhs.isNegative ? -.infinity : .infinity
    }

    // Calculate the desired scale for the result
    let desiredScale = max(lhs.scale, rhs.scale) + Self.precisionBuffer

    // Align scales and perform division
    let (lhs, rhs) = alignScales(lhs, rhs)
    let result = Self(
      mantissa: lhs.mantissa * .ten.raised(to: desiredScale) / rhs.mantissa,
      scale: desiredScale
    )

    return result.normalized()
  }

  public static func /= (lhs: inout Self, rhs: Self) {
    lhs = lhs / rhs
  }

  internal static func alignScales(_ lhs: Self, _ rhs: Self) -> (Self, Self) {
    if lhs.scale == rhs.scale {
      return (lhs, rhs)
    }

    let scaleDiff = lhs.scale - rhs.scale
    guard scaleDiff > 0 else {
      return (
        Self(
          mantissa: lhs.mantissa * .ten.raised(to: -scaleDiff),
          scale: rhs.scale
        ),
        rhs
      )
    }
    return (
      lhs,
      Self(
        mantissa: rhs.mantissa * .ten.raised(to: scaleDiff),
        scale: lhs.scale
      )
    )
  }

  public static prefix func - (value: Self) -> Self {
    switch value.storage {
    case .nan:
      return .nan
    case .infinity(let sign):
      return Self(storage: .infinity(sign: sign == .plus ? .minus : .plus))
    case .mantissa(let m, let s):
      return Self(mantissa: -m, scale: s)
    }
  }

}

// MARK: - Comparison

extension BigDecimal: Equatable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    // NaN is not equal to anything, including itself
    if lhs.isNaN || rhs.isNaN {
      return false
    }
    // Compare infinities
    if lhs.isInfinite || rhs.isInfinite {
      return lhs.isInfinite && rhs.isInfinite && lhs.isNegative == rhs.isNegative
    }
    let (lhs, rhs) = alignScales(lhs, rhs)
    return lhs.mantissa == rhs.mantissa
  }

}

extension BigDecimal: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    // NaN is not comparable
    if lhs.isNaN || rhs.isNaN {
      return false
    }
    // Compare infinities
    if lhs.isInfinite {
      if lhs.isNegative {
        return rhs != lhs
      }
      return false
    }
    if rhs.isInfinite {
      if !rhs.isNegative {
        return lhs != rhs
      }
      return false
    }
    let (lhs, rhs) = alignScales(lhs, rhs)
    return lhs.mantissa < rhs.mantissa
  }

  public static func <= (lhs: Self, rhs: Self) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      return false
    }
    return lhs < rhs || lhs == rhs
  }

  public static func > (lhs: Self, rhs: Self) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      return false
    }
    return !(lhs <= rhs)
  }

  public static func >= (lhs: Self, rhs: Self) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      return false
    }
    return !(lhs < rhs)
  }

}

// MARK: - String Conversion

extension BigDecimal: CustomStringConvertible {

  public var description: String {
    switch storage {
    case .nan:
      return "nan"
    case .infinity(let sign):
      return sign == .plus ? "inf" : "-inf"
    case .mantissa(let mantissa, let scale):

      // Handle zero
      guard !mantissa.isZero else {
        return switch scale {
        case 0: "0"
        case _ where scale > 0: "0.\(String(repeating: "0", count: scale))"
        default: "0E+1\(String(repeating: "0", count: -scale - 1))"
        }
      }

      // Convert mantissa to string
      var str = mantissa.magnitude.description

      if scale > 0 {
        if str.count < scale {
          str = String(repeating: "0", count: scale - str.count) + str
        }
        let decimalIndex = str.count - scale
        str.insert(".", at: str.index(str.startIndex, offsetBy: decimalIndex))
      } else if scale < 0 {
        str += String(repeating: "0", count: -scale)
      }

      if str.last == "." {
        str += "0"
      } else if str.first == "." {
        str = "0" + str
      }

      return (isNegative ? "-" : "") + str
    }
  }

}

extension BigDecimal: CustomDebugStringConvertible {

  public var debugDescription: String {
    return "BigDecimal(\(description))"
  }

}

extension BigDecimal: Sendable {}

// MARK: - FloatingPoint Protocol

extension BigDecimal: FloatingPoint {

  public typealias Magnitude = Self
  public typealias Exponent = Int

  public static var radix: Int { 10 }
  public static var nan: Self { Self(storage: .nan) }
  public static var signalingNaN: Self { Self(storage: .nan) }
  public static var infinity: Self { Self(storage: .infinity(sign: .plus)) }

  public static var greatestFiniteMagnitude: Self {
    // Maximum value is limited by available memory
    return Self(mantissa: .one << 1024, scale: 0)
  }

  public static var leastNormalMagnitude: Self {
    return Self(mantissa: .one, scale: 0)
  }

  public static var leastNonzeroMagnitude: Self {
    return Self(mantissa: .one, scale: Int.max)
  }

  public init(sign: FloatingPointSign, exponent: Exponent, significand: Self) {
    let isNegative = sign == .minus

    // The scale is the negative of the exponent in
    // FloatingPoint/IEEE754 protocol terms.
    let scale = -exponent

    if significand.isNaN {
      self.storage = .nan
    } else if significand.isInfinite {
      self.storage = .infinity(sign: sign)
    } else {
      self.storage = .mantissa(
        isNegative ? -BigInt(significand.mantissa.magnitude) : BigInt(significand.mantissa.magnitude),
        scale: scale
      )
    }
  }

  public init(signOf: Self, magnitudeOf: Self) {
    if magnitudeOf.isNaN {
      self.storage = .nan
    } else if magnitudeOf.isInfinite {
      self.storage = .infinity(sign: signOf.isNegative ? .minus : .plus)
    } else {
      self.storage = .mantissa(
        signOf.isNegative ? -BigInt(magnitudeOf.mantissa.magnitude) : BigInt(magnitudeOf.mantissa.magnitude),
        scale: magnitudeOf.scale
      )
    }
  }

  public init<Source>(_ value: Source) where Source: BinaryInteger {
    self.init(BigInt(value))
  }

  public init?<Source>(exactly source: Source) where Source: BinaryInteger {
    self.init(BigInt(source))
  }

  public var ulp: Self {
    if !isFinite { return .nan }
    return Self(mantissa: .one, scale: scale)
  }

  public var nextUp: Self {
    if !isFinite { return self }
    return self + ulp
  }

  public var nextDown: Self {
    if !isFinite { return self }
    return self - ulp
  }

  public var exponent: Exponent {
    if !isFinite { return 0 }
    // The exponent is the negative of the scale in
    // FloatingPoint/IEEE754 protocol terms.
    return -scale
  }

  public var significandWidth: Int {
    if !isFinite { return 0 }
    return mantissa.bitWidth
  }

  internal static func remainder(dividend: Self, divisor: Self, rounding rule: FloatingPointRoundingRule) -> Self {
    // Handle special values
    guard !dividend.isNaN && !divisor.isNaN && !divisor.isZero && !dividend.isInfinite else {
      return .nan
    }

    if divisor.isInfinite {
      // x % ±infinity = x for finite x
      return dividend
    }

    // For correct sign handling according to IEEE 754:
    // The sign of the result matches the sign of the dividend (dividend)

    let divisorMagnitude = divisor.magnitude

    guard dividend.magnitude >= divisorMagnitude else {
      // If |dividend| < |divisor|, result is just dividend
      return dividend
    }

    // Calculate remainder using proper truncating division for negative values
    let quotient = (dividend / divisorMagnitude).rounded(rule, places: 0)
    return dividend - quotient * divisorMagnitude
  }

  public func remainder(dividingBy other: Self) -> Self {
    return Self.remainder(dividend: self, divisor: other, rounding: .toNearestOrEven)
  }

  public mutating func formRemainder(dividingBy other: Self) {
    self = Self.remainder(dividend: self, divisor: other, rounding: .toNearestOrEven)
  }

  public func truncatingRemainder(dividingBy other: Self) -> Self {
    return Self.remainder(dividend: self, divisor: other, rounding: .towardZero)
  }

  public mutating func formTruncatingRemainder(dividingBy other: Self) {
    self = Self.remainder(dividend: self, divisor: other, rounding: .towardZero)
  }

  public mutating func formSquareRoot() {
    self = squareRoot()
  }

  public mutating func addProduct(_ lhs: Self, _ rhs: Self) {
    self += lhs * rhs
  }

  public func isEqual(to other: Self) -> Bool {
    return self == other
  }

  public func isLess(than other: Self) -> Bool {
    return self < other
  }

  public func isLessThanOrEqualTo(_ other: Self) -> Bool {
    return self <= other
  }

  public func isTotallyOrdered(belowOrEqualTo other: Self) -> Bool {
    if self.isNaN || other.isNaN {
      return false
    }
    return self <= other
  }

  public var floatingPointClass: FloatingPointClassification {
    if isNaN {
      return .quietNaN
    }
    if isInfinite {
      return isNegative ? .negativeInfinity : .positiveInfinity
    }
    if isZero {
      return isNegative ? .negativeZero : .positiveZero
    }
    return isNegative ? .negativeNormal : .positiveNormal
  }

  public var isCanonical: Bool { true }
  public var isNormal: Bool { !isNaN && !isInfinite && !isZero }
  public var isSubnormal: Bool { false }
  public var isSignalingNaN: Bool { false }
  public var isSignaling: Bool { false }

  public static let pi: Self =
    "3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679"

  public var sign: FloatingPointSign {
    if isNaN {
      return .plus
    }
    return isNegative ? .minus : .plus
  }

  public var significand: Self {
    if !isFinite {
      return self
    }
    return Self(mantissa: self.mantissa, scale: 0)
  }

  public mutating func round(_ rule: FloatingPointRoundingRule) {
    self = rounded(rule, places: 0)
  }
}

// MARK: - Constants

extension BigDecimal {

  public static let zero = Self(mantissa: .zero, scale: 0)
  public static let one = Self(mantissa: .one, scale: 0)
  public static let two = Self(mantissa: .two, scale: 0)
  public static let ten = Self(mantissa: .ten, scale: 0)

  public static let e: BigDecimal = Self(
    "2.718281828459045235360287471352662497757247093699959574966967627724076630353547594571382178525166427"
  )

}

extension BigDecimal: Hashable {

  public func hash(into hasher: inout Hasher) {
    hasher.combine(storage)
  }

}


extension BigDecimal: ExpressibleByIntegerLiteral {

  public init(integerLiteral value: StaticBigInt) {
    self.storage = .mantissa(BigInt(integerLiteral: value), scale: 0)
  }

}

extension BigDecimal: ExpressibleByStringLiteral {

  public init(stringLiteral value: StaticString) {
    let string = value.withUTF8Buffer { buffer in String(data: Data(buffer), encoding: .utf8).neverNil() }
    guard let decimal = Self(string) else {
      fatalError("Invalid decimal literal: \(value)")
    }
    self = decimal
  }
}

extension BigDecimal: Strideable {

  public func distance(to other: Self) -> Self {
    return other - self
  }

  public func advanced(by n: Self) -> Self {
    return self + n
  }

}

// MARK: - Protocol Extensions

extension BinaryInteger {
  /// Creates a new instance from the given BigDecimal, if it can be represented exactly.
  ///
  /// Initializes an instance with an exact representation of the value passed as `source`.
  /// If `source` is not an exact integer, this initializer fails.
  ///
  public init?(exactly source: BigDecimal) {
    guard let integer = source.integer else { return nil }
    self.init(exactly: integer)
  }

  /// Creates a new instance from the given BigDecimal.
  ///
  /// Initializes an instance with the integer part of the value passed as `source`.
  /// If `source` is not an exact integer, this initializer generates a fatal error.
  ///
  public init(_ source: BigDecimal) {
    guard let integer = source.integer else {
      fatalError("Cannot initialize '\(Self.self)' from \(Self.self)(\(source))")
    }
    self.init(integer)
  }
}

extension BinaryFloatingPoint {
  /// Creates a new instance from the given BigDecimal, if it can be represented exactly.
  ///
  /// Initializes an instance with an exact representation of the value passed as `source`.
  ///
  public init?(exactly source: BigDecimal) {
    guard
      !source.isNaN,
      Self.significandBitCount + 1 >= source.mantissa.magnitude.bitWidth,
      Self.exponentBitCount >= BigDecimal.Exponent.bitWidth - source.scale.leadingZeroBitCount
    else {
      return nil
    }
    guard let value = Double(source.description), !value.isNaN else {
      return nil
    }
    self.init(exactly: value)
  }

  /// Creates a new instance from the given BigDecimal, rounded to the closest
  /// possible representation.
  public init(_ source: BigDecimal) {
    if source.isNaN {
      self = .nan
      return
    }
    if source.isInfinite {
      self = source.isNegative ? -.infinity : .infinity
      return
    }
    // Convert through Double as an intermediate step
    self = Self(Double(source.description) ?? .nan)
  }
}

// MARK: - Mathematical Functions

extension BigDecimal {

  /// Returns the value raised to the specified power.
  ///
  /// - Parameter exponent: The exponent to raise this value to
  /// - Returns: This value raised to the specified power
  ///
  public func raised(to exponent: Int) -> Self {
    if exponent == 0 { return .one }
    if exponent == 1 { return self }

    // Handle special cases
    if isNaN { return .nan }
    if isInfinite {
      if exponent < 0 {
        return .zero    // Infinity raised to negative power is zero
      }
      return isNegative && exponent.isMultiple(of: 2) ? .infinity : self
    }
    if isZero {
      if exponent < 0 {
        return .infinity    // Zero raised to negative power is infinity
      }
      return .zero    // Zero raised to positive power is zero
    }

    guard case .mantissa(let m, let s) = storage else {
      return self
    }

    guard exponent < 0 else {
      // For positive powers, use the existing approach
      let newMantissa = m.raised(to: exponent)
      let newScale = s * exponent

      return Self(mantissa: newMantissa, scale: newScale)
    }
    // For negative powers, compute 1 / (self^|power|)
    // We need high precision for the division
    let absPower = -exponent
    let precisionScale = absPower * max(10, s)    // Scale based on the absolute power and current scale

    // Create 1 with enough precision
    let one = Self(mantissa: .one, scale: 0).scaled(to: precisionScale)

    // Calculate denominator: self^|power|
    let denominator = Self(
      mantissa: m.raised(to: absPower),
      scale: s * absPower
    )

    return one / denominator
  }

  /// Returns the square root of this value, rounded to the specified number of decimal places.
  /// - Returns: The square root of this value
  public func squareRoot() -> Self {
    guard isFinite && !isNegative else { return .nan }
    guard !isZero else { return .zero }

    // Use Newton's method to compute the square root
    // Start with an initial guess: x₀ = value / 2
    var x = self / 2
    var prev: Self

    // Iterate until we reach the desired precision
    repeat {
      prev = x
      // xₙ₊₁ = (xₙ + value/xₙ) / 2
      x = (x + self / x) / 2
    } while x != prev

    return x
  }

  /// Returns the absolute value of this value.
  public var abs: Self {
    return magnitude
  }

  /// Returns the greatest common divisor of this value and another value.
  /// - Parameter other: The other value
  /// - Returns: The greatest common divisor
  public func greatestCommonDivisor(_ other: Self) -> Self {
    if isZero {
      return other.abs
    }
    if other.isZero {
      return abs
    }

    // Align scales and compute GCD of mantissas
    let (a, b) = Self.alignScales(self, other)
    let gcdMantissa = a.mantissa.magnitude.greatestCommonDivisor(b.mantissa.magnitude)
    return Self(mantissa: BigInt(gcdMantissa), scale: a.scale)
  }

  /// Returns the least common multiple of this value and another value.
  /// - Parameter other: The other value
  /// - Returns: The least common multiple
  public func lowestCommonMultiple(_ other: Self) -> Self {
    if isZero || other.isZero {
      return .zero
    }

    // Align scales and compute LCM of mantissas
    let (a, b) = Self.alignScales(self, other)
    let lcmMantissa = a.mantissa.magnitude.lowestCommonMultiple(b.mantissa.magnitude)
    return Self(mantissa: BigInt(lcmMantissa), scale: a.scale)
  }

}

// MARK: - String Extensions

extension String {
  /// Creates a new string from a BigDecimal value.
  /// - Parameter decimal: The BigDecimal value to convert to a string.
  public init(_ decimal: BigDecimal) {
    self = decimal.description
  }
}

// MARK: - BinaryFloatingPoint Extensions

private let LOG10_2_FIXED: Int = 315653
private let SHIFT: Int = 20

extension BinaryFloatingPoint {

  private var significandMagnitude: BigUInt {
    let significandBits = BigUInt(significandBitPattern)
    return isSubnormal ? significandBits : (1 << Self.significandBitCount) | significandBits
  }

  internal var components: (significand: BigInt, exponent: Int) {
    let normalizeScale = Self.significandBitCount - significandWidth
    let exponent = Int(exponent) - Int(Self.significandBitCount) + normalizeScale
    let significand = significandMagnitude >> normalizeScale
    return (BigInt(isNegative: sign == .minus, magnitude: significand), exponent)
  }

  @inline(__always)
  private static func decimalScale(forBinaryExponent exp: Int) -> Int {
    let raw = exp * LOG10_2_FIXED
    return (raw >> SHIFT) + ((raw & ((1 << SHIFT) - 1)) == 0 ? 0 : 1)
  }

  fileprivate static func decimalComponents(binarySignificand significand: BigInt, exponent: Int) -> (BigInt, Int) {
    guard exponent < 0 else {
      return (significand << exponent, 0)
    }

    let negExponent = -exponent
    let divisor = BigInt.one << negExponent
    var scale = decimalScale(forBinaryExponent: negExponent)
    var mantissaScaler = BigInt.ten.raised(to: scale)

    while true {
      let significandRaised = significand * mantissaScaler
      let (mantissa, remainder) = significandRaised.quotientAndRemainder(dividingBy: divisor)
      guard !remainder.isZero else {
        return (mantissa, scale)
      }
      scale += 1
      mantissaScaler *= 10
    }
  }

}
