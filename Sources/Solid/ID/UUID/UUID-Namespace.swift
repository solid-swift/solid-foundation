//
//  UUID-Namespace.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public extension UUID {

  /// Namespace for v3 and v5 hashed UUID versions.
  ///
  struct Namespace: Sendable {

    public var uuid: UUID

    public init(_ string: String) {
      self.uuid = UUID(string: string, using: .canonical).neverNil()
    }

    /// Namespace for DNS style hashed UUIDs.
    public static let dns = Self("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

    /// Namespace for URL style hashed UUIDs.
    public static let url = Self("6ba7b811-9dad-11d1-80b4-00c04fd430c8")

    /// Namespace for OID style hashed UUIDs.
    public static let oid = Self("6ba7b812-9dad-11d1-80b4-00c04fd430c8")

    /// Namespace for X.500 style hashed UUIDs.
    public static let x500 = Self("6ba7b814-9dad-11d1-80b4-00c04fd430c8")
  }

}
