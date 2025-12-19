//
//  AtomicCounterIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import Synchronization


public final class AtomicCounterSource<
  Count: FixedWidthInteger & AtomicRepresentable & Sendable
>: CounterSource, Sendable {

  let raw: Atomic<Count>
  let incrementer: @Sendable (borrowing Atomic<Count>) -> Count

  public required init(
    raw: consuming Atomic<Count>,
    incrementer: @escaping @Sendable (borrowing Atomic<Count>) -> Count
  ) {
    self.raw = raw
    self.incrementer = incrementer
  }

  public convenience init(initialValue: Count = 0) where Count == UInt32 {
    self.init(raw: Atomic(initialValue)) { $0.add(1, ordering: .acquiring).newValue }
  }

  public convenience init(initialValue: Count = 0) where Count == UInt64 {
    self.init(raw: Atomic(initialValue)) { $0.add(1, ordering: .acquiring).newValue }
  }

  public convenience init(initialValue: Count = 0) where Count == UInt128 {
    self.init(raw: Atomic(initialValue)) { $0.add(1, ordering: .acquiring).newValue }
  }

  public func next() -> Count { incrementer(raw) }

}
