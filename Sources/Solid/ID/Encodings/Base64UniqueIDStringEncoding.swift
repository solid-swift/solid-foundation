//
//  Base64UniqueIDStringEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation
import SolidCore


public enum Base64UniqueIDStringEncoding<ID: UniqueID>: UniqueIDStringEncoding {
  case instance

  public func encode(_ id: ID) -> String {
    id.withUnsafeBytes(Base64StringEncoding.default.encode)
  }

  public func decode(_ string: String) throws -> ID {
    try ID { span in
      try Base64StringEncoding.default.decode(string, into: &span)
    }
  }

}


public extension UniqueIDStringEncoding where Self == Base64UniqueIDStringEncoding<UUID> {

  static var base64: Self { Self.instance }

}
