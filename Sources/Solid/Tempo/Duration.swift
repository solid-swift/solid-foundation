//
//  Duration.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/26/25.
//

import SolidCore
import Foundation

/// A duration of time with nanosecond precision.
///
public struct Duration {

  /// The zero duration.
  ///
  /// - Returns: A duration representing the zero duration.
  ///
  public static let zero = Self(nanoseconds: 0)

  /// The minimum duration.
  ///
  /// - Returns: A duration representing the minimum duration.
  ///
  public static let min = Self(nanoseconds: .min)

  /// The maximum duration.
  ///
  /// - Returns: A duration representing the maximum duration.
  ///
  public static let max = Self(nanoseconds: .max)

  /// The number of nanoseconds in the duration.
  ///
  /// - Returns: The number of nanoseconds in the duration.
  ///
  public private(set) var nanoseconds: Int128

  /// Initializes a `Duration` with the given number of nanoseconds.
  ///
  /// - Parameter nanoseconds: The number of nanoseconds.
  ///
  public init(nanoseconds: Int128) {
    self.nanoseconds = nanoseconds
  }

  /// Initializes a `Duration` with the given number of seconds and nanoseconds.
  ///
  /// - Parameters:
  ///  - seconds: The number of seconds.
  ///  - nanoseconds: The number of nanoseconds.
  ///
  public init(seconds: Int64, nanoseconds: Int) {
    self.init(nanoseconds: Int128(seconds) * 1_000_000_000 + Int128(nanoseconds))
  }

  /// Initializes a `Duration` with the given number of fractional seconds.
  ///
  /// - Parameter seconds: The number of seconds.
  ///
  public init(seconds: Double) {
    self.init(nanoseconds: Int128(seconds * 1_000_000_000))
  }

  /// Returns the magnitude of the duration.
  ///
  /// - Returns: The magnitude of the duration.
  ///
  public var magnitude: Duration {
    return Duration(nanoseconds: Int128(nanoseconds.magnitude))
  }

  internal var integerComponents: (hi: Int64, lo: Int64) {
    let hi = nanoseconds >> Int64.bitWidth
    let lo = nanoseconds & Int128(Int64.max)
    return (hi: Int64(hi), lo: Int64(lo))
  }
}

extension Duration: Sendable {}
extension Duration: Hashable {}
extension Duration: Equatable {}

extension Duration: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.nanoseconds < rhs.nanoseconds
  }

}

extension Duration: CustomStringConvertible {

  public var description: String {
    let days = self[.numberOfDays]
    let daysField = days != 0 ? "\(days) day\(days == 1 ? "" : "s")" : ""
    let hours = self[.hoursOfDay]
    let hoursField = hours != 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : ""
    let minutes = self[.minutesOfHour]
    let minutesField = minutes != 0 ? "\(minutes) minute\(minutes == 1 ? "" : "s")" : ""
    let seconds = self[.secondsOfMinute]
    let secondsField = seconds != 0 ? "\(seconds) second\(seconds == 1 ? "" : "s")" : ""
    let nanoseconds = self[.nanosecondsOfSecond]
    let nanosecondsField = nanoseconds != 0 ? "\(nanoseconds) nanoseconds" : ""
    return [daysField, hoursField, minutesField, secondsField, nanosecondsField]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

}

extension Duration: LinkedComponentContainer, ComponentBuildable {

  public static let links: [any ComponentLink<Self>] = [
    ComponentKeyPathLink(.totalNanoseconds, to: \.nanoseconds)
  ]

