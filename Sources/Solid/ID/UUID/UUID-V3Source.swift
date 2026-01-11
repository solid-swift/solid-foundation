//
//  UUID-V3Source.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation
import Crypto


public extension UUID {

  /// Source for UUID v3 Hashed Namespace/Name UUID following RFC-9562/4122.
  ///
  struct V3Source: UniqueIDSource, Sendable {

    public static let format = HashedNameFormat(version: .v3) { Insecure.MD5.hash(data: $0) }

    public let namespace: UUID
    public let name: Data

    public init(namespace: UUID, name: Data) {
      self.namespace = namespace
      self.name = name
    }

    public func generate() -> UUID {
      return UUID { out in
        Self.format.pack(namespace: namespace, name: name, out: &out)
      }
    }
  }

  /// UUID v3 (name-based, MD5).
  static func v3(namespace: Namespace, name: String) -> UUID {
    V3Source(namespace: namespace.uuid, name: Data(name.utf8)).generate()
  }

  /// UUID v3 (name-based, MD5).
  static func v3(namespace: Namespace, name: Data) -> UUID {
    V3Source(namespace: namespace.uuid, name: name).generate()
  }

  /// UUID v3 (name-based, MD5).
  static func v3(namespace: UUID, name: String) -> UUID {
    V3Source(namespace: namespace, name: Data(name.utf8)).generate()
  }

  /// UUID v3 (name-based, MD5).
  static func v3(namespace: UUID, name: Data) -> UUID {
    V3Source(namespace: namespace, name: name).generate()
  }
}
