//
//  UptimeInstantSource+Linux.swift
//  SolidFoundation
//

#if os(Linux)
  #if canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #endif

  extension UptimeInstantSource {

    public var instant: Instant {
      var time = timespec()
      let result = clock_gettime(CLOCK_MONOTONIC, &time)
      precondition(result == 0, "clock_gettime failed")

      let nanoseconds = Int128(time.tv_sec) * 1_000_000_000 + Int128(time.tv_nsec)
      return Instant(durationSinceEpoch: .nanoseconds(nanoseconds))
    }
  }

#endif
