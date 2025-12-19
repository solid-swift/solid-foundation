//
//  UUID-V5Source.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation
import Crypto


public extension UUID {

  /// Source for UUID v5 Hashed Namespace/Name UUID following RFC-9562/4122.
  ///
  struct V5Source: UniqueIDSource, Sendable {

    public static let format = HashedNameFormat(version: .v5) { Insecure.SHA1.hash(data: $0) }

    public let namespace: UUID
    public let name: Data

    public init(namespace: UUID, name: Data) {
      self.namespace = namespace
      self.name = name
    }

    public func generate() -> UUID {
      do {
        return try UUID { out in
          Self.format.pack(namespace: namespace, name: name, out: &out)
        }
      } catch let e {
        fatalError("Failed to initialize UUID: \(e)")
      }
    }
  }

  /// UUID v5 (name-based, SHA-1).
  static func v5(namespace: Namespace, name: String) -> UUID {
    V5Source(namespace: namespace.uuid, name: Data(name.utf8)).generate()
  }

  /// UUID v5 (name-based, SHA-1).
  static func v5(namespace: Namespace, name: Data) -> UUID {
    V5Source(namespace: namespace.uuid, name: name).generate()
  }

  /// UUID v5 (name-based, SHA-1).
  static func v5(namespace: UUID, name: String) -> UUID {
    V5Source(namespace: namespace, name: Data(name.utf8)).generate()
  }

  /// UUID v5 (name-based, SHA-1).
  static func v5(namespace: UUID, name: Data) -> UUID {
    V5Source(namespace: namespace, name: name).generate()
  }
}
