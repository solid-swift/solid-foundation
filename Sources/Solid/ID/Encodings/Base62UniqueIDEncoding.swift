//
//  Base62UniqueIDEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import SolidCore


public enum Base62UniqueIDEncoding<ID: UniqueID>: UniqueIDEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(BaseEncoding.base62.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try BaseEncoding.base62.decode(string, into: &span)
    }
  }

}


public extension UniqueIDEncoding where Self == Base62UniqueIDEncoding<UUID> {

  static var base62: Self { Self.instance }

}
