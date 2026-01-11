//
//  ZoneOffset.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//

import SolidCore


public struct ZoneOffset {

  public static let zero = neverThrow(try ZoneOffset(totalSeconds: 0))
  public static let utc = zero

  internal typealias Storage = Int32

  internal var storage: Storage

  public var totalSeconds: Int {
    get { Int(storage) }
    set { storage = Storage(newValue) }
  }

  public var duration: Duration {
    .seconds(totalSeconds)
  }

  public var hours: Int {
    return Int(totalSeconds / 3600)
  }

  public var minutes: Int {
    return Int((totalSeconds / 60) % 60)
  }

  public var seconds: Int {
    return Int(totalSeconds % 60)
  }

  internal init(storage: Storage) {
    self.storage = storage
  }

  public init(totalSeconds: Int) throws {
    guard totalSeconds.magnitude <= 24 * 3600 else {
      throw TempoError.invalidComponentValue(
        component: .totalSeconds,
        reason: .extended(reason: "Total offset must be less than ±24 hours.")
      )
    }
    self.init(storage: Storage(totalSeconds))
  }

  public init(
    @Validated(.hoursOfZoneOffset) hours: Int,
    @Validated(.minutesOfZoneOffset) minutes: Int,
    @Validated(.secondsOfZoneOffset) seconds: Int
  ) throws {
    let totalSeconds = try $hours.get() * 3600 + $minutes.get() * 60 + $seconds.get()
    if hours > 0 {
      try _minutes.assert(minutes >= 0, "Minutes must be positive when the hour is positive.")
      try _seconds.assert(seconds >= 0, "Seconds must be positive when the hour is positive.")
    } else if hours < 0 {
      try _minutes.assert(minutes <= 0, "Minutes must be negative when the hour is negative.")
      try _seconds.assert(seconds <= 0, "Seconds must be negative when the hour is negative.")
    } else if minutes > 0 {
      try _seconds.assert(seconds >= 0, "Seconds must be positive when the minutes is positive.")
    } else if minutes < 0 {
      try _seconds.assert(seconds <= 0, "Seconds must be negative when the minutes is negative.")
    }
    try self.init(totalSeconds: totalSeconds)
  }

  public func with(
    hours: Int?,
    minutes: Int?,
    seconds: Int?
  ) throws -> Self {
    return try Self(
      hours: hours ?? self.hours,
      minutes: minutes ?? self.minutes,
      seconds: seconds ?? self.seconds
    )
  }
}

extension ZoneOffset: Hashable {}
extension ZoneOffset: Equatable {}
extension ZoneOffset: Sendable {}

extension ZoneOffset: CustomStringConvertible {

  private static let hourFormatter = fixedWidthFormat(Int.self, width: 2)
  private static let minuteFormatter = fixedWidthFormat(Int.self, width: 2)
  private static let secondFormatter = fixedWidthFormat(Int.self, width: 2)

  /// Returns a human-readable description of the zone offset.
  ///
  /// - Note: The _current_ format is equivalent to the ISO 8601 format,
  /// but this is not guaranteed and may change in the future.
  ///
  public var description: String { description(style: .default) }

  public enum DescriptionStyle: Int, Equatable, Hashable, Comparable {
    case complete
    case `default`
    case minimal

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  public func description(style: DescriptionStyle, separator: String = ":") -> String {
    let sign = totalSeconds >= 0 ? "+" : "-"
    let hoursField = hours.magnitude.formatted(Self.hourFormatter)
    let minutesField =
      minutes != 0 || seconds != 0 || style < .minimal
      ? "\(separator)\(minutes.magnitude.formatted(Self.minuteFormatter))"
      : ""
    let secondsField =
      seconds != 0 || style < .default
      ? "\(separator)\(seconds.magnitude.formatted(Self.secondFormatter))"
      : ""
    return "\(sign)\(hoursField)\(minutesField)\(secondsField)"
  }

  public var designation: String { description(style: .minimal, separator: "") }

}

extension ZoneOffset: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.totalSeconds < rhs.totalSeconds
  }

}

extension ZoneOffset {

  public init(availableComponents components: some ComponentContainer) {
    if let zoneOffsetSeconds = components.valueIfPresent(for: .zoneOffset) {
      self.init(storage: Storage(zoneOffsetSeconds))
    } else if let totalSeconds = components.valueIfPresent(for: .totalSeconds) {
      self.init(storage: Storage(totalSeconds))
    } else {
      let hours = components.value(for: .hoursOfZoneOffset)
      let minutes = components.value(for: .minutesOfZoneOffset)
      let seconds = components.value(for: .secondsOfZoneOffset)
      self.init(storage: Storage(hours * 3600 + minutes * 60 + seconds))
    }
  }
}

extension ZoneOffset {

  public static func hours(_ hours: Int) throws -> Self {
    return try Self(hours: hours, minutes: 0, seconds: 0)
  }

}

extension ZoneOffset: Codable {

  enum CodingKeys: String, CodingKey {
    case hours
    case minutes
    case seconds
  }

  public init(from decoder: Decoder) throws {
    guard let keyed = try? decoder.container(keyedBy: CodingKeys.self) else {
      guard let totalSeconds = try? decoder.singleValueContainer().decode(Int.self) else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription:
              "Expected ZoneOffset to be encoded as object with hours, minutes, or seconds or as integer total seconds"
          )
        )
      }
      try self.init(totalSeconds: totalSeconds)
      return
    }
    try self.init(
      hours: try keyed.decode(Int.self, forKey: .hours),
      minutes: try keyed.decode(Int.self, forKey: .minutes),
      seconds: try keyed.decode(Int.self, forKey: .seconds)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(totalSeconds)
  }
}
