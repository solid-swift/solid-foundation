//
//  OffsetDateTime.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//

import SolidCore


/// A date & time at a specific fixed zone offset.
///
public struct OffsetDateTime: DateTime {

  public var dateTime: LocalDateTime
  public var offset: ZoneOffset

  /// The date part.
  public var date: LocalDate { dateTime.date }
  /// The time part.
  public var time: LocalTime { dateTime.time }

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

  /// Initializes an instance of ``OffsetDateTime`` with the specified date and time components
  /// at the specified zone offset.
  ///
  /// - Parameters:
  ///   - dateTime: The date and time components to use.
  ///   - offset: The time zone offset to use.
  ///
  public init(dateTime: LocalDateTime, offset: ZoneOffset) {
    self.dateTime = dateTime
    self.offset = offset
  }

  /// Initializes an instance of ``OffsetDateTime`` with the specified date/time at the
  /// offset of specified time zone.
  ///
  /// - Parameters:
  ///   - dateTime: The date and time components to use.
  ///   - zone: The time zone used to determine the `offset`.
  ///   - resolving: The resolution strategy to use. Defaults to `.default`.
  ///   - calendarSystem: The calendar system to use. Defaults to `.default`.
  /// - Throws: A ``TempoError`` if the local-time is unresolvable.
  ///
  public init(
    dateTime: LocalDateTime,
    zone: Zone,
    resolving: ResolutionStrategy.Options = [],
    in calendarSystem: CalendarSystem = .default
  ) throws {
    let instant = try calendarSystem.instant(from: dateTime, resolution: resolving.strategy)
    self.dateTime = dateTime
    self.offset = zone.offset(at: instant)
  }

  /// Initializes an instance of ``OffsetDateTime`` with the specified date and time components
  /// at the specified zone offset.
  ///
  /// - Parameters:
  ///   - year: The year component of the date.
  ///   - month: The month component of the date.
  ///   - day: The day component of the date.
  ///   - hour: The hour component of the time.
  ///   - minute: The minute component of the time.
  ///   - second: The second component of the time.
  ///   - nanosecond: The nanosecond component of the time.
  ///   - offset: The time zone offset to use.
  /// - Throws: A ``TempoError`` if the conversion local-time is an unresolvable local-time.
  ///
  public init(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    nanosecond: Int,
    offset: ZoneOffset
  ) throws {
    self.init(
      dateTime: try LocalDateTime(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        nanosecond: nanosecond
      ),
      offset: offset
    )
  }

  /// Creates a new instance of ``OffsetDateTime`` with one or more of the date, time or zone parts
  /// modified.
  ///
  /// - Note: Modifying the `offset` part using this function will anchor to the same local-time. If
  ///    you want to preserve the same instant, use the `withOffset(_:anchor:)` method instead,
  ///    passing `.sameInstant` as the anchor.
  ///
  /// - Parameters:
  ///   - date: The new date to set. If `nil`, the current date is used.
  ///   - time: The new time to set. If `nil`, the current time is used.
  ///   - offset: The new time zone offset to set, anchoring to the local-time. If `nil`, the current time zone is used.
  /// - Returns: A new instance of ``OffsetDateTime`` with the specified parts modified.
  ///
  public func with(
    date: LocalDate? = nil,
    time: LocalTime? = nil,
    offset: ZoneOffset? = nil,
  ) -> Self {
    let dateTime = dateTime.with(date: date ?? self.date, time: time ?? self.time)
    return Self(
      dateTime: dateTime,
      offset: offset ?? self.offset
    )
  }

  /// Creates a new instance of ``OffsetDateTime`` with one or components of the date and time
  /// or the zone part modified.
  ///
  /// - Note: Modifying the `offset` part using this function will anchor to the same local-time. If
  ///    you want to preserve the same instant, use the ``at(offset:anchor:in:)`` method instead,
  ///    passing ``AdjustmentAnchor/sameInstant`` as the anchor.
  ///
  /// - Parameters:
  ///   - year: The new year to set. If `nil`, the current year is used.
  ///   - month: The new month to set. If `nil`, the current month is used.
  ///   - day: The new day to set. If `nil`, the current day is used.
  ///   - hour: The new hour to set. If `nil`, the current hour is used.
  ///   - minute: The new minute to set. If `nil`, the current minute is used.
  ///   - second: The new second to set. If `nil`, the current second is used.
  ///   - nanosecond: The new nanosecond to set. If `nil`, the current nanosecond is used.
  ///   - offset: The new time zone offset to set, anchoring to the local-time. If `nil`, the current time zone is used.
  /// - Returns: A new instance of ``OffsetDateTime`` with the specified parts modified.
  /// - Throws: A ``TempoError`` if the conversion fails due to an unresolvable local-time.
  ///
  public func with(
    year: Int? = nil,
    month: Int? = nil,
    day: Int? = nil,
    hour: Int? = nil,
    minute: Int? = nil,
    second: Int? = nil,
    nanosecond: Int? = nil,
    offset: ZoneOffset? = nil,
  ) throws -> Self {
    let date = date
    let time = time
    return try self.with(
      date: date.with(
        year: year ?? date.year,
        month: month ?? date.month,
        day: day ?? date.day
      ),
      time: time.with(
        hour: hour ?? time.hour,
        minute: minute ?? time.minute,
        second: second ?? time.second,
        nanosecond: nanosecond ?? time.nanosecond
      ),
      offset: offset ?? self.offset,
    )
  }

