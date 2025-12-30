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
    id.withUnsafeBytes(encoding.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try encoding.decode(string, into: &span)
    }
  }

}


private let encoding = BaseEncoding.base32.unpadded()


public extension UniqueIDEncoding where Self == Base32UniqueIDEncoding<UUID> {

  static var base32: Self { Self.instance }

}
