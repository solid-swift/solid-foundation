//
//  LogContextKey.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//


public struct LogContextKey: Equatable, Hashable, Sendable {

  public var scope: LogScope
  public var key: String

  public init(scope: LogScope, key: String) {
    self.scope = scope
    self.key = key
  }

  public static func == (lhs: LogContextKey, rhs: LogContextKey) -> Bool {
    return lhs.scope.name == rhs.scope.name && lhs.key == rhs.key
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(scope.name)
    hasher.combine(key)
  }

}
