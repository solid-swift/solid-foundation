//
//  UUIDv7Tests.swift
//

import Testing
import SolidTempo
@testable import SolidID


@Suite struct UUIDv7Suite {

  @Test func versionAndVariant() {
    let u = UUID.v7()
    #expect(u.version == .v7)
    #expect(u.variant == .rfc)
  }

  @Test func ordering() {
    var prev = UUID.v7()
    for _ in 0..<500 {
      let next = UUID.v7()
      // v7 is time-ordered; lexicographic string order should be non-decreasing
      #expect(prev.description <= next.description)
      prev = next
    }
  }

  @Test func timeAccessor() throws {
    let uuid = UUID.v7()
    let timestamp = try #require(uuid.timestamp)
    let sinceNow = Duration.between(timestamp, OffsetDateTime.now())
    #expect(sinceNow < .seconds(1))
  }
}
