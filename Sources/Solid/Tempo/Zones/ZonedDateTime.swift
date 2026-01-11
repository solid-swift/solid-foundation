//
//  ZonedDateTime.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//


/// A date & time in a specific time zone.
///
public struct ZonedDateTime: DateTime {

  /// The date and time parts.
  public var dateTime: LocalDateTime
  /// The time zone.
  public var zone: Zone
  /// The specific zone offset for this date and time in ``zone``.
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

  internal init(dateTime: LocalDateTime, zone: Zone, offset: ZoneOffset) {
    self.dateTime = dateTime
    self.zone = zone
    self.offset = offset
  }

  /// Initializes an instance of ``ZonedDateTime`` with the specified date and time
  /// in the specified time zone.
  ///
  /// - Parameters:
  ///   - dateTime: The date and time to use.
  ///   - zone: The time zone to use.
  ///   - resolving: The resolution strategy to use when converting the date and time.
  ///   - calendarSystem: The calendar system to use.
  /// - Throws: A ``TempoError`` if the conversion fails due to an unresolvable local-time.
  ///
  public init(
    dateTime: LocalDateTime,
    zone: Zone,
    resolving: ResolutionStrategy.Options = [],
    in calendarSystem: CalendarSystem = .default
  ) throws {
    if let fixedOffset = zone.fixedOffset {
      self.init(dateTime: dateTime, zone: zone, offset: fixedOffset)
    } else {
      let dateTimeZone = dateTime.append(.zoneId(zone.identifier))
      self = try calendarSystem.resolve(components: dateTimeZone, resolution: resolving.strategy)
    }
  }

  /// Initializes an instance of ``ZonedDateTime`` with the specified date and time
  /// in the specified fixed offset time zone.
  ///
  /// - Parameters:
  ///   - dateTime: The date and time to use.
  ///   - zoneOffset: The time zone to use.
  ///
  public init(dateTime: LocalDateTime, zoneOffset: ZoneOffset) {
    self.init(dateTime: dateTime, zone: .fixed(offset: zoneOffset), offset: zoneOffset)
  }

