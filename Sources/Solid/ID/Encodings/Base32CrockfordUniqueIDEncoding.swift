//
//  Base32CrockfordUniqueIDStringEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public enum Base32CrockfordUniqueIDStringEncoding<ID: UniqueID>: UniqueIDStringEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(Base32CrockfordStringEncoding.default.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try Base32CrockfordStringEncoding.default.decode(string, into: &span)
    }
  }

}


public extension UniqueIDStringEncoding where Self == Base32CrockfordUniqueIDStringEncoding<UUID> {

  static var base32Crockford: Self { Self.instance }

}
