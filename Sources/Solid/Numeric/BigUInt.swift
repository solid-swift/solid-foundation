//
//  BigUInt.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/16/25.
//

import SolidCore
import Algorithms


/// arbitrary‑precision unsigned integer.
///
/// An arbitrary-precision unsigned integer that implements Swift's numeric protocols.
/// The value is backed by a little‑endian array of machine words (`UInt`).
/// The array never contains leading‑zero words *unless* the value is exactly zero
/// (represented by a single `0` word).
///
public struct BigUInt {

  @usableFromInline
  internal static let wordBits = UInt.bitWidth
  @usableFromInline
  internal static let wordMask = UInt.max

  @usableFromInline
  internal static let wordBitsDW = UInt128(Self.wordBits)
  @usableFromInline
  internal static let wordMaskDW = UInt128(Self.wordMask)

  @usableFromInline
  internal static let msbShift = UInt.bitWidth - 1

  public private(set) var words: Words

  public init() {
    self.words = .zero
  }

  internal init<S>(words: S, preNormalized: Bool = false) where S: Collection, S.Element == UInt {
    self.init(words: Words(words), preNormalized: preNormalized)
  }

  internal init(words: Words, preNormalized: Bool = false) {
    precondition(words.count > 0, "words must not be empty")
    self.words = words
    if !preNormalized { normalize() }
  }

  // Remove leading‑zero words so that `words.last! != 0`, except for zero.
  internal mutating func normalize() {
    let wordCount = words.count
    guard wordCount > 1 else {
      return
    }
    let mszwCount = words.mostSignificantZeroCount
    let trimCount = mszwCount == wordCount ? wordCount - 1 : mszwCount
    if trimCount > 0 {
      words.removeLast(trimCount)
    }
  }

  internal var isZero: Bool {
    return words.count == 1 && words.leastSignificant == 0
  }

  public static let zero = Self()
  public static let one = Self(words: [1])
  public static let two = Self(words: [2])
  public static let ten = Self(words: [10])
}

extension BigUInt: Sendable {}
extension BigUInt: Equatable {}
extension BigUInt: Hashable {}

extension BigUInt: Numeric, BinaryInteger, UnsignedInteger {

  public typealias Magnitude = BigUInt

  public static let isSigned: Bool = false

  // MARK - Integer initializers

  public init?<T>(exactly source: T) where T: BinaryInteger {
    guard source >= 0 else { return nil }
    self.init(words: Words(source.magnitude.words))
  }

  public init<T>(_ source: T) where T: BinaryInteger {
    precondition(source >= 0, "negative integer '\(source)' overflows when stored into unsigned type 'BigUInt'")
    self.init(words: Words(source.magnitude.words))
  }

  public init<T>(truncatingIfNeeded source: T) where T: BinaryInteger {
    let totalBits = source.bitWidth
    guard totalBits != 0 else {
      self = .zero
      return
    }
    let neededWords = (totalBits + Self.wordBits - 1) / Self.wordBits
    var w = Words(count: neededWords)
    // copy the low‑order words verbatim (little‑endian)
    for (i, word) in source.words.enumerated() where i < neededWords {
      w[i] = UInt(word)
    }
    // mask off unused high bits in the last word so that only `totalBits` remain
    let highBits = totalBits % Self.wordBits
    if highBits != 0 {
      let mask = (UInt(1) << UInt(highBits)) - 1
      w[neededWords - 1] &= mask
    }
    self.init(words: w)
  }

  public init<T>(clamping source: T) where T: BinaryInteger {
    if source < 0 {
      self = .zero
    } else {
      self.init(source)
    }
  }

  // MARK - Floating point initializers

