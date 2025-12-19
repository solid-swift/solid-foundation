//
//  UUID-Timestamps.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import SolidTempo


public extension UUID {

  var timestamp: OffsetDateTime? {

    switch version {
    case .v1:
      var timestamp: UInt64 = 0
      var clockSequence: UInt16 = 0
      V1Format.unpack(in: storage.span, timestamp: &timestamp, clockSequence: &clockSequence)
      return GregorianTimestampSource.offsetDateTime(from: (timestamp, clockSequence))

    case .v6:
      var timestamp: UInt64 = 0
      var clockSequence: UInt16 = 0
      V6Format.unpack(in: storage.span, timestamp: &timestamp, clockSequence: &clockSequence)
      return GregorianTimestampSource.offsetDateTime(from: (timestamp, clockSequence))

    case .v7:
      var timestamp: UInt64 = 0
      var clockSequence: UInt16 = 0
      V7Format.unpack(in: storage.span, timestamp: &timestamp, clockSequence: &clockSequence)
      return UnixTimestampSource.offsetDateTime(from: (timestamp, clockSequence))

    default:
      return nil
    }
  }
}
