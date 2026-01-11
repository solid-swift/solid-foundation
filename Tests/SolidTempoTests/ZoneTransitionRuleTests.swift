//
//  ZoneTransitionRuleTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/13/25.
//

@testable import SolidTempo
import SolidTesting
import Testing
import Foundation

@Suite("ZoneTransitionRule Tests")
struct ZoneTransitionRuleTests {

  static let ruleDetails = ZoneTransitionRuleTestData.loadFromBundle(bundle: .module).flattened

  @Test(
    "offset at instant",
    arguments: ruleDetails.map { ($0.zone, $0.entry.instant, $0.entry.instantOffset) }
  )
  func testOffsetAtInstant(zone: Zone, instant: Instant, expectedOffset: ZoneOffset) throws {
    let rule = try rule(for: zone)
    let offset = rule.offset(at: instant)
    #expect(offset == expectedOffset)
  }

  @Test(
    "offset for local",
    arguments: ruleDetails.map { ($0.zone, $0.entry.local, $0.entry.localOffset) }
  )
  func testOffsetForLocal(zone: Zone, local: LocalDateTime, expectedOffset: ZoneOffset) throws {
    let rule = try rule(for: zone)
    let offset = rule.offset(for: local)
    #expect(offset == expectedOffset)
  }

  @Test(
    "valid offsets for local",
    arguments: ruleDetails.map { ($0.zone, $0.entry.local, $0.entry.localValidOffsets) }
  )
  func testValidOffsetsForLocal(zone: Zone, local: LocalDateTime, expectedOffsets: [ZoneOffset]) throws {
    let rule = try rule(for: zone)
    let validOffsets = Array(rule.validOffsets(for: local))
    #expect(validOffsets == expectedOffsets)
  }

  @Test(
    "applicable transition for local",
    arguments: ruleDetails.map { ($0.zone, $0.entry.local, $0.entry.localApplicableTransition) }
  )
  func testApplicableTransitionForLocal(
    zone: Zone,
    local: LocalDateTime,
    expectedTransition: ZoneTransitionRuleTestData.ZoneDetails.Entry.Transition?
  ) throws {
    let rule = try rule(for: zone)
    let foundTransition = rule.applicableTransition(at: local)
    guard let expectedTransition else {
      #expect(foundTransition == nil)
      return
    }

    let transition = try #require(foundTransition)
    #expect(transition.instant == expectedTransition.instant)
    #expect(transition.before.local == expectedTransition.localBefore)
    #expect(transition.after.local == expectedTransition.localAfter)
    #expect(transition.before.offset == expectedTransition.offsetBefore)
    #expect(transition.after.offset == expectedTransition.offsetAfter)
    #expect(transition.kind == (expectedTransition.isGap ? .gap : .overlap))
    #expect(transition.duration == expectedTransition.duration)
  }

  @Test(
    "next transition at instant",
    arguments: ruleDetails.map { ($0.zone, $0.entry.instant, $0.entry.instantNextTransition) }
  )
  func testNextTransitionAtInstant(
    zone: Zone,
    instant: Instant,
    expectedTransition: ZoneTransitionRuleTestData.ZoneDetails.Entry.Transition?
  ) throws {
    let rule = try rule(for: zone)
    let finalOffset = try #require((zone.rules as? RegionZoneRules)?.final.offset)
    let foundTransition = rule.nextTransition(after: instant, at: finalOffset)
    guard let expectedTransition else {
      #expect(foundTransition == nil)
      return
    }

    let transition = try #require(foundTransition)
    #expect(transition.instant == expectedTransition.instant)
    #expect(transition.before.local == expectedTransition.localBefore)
    #expect(transition.after.local == expectedTransition.localAfter)
    #expect(transition.before.offset == expectedTransition.offsetBefore)
    #expect(transition.after.offset == expectedTransition.offsetAfter)
    #expect(transition.kind == (expectedTransition.isGap ? .gap : .overlap))
    #expect(transition.duration == expectedTransition.duration)
  }

