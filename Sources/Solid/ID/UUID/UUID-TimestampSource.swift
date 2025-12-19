//
//  UUID-TimestampSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//

import SolidTempo


public extension UUID {

  protocol TimestampSource {

    func current(randomGenerator: inout any RandomNumberGenerator) -> (timestamp: UInt64, clockSequence: UInt16)

    static func offsetDateTime(from: (timestamp: UInt64, clockSequence: UInt16)) -> OffsetDateTime

  }

}