  public init<T>(_ source: T) where T: BinaryFloatingPoint {
    precondition(
      source.isFinite,
      "\(String(describing: type(of: source))) value cannot be converted to BigUInt because it is either infinite or NaN"
    )
    precondition(source >= 0, "Negative value is not representable")

    guard source != 0 else {
      self = .zero
      return
    }

    // Decompose: value = significand × 2^exponent (significand in [1,2))
    let exponent = source.exponent
    let significand = source.significand

    // Initialize with the normalized significand (a value between 1 and 2)
    self = Self(UInt(significand * T(1 << T.significandBitCount)))

    // Scale by the exponent, accounting for the bits we've already used
    let bitsToShift = Int(exponent) - T.significandBitCount

    if bitsToShift > 0 {
      self.shiftLeft(bitsToShift)
    } else if bitsToShift < 0 {
      self.shiftRight(-bitsToShift)
    }
  }

  /// Exact conversion from a floating‑point value.
  ///
  /// Converts the floating point value to an exact representation if it can
  /// be represented exactly. Fails if the value is NaN, ±∞, negative, or not
  /// an integer in base‑10.
  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    // must be finite, non‑negative, and an *integer*
    guard source.isFinite,
      source >= 0,
      source.rounded(.towardZero) == source
    else {
      return nil
    }

