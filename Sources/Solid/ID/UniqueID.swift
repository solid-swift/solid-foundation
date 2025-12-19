//
//  UniqueID.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//


public protocol UniqueID: Equatable, Hashable, Sendable, CustomStringConvertible {

  associatedtype Storage

  static var byteCount: Int { get }

  var storage: Storage { get }

  init(storage: Storage)

  init(initializer: (inout OutputSpan<UInt8>) throws -> Void) throws

  init?<E: UniqueIDStringEncoding>(string: String, encoding: E) where E.ID == Self

  func encode<E: UniqueIDStringEncoding>(using encoding: E) -> String where E.ID == Self

  func withUnsafeBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R

}

extension UniqueID {

  @inlinable public init?<E: UniqueIDStringEncoding>(string: String, encoding: E) where E.ID == Self {
    guard let decoded = try? encoding.decode(string) else {
      return nil
    }
    self = decoded
  }

  @inlinable public func encode<E: UniqueIDStringEncoding>(using encoding: E) -> String where E.ID == Self {
    return encoding.encode(self)
  }

}
