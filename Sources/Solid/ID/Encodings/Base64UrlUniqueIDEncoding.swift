//
//  Base64UrlUniqueIDEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public enum Base64UrlUniqueIDEncoding<ID: UniqueID>: UniqueIDEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(BaseEncoding.base64Url.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try BaseEncoding.base64Url.decode(string, into: &span)
    }
  }

}


public extension UniqueIDEncoding where Self == Base64UrlUniqueIDEncoding<UUID> {

  static var base64Url: Self { Self.instance }

}
