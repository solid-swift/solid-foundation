//
//  Base32UniqueIDEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public enum Base32UniqueIDEncoding<ID: UniqueID>: UniqueIDEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(BaseEncoding.base32Lower.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try BaseEncoding.base32Lower.decode(string, into: &span)
    }
  }

}


public extension UniqueIDEncoding where Self == Base32UniqueIDEncoding<UUID> {

  static var base32: Self { Self.instance }

}
