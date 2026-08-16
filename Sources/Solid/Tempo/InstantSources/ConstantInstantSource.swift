//
//  ConstantInstantSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/24/25.
//

public struct ConstantInstantSource: MonotonicInstantSource {

  public var instant: Instant

  public init(instant: Instant) {
    self.instant = instant
  }

}