    self.init(source)
  }

  // MARK - Properties

  public var magnitude: Magnitude {
    return self
  }

  public var bitWidth: Int {
    return (words.count - 1) * Self.wordBits + (Self.wordBits - words.mostSignificant.leadingZeroBitCount)
  }

  public var leadingZeroBitCount: Int {
    return 0
  }

  public var trailingZeroBitCount: Int {
    let lszwCount = words.leastSignificantZeroCount
    guard lszwCount < words.count else {
      return 0
    }
    return lszwCount * Self.wordBits + words[lszwCount].trailingZeroBitCount
  }

  // MARK: - Arithmetic

  public static func += (lhs: inout Self, rhs: Self) {
    withUnsafeOutputBuffer(of: UInt.self, count: lhs.words.count + rhs.words.count) { result in

      let count = Swift.max(lhs.words.count, rhs.words.count)
      result.resize(to: count)

      var carry: UInt = 0
      for i in 0..<count {
        let a = i < lhs.words.count ? lhs.words[i] : 0
        let b = i < rhs.words.count ? rhs.words[i] : 0
        let (sum1, ov1) = a.addingReportingOverflow(b)
        let (sum2, ov2) = sum1.addingReportingOverflow(carry)
        result[i] = sum2
        carry = (ov1 ? 1 : 0) + (ov2 ? 1 : 0)
      }

      if carry != 0 { result.append(carry) }

      // Normalize & assign the result
      result.normalize()
      lhs.words.replaceAll(with: result)
    }
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    var result = lhs
    result += rhs
    return result
  }

  public static func -= (lhs: inout Self, rhs: Self) {
    precondition(lhs >= rhs, "arithmetic operation '\(lhs) - \(rhs)' (on type 'BigUInt') results in an underflow")
    withUnsafeOutputBuffer(of: UInt.self, count: lhs.words.count) { result in

      result.resize(to: lhs.words.count)

      var borrow: UInt = 0
      for i in 0..<lhs.words.count {
        let a = lhs.words[i]
        let b = i < rhs.words.count ? rhs.words[i] : 0
        let (sub1, ov1) = a.subtractingReportingOverflow(b)
        let (sub2, ov2) = sub1.subtractingReportingOverflow(borrow)
        result[i] = sub2
        borrow = (ov1 ? 1 : 0) + (ov2 ? 1 : 0)
      }

      // Normalize & assign the result
      result.normalize()
      lhs.words.replaceAll(with: result)
    }
  }

  public static func - (lhs: Self, rhs: Self) -> Self {
    var result = lhs
    result -= rhs
    return result
  }

  public static func *= (lhs: inout Self, rhs: Self) {
    if lhs.isZero || rhs.isZero {
      lhs = .zero
      return
    }
    // Ensure lhs is the longer number
    let (a, b) = lhs.words.count >= rhs.words.count ? (lhs, rhs) : (rhs, lhs)
    withUnsafeOutputBuffer(repeating: UInt(0), count: a.words.count + b.words.count) { result in

      result.resize(to: a.words.count + b.words.count)

      for i in 0..<a.words.count {
        var carry: UInt = 0
        for j in 0..<b.words.count {
          let idx = i + j
          let (hi, lo) = a.words[i].multipliedFullWidth(by: b.words[j])

          // add lo to current limb
          let (sumLo, ovLo) = result[idx].addingReportingOverflow(lo)

          // add hi + old carry + overflow‑from‑lo to next limb
          let hiPlusCarry = hi &+ carry &+ (ovLo ? 1 : 0)
          let (sumHi, ovHi) =
            result[idx + 1].addingReportingOverflow(hiPlusCarry)
          result[idx] = sumLo
          result[idx + 1] = sumHi
          carry = ovHi ? 1 : 0    // propagate overflow
        }

        // propagate remaining carry
        var k = i + b.words.count
        while carry != 0 {
          let (s, ov) = result[k].addingReportingOverflow(carry)
          result[k] = s
          carry = ov ? 1 : 0
          k += 1
        }
      }

      // Normalize & assign the result
      result.normalize()
      lhs.words.replaceAll(with: result)
    }
  }

  public static func * (lhs: Self, rhs: Self) -> Self {
    var result = lhs
    result *= rhs
    return result
  }

  private static let divBeta = UInt128(UInt64.max) + 1

  // Long division (Knuth D, radix 2⁶⁴)
  internal func quotientAndRemainder(
    dividingBy divisor: Self,
    quotient: inout UnsafeOutputBuffer<UInt>,
    remainder: inout UnsafeOutputBuffer<UInt>?
  ) {
    precondition(!divisor.isZero, "division by zero")

    // Knuth D: m >= n
    if self < divisor {
      quotient.append(0)
      remainder?.append(contentsOf: self.words)
      return
    }

    // Knuth D: n >= 2
    guard divisor.words.count >= 2 else {
      let d = divisor.words.leastSignificant
      quotient.resize(to: words.count)
      var r: UInt = 0
      for i in stride(from: words.count &- 1, through: 0, by: -1) {
        (quotient[i], r) = d.dividingFullWidth((high: r, low: words[i]))
      }
      remainder?.append(r)
      // Normalize the quotient
      quotient.normalize()
      return
    }

    let m = self.words.count    // dividend length
    let n = divisor.words.count    // divisor length

    // ────────────────────────────────────────────────────────────────────
    // D1  normalise  (shift so v₁ ≥ β/2)
    let shift = divisor.words.mostSignificant.leadingZeroBitCount
    let unCount = m + 1 + (shift > self.words.mostSignificant.leadingZeroBitCount ? 1 : 0)
    let vnCount = n
    let qCount = m - n + 1

    return withUnsafeTemporaryAllocation(of: UInt.self, capacity: unCount + vnCount) { wordBuffer in
      var un = wordBuffer.extracting(..<unCount)
      var vn = wordBuffer.extracting(unCount..<(unCount + vnCount))
      quotient.resize(to: qCount)

      // Shift and copy the source values
      Self.copyAndShift(source: words, destination: &un, shift: shift)
      Self.copyAndShift(source: divisor.words, destination: &vn, shift: shift)
      // Zero out the extra word in un
      un[unCount - 1] = 0

      // ────────────────────────────────────────────────────────────────────
      // D2 … D7
      for j in stride(from: m - n, through: 0, by: -1) {
        let un0 = UInt128(un[j + n])
        let un1 = UInt128(un[j + n - 1])
        let un2 = UInt128(un[j + n - 2])
        let vn1 = UInt128(vn[n - 1])
        let vn2 = UInt128(vn[n - 2])

        // ---------- D3  estimate q̂
        var (qHat, rHat) = (un0 << Self.wordBits | un1).quotientAndRemainder(dividingBy: vn1)

        // correct if q̂ = β or q̂·v₂ > (r̂·β + u₀)
        while (qHat == Self.divBeta) || (qHat * vn2 > (rHat * Self.divBeta + un2)) {
          qHat -= 1
          rHat += vn1
          if rHat >= Self.divBeta { break }    // at most one more loop
        }

        // ---------- D4  multiply‑subtract
        var borrow: UInt = 0
        for i in 0..<n {
          let prod = UInt128(vn[i]) * qHat    // 128‑bit product
          let prodLo = UInt(prod & UInt128(UInt.max))    // low 64 product
          let prodHi = UInt(prod >> 64)    // high 64 product

          //  ui ← ui - lo - borrow
          let (u1, ov1) = un[i + j].subtractingReportingOverflow(prodLo)
          let (u2, ov2) = u1.subtractingReportingOverflow(borrow)
          un[i + j] = u2
          borrow = prodHi &+ (ov1 ? 1 : 0) &+ (ov2 ? 1 : 0)    // 0,1, or 2
        }

        // top word
        let (top, ov3) = un[j + n].subtractingReportingOverflow(borrow)
        un[j + n] = top
        var qWord = UInt(qHat & UInt128(UInt.max))

        // ---------- D5  q̂ one too large →  add divisor back
        if ov3 {
          qWord &-= 1
          var carry: UInt = 0
          for i in 0..<n {
            let (s1, ov1) = un[i + j].addingReportingOverflow(vn[i])
            let (s2, ov2) = s1.addingReportingOverflow(carry)
            un[i + j] = s2
            carry = (ov1 ? 1 : 0) &+ (ov2 ? 1 : 0)
          }
          un[j + n] &+= carry
        }
        quotient[j] = qWord
      }

      // ---------- D8  prepare remainder and quotient

      quotient.normalize()

      if var rem = remainder {
        rem.resize(to: unCount)
        Self.copyAndShift(source: un, destination: &rem, shift: -shift)
        rem.normalize()
        remainder = rem
      }
    }
  }

  public func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
    return withUnsafeOutputBuffers(counts: (words.count + 2, words.count + 2)) { (q, r) in
      // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
      var ro: UnsafeOutputBuffer<UInt>! = r
      self.quotientAndRemainder(dividingBy: rhs, quotient: &q, remainder: &ro)
      return (Self(words: q, preNormalized: true), Self(words: ro, preNormalized: true))
    }
  }

  /// Divides the value by another value, only if it is a multiple of the divisor.
  ///
  /// - Parameter divisor: The divisor.
  /// - Returns: `true` if the value is a multiple of the divisor; otherwise, `false`.
  ///
  public mutating func divide(ifMultipleOf divisor: Self) -> Bool {
    return withUnsafeOutputBuffers(counts: (words.count + 2, words.count + 2)) { (q, r) in
      // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
      var ro: UnsafeOutputBuffer<UInt>! = r
      self.quotientAndRemainder(dividingBy: divisor, quotient: &q, remainder: &ro)
      if !ro.isZero {
        return false
      }
      self.words.replaceAll(with: q)
      return true
    }
  }

  public func remainder(dividingBy divisor: Self) -> Self {
    return withUnsafeOutputBuffers(counts: (words.count + 2, words.count + 2)) { (q, r) in
      // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
      var ro: UnsafeOutputBuffer<UInt>! = r
      self.quotientAndRemainder(dividingBy: divisor, quotient: &q, remainder: &ro)
      return Self(words: ro, preNormalized: true)
    }
  }

  /// Replaces the value with the remainder of the division by another value.
  ///
  /// - Parameter dividend: The value to divide.
  ///
  public mutating func formRemainder(dividing dividend: Self) {
    return withUnsafeOutputBuffers(counts: (dividend.words.count + 2, dividend.words.count + 2)) { (q, r) in
      // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
      var ro: UnsafeOutputBuffer<UInt>! = r
      dividend.quotientAndRemainder(dividingBy: self, quotient: &q, remainder: &ro)
      self.words.replaceAll(with: ro)
    }
  }

  /// Returns a Boolean value indicating whether this value is a multiple of the given value.
  ///
  /// - Parameter other: The value to test as a divisor.
  /// - Returns: `true` if this value is a multiple of `other`; otherwise, `false`.
  ///
  public func isMultiple(of other: Self) -> Bool {

    // Easy cases
    if other == .one || self == other { return true }
    if self.isZero { return true }
    if other.isZero { return false }
    if self < other { return false }

    // Use trailing zeros optimization: if other has more trailing zeros than self,
    // then self cannot be multiple of other
    let otherTrailingZeros = other.trailingZeroBitCount
    let selfTrailingZeros = self.trailingZeroBitCount
    if otherTrailingZeros > selfTrailingZeros {
      return false
    }

    // For small divisors, check for divisibility using the GCD method
    // which is faster than full division for large numbers
    if other.words.count <= 2 {
      return self.greatestCommonDivisor(other) == other
    }

    // Fall back to remainder test
    var temp = self
    return temp.divide(ifMultipleOf: other)
  }

  public static func / (lhs: Self, rhs: Self) -> Self {
    withUnsafeOutputBuffer(count: lhs.words.count + 2) { q in
      var ro: UnsafeOutputBuffer<UInt>? = nil
      lhs.quotientAndRemainder(dividingBy: rhs, quotient: &q, remainder: &ro)
      return Self(words: q, preNormalized: true)
    }
  }

  public static func /= (lhs: inout Self, rhs: Self) {
    withUnsafeOutputBuffer(count: lhs.words.count + 2) { q in
      var ro: UnsafeOutputBuffer<UInt>? = nil
      lhs.quotientAndRemainder(dividingBy: rhs, quotient: &q, remainder: &ro)
      lhs.words.replaceAll(with: q)
    }
  }

  public static func % (lhs: Self, rhs: Self) -> Self {
    withUnsafeOutputBuffers(counts: (lhs.words.count + 2, lhs.words.count + 2)) { (q, r) in
      // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
      var ro: UnsafeOutputBuffer<UInt>! = r
      lhs.quotientAndRemainder(dividingBy: rhs, quotient: &q, remainder: &ro)
      return Self(words: ro, preNormalized: true)
    }
  }

  public static func %= (lhs: inout Self, rhs: Self) {
    withUnsafeOutputBuffers(counts: (lhs.words.count + 2, lhs.words.count + 2)) { (q, r) in
      // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
      var ro: UnsafeOutputBuffer<UInt>! = r
      lhs.quotientAndRemainder(dividingBy: rhs, quotient: &q, remainder: &ro)
      lhs.words.replaceAll(with: ro)
    }
  }

  /// Raises the value to the specified power.
  ///
  /// - Parameter power: The power to raise the value to.
  /// - Returns: The result of raising the value to the specified power.
  ///
  public func raised(to power: Int) -> Self {
    precondition(power >= 0, "Negative powers are not supported")
    if power == 0 { return .one }
    if power == 1 { return self }

    var result = Self.one
    var base = self
    var exp = power

    while exp > 0 {
      if (exp & 1) == 1 {    // low bit set → multiply
        result *= base
      }
      exp >>= 1    // shift exponent
      if exp != 0 {    // square only if more bits remain
        base *= base
      }
    }

    return result
  }

  /// Returns the greatest common divisor of this value and another value.
  /// - Parameter other: The other value
  /// - Returns: The greatest common divisor
  public func greatestCommonDivisor(_ other: Self) -> Self {
    var a = self
    var b = other
    while !b.isZero {
      let temp = b
      b.formRemainder(dividing: a)
      a = temp
    }
    return a
  }

  /// Returns the least common multiple of this value and another value.
  /// - Parameter other: The other value
  /// - Returns: The least common multiple
  public func lowestCommonMultiple(_ other: Self) -> Self {
    if isZero || other.isZero {
      return .zero
    }
    return (self / greatestCommonDivisor(other)) * other
  }

  // MARK: - Bitwise

  internal static func bitwiseOperation(lhs: inout Self, rhs: Self, _ op: (UInt, UInt) -> UInt) {
    let count = Swift.max(lhs.words.count, rhs.words.count)
    withUnsafeOutputBuffer(repeating: UInt(0), count: count) { result in

      result.resize(to: count)

      for i in 0..<count {
        let a = i < lhs.words.count ? lhs.words[i] : 0
        let b = i < rhs.words.count ? rhs.words[i] : 0
        result[i] = op(a, b)
      }

      result.normalize()
      lhs.words.replaceAll(with: result)
    }
  }

  public static func & (lhs: Self, rhs: Self) -> Self {
    var result = lhs
    bitwiseOperation(lhs: &result, rhs: rhs, &)
    return result
  }

  public static func &= (lhs: inout Self, rhs: Self) {
    bitwiseOperation(lhs: &lhs, rhs: rhs, &)
  }

  public static func | (lhs: Self, rhs: Self) -> Self {
    var result = lhs
    bitwiseOperation(lhs: &result, rhs: rhs, |)
    return result
  }

  public static func |= (lhs: inout Self, rhs: Self) {
    bitwiseOperation(lhs: &lhs, rhs: rhs, |)
  }

  public static func ^ (lhs: Self, rhs: Self) -> Self {
    var result = lhs
    bitwiseOperation(lhs: &result, rhs: rhs, ^)
    return result
  }

  public static func ^= (lhs: inout Self, rhs: Self) {
    bitwiseOperation(lhs: &lhs, rhs: rhs, ^)
  }

  public mutating func formComplement() {
    if isZero { return }
    // 2^n - 1 - x
    var mask = Self.one
    mask.shiftLeft(bitWidth)
    mask -= .one
    mask -= self
    self = mask
  }

  public static prefix func ~ (x: Self) -> Self {
    var result = x
    result.formComplement()
    return result
  }

  // MARK: - Shifts

  internal mutating func shiftLeft(_ k: Int) {
    guard k > 0 else { return }
    let wordShift = k / UInt.bitWidth
    let bitShift = k % UInt.bitWidth
    if bitShift == 0 {
      words.insert(contentsOf: repeatElement(0, count: wordShift), at: 0)
      return
    }
    var carry: UInt = 0
    for i in 0..<words.count {
      let newCarry = words[i] >> (UInt.bitWidth - bitShift)
      words[i] = (words[i] << bitShift) | carry
      carry = newCarry
    }
    if carry != 0 { words.append(carry) }
    if wordShift > 0 { words.insert(contentsOf: repeatElement(0, count: wordShift), at: 0) }
  }

  internal mutating func shiftRight(_ k: Int) {
    guard k > 0 else { return }
    let wordShift = k / UInt.bitWidth
    let bitShift = k % UInt.bitWidth
    if wordShift >= words.count {
      self = .zero
      return
    }
    words.removeFirst(wordShift)
    if bitShift == 0 { return }
    var carry: UInt = 0
    for i in stride(from: words.count - 1, through: 0, by: -1) {
      let newCarry = words[i] << (UInt.bitWidth - bitShift)
      words[i] = (words[i] >> bitShift) | carry
      carry = newCarry
    }
    normalize()
  }

  public static func << <RHS>(lhs: Self, rhs: RHS) -> Self where RHS: BinaryInteger {
    var result = lhs
    result.shiftLeft(Int(rhs))
    return result
  }

  public static func <<= <RHS>(lhs: inout Self, rhs: RHS) where RHS: BinaryInteger {
    lhs.shiftLeft(Int(rhs))
  }

  public static func >> <RHS>(lhs: Self, rhs: RHS) -> Self where RHS: BinaryInteger {
    var result = lhs
    result.shiftRight(Int(rhs))
    return result
  }

  public static func >>= <RHS>(lhs: inout Self, rhs: RHS) where RHS: BinaryInteger {
    lhs.shiftRight(Int(rhs))
  }

}