  /// Initializes an instance of ``ZonedDateTime`` with the specified date and time components
  /// in the specified time zone.
  ///
  /// - Parameters:
  ///   - year: The year component of the date.
  ///   - month: The month component of the date.
  ///   - day: The day component of the date.
  ///   - hour: The hour component of the time.
  ///   - minute: The minute component of the time.
  ///   - second: The second component of the time.
  ///   - nanosecond: The nanosecond component of the time.
  ///   - zone: The time zone to use.
  ///   - calendarSystem: The calendar system to use.
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
    zone: Zone,
    in calendarSystem: CalendarSystem = .default
  ) throws {
    try self.init(
      dateTime: LocalDateTime(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        nanosecond: nanosecond
      ),
      zone: zone,
      in: calendarSystem
    )
  }

  /// Creates a new instance of ``ZonedDateTime`` with one or more of the date, time or zone parts
  /// modified.
  ///
  /// - Note: Modifying the `zone` part using this function will anchor to the same local-time. If
  ///    you want to preserve the same instant, use the ``at(zone:anchor:resolving:in:)``
  ///    method instead, passing ``AdjustmentAnchor/sameInstant`` as the anchor.
  ///
  /// - Parameters:
  ///   - date: The new date to set. If `nil`, the current date is used.
  ///   - time: The new time to set. If `nil`, the current time is used.
  ///   - zone: The new time zone to set, anchoring to the local-time. If `nil`, the current time zone offset is used.
  ///   - resolving: The resolution strategy to use when converting the date and time.
  ///   - calendarSystem: The calendar system to use.
  /// - Returns: A new instance of ``ZonedDateTime`` with the specified parts modified.
  /// - Throws: A ``TempoError`` if the conversion fails due to an unresolvable local-time.
  ///
  public func with(
    date: LocalDate? = nil,
    time: LocalTime? = nil,
    zone: Zone? = nil,
    resolving: ResolutionStrategy.Options = [],
    in calendarSystem: CalendarSystem = .default
  ) throws -> Self {
    let dateTime = dateTime.with(date: date ?? self.date, time: time ?? self.time)
    return try Self(
      dateTime: dateTime,
      zone: zone ?? self.zone,
      resolving: resolving,
      in: calendarSystem
    )
  }

  /// Creates a new instance of ``ZonedDateTime`` with one or components of the date and time
  /// or the zone part modified.
  ///
  /// - Note: Modifying the `zone` part using this function will anchor to the same local-time. If
  ///    you want to preserve the same instant, use the ``at(zone:anchor:resolving:in:)``
  ///    method instead, passing ``AdjustmentAnchor/sameInstant`` as the anchor.
  ///
  /// - Parameters:
  ///   - year: The new year to set. If `nil`, the current year is used.
  ///   - month: The new month to set. If `nil`, the current month is used.
  ///   - day: The new day to set. If `nil`, the current day is used.
  ///   - hour: The new hour to set. If `nil`, the current hour is used.
  ///   - minute: The new minute to set. If `nil`, the current minute is used.
  ///   - second: The new second to set. If `nil`, the current second is used.
  ///   - nanosecond: The new nanosecond to set. If `nil`, the current nanosecond is used.
  ///   - zone: The new time zone to set, anchoring to the local-time. If `nil`, the current time zone is used.
  ///   - resolving: The resolution strategy to use when converting the date and time
  ///   - calendarSystem: The calendar system to use.
  /// - Returns: A new instance of ``ZonedDateTime`` with the specified components & parts modified.
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
    zone: Zone? = nil,
    resolving: ResolutionStrategy.Options = [],
    in calendarSystem: CalendarSystem = .default
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
      zone: zone ?? self.zone,
      resolving: resolving,
      in: calendarSystem
    )
  }

  /// Creates a new instance of ``ZonedDateTime`` in the specified time zone.
  ///
  /// - Parameters:
  ///   - zone: The time zone to use.
  ///   - anchor: The ``AdjustmentAnchor`` that determines whether the
  ///   instant or local-time the is preserved. Defaults to ``AdjustmentAnchor/sameInstant``.
  ///   - resolving: The resolution strategy to use when converting the date and time.
  ///   - calendarSystem: The calendar system to use.
  /// - Returns: A new instance of ``ZonedDateTime`` in the specified time zone.
  /// - Throws: A ``TempoError`` if the conversion fails due to an unresolvable local-time.
  ///
  public func at(
    zone: Zone,
    anchor: AdjustmentAnchor = .sameInstant,
    resolving: ResolutionStrategy.Options = [],
    in calendarSystem: CalendarSystem = .default
  ) throws -> Self {
    switch anchor {
    case .sameLocalTime:
      return try with(zone: zone, resolving: resolving)
    case .sameInstant:
      let instant = try calendarSystem.instant(from: self, resolution: resolving.strategy)
      return try Self.of(instant: instant, zone: zone, in: calendarSystem)
    }
  }

  /// Creates a new instance of ``ZonedDateTime`` sourced from a provided ``Clock``.
  ///
  /// - Parameters:
  ///   - clock: The clock to use. Defaults to ``Clock/system``.
  ///   - calendarSystem: The calendar system to use.
  /// - Returns: A new instance of ``ZonedDateTime`` sourced from the provided `clock`.
  /// - Throws: A ``TempoError`` if the conversion fails due to an unresolvable local-time.
  ///
  public static func now(clock: some Clock = .system, in calendarSystem: CalendarSystem = .default) throws -> Self {
    return try of(instant: clock.instant, zone: clock.zone)
  }
}

extension ZonedDateTime: Sendable {}
extension ZonedDateTime: Hashable {}
extension ZonedDateTime: Equatable {}

extension ZonedDateTime: CustomStringConvertible {

  public var description: String {
    let dateTimeField = "\(dateTime)"
    let offsetField =
      offset == .zero
      ? "Z"
      : "\(offset)"
    let zoneField =
      if !zone.isFixedOffset {
        "[\(zone.identifier)]"
      } else {
        ""
      }
    return "\(dateTimeField) \(offsetField) \(zoneField)"
  }
}

extension ZonedDateTime: LinkedComponentContainer, ComponentBuildable {

