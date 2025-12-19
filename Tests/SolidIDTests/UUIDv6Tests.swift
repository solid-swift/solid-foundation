//
//  UUIDv6Tests.swift
//

import Testing
import SolidTempo
@testable import SolidID


@Suite struct UUIDv6Suite {

  @Test func versionAndVariant() {
    let u = UUID.v6()
    #expect(u.version == .v6)
    #expect(u.variant == .rfc)
  }

  @Test func ordering() {
    var prev = UUID.v6()
    for _ in 0..<500 {
      let next = UUID.v6()
      // v6 is time-ordered; lexicographic string order should be non-decreasing
      #expect(prev.description <= next.description)
      prev = next
    }
  }

  @Test func timeAccessor() throws {
    let uuid = UUID.v6()
    let timestamp = try #require(uuid.timestamp)
    let sinceNow = Duration.between(timestamp, OffsetDateTime.now())
    #expect(sinceNow < .seconds(1))
  }
}
