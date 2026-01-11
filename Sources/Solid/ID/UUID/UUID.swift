//
//  UUID.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public struct UUID: UniqueID {

  public static let byteCount = 16

  public typealias Storage = InlineArray<16, UInt8>

  public private(set) var storage: Storage

  public init(storage: Storage) {
    self.storage = storage
  }

  public init<E>(initializer: (inout OutputSpan<UInt8>) throws(E) -> Void) throws(E) {
    self.storage = try Storage(initializingWith: initializer)
  }

  @inlinable public init?<E: UniqueIDEncoding>(string: String, using encoding: E) where E.ID == UUID {
    do {
      self = try encoding.decode(string)
    } catch {
      return nil
    }
  }

  public var version: Version {
    guard let version = Version(rawValue: storage[6] >> 4) else {
      return .reserved
    }
    return version
  }

  public var variant: Variant {
    switch storage[8] >> 4 {
    case 1...7:
      return .ncs
    case 0x8...0xb:
      return .rfc
    case 0xc...0xd:
      return .ms
    default:
      return .future
    }
  }

  @inlinable public func encode<E: UniqueIDEncoding>(using encoding: E) -> String where E.ID == UUID {
    encoding.encode(self)
  }

  @inlinable public func withUnsafeBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    try storage.span.withUnsafeBufferPointer(body)
  }

  @inlinable public var description: String {
    CanonicalUUIDEncoding.instance.encode(self)
  }

  @inlinable public func hash(into hasher: inout Hasher) {
    for idx in 0..<storage.count {
      storage[idx].hash(into: &hasher)
    }
  }

  @inlinable public static func == (lhs: UUID, rhs: UUID) -> Bool {
    if lhs.storage.count != rhs.storage.count { return false }
    for idx in 0..<lhs.storage.count where lhs.storage[idx] != rhs.storage[idx] {
      return false
    }
    return true
  }
}
