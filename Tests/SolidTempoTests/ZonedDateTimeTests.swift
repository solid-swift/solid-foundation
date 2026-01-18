//
//  ZonedDateTimeTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/27/25.
//

@testable import SolidTempo
import Foundation
import Testing


@Suite("ZonedDateTime Tests")
struct ZonedDateTimeTests {

  public typealias ZDT = ZonedDateTime
  public typealias LDT = LocalDateTime
  public typealias RSO = ResolutionStrategy.Options

  public typealias ZDTT =
    (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nano: Int, zone: Zone)
  public typealias LDTT =
    (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nano: Int)

  public static let LAZone: Zone = "America/Los_Angeles"
  public static let skoDefault: RSO = [.skipped(.nextValid)]

  @Test(
    "Skipped Time Resolution",
    arguments: [
      (
        "Typical",
        (year: 2024, month: 3, day: 10, hour: 2, minute: 29, second: 17, nano: 123456789, zone: LAZone),
        (year: 2024, month: 3, day: 10, hour: 3, minute: 29, second: 17, nano: 123456789),
        skoDefault
      ),
      (
        "Start of Transition",
        (year: 2024, month: 3, day: 10, hour: 2, minute: 0, second: 0, nano: 0, zone: LAZone),
        (year: 2024, month: 3, day: 10, hour: 3, minute: 0, second: 0, nano: 0),
        skoDefault
      ),
      (
        "End of Transition",
        (year: 2024, month: 3, day: 10, hour: 2, minute: 59, second: 59, nano: 999_999_999, zone: LAZone),
        (year: 2024, month: 3, day: 10, hour: 3, minute: 59, second: 59, nano: 999_999_999),
        skoDefault
      ),
      (
        "Immediately After Transition",
        (year: 2024, month: 3, day: 10, hour: 3, minute: 0, second: 0, nano: 0, zone: LAZone),
        (year: 2024, month: 3, day: 10, hour: 3, minute: 0, second: 0, nano: 0),
        skoDefault
      ),
    ] as [(String, ZDTT, LDTT, ResolutionStrategy.Options)]
  )
  func testInstantResolution(
    testing: String,
    dateTimeTuple: ZDTT,
    expectedLocalTime: LDTT,
    resolutionOptions: RSO
  ) throws {
    let zonedDateTime = try ZDT(dateTimeTuple)
    expectEqual(zonedDateTime, expectedLocalTime)
  }

  func expectEqual(
    _ left: ZDT,
    _ right: LDTT,
  ) {
    #expect(left.date.year == right.year)
    #expect(left.date.month == right.month)
    #expect(left.date.day == right.day)
    #expect(left.time.hour == right.hour)
    #expect(left.time.minute == right.minute)
    #expect(left.time.second == right.second)
    #expect(left.time.nanosecond == right.nano)
  }

  func printDate(_ date: Date, in timeZoneID: String) {
    let dateStyle =
      Date.VerbatimFormatStyle(
        format:
          "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(9)) \(timeZone: .iso8601(.long)) [\(timeZone: .identifier(.long))]",
        timeZone: TimeZone(identifier: timeZoneID).neverNil(),
        calendar: Calendar(
          identifier: .iso8601
        )
      )
    print(date.formatted(dateStyle))
  }

  @Test("ZonedDateTime computed components via subscripting")
  func testComputedComponents() throws {
    // March 15, 2024 14:30:45 in LA is a Friday (day 5 in ISO week, where Monday=1)
    // It's the 75th day of the year (31 Jan + 29 Feb leap + 15 Mar)
    let zonedDateTime = try ZonedDateTime(
      year: 2024,
      month: 3,
      day: 15,
      hour: 14,
      minute: 30,
      second: 45,
      nanosecond: 0,
      zone: Self.LAZone
    )

    #expect(zonedDateTime[.dayOfYear] == 75)
    #expect(zonedDateTime[.dayOfWeek] == 5)  // Friday

    // Week calculations - March 15, 2024 is in week 11 of the year
    #expect(zonedDateTime[.weekOfYear] == 11)
    #expect(zonedDateTime[.weekOfMonth] == 3)  // 3rd week of March
    #expect(zonedDateTime[.yearForWeekOfYear] == 2024)
    #expect(zonedDateTime[.dayOfWeekForMonth] == 3)  // 3rd Friday of the month
  }

  @Test("ZonedDateTime computed components for edge cases")
  func testComputedComponentsEdgeCases() throws {
    // January 1, 2024 00:00:00 in LA (Monday, first day of year)
    let jan1 = try ZonedDateTime(
      year: 2024,
      month: 1,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      nanosecond: 0,
      zone: Self.LAZone
    )
    #expect(jan1[.dayOfYear] == 1)
    #expect(jan1[.dayOfWeek] == 1)  // Monday
    #expect(jan1[.weekOfYear] == 1)
    #expect(jan1[.weekOfMonth] == 1)
    #expect(jan1[.dayOfWeekForMonth] == 1)  // 1st Monday of the month

    // December 31, 2024 23:59:59 in LA (Tuesday, last day of leap year)
    let dec31 = try ZonedDateTime(
      year: 2024,
      month: 12,
      day: 31,
      hour: 23,
      minute: 59,
      second: 59,
      nanosecond: 999_999_999,
      zone: Self.LAZone
    )
    #expect(dec31[.dayOfYear] == 366)  // Leap year
    #expect(dec31[.dayOfWeek] == 2)  // Tuesday
  }
}

extension ZonedDateTime {

  init(_ tuple: ZonedDateTimeTests.ZDTT) throws {
    try self.init(
      year: tuple.year,
      month: tuple.month,
      day: tuple.day,
      hour: tuple.hour,
      minute: tuple.minute,
      second: tuple.second,
      nanosecond: tuple.nano,
      zone: tuple.zone
    )
  }

}