  @Test(
    "prior transition at instant",
    arguments: ruleDetails.map { ($0.zone, $0.entry.instant, $0.entry.instantPriorTransition) }
  )
  func testPriorTransitionAtInstant(
    zone: Zone,
    instant: Instant,
    expectedTransition: ZoneTransitionRuleTestData.ZoneDetails.Entry.Transition?
  ) throws {
    let rule = try rule(for: zone)
    let finalOffset = try #require((zone.rules as? RegionZoneRules)?.final.offset)
    let foundTransition = rule.priorTransition(before: instant, at: finalOffset)
    guard let expectedTransition else {
      #expect(foundTransition == nil)
      return
    }

    let transition = try #require(foundTransition)
    #expect(transition.instant == expectedTransition.instant)
    #expect(transition.before.local == expectedTransition.localBefore)
    #expect(transition.after.local == expectedTransition.localAfter)
    #expect(transition.before.offset == expectedTransition.offsetBefore)
    #expect(transition.after.offset == expectedTransition.offsetAfter)
    #expect(transition.kind == (expectedTransition.isGap ? .gap : .overlap))
    #expect(transition.duration == expectedTransition.duration)
  }

  @Test(
    "designation at instant",
    arguments: ruleDetails.map { ($0.zone, $0.entry.instant, $0.entry.instantOffset, $0.entry.designation) }
  )
  func testDesignationAtInstant(
    zone: Zone,
    instant: Instant,
    instantOffset: ZoneOffset,
    expectedDesignation: String
  ) throws {
    let rule = try rule(for: zone)
    let designation = rule.designation(at: instant)
    let expected =
      if designation.wholeMatch(of: /^(\+|\-)\d+$/) != nil {
        instantOffset.designation
      } else {
        expectedDesignation
      }
    #expect(designation == expected)
  }

  @Test(
    "dst duration",
    arguments: ruleDetails.map { ($0.zone, $0.entry.instant, $0.entry.instantDstDuration[.totalSeconds]) }
  )
  func testDaylightSavingTime(zone: Zone, instant: Instant, expectedDstDurationSeconds: Int) throws {
    let rule = try rule(for: zone)
    let finalOffset = try #require((zone.rules as? RegionZoneRules)?.final.offset)
    let dstDuration = rule.daylightSavingTime(for: instant, at: finalOffset)
    let expectedDstDuration: Duration = .seconds(expectedDstDurationSeconds)
    #expect(dstDuration == expectedDstDuration)
  }

  func rule(for zone: Zone) throws -> ZoneTransitionRule {
    return try #require((zone.rules as? RegionZoneRules)?.tailRule)
  }

  /// Creates an instant/offset using Foundation.
  ///
  /// - Note: The nanoseconds are truncated to microseconds ot match Foundation's precision.
  ///
  func foundationDetails(date: LocalDateTime, zone: Zone) throws -> (instant: Int, offset: Int) {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = try #require(TimeZone(identifier: zone.identifier))
    let date = try #require(
      cal.date(
        from: .init(
          year: date.year,
          month: date.month,
          day: date.day,
          hour: date.hour,
          minute: date.minute,
          second: date.second,
          nanosecond: (date.nanosecond / 1000) * 1000,
        )
      )
    )
    let off = cal.timeZone.secondsFromGMT(for: date)
    return (Int(date.timeIntervalSince1970.rounded(.towardZero)), off)
  }

}

extension LocalDateTime {

  public init(
    _ c: (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nanosecond: Int)
  ) throws {
    try self.init(
      year: c.year,
      month: c.month,
      day: c.day,
      hour: c.hour,
      minute: c.minute,
      second: c.second,
      nanosecond: c.nanosecond
    )
  }

}

struct ZoneTransitionRuleTestData: TestData, Decodable {

  struct ZoneDetails: Codable, Sendable {

    struct Entry: Codable, Sendable {

      struct Transition: Codable, Sendable {
        let instant: Instant
        let localBefore: LocalDateTime
        let localAfter: LocalDateTime
        let offsetBefore: ZoneOffset
        let offsetAfter: ZoneOffset
        let isGap: Bool
        let duration: Duration
      }

      let local: LocalDateTime
      let instant: Instant
      let localOffset: ZoneOffset
      let instantOffset: ZoneOffset
      let localValidOffsets: [ZoneOffset]
      let localApplicableTransition: Transition?
      let instantNextTransition: Transition?
      let instantPriorTransition: Transition?
      let instantDstDuration: Duration
      let designation: String
    }

    let zone: Zone
    let entries: [Entry]
  }

  let zones: [ZoneDetails]

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.zones = try container.decode([ZoneDetails].self)
  }

  var flattened: [(zone: Zone, entry: ZoneDetails.Entry)] {
    return zones.flatMap { zone in zone.entries.map { (zone.zone, $0) } }
  }
}
