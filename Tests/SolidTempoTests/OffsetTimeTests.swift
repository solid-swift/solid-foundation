//
//  OffsetTimeTests.swift
//  SolidFoundation
//
//  Created by Devin AI on 1/18/26.
//

@testable import SolidTempo
import Testing

@Suite("OffsetTime Tests")
struct OffsetTimeTests {

  @Test("OffsetTime initialization")
  func testInitialization() throws {
    let offset = try ZoneOffset(hours: -5, minutes: 0, seconds: 0)
    let time = try OffsetTime(hour: 14, minute: 30, second: 45, nanosecond: 123456789, offset: offset)

    #expect(time.hour == 14)
    #expect(time.minute == 30)
    #expect(time.second == 45)
    #expect(time.nanosecond == 123456789)
    #expect(time.offset == offset)
  }

  @Test("OffsetTime component subscripting")
  func testComponentSubscripting() throws {
    let offset = try ZoneOffset(hours: -5, minutes: 0, seconds: 0)
    let time = try OffsetTime(hour: 14, minute: 30, second: 45, nanosecond: 123456789, offset: offset)

    #expect(time[.hourOfDay] == 14)
    #expect(time[.minuteOfHour] == 30)
    #expect(time[.secondOfMinute] == 45)
    #expect(time[.nanosecondOfSecond] == 123456789)
    #expect(time[.zoneOffset] == -5 * 3600)    // -5 hours in seconds
  }

  @Test("OffsetTime component subscripting with positive offset")
  func testComponentSubscriptingPositiveOffset() throws {
    let offset = try ZoneOffset(hours: 5, minutes: 30, seconds: 0)
    let time = try OffsetTime(hour: 9, minute: 15, second: 0, nanosecond: 0, offset: offset)

    #expect(time[.hourOfDay] == 9)
    #expect(time[.minuteOfHour] == 15)
    #expect(time[.secondOfMinute] == 0)
    #expect(time[.nanosecondOfSecond] == 0)
    #expect(time[.zoneOffset] == 5 * 3600 + 30 * 60)    // +5:30 in seconds
  }

  @Test("OffsetTime component subscripting with UTC offset")
  func testComponentSubscriptingUTC() throws {
    let time = try OffsetTime(hour: 12, minute: 0, second: 0, nanosecond: 0, offset: .zero)

    #expect(time[.hourOfDay] == 12)
    #expect(time[.minuteOfHour] == 0)
    #expect(time[.secondOfMinute] == 0)
    #expect(time[.nanosecondOfSecond] == 0)
    #expect(time[.zoneOffset] == 0)
  }

  @Test("OffsetTime description")
  func testDescription() throws {
    let offset = try ZoneOffset(hours: -5, minutes: 0, seconds: 0)
    let time = try OffsetTime(hour: 14, minute: 30, second: 45, nanosecond: 0, offset: offset)

    #expect(time.description.contains("14:30:45"))
    #expect(time.description.contains("-05:00"))
  }

  @Test("OffsetTime parsing")
  func testParsing() throws {
    let time = OffsetTime.parse(string: "14:30:45-05:00")
    #expect(time != nil)
    #expect(time?.hour == 14)
    #expect(time?.minute == 30)
    #expect(time?.second == 45)
    #expect(time?.offset.totalSeconds == -5 * 3600)
  }

  @Test("OffsetTime parsing with UTC")
  func testParsingUTC() throws {
    let time = OffsetTime.parse(string: "12:00:00Z")
    #expect(time != nil)
    #expect(time?.hour == 12)
    #expect(time?.minute == 0)
    #expect(time?.second == 0)
    #expect(time?.offset.totalSeconds == 0)
  }
}