// MARK: - Comparison

extension BigUInt {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.words == rhs.words
  }

}

extension BigUInt: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.words.count != rhs.words.count {
      return lhs.words.count < rhs.words.count
    }
    for i in stride(from: lhs.words.count - 1, through: 0, by: -1) where lhs.words[i] != rhs.words[i] {
      return lhs.words[i] < rhs.words[i]
    }
    return false
  }

}

// MARK: - Literals

extension BigUInt: ExpressibleByIntegerLiteral {

  public init(integerLiteral value: StaticBigInt) {
    precondition(value.signum() >= 0, "BigUInt cannot represent a negative integer literal")
    let bitWidth = value.bitWidth
    guard bitWidth != 0 else {
      self = .zero
      return
    }

    let wordCount = (bitWidth + Self.wordBits - 1) / Self.wordBits
    let words = withUnsafeOutputBuffer(of: UInt.self, count: wordCount) { buffer in

      buffer.resize(to: buffer.capacity)
      for i in 0..<buffer.count {
        buffer[i] = UInt(value[i])
      }

      buffer.normalize()
      return Words(buffer)
    }

    self.init(words: words, preNormalized: true)
  }

}

// MARK: - Strings

extension BigUInt: LosslessStringConvertible {

  public init?(_ description: some StringProtocol) {
    guard !description.isEmpty else {
      return nil
    }

    var start = description.startIndex
    if description[start] == "+" { start = description.index(after: start) }
    guard start < description.endIndex else {
      return nil
    }

    var value: Self = .zero
    for ch in description[start...] {
      guard ch.isASCII, let d = ch.wholeNumberValue else {
        return nil
      }
      value *= 10
      value += Self(UInt(d))
    }

    self = value
  }

}

