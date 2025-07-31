//
//  Synchronization.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/10/25.
//

import Synchronization

@propertyWrapper
public struct AtomicReference<T: AnyObject>: ~Copyable {

  public let storage: Atomic<Unmanaged<T>>

  public init(value: T) {
    self.storage = Atomic(Unmanaged.passRetained(value))
  }

  deinit {
    storage.load(ordering: .acquiring).release()
  }

  public var wrappedValue: T {
    get {
      storage.load(ordering: .acquiring).takeUnretainedValue()
    }
    set {
      let new = Unmanaged.passRetained(newValue)

      let previous = storage.exchange(new, ordering: .acquiringAndReleasing)

      previous.release()
    }
  }

}

@propertyWrapper
public struct AtomicOptionalReference<T: AnyObject>: ~Copyable {

  public let storage: Atomic<Unmanaged<T>?>

  public init(value: T?) {
    self.storage = Atomic(value.map(Unmanaged.passRetained))
  }

  deinit {
    storage.load(ordering: .acquiring)?.release()
  }

  public var wrappedValue: T? {
    get {
      storage.load(ordering: .acquiring)?.takeUnretainedValue()
    }
    set {
      let new = newValue.map(Unmanaged.passRetained)

      let previous = storage.exchange(new, ordering: .acquiringAndReleasing)

      previous?.release()
    }
  }

  public func nilify() -> T? {
    storage.exchange(nil, ordering: .acquiringAndReleasing)?.takeRetainedValue()
  }

}

@propertyWrapper
public struct AtomicCounter: ~Copyable {

  private let storage: Atomic<Int>

  public init(value: Int = 0) {
    self.storage = Atomic(value)
  }

  public var wrappedValue: Int { storage.load(ordering: .relaxed) }

  public var projectedValue: Int {
    get { storage.load(ordering: .relaxed) }
  }

  public mutating func add(_ count: Int) {
    storage.add(count, ordering: .acquiringAndReleasing)
  }

  public mutating func subtract(_ count: Int) {
    storage.add(count, ordering: .acquiringAndReleasing)
  }
}

@propertyWrapper
public struct AtomicFlag: ~Copyable {

  private let storage: Atomic<Bool>

  public init() {
    self.storage = Atomic(false)
  }

  public var wrappedValue: Bool {
    get { storage.load(ordering: .sequentiallyConsistent) }
  }

  @discardableResult
  public func signal() -> Bool {
    storage.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).original
  }

}
