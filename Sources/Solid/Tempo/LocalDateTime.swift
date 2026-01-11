//
//  LocalDateTime.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//

/// A date and time without a time zone.
///
public struct LocalDateTime: DateTime {

  public static let min = LocalDateTime(date: .min, time: .min)
  public static let max = LocalDateTime(date: .max, time: .max)

  /// The date part.
  public var date: LocalDate
  /// The time part.
  public var time: LocalTime

  /// The year component of the date.
  public var year: Int { date.year }
  /// The month component of the date.
  public var month: Int { date.month }
  /// The day component of the date.
  public var day: Int { date.day }
  /// The hour component of the time.
  public var hour: Int { time.hour }
  /// The minute component of the time.
  public var minute: Int { time.minute }
  /// The second component of the time.
  public var second: Int { time.second }
  /// The nanosecond component of the time.
  public var nanosecond: Int { time.nanosecond }

  public init(date: LocalDate, time: LocalTime) {
    self.date = date
    self.time = time
  }

  public init(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    nanosecond: Int
  ) throws {
    self.init(
      date: try LocalDate(year: year, month: month, day: day),
      time: try LocalTime(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
    )
  }

  public func at(zone: Zone, resolving: ResolutionStrategy.Options = []) throws -> ZonedDateTime {
    return try ZonedDateTime(
      dateTime: self,
      zone: zone,
      resolving: resolving,
    )
  }

  public func at(offset: ZoneOffset) -> OffsetDateTime {
    return OffsetDateTime(dateTime: self, offset: offset)
  }

  public func with(
    year: Int? = nil,
    month: Int? = nil,
    day: Int? = nil,
    hour: Int? = nil,
    minute: Int? = nil,
    second: Int? = nil,
    nanosecond: Int? = nil
  ) throws -> Self {
    return Self(
      date: try date.with(year: year, month: month, day: day),
      time: try time.with(hour: hour, minute: minute, second: second, nanosecond: nanosecond)
    )
  }

  public func with(date: LocalDate? = nil, time: LocalTime? = nil) -> Self {
    return Self(
      date: date ?? self.date,
      time: time ?? self.time
    )
  }

  public static func now(clock: some Clock = .system, in calendarSystem: GregorianCalendarSystem = .default) -> Self {
    let instant = clock.instant
    let offset = clock.zone.offset(at: instant)
    return calendarSystem.localDateTime(instant: clock.instant, at: offset)
  }

}

extension LocalDateTime: Sendable {}
extension LocalDateTime: Hashable {}
extension LocalDateTime: Equatable {}

extension LocalDateTime: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.date != rhs.date {
      return lhs.date < rhs.date
    }
    return lhs.time < rhs.time
  }
}

extension LocalDateTime: CustomStringConvertible {

  public var description: String {
    return "\(date) \(time)"
  }
}

extension LocalDateTime: LinkedComponentContainer, ComponentBuildable {

  public static let links: [any ComponentLink<Self>] = [
    ComponentKeyPathLink(.year, to: \.date.year),
    ComponentKeyPathLink(.monthOfYear, to: \.date.month),
    ComponentKeyPathLink(.dayOfMonth, to: \.date.day),
    ComponentKeyPathLink(.hourOfDay, to: \.time.hour),
    ComponentKeyPathLink(.minuteOfHour, to: \.time.minute),
    ComponentKeyPathLink(.secondOfMinute, to: \.time.second),
    ComponentKeyPathLink(.nanosecondOfSecond, to: \.time.nanosecond),
    ComputedComponentLink(.dayOfYear) { GregorianCalendarSystem.default.dayOfYear(for: $0) },
    ComputedComponentLink(.dayOfWeek) { GregorianCalendarSystem.default.dayOfWeek(for: $0) },
    ComputedComponentLink(.weekOfYear) { GregorianCalendarSystem.default.weekOfYear(for: $0) },
    ComputedComponentLink(.weekOfMonth) { GregorianCalendarSystem.default.weekOfMonth(for: $0) },
    ComputedComponentLink(.yearForWeekOfYear) { GregorianCalendarSystem.default.yearForWeekOfYear(for: $0) },
    ComputedComponentLink(.dayOfWeekForMonth) { ($0.day - 1) / 7 + 1 },
  ]

  public init(components: some ComponentContainer) {

    if let dateTime = components as? LocalDateTime {
      self = dateTime
      return
    } else if let dateTime = components as? DateTime {
      self.init(date: dateTime.date, time: dateTime.time)
      return
    }

    self.init(
      date: LocalDate(components: components),
      time: LocalTime(components: components),
    )
  }

