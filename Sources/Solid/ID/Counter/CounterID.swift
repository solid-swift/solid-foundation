//
//  CounterID.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//

import SolidCore
import Synchronization


public struct CounterID<Count: FixedWidthInteger & AtomicRepresentable & Sendable>: UniqueID {

  @inlinable public static var byteCount: Int { MemoryLayout<Count>.size }

  public private(set) var storage: Count

  public init(storage: Count) {
    self.storage = storage
  }

  public init(initializer: (inout OutputSpan<UInt8>) throws -> Void) throws {
    var value: Count = 0
    try withUnsafeMutableBytes(of: &value) { ptr in
      var out = OutputSpan<UInt8>(buffer: ptr.assumingMemoryBound(to: UInt8.self), initializedCount: 0)
      try initializer(&out)
    }
    self.storage = value
  }

  @inlinable public init?<E: UniqueIDStringEncoding>(string: String, encoding: E) where CounterID<Count> == E.ID {
    do {
      self = try encoding.decode(string)
    } catch {
      return nil
    }
  }

  @inlinable public func encode<E: UniqueIDStringEncoding>(using encoding: E) -> String where CounterID<Count> == E.ID {
    encoding.encode(self)
  }

  @inlinable public func withUnsafeBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    var storage = self.storage
    return try Swift.withUnsafeBytes(of: &storage) { ptr in
      try body(ptr.assumingMemoryBound(to: UInt8.self))
    }
  }

  @inlinable public var description: String { String(storage) }

}