extension BigUInt: CustomStringConvertible, CustomDebugStringConvertible {

  /// Decimal representation (no leading zeros, "0" for zero).
  public var description: String {
    // 0 and single‑limb fast paths
    guard !isZero else { return "0" }
    guard words.count > 1 else { return String(words.leastSignificant) }

    // Split the number into base‑10¹⁸ chunks
    let base = BigUInt(1_000_000_000_000_000_000)
    var chunks: [String] = []

    var n = self
    var tr = BigUInt.zero
    while !n.isZero {
      withUnsafeOutputBuffers(counts: (words.count + 2, words.count + 2)) { (q, r) in
        var ro: UnsafeOutputBuffer<UInt>! = r
        n.quotientAndRemainder(dividingBy: base, quotient: &q, remainder: &ro)
        n.words.replaceAll(with: q)
        tr.words.replaceAll(with: ro)
        chunks.append(String(tr))
      }
    }

    // Most‑significant chunk is already un‑padded; pad the rest to 18 digits
    var result = chunks.removeLast()
    for chunk in chunks.reversed() {
      result += String(repeating: "0", count: 18 - chunk.count) + chunk
    }
    return result
  }

  public var debugDescription: String {
    return "BigUInt(\(self))"
  }

}

// MARK: - Encode/Decode