  public init(components: some ComponentContainer) {

    if let duration = components as? Self {
      self = duration
      return
    }

    var duration: Self = .nanoseconds(0)

    if let totalNanoseconds = components[.totalNanoseconds] {
      duration += .nanoseconds(totalNanoseconds)
    }
    if let totalMicroseconds = components[.totalMicroseconds] {
      duration += .microseconds(totalMicroseconds)
    }
    if let totalMilliseconds = components[.totalMilliseconds] {
      duration += .milliseconds(totalMilliseconds)
    }
    if let totalSeconds = components[.totalSeconds] {
      duration += .seconds(totalSeconds)
    }
    if let totalMinutes = components[.totalMinutes] {
      duration += .minutes(totalMinutes)
    }
    if let totalHours = components[.totalHours] {
      duration += .hours(totalHours)
    }
    if let totalDays = components[.totalDays] {
      duration += .days(totalDays)
    }
    if let numberOfNanoseconds = components[.numberOfNanoseconds] {
      duration += .nanoseconds(numberOfNanoseconds)
    }
    if let numberOfMicroseconds = components[.numberOfMicroseconds] {
      duration += .microseconds(numberOfMicroseconds)
    }
    if let numberOfMilliseconds = components[.numberOfMilliseconds] {
      duration += .milliseconds(numberOfMilliseconds)
    }
    if let numberOfSeconds = components[.numberOfSeconds] {
      duration += .seconds(numberOfSeconds)
    }
    if let numberOfMinutes = components[.numberOfMinutes] {
      duration += .minutes(numberOfMinutes)
    }
    if let numberOfHours = components[.numberOfHours] {
      duration += .hours(numberOfHours)
    }
    if let numberOfDays = components[.numberOfDays] {
      duration += .days(numberOfDays)
    }
    if let nanosecondsOfSecond = components[.nanosecondsOfSecond] {
      duration += .nanoseconds(nanosecondsOfSecond)
    }
    if let microsecondsOfSecond = components[.microsecondsOfSecond] {
      duration += .microseconds(microsecondsOfSecond)
    }
    if let millisecondsOfSecond = components[.millisecondsOfSecond] {
      duration += .milliseconds(millisecondsOfSecond)
    }
    if let nanoosecondOfSecond = components[.nanosecondOfSecond] {
      duration += .nanoseconds(nanoosecondOfSecond)
    }
    if let secondOfMinute = components[.secondOfMinute] {
      duration += .seconds(secondOfMinute)
    }
    if let minuteOfHour = components[.minuteOfHour] {
      duration += .minutes(minuteOfHour)
    }
    if let hourOfDay = components[.hourOfDay] {
      duration += .hours(hourOfDay)
    }
    if let zoneOffset = components[.zoneOffset] {
      duration += .seconds(zoneOffset)
    }

    self = duration
  }
}

extension Duration: ComponentContainerDurationArithmetic {

  public mutating func addReportingOverflow(duration components: some ComponentContainer) throws -> Duration {
    self = self + Duration(components: components)
    return .zero
  }

}

extension Duration: ComponentContainerTimeArithmetic {

  public mutating func addReportingOverflow(time components: some ComponentContainer) throws -> Duration {
    self = self + Duration(components: components)
    return .zero
  }
}

// MARK: - Conversion Initializers

extension Duration {

  /// Initialize a duration from a specified number of units.
  ///
  /// - Parameters:
  ///   - value: The value in `unit`s.
  ///   - unit: The unit of `value`.
  ///
  public init<I>(_ value: I, unit: Unit) where I: SignedInteger {
    switch unit {
    case .days:
      self = .days(value)
    case .hours:
      self = .hours(value)
    case .minutes:
      self = .minutes(value)
    case .seconds:
      self = .seconds(value)
    case .milliseconds:
      self = .milliseconds(value)
    case .microseconds:
      self = .microseconds(value)
    case .nanoseconds:
      self = .nanoseconds(value)
    case .eras, .centuries, .millenia, .decades, .years, .months, .weeks, .nan:
      preconditionFailure("Invalid unit for duration value: \(unit)")
    }
  }

  public init(_ component: Component) {
    guard let durationComponent = component.kind as? any DurationComponentKind else {
      preconditionFailure("Invalid component for initializing Duration: \(component)")
    }

    func unwrapInit<K>(_ kind: K, value: some Sendable) -> Self where K: DurationComponentKind {
      let typedValue = knownSafeCast(value, to: K.Value.self)
      return Self(typedValue, unit: kind.unit)
    }

    self = unwrapInit(durationComponent, value: component.value)
  }

  public init(_ zoneOffset: ZoneOffset) {
    self = .seconds(zoneOffset.totalSeconds)
  }

}

// MARK: - Accessors

extension Duration {

