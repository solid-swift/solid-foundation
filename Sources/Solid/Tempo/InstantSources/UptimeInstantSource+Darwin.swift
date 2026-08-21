//
//  UptimeInstantSource+Darwin.swift
//  SolidFoundation
//

#if canImport(Darwin)

  import Darwin

  extension UptimeInstantSource {

    public var instant: Instant {
      let nanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
      return Instant(durationSinceEpoch: Duration(nanoseconds: Int128(nanoseconds)))
    }
  }

#endif
