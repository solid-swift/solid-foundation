//
//  LinkedComponentContainer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/30/25.
//


public protocol LinkedComponentContainer: ComponentContainer {
  static var links: [any ComponentLink<Self>] { get }
}

public protocol ComponentLink<Root>: Sendable {
  associatedtype Root: Sendable
  associatedtype Value: Sendable

  var kind: any ComponentKind<Value> { get }
  func value(in root: Root) -> Value
}

public struct ComponentKeyPathLink<Root, Value>: ComponentLink where Root: Sendable, Value: Sendable {

  private nonisolated(unsafe) let keyPath: KeyPath<Root, Value>

  public init(_ kind: some ComponentKind<Value>, to keyPath: KeyPath<Root, Value>) where Value: Sendable {
    self.kind = kind
    self.keyPath = keyPath
  }

  public let kind: any ComponentKind<Value>

  public func value(in root: Root) -> Self.Value {
    root[keyPath: keyPath]
  }
}

public struct ComputedComponentLink<Root, Value>: ComponentLink where Root: Sendable, Value: Sendable {

  private nonisolated(unsafe) let compute: (Root) -> Value

  public init(_ kind: some ComponentKind<Value>, compute: @escaping @Sendable (Root) -> Value) {
    self.kind = kind
    self.compute = compute
  }

  public let kind: any ComponentKind<Value>

  public func value(in root: Root) -> Value {
    compute(root)
  }
}


extension LinkedComponentContainer where Self: ComponentContainer {

  public var availableComponentKinds: Set<AnyComponentKind> {
    return Set(Self.links.map { AnyComponentKind($0.kind) })
  }

  public func valueIfPresent<K>(for kind: K) -> K.Value? where K: ComponentKind {
    guard
      let link = Self.links.first(where: { $0.kind.id == kind.id })
    else {
      return nil
    }
    return link.value(in: self) as? K.Value
  }

}