extension BigUInt {

  /// Encodes the BigUInt as a byte array in big-endian format.
  ///
  /// - Returns: A byte array representing the BigUInt in big-endian format.
  ///
  public func encode() -> [UInt8] {

    var result: [UInt8] = []
    for i in stride(from: words.count - 1, through: 0, by: -1) {
      let word = words[i]
      for j in stride(from: UInt.bitWidth - 8, through: 0, by: -8) {
        result.append(UInt8((word >> j) & 0xFF))
      }
    }

    // Strip leading 0s (they're not meaningful in big-endian bignum)
    while result.first == 0 && result.count > 1 {
      result.removeFirst()
    }

    return result
  }

  public init<C>(encoded bytes: C) where C: RandomAccessCollection, C: Collection, C.Element == UInt8 {
    guard !bytes.isEmpty else {
      self = .zero
      return
    }

    let wordBytes = UInt.bitWidth / 8
    let wordCount = (bytes.count + (wordBytes - 1)) / wordBytes
    var words = Words(count: wordCount)

    let fill = (wordBytes - (bytes.count % wordBytes)) % wordBytes
    let msWordIndex = words.endIndex - 1
    var wordIndex = words.endIndex
    var byteIndex = bytes.startIndex

    while wordIndex > words.startIndex {
      wordIndex = words.index(before: wordIndex)
      var word: UInt = 0
      let currentWordBytes = wordIndex == msWordIndex ? wordBytes - fill : wordBytes
      let wordEndIndex = bytes.index(byteIndex, offsetBy: currentWordBytes)
      while byteIndex < wordEndIndex {
        word <<= 8
        word |= UInt(bytes[byteIndex])
        byteIndex = bytes.index(after: byteIndex)
      }
      words[wordIndex] = word
    }

    self.init(words: words)
  }

}

