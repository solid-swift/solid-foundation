//
//  SchemaAttributes.swift
//  SolidFoundation
//
//  Created by Warp on 12/24/25.
//

/// Marker attributes consumed by the SchemaCodable macro.
public struct SchemaFormat: Sendable {
  public let value: String
  public init(_ value: String) { self.value = value }
}

public struct SchemaEncoding: Sendable {
  public let value: String
  public init(_ value: String) { self.value = value }
}

public struct SchemaName: Sendable {
  public let value: String
  public init(_ value: String) { self.value = value }
}

public struct SchemaRequired: Sendable {
  public init() {}
}

public struct SchemaNullable: Sendable {
  public init() {}
}
