//
//  UUID-GregorianTimestampSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import SolidTempo


public extension UUID {

  /// Generates a 48bit timestamp of 100ns intervals using the Gregorian epoch.
  ///
  class GregorianTimestampSource: TimestampSource {

    private static let unixEpochOffset = Duration.seconds(-12219292800)

    private var lastTime: UInt64
    private var lastTimestamp: UInt64
    private var clockSequence: UInt16
    private let instantSource: InstantSource

    public init(instantSource: InstantSource = .system) {
      self.lastTime = 0
      self.lastTimestamp = 0
      self.clockSequence = 0
      self.instantSource = instantSource
    }

    /// Generate a current timestamp in 100ns intervals from the Gregorian calendar epoch.
    ///
    /// If the clock moved backward, or stayed the same, since the last generation the timestamp
    /// is corrected by incrementing the clock sequence and producing an increasing timestamp.
    ///
    public func current(randomGenerator: inout RandomNumberGenerator) -> (timestamp: UInt64, clockSequence: UInt16) {

      if clockSequence == 0 {
        clockSequence = Self.clockSequenceSeed(randomGenerator: &randomGenerator)
      }

      let time = currentTime()

      if time > lastTime {
        // Clock moved forward.
        lastTime = time
        if time > lastTimestamp {
          lastTimestamp = time
        } else {
          // Clock is forward relative to lastTime, but still behind emitted time.
          // Keep monotonicity.
          lastTimestamp &+= 1
        }
      } else if time == lastTime {
        // Same clock tick: simulate higher resolution by incrementing emitted timestamp.
        lastTimestamp &+= 1
      } else {
        // Clock moved backward: bump clock sequence and force monotonic timestamp.
        clockSequence = (clockSequence &+ 1) & 0x3FFF
        lastTime = time
        lastTimestamp &+= 1
      }

      assert((lastTimestamp >> 60) == 0)
      assert((clockSequence >> 14) == 0)

      return (lastTimestamp, clockSequence)
    }

    /// Generate the current time (as 100ns intervals) from the Gregorian calendar epoch.
    ///
    private func currentTime() -> UInt64 {
      let instant = instantSource.instant - Self.unixEpochOffset
      return UInt64(instant.durationSinceEpoch.nanoseconds / 100)
    }

    private static func clockSequenceSeed(randomGenerator: inout any RandomNumberGenerator) -> UInt16 {
      UInt16.random(in: 0..<(1 << 14), using: &randomGenerator)
    }

    /// Converts a timestamp (in 100ns intervals from Gregorian calendar epoch) into an ``OffsetDateTime``.
    ///
    public static func offsetDateTime(from: (timestamp: UInt64, clockSequence: UInt16)) -> OffsetDateTime {

      let ns = Int128(from.timestamp) * 100

      let instant = Instant(durationSinceEpoch: Self.unixEpochOffset + Duration(nanoseconds: ns))
      return GregorianCalendarSystem.default.localDateTime(instant: instant, at: .utc).at(offset: .utc)
    }
  }
}
