//
//  InstantSourceTests.swift
//  SolidFoundation
//

@testable import SolidTempo
import Testing


@Suite("Instant Source Tests")
struct InstantSourceTests {

  @Test("Uptime source is nondecreasing")
  func uptimeIsNondecreasing() {
    let source = UptimeInstantSource.instance
    let first = source.instant
    let second = source.instant

    #expect(second >= first)
  }

  @Test("Manual source advances deterministically")
  func manualSourceAdvances() throws {
    let source = ManualInstantSource(instant: Instant(durationSinceEpoch: .seconds(10)))

    try source.advance(by: .milliseconds(250))

    #expect(source.instant == Instant(durationSinceEpoch: .milliseconds(10_250)))
  }

  @Test("Manual source rejects negative advancement")
  func manualSourceRejectsNegativeAdvancement() {
    let source = ManualInstantSource()

    #expect(throws: ManualInstantSource.AdvanceError.negativeDuration) {
      try source.advance(by: .nanoseconds(-1))
    }
    #expect(source.instant == .epoch)
  }

  @Test("Constant source satisfies the monotonic source contract")
  func constantSourceIsMonotonic() {
    let source: any MonotonicInstantSource = ConstantInstantSource(
      instant: Instant(durationSinceEpoch: .seconds(42))
    )

    #expect(source.instant == source.instant)
  }
}

