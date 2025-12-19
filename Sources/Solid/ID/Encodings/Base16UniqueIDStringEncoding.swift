//
//  Base16UniqueIDStringEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import SolidCore


public enum Base16UniqueIDStringEncoding<ID: UniqueID>: UniqueIDStringEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(Base16StringEncoding.default.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try Base16StringEncoding.default.decode(string, into: &span)
    }
  }

}


public extension UniqueIDStringEncoding where Self == Base16UniqueIDStringEncoding<UUID> {

  static var base16: Self { Self.instance }

  static var hex: Self { Self.instance }

}
