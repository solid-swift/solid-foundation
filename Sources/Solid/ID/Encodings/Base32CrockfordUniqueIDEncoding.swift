//
//  Base32CrockfordUniqueIDEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public enum Base32CrockfordUniqueIDEncoding<ID: UniqueID>: UniqueIDEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(BaseEncoding.base32CrockfordLower.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try BaseEncoding.base32CrockfordLower.decode(string, into: &span)
    }
  }

}


public extension UniqueIDEncoding where Self == Base32CrockfordUniqueIDEncoding<UUID> {

  static var base32Crockford: Self { Self.instance }

}
