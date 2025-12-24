//
//  UUIDv6Tests.swift
//

import Testing
import SolidTempo
@testable import SolidID


@Suite struct `UUIDv6 Tests` {

  @Test func `version & variant`() {
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

  @Test func `time accessor`() throws {
    let uuid = UUID.v6()
    let timestamp = try #require(uuid.timestamp)
    let sinceNow = Duration.between(timestamp, OffsetDateTime.now())
    #expect(sinceNow < .seconds(1))
  }

  @Test func `rfc test vector`() throws {
    let instant = Instant(durationSinceEpoch: .nanoseconds(1645557742000000000))
    let source =
      UUID.V1Source(
        instantSource: ConstantInstantSource(instant: instant),
        nodeIDSource: UUID.ConstantNodeIDSource(nodeID: [0x9F, 0x6B, 0xDE, 0xCE, 0xD8, 0x46]),
      )
    var uuid = source.generate().description
    uuid.replaceSubrange(
      uuid.index(uuid.startIndex, offsetBy: 19)..<uuid.index(uuid.startIndex, offsetBy: 23),
      with: "b3c8"
    )
    #expect(uuid == "c232ab00-9414-11ec-b3c8-9f6bdeced846")
  }
}