// MARK: - String Extensions

extension String {
  /// Creates a new string from a ``BigUInt`` value.
  /// - Parameter integer: The value to convert to a string.
  public init(_ integer: BigUInt) {
    self = integer.description
  }
}

extension BigUInt {
  /// Copies the source array to the destination, applying a bit shift if needed.
  ///
  /// - Parameters:
  ///   - source: The source array to copy from
  ///   - destination: The destination buffer to copy to
  ///   - shift: Number of bits to shift left (0 for no shift)
  @inline(__always)
  private static func copyAndShift<S, D>(
    source: S,
    destination: inout D,
    shift: Int,
  )
  where
    S: BidirectionalCollection,
    S.Element == UInt,
    D: MutableCollection,
    D: BidirectionalCollection,
    D.Element == UInt
  {
    if shift > 0 {
      assert(source.count <= destination.count, "Source must be smaller than or equal to destination")
      let leftShift = shift
      var sourceIndex = source.startIndex
      var destinationIndex = destination.startIndex

      var carry: UInt = 0
      while sourceIndex < source.endIndex && destinationIndex < destination.endIndex {
        let word = source[sourceIndex]
        destination[destinationIndex] = (word << leftShift) | carry
        carry = word >> (UInt.bitWidth - leftShift)
        sourceIndex = source.index(after: sourceIndex)
        destinationIndex = destination.index(after: destinationIndex)
      }

      if carry > 0 {
        destination[destinationIndex] = carry
      }
    } else if shift < 0 {

      let rightShift = -shift
      var sourceIndex = source.endIndex
      var destinationIndex = destination.endIndex

      var carry: UInt = 0
      while sourceIndex > source.startIndex && destinationIndex > destination.startIndex {
        sourceIndex = source.index(before: sourceIndex)
        destinationIndex = destination.index(before: destinationIndex)
        let newCarry = source[sourceIndex] << (UInt.bitWidth - rightShift)
        destination[destinationIndex] = (source[sourceIndex] >> rightShift) | carry
        carry = newCarry
      }
    } else {
      var sourceIndex = source.startIndex
      var destinationIndex = destination.startIndex

      while sourceIndex < source.endIndex && destinationIndex < destination.endIndex {
        destination[destinationIndex] = source[sourceIndex]
        sourceIndex = source.index(after: sourceIndex)
        destinationIndex = destination.index(after: destinationIndex)
      }
    }
  }

}

extension BigUInt {
  /// Estimates the number of decimal digits required to represent this value.
  ///
  /// This estimation uses the relationship between binary and decimal digits:
  /// log10(2^n) ≈ n * log10(2)
  ///
  /// - Returns: The approximate number of decimal digits.
  public var decimalDigitCount: Int {
    if isZero {
      return 1
    }

    // log10(2) ≈ 0.301029995663981
    // We multiply by bitWidth and divide by 1_000_000_000 to avoid floating-point operations
    let approximateDigits = (bitWidth * 301_029_996) / 1_000_000_000

    // Add 1 because log10 gives us one less than the number of digits
    return approximateDigits + 1
  }
}

extension UnsafeOutputBuffer<UInt> {

  @inline(__always)
  internal var mostSignificant: UInt {
    return self[self.count - 1]
  }

  @inline(__always)
  internal var isZero: Bool {
    return count == 1 && self[0] == 0
  }

  @inline(__always)
  internal mutating func normalize() {
    resize(to: Swift.max(1, startOfSuffix { $0 == 0 }))
  }
}
