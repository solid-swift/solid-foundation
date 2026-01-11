//
//  Base64UniqueIDEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public enum Base64UniqueIDEncoding<ID: UniqueID>: UniqueIDEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(BaseEncoding.base64.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try BaseEncoding.base64.decode(string, into: &span)
    }
  }

}


public extension UniqueIDEncoding where Self == Base64UniqueIDEncoding<UUID> {

  static var base64: Self { Self.instance }

}
