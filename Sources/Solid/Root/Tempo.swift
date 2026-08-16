//
//  Tempo.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import SolidTempo

public enum Tempo {

  public typealias Instant = SolidTempo.Instant
  public typealias Duration = SolidTempo.Duration
  public typealias Stopwatch = SolidTempo.Stopwatch

  public typealias Clock = SolidTempo.Clock
  public typealias SystemClock = SolidTempo.SystemClock

  public typealias InstantSource = SolidTempo.InstantSource
  public typealias MonotonicInstantSource = SolidTempo.MonotonicInstantSource
  public typealias SystemInstantSource = SolidTempo.SystemInstantSource
  public typealias UptimeInstantSource = SolidTempo.UptimeInstantSource
  public typealias ManualInstantSource = SolidTempo.ManualInstantSource
  public typealias ConstantInstantSource = SolidTempo.ConstantInstantSource
  public typealias SnapshotInstantSource = SolidTempo.SnapshotInstantSource

  public typealias LocalDate = SolidTempo.LocalDate
  public typealias LocalTime = SolidTempo.LocalTime
  public typealias DateTime = SolidTempo.DateTime
  public typealias LocalDateTime = SolidTempo.LocalDateTime
  public typealias ZonedDateTime = SolidTempo.ZonedDateTime
  public typealias OffsetDateTime = SolidTempo.OffsetDateTime

  public typealias Zone = SolidTempo.Zone
  public typealias ZoneOffset = SolidTempo.ZoneOffset
  public typealias ZoneRules = SolidTempo.ZoneRules
  public typealias RegionZoneRules = SolidTempo.RegionZoneRules
  public typealias FixedOffsetZoneRules = SolidTempo.FixedOffsetZoneRules

}
