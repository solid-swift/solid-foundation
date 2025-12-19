//
//  UUID-UnixTimestampSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import SolidTempo


public extension UUID {

  /// Generates a 48-bit Unix millisecond timestamp and a 12-bit sub-millisecond fraction
  /// per RFC 9562 UUIDv7 (Section 5.7 and 6.2 Method 3).
  ///
  /// The 12-bit value returned as `clockSequence` encodes the fractional part of the
  /// current millisecond using available clock precision:
  ///   fraction_bits = floor((sub_ms / 1ms) * 4096)
  ///
  /// This replaces the prior counter-based behavior and avoids stalling within the
  /// same millisecond while remaining time-ordered.
  ///
  class UnixTimestampSource: TimestampSource {

    private let instantSource: any InstantSource

    public init(instantSource: any InstantSource = .system) {
      self.instantSource = instantSource
    }

    public func current(randomGenerator: inout RandomNumberGenerator) -> (timestamp: UInt64, clockSequence: UInt16) {
      let now = instantSource.instant.durationSinceEpoch

      // Milliseconds since Unix epoch (fits in 48 bits per RFC until year ~10889)
      let ms = UInt64(now[.totalMilliseconds])

      // Sub-millisecond remainder and fractional bits per RFC 9562 §6.2 Method 3
      // Use microseconds to avoid large Int128 arithmetic: 0..999 µs within the millisecond
      let subMsMicros = UInt64(now.remainder(in: .milliseconds)[.totalMicroseconds])    // 0..999
      let fractionBits = UInt16((subMsMicros * 4096) / 1000)    // 0..4095 (12 bits)

      assert((ms >> 48) == 0)
      assert((fractionBits >> 12) == 0)

      return (ms, fractionBits)
    }

    public static func offsetDateTime(from: (timestamp: UInt64, clockSequence: UInt16)) -> OffsetDateTime {
      let ms = Int128(from.timestamp)
      let instant = Instant(durationSinceEpoch: Duration.milliseconds(ms))
      return GregorianCalendarSystem.default.localDateTime(instant: instant, at: .utc).at(offset: .utc)
    }
  }
}