  public func valueIfPresent<K>(for kind: K) -> K.Value? where K: ComponentKind {
    guard let durationKind = kind as? any DurationComponentKind else {
      return nil
    }
    return durationKind.extract(from: self, forceRollOver: nil) as? K.Value
  }

  public subscript<K>(_ kind: K, forceRollOver: Bool? = nil) -> K.Value where K: DurationComponentKind {
    kind.extract(from: self, forceRollOver: forceRollOver)
  }

}

// MARK: - Mathematical Operators

private let twoToThe64th = pow(2.0, 64.0)

extension Duration {

  public static func + (lhs: Self, rhs: Self) -> Self {
    let (sum, overflow) = Int128(lhs.nanoseconds).addingReportingOverflow(rhs.nanoseconds)
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: sum)
  }

  public static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }

  public static func - (lhs: Self, rhs: Self) -> Self {
    let (difference, overflow) = Int128(lhs.nanoseconds).subtractingReportingOverflow(rhs.nanoseconds)
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: difference)
  }

  public static func -= (lhs: inout Self, rhs: Self) {
    lhs = lhs - rhs
  }

  public static prefix func - (lhs: Self) -> Self {
    return Self(nanoseconds: -lhs.nanoseconds)
  }

  public static func * (lhs: Self, rhs: Self) -> Self {
    let (product, overflow) = Int128(lhs.nanoseconds).multipliedReportingOverflow(by: rhs.nanoseconds)
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: product)
  }

  public static func *= (lhs: inout Self, rhs: Self) {
    lhs = lhs * rhs
  }

  public static func * <I>(lhs: I, rhs: Self) -> Self where I: BinaryInteger {
    let (product, overflow) = Int128(lhs).multipliedReportingOverflow(by: rhs.nanoseconds)
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: product)
  }

  public static func * <I>(lhs: Self, rhs: I) -> Self where I: BinaryInteger {
    return rhs * lhs
  }

  public static func *= <I>(lhs: inout Self, rhs: I) where I: BinaryInteger {
    lhs = lhs * rhs
  }

  public static func * <F>(lhs: F, rhs: Self) -> Self where F: BinaryFloatingPoint {

    // Convert to Double separately for maximum precision
    let (rhsHi, rhsLo) = rhs.integerComponents
    let highProduct = Double(rhsHi) * Double(lhs)
    let lowProduct = Double(rhsLo) * Double(lhs)

    // Recombine & round explicitly
    let combinedProduct = highProduct * twoToThe64th + lowProduct
    let product = combinedProduct.rounded(.toNearestOrAwayFromZero)

    return Self(nanoseconds: Int128(product))
  }

  public static func * <F>(lhs: Self, rhs: F) -> Self where F: BinaryFloatingPoint {
    return rhs * lhs
  }

  public static func *= <F>(lhs: inout Self, rhs: F) where F: BinaryFloatingPoint {
    lhs = lhs * rhs
  }

  public static func / (lhs: Self, rhs: Self) -> Self {
    let (quotient, overflow) = Int128(lhs.nanoseconds).dividedReportingOverflow(by: rhs.nanoseconds)
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: quotient)
  }

  public static func /= (lhs: inout Self, rhs: Self) {
    lhs = lhs / rhs
  }

  public static func / <I>(lhs: Self, rhs: I) -> Self where I: BinaryInteger {
    let (quotient, overflow) = Int128(lhs.nanoseconds).dividedReportingOverflow(by: Int128(rhs))
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: quotient)
  }

  public static func /= <I>(lhs: inout Self, rhs: I) where I: BinaryInteger {
    lhs = lhs / rhs
  }

  public static func / <F>(lhs: Self, rhs: F) -> Self where F: BinaryFloatingPoint {

    // Convert to Double separately for maximum precision
    let (lhsHi, lhsLo) = lhs.integerComponents
    let lhsDouble = Double(lhsHi) * twoToThe64th + Double(lhsLo)

    // Divide & round explicitly
    let quotientDouble = lhsDouble / Double(rhs)
    let quotient = quotientDouble.rounded(.toNearestOrAwayFromZero)

    return Self(nanoseconds: Int128(quotient))
  }

  public static func /= <F>(lhs: inout Self, rhs: F) where F: BinaryFloatingPoint {
    lhs = lhs / rhs
  }

  public static func % (lhs: Self, rhs: Self) -> Self {
    let (remainder, overflow) = Int128(lhs.nanoseconds).remainderReportingOverflow(dividingBy: rhs.nanoseconds)
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: remainder)
  }

  public static func %= (lhs: inout Self, rhs: Self) {
    lhs = lhs % rhs
  }

  public static func % <I>(lhs: Self, rhs: I) -> Self where I: BinaryInteger {
    let (remainder, overflow) = Int128(lhs.nanoseconds).remainderReportingOverflow(dividingBy: Int128(rhs))
    assert(!overflow, "\(String(describing: self)) overflow")
    return Self(nanoseconds: remainder)
  }

  public static func %= <I>(lhs: inout Self, rhs: I) where I: BinaryInteger {
    lhs = lhs % rhs
  }

  public static func % <F>(lhs: Self, rhs: F) -> Self where F: BinaryFloatingPoint {

    // Convert to Double separately for maximum precision
    let (lhsHi, lhsLo) = lhs.integerComponents
    let lhsDouble = Double(lhsHi) * twoToThe64th + Double(lhsLo)

    // Remainder & round explicitly
    let remainderDouble = lhsDouble.remainder(dividingBy: Double(rhs))
    let remainder = remainderDouble.rounded(.toNearestOrAwayFromZero)

    return Self(nanoseconds: Int128(remainder))
  }

  public static func %= <F>(lhs: inout Self, rhs: F) where F: BinaryFloatingPoint {
    lhs = lhs % rhs
  }

  /// Returns the remainder of the duration when divided by the given unit.
  ///
  /// - Parameter unit: The unit to divide the duration by.
  ///
  /// - Returns: The remainder of the duration when divided by the given unit.
  ///
  public func remainder(in unit: Unit) -> Duration {
    switch unit {
    case .days:
      return self - .days(self[.totalDays])
    case .hours:
      return self - .hours(self[.totalHours])
    case .minutes:
      return self - .minutes(self[.totalMinutes])
    case .seconds:
      return self - .seconds(self[.totalSeconds])
    case .milliseconds:
      return self - .milliseconds(self[.totalMilliseconds])
    case .microseconds:
      return self - .microseconds(self[.totalMicroseconds])
    case .nanoseconds:
      return .zero
    default:
      preconditionFailure("Unsupported unit for remainder: \(unit)")
    }
  }

  /// Returns the truncated duration when divided by the given unit.
  ///
  /// - Parameter unit: The unit to divide the duration by.
  ///
  /// - Returns: The truncated duration when divided by the given unit.
  ///
  public func truncated(to unit: Unit) -> Duration {
    switch unit {
    case .days:
      .days(self[.totalDays])
    case .hours:
      .hours(self[.totalHours])
    case .minutes:
      .minutes(self[.totalMinutes])
    case .seconds:
      .seconds(self[.totalSeconds])
    case .milliseconds:
      .milliseconds(self[.totalMilliseconds])
    case .microseconds:
      .microseconds(self[.totalMicroseconds])
    case .nanoseconds:
      self
    default:
      preconditionFailure("Unsupported unit for truncation: \(unit)")
    }
  }

  /// Returns the quotient and remainder of the duration when divided by the given unit.
  ///
  /// - Parameter unit: The unit to divide the duration by.
  ///
  /// - Returns: The quotient and remainder of the duration when divided by the given unit.
  ///
  public func divided(at unit: Unit) -> (quotient: Self, remainder: Self) {
    (truncated(to: unit), remainder(in: unit))
  }
}