  /// Creates a new instance of ``OffsetDateTime`` at the specified time zone offset.
  ///
  /// - Parameters:
  ///   - offset: The time zone offset to use.
  ///   - anchor: The ``AdjustmentAnchor`` that determines whether the
  ///   instant or local-time the is preserved. Defaults to ``AdjustmentAnchor/sameInstant``.
  ///   - calendarSystem: The calendar system to use. Defaults to `.default`.
  /// - Returns: A new instance of ``ZonedDateTime`` in the specified time zone.
  ///
  public func at(
    offset: ZoneOffset,
    anchor: AdjustmentAnchor = .sameInstant,
    in calendarSystem: GregorianCalendarSystem = .default
  ) -> Self {
    switch anchor {
    case .sameLocalTime:
      return with(offset: offset)
    case .sameInstant:
      let instant = calendarSystem.instant(from: self, at: self.offset)
      let dateTime = calendarSystem.localDateTime(instant: instant, at: offset)
      return Self(dateTime: dateTime, offset: offset)
    }
  }

  /// Creates a new instance of ``OffsetDateTime`` sourced from a provided ``Clock``.
  ///
  /// - Parameters:
  ///   - clock: The clock to use. Defaults to ``Clock/system``.
  ///   - calendarSystem: The calendar system to use. Defaults to `.default`.
  /// - Returns: A new instance of ``OffsetDateTime`` sourced from the provided `clock`.
  ///
  public static func now(clock: some Clock = .system, in calendarSystem: GregorianCalendarSystem = .default) -> Self {
    return of(instant: clock.instant, zone: clock.zone)
  }

}

extension OffsetDateTime: Sendable {}
extension OffsetDateTime: Hashable {}
extension OffsetDateTime: Equatable {}

extension OffsetDateTime: Comparable {

  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.dateTime < rhs.dateTime
  }

}

extension OffsetDateTime: CustomStringConvertible {

  public var description: String {
    "\(dateTime)\(offset)"
  }
}

extension OffsetDateTime: LinkedComponentContainer, ComponentBuildable {

  public static let links: [any ComponentLink<Self>] = [
    ComponentKeyPathLink(.year, to: \.dateTime.date.year),
    ComponentKeyPathLink(.monthOfYear, to: \.dateTime.date.month),
    ComponentKeyPathLink(.dayOfMonth, to: \.dateTime.date.day),
    ComponentKeyPathLink(.hourOfDay, to: \.dateTime.time.hour),
    ComponentKeyPathLink(.minuteOfHour, to: \.dateTime.time.minute),
    ComponentKeyPathLink(.secondOfMinute, to: \.dateTime.time.second),
    ComponentKeyPathLink(.nanosecondOfSecond, to: \.dateTime.time.nanosecond),
    ComponentKeyPathLink(.zoneOffset, to: \.offset.totalSeconds),
    ComputedComponentLink(.dayOfYear) { GregorianCalendarSystem.default.dayOfYear(for: $0) },
    ComputedComponentLink(.dayOfWeek) { GregorianCalendarSystem.default.dayOfWeek(for: $0) },
    ComputedComponentLink(.weekOfYear) { GregorianCalendarSystem.default.weekOfYear(for: $0) },
    ComputedComponentLink(.weekOfMonth) { GregorianCalendarSystem.default.weekOfMonth(for: $0) },
    ComputedComponentLink(.yearForWeekOfYear) { GregorianCalendarSystem.default.yearForWeekOfYear(for: $0) },
    ComputedComponentLink(.dayOfWeekForMonth) { ($0.day - 1) / 7 + 1 },
  ]

  public init(components: some ComponentContainer) {

    if let dateTime = components as? OffsetDateTime {
      self = dateTime
      return
    }

    self.init(
      dateTime: LocalDateTime(components: components),
      offset: ZoneOffset(availableComponents: components)
    )
  }

}

extension OffsetDateTime {

  public static func of(
    instant: Instant,
    zone: Zone,
    in calendarSystem: CalendarSystem = .default
  ) -> OffsetDateTime {
    let offset = zone.offset(at: instant)
    let localDateTime = calendarSystem.localDateTime(instant: instant, at: offset)
    return OffsetDateTime(dateTime: localDateTime, offset: offset)
  }

}

extension OffsetDateTime {

  /// Parses a date and offset time string per RFC-3339 (`YYYY-MM-DDTHH:MM:SS[.ssssssss](Z|[+-]HH:MM)`) .
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
      let (time, rollover) = OffsetTime.parseReportingRollover(string: timePart)
    else {
      return nil
    }

    guard rollover else {
      return Self(dateTime: LocalDateTime(date: date, time: time.time), offset: time.offset)
    }

    guard
      let rolloverDate = try? GregorianCalendarSystem.default.adding(components: [.numberOfDays(1)], to: date)
    else {
      return nil
    }
    return Self(dateTime: LocalDateTime(date: rolloverDate, time: time.time), offset: time.offset)
  }
}

extension OffsetDateTime {

  public static func - (lhs: Self, rhs: Self) -> Duration {
    return lhs.durationSinceEpoch(at: .utc) - rhs.durationSinceEpoch(at: .utc)
  }

}
