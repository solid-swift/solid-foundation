//
//  RandomID.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//


public struct RandomID<Value: FixedWidthInteger & UnsignedInteger & Sendable>: UniqueID {

  @inlinable public static var byteCount: Int { MemoryLayout<Value>.size }

  public private(set) var storage: Value

  public init(randomGenerator: inout some RandomNumberGenerator) {
    self.init(storage: Value.random(in: 0 ... .max, using: &randomGenerator))
  }

  public init(storage: Value) {
    self.storage = storage
  }

  public init(initializer: (inout OutputSpan<UInt8>) throws -> Void) throws {
    var value: Value = 0
    try withUnsafeMutableBytes(of: &value) { ptr in
      var out = OutputSpan<UInt8>(buffer: ptr.assumingMemoryBound(to: UInt8.self), initializedCount: 0)
      try initializer(&out)
    }
    self.storage = value
  }

  @inlinable public init?<E: UniqueIDEncoding>(string: String, encoding: E) where RandomID<Value> == E.ID {
    do {
      self = try encoding.decode(string)
    } catch {
      return nil
    }
  }

  @inlinable public func encode<E: UniqueIDEncoding>(using encoding: E) -> String where RandomID<Value> == E.ID {
    encoding.encode(self)
  }

  @inlinable public func withUnsafeBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    var storage = self.storage
    return try Swift.withUnsafeBytes(of: &storage) { ptr in
      try body(ptr.assumingMemoryBound(to: UInt8.self))
    }
  }

  @inlinable public var description: String { Base64UniqueIDEncoding.instance.encode(self) }

}