// MARK: - Factory Methods

extension Duration {

  /// Returns a duration representing the given number of days.
  ///
  /// - Parameter days: The number of days.
  ///
  /// - Returns: A duration representing the given number of days.
  ///
  public static func days<I>(_ days: I) -> Self where I: SignedInteger {
    return days * Self.hours(24)
  }

  /// Returns a duration representing the given number of days.
  ///
  /// - Parameter days: The number of days.
  ///
  /// - Returns: A duration representing the given number of days.
  ///
  public static func days<F>(_ days: F) -> Self where F: BinaryFloatingPoint {
    return days * Self.hours(24)
  }

  /// Returns a duration representing the given number of hours.
  ///
  /// - Parameter hours: The number of hours.
  ///
  /// - Returns: A duration representing the given number of hours.
  ///
  public static func hours<I>(_ hours: I) -> Self where I: SignedInteger {
    return hours * Self.minutes(60)
  }

  /// Returns a duration representing the given number of hours.
  ///
  /// - Parameter hours: The number of hours.
  ///
  /// - Returns: A duration representing the given number of hours.
  ///
  public static func hours<F>(_ hours: F) -> Self where F: BinaryFloatingPoint {
    return hours * Self.minutes(60)
  }

  /// Returns a duration representing the given number of minutes.
  ///
  /// - Parameter minutes: The number of minutes.
  ///
  /// - Returns: A duration representing the given number of minutes.
  ///
  public static func minutes<I>(_ minutes: I) -> Self where I: SignedInteger {
    return minutes * Self.seconds(60)
  }

