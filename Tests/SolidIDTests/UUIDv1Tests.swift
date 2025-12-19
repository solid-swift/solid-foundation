//
//  UUIDv1Tests.swift
//

import Testing
import SolidTempo
import SolidID


@Suite struct UUIDv1Suite {

  @Test func versionAndVariant() {
    let u = UUID.v1()
    #expect(u.version == .v1)
    #expect(u.variant == .rfc)
  }

  @Test func uniquenessSample() {
    var set = Set<String>()
    for _ in 0..<2000 {
      let u = UUID.v1()
      let s = u.description
      #expect(!set.contains(s))
      set.insert(s)
    }
  }

  @Test func timeAccessor() throws {
    let uuid = UUID.v1()
    let timestamp = try #require(uuid.timestamp)
    let sinceNow = Duration.between(timestamp, OffsetDateTime.now())
    #expect(sinceNow < .seconds(1))
  }

}