  public static let links: [any ComponentLink<Self>] = [
    ComponentKeyPathLink(.year, to: \.dateTime.date.year),
    ComponentKeyPathLink(.monthOfYear, to: \.dateTime.date.month),
    ComponentKeyPathLink(.dayOfMonth, to: \.dateTime.date.day),
    ComponentKeyPathLink(.hourOfDay, to: \.dateTime.time.hour),
    ComponentKeyPathLink(.minuteOfHour, to: \.dateTime.time.minute),
    ComponentKeyPathLink(.secondOfMinute, to: \.dateTime.time.second),
    ComponentKeyPathLink(.nanosecondOfSecond, to: \.dateTime.time.nanosecond),
    ComponentKeyPathLink(.zoneOffset, to: \.offset.totalSeconds),
    ComponentKeyPathLink(.zoneId, to: \.zone.identifier),
    ComputedComponentLink(.dayOfYear) { GregorianCalendarSystem.default.dayOfYear(for: $0) },
    ComputedComponentLink(.dayOfWeek) { GregorianCalendarSystem.default.dayOfWeek(for: $0) },
    ComputedComponentLink(.weekOfYear) { GregorianCalendarSystem.default.weekOfYear(for: $0) },
    ComputedComponentLink(.weekOfMonth) { GregorianCalendarSystem.default.weekOfMonth(for: $0) },
    ComputedComponentLink(.yearForWeekOfYear) { GregorianCalendarSystem.default.yearForWeekOfYear(for: $0) },
    ComputedComponentLink(.dayOfWeekForMonth) { ($0.day - 1) / 7 + 1 },
  ]

  public init(components: some ComponentContainer) {
    self.init(
      dateTime: LocalDateTime(components: components),
      zone: Zone(availableComponents: [.zoneId(components.value(for: .zoneId))]),
      offset: ZoneOffset(availableComponents: [.zoneOffset(components.value(for: .zoneOffset))]),
    )
  }

}

extension ZonedDateTime {

  public static func of(
    instant: Instant,
    zone: Zone,
    in calendarSystem: CalendarSystem = .default
  ) throws -> ZonedDateTime {
    return try calendarSystem.components(from: instant, in: zone)
  }

}

extension ZonedDateTime {

  // MARK: Mathemtical Operations

  public mutating func add(_ duration: Duration) throws {
    // TODO: do something
  }

  public func adding(_ duration: Duration) throws -> Self {
    var result = self
    try result.add(duration)
    return result
  }

}

extension ZonedDateTime {

  /// Parses a date and time string  in the format `YYYY-MM-DDTHH:MM:SS[.sssssssss]'['ZoneID']'`.
  ///
  /// This is similar to extended ISO-8601 formats used in Java and RFC-3339, with the addition
  /// of the `[ZoneID]` suffix (e.g., `2024-03-10T02:30:00[America/Los_Angeles]`).
  ///
  /// - Parameters:
  ///   - string: The date-time string.
  ///   - resolving: The resolution strategy to use when converting the date and time.
  ///   - calendarSystem: The calendar system to use.
  /// - Returns: Parsed `ZonedDateTime` if valid; otherwise `nil`.
  ///
  public static func parse(
    string: String,
    resolving: ResolutionStrategy.Options = [],
    in calendarSystem: CalendarSystem = .default
  ) -> Self? {

    // Look for the zone identifier suffix in square brackets
    guard
      let zoneStart = string.lastIndex(of: "["),
      let zoneEnd = string.lastIndex(of: "]"),
      zoneEnd > zoneStart
    else {
      return nil
    }

    let zoneStr = String(string[string.index(after: zoneStart)..<zoneEnd])
    let dateTimeStr = String(string[string.startIndex..<zoneStart])

    guard
      let zone = try? Zone(identifier: zoneStr),
      let dateTime = LocalDateTime.parse(string: dateTimeStr)
    else {
      return nil
    }

    return try? Self(dateTime: dateTime, zone: zone, resolving: resolving)
  }
}

extension ZonedDateTime {

  public static func - (lhs: Self, rhs: Self) -> Duration {
    return lhs.durationSinceEpoch(at: .utc) - rhs.durationSinceEpoch(at: .utc)
  }

}