  /// Returns a duration representing the given number of minutes.
  ///
  /// - Parameter minutes: The number of minutes.
  ///
  /// - Returns: A duration representing the given number of minutes.
  ///
  public static func minutes<F>(_ minutes: F) -> Self where F: BinaryFloatingPoint {
    return minutes * Self.seconds(60)
  }

  /// Returns a duration representing the given number of seconds.
  ///
  /// - Parameter seconds: The number of seconds.
  ///
  /// - Returns: A duration representing the given number of seconds.
  ///
  public static func seconds<I>(_ seconds: I) -> Self where I: SignedInteger {
    return seconds * Self.nanoseconds(1_000_000_000)
  }

  /// Returns a duration representing the given number of seconds.
  ///
  /// - Parameter seconds: The number of seconds.
  ///
  /// - Returns: A duration representing the given number of seconds.
  ///
  public static func seconds<F>(_ seconds: F) -> Self where F: BinaryFloatingPoint {
    return Self(seconds: Double(seconds))
  }

  /// Returns a duration representing the given number of milliseconds.
  ///
  /// - Parameter milliseconds: The number of milliseconds.
  ///
  /// - Returns: A duration representing the given number of milliseconds.
  ///
  public static func milliseconds<I>(_ milliseconds: I) -> Self where I: SignedInteger {
    return Self(nanoseconds: Int128(milliseconds) * 1_000_000)
  }

  /// Returns a duration representing the given number of microseconds.
  ///
  /// - Parameter microseconds: The number of microseconds.
  ///
  /// - Returns: A duration representing the given number of microseconds.
  ///
  public static func microseconds<I>(_ microseconds: I) -> Self where I: SignedInteger {
    return Self(nanoseconds: Int128(microseconds) * 1_000)
  }

  /// Returns a duration representing the given number of nanoseconds.
  ///
  /// - Parameter nanoseconds: The number of nanoseconds.
  ///
  /// - Returns: A duration representing the given number of nanoseconds.
  ///
  public static func nanoseconds<I>(_ nanoseconds: I) -> Self where I: SignedInteger {
    return Self(nanoseconds: Int128(nanoseconds))
  }
}

extension Duration: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(nanoseconds: try container.decode(Int128.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(nanoseconds)
  }

}

extension Duration {

  /// Order independent different between two ``OffsetDateTime`` values.
  ///
  public static func between(_ a: OffsetDateTime, _ b: OffsetDateTime) -> Duration {
    let ad = a.durationSinceEpoch(at: .utc)
    let bd = b.durationSinceEpoch(at: .utc)
    guard ad > bd else {
      return bd - ad
    }
    return ad - bd
  }

  /// Order independent different between two ``ZonedDateTime`` values.
  ///
  public static func between(_ a: ZonedDateTime, _ b: ZonedDateTime) -> Duration {
    let ad = a.durationSinceEpoch(at: .utc)
    let bd = b.durationSinceEpoch(at: .utc)
    guard ad > bd else {
      return bd - ad
    }
    return ad - bd
  }

}
