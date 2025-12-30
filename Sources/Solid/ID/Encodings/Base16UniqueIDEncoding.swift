//
//  Base16UniqueIDEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import SolidCore


public enum Base16UniqueIDEncoding<ID: UniqueID>: UniqueIDEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(BaseEncoding.base16.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try BaseEncoding.base16.decode(string, into: &span)
    }
  }

}


public extension UniqueIDEncoding where Self == Base16UniqueIDEncoding<UUID> {

  static var base16: Self { Self.instance }

  static var hex: Self { Self.instance }

}