  public init(availableComponents components: some ComponentContainer) {

    if let dateTime = components as? LocalDateTime {
      self = dateTime
      return
    } else if let dateTime = components as? DateTime {
      self.init(date: dateTime.date, time: dateTime.time)
      return
    }

    self.init(
      date: LocalDate(availableComponents: components),
      time: LocalTime(availableComponents: components),
    )
  }

}

// MARK - Conversion Initializers

extension LocalDateTime {

  /// Initializes a local date/time by converting an instance of the ``DateTime`` protocol.
  ///
  /// - Parameter dateTime: The ``DateTime`` to convert.
  ///
  public init(_ dateTime: some DateTime) {
    self.init(date: dateTime.date, time: dateTime.time)
  }

  /// Inlitializes a local date/time from a date and a duration of time.
  ///
  /// The time duration is converted to a local time with any duration of time over 24 hours
  /// added to the date.
  ///
  /// - Parameters:
  ///   - date: The local date.
  ///   - time: The duration of time to convert to a local time with any overflow added to the date.
  /// - Throws: A ``TempoError`` if the date, after applying any overflow, is invalid.
  ///
  public init(date: LocalDate, adding time: Duration) throws {
    let (dateOverflow, timeOfDay) = time.divided(at: .days)
    let time = LocalTime(durationSinceMidnight: timeOfDay)
    let rolledDate = try GregorianCalendarSystem.default.adding(components: dateOverflow, to: date)
    self.init(date: rolledDate, time: time)
  }

}

extension LocalDateTime {

  /// Parses a date and time string per RFC-3339 (`YYYY-MM-DDTHH:MM:SS[.ssssssss]`) .
  ///
  /// - Parameter string: The date-time string.
  /// - Returns: Parsed date and time instance if valid; otherwise, nil.
  ///
  public static func parse(string: String) -> Self? {

    guard let sepIndex = string.firstIndex(where: { $0 == "T" || $0 == "t" }) else {
      return nil
    }

    let datePart = String(string[..<sepIndex])
    let timePart = String(string[string.index(after: sepIndex)...])

    guard
      let date = LocalDate.parse(string: datePart),
      let (time, rollover) = LocalTime.parseReportingRollver(string: timePart)
    else {
      return nil
    }

    guard rollover else {
      return Self(date: date, time: time)
    }

    guard
      let rolloverDate = try? GregorianCalendarSystem.default.adding(components: [.numberOfDays(1)], to: date)
    else {
      return nil
    }
    return Self(date: rolloverDate, time: time)
  }
}

extension LocalDateTime: Codable {

  enum CodingKeys: String, CodingKey {
    case year
    case month
    case day
    case hour
    case minute
    case second
    case nanosecond
    case date
    case time
  }

  public init(from decoder: any Decoder) throws {
    guard let keyed = try? decoder.container(keyedBy: CodingKeys.self) else {
      guard let values = try? decoder.singleValueContainer().decode([Int].self) else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Invalid local date time, must be array of int or object"
          )
        )
      }
      guard values.count >= 4 && values.count <= 7 else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Invalid local date time, array must contain 4-7 values"
          )
        )
      }
      try self.init(
        year: values[0],
        month: values[1],
        day: values[2],
        hour: values[3],
        minute: values.count > 4 ? values[4] : 0,
        second: values.count > 5 ? values[5] : 0,
        nanosecond: values.count > 6 ? values[6] : 0
      )
      return
    }
    if keyed.contains(.date) {
      let date = try keyed.decode(LocalDate.self, forKey: .date)
      let time = try keyed.decode(LocalTime.self, forKey: .time)
      self.init(date: date, time: time)
    } else {
      try self.init(
        year: keyed.decode(Int.self, forKey: .year),
        month: keyed.decode(Int.self, forKey: .month),
        day: keyed.decode(Int.self, forKey: .day),
        hour: keyed.decode(Int.self, forKey: .hour),
        minute: keyed.decodeIfPresent(Int.self, forKey: .minute) ?? 0,
        second: keyed.decodeIfPresent(Int.self, forKey: .second) ?? 0,
        nanosecond: keyed.decodeIfPresent(Int.self, forKey: .nanosecond) ?? 0
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var keyed = encoder.container(keyedBy: CodingKeys.self)
    try keyed.encode(date, forKey: .date)
    try keyed.encode(time, forKey: .time)
  }

}
