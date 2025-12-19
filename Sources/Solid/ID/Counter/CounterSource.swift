//
//  CounterSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import Synchronization


public protocol CounterSource<Count>: Sendable {

  associatedtype Count: FixedWidthInteger & AtomicRepresentable & Sendable

  func next() -> Count

}
