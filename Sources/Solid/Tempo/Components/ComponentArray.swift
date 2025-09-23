//
//  ComponentSet.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/30/25.
//

import SolidCore
import Collections

public struct ComponentSet {

  public typealias Elements = [AnyComponentKind: any Equatable & Sendable]

  fileprivate var elements: Elements

  public init(_ components: some Sequence<Component>) {
    let uniqe = components.map { (AnyComponentKind($0.kind), $0.value) }
    self.elements = Dictionary(uniqe, uniquingKeysWith: { $1 })
  }

}

extension ComponentSet: Equatable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.count == rhs.count else {
      return false
    }
    for (lIdx, rIdx) in zip(lhs.indices, rhs.indices) where lhs[lIdx] != rhs[rIdx] {
      return false
    }
    return true
  }

}

extension ComponentSet: Hashable {

  public func hash(into hasher: inout Hasher) {
    for idx in indices {
      hasher.combine(self[idx])
    }
  }

}

extension ComponentSet: CustomStringConvertible {

  public var description: String {
    elements
      .sorted { $0.key.id < $1.key.id }
      .map { key, value in "- (\(key.id)) \(value)" }
      .joined(separator: "\n")
  }

}

extension ComponentSet: CustomReflectable {

  public var customMirror: Mirror {
    Mirror(
      self,
      children: elements.map { ($0.key.name, $0.value) },
      displayStyle: .struct,
      ancestorRepresentation: .suppressed
    )
  }

}

extension ComponentSet: MutableComponentContainer {

  public var availableComponentKinds: Set<AnyComponentKind> {
    Set(elements.map { AnyComponentKind($0.key) })
  }

  public func valueIfPresent<K>(for kind: K) -> K.Value? where K: ComponentKind {
    guard let value = elements.first(where: { $0.key.id == kind.id }) else {
      return nil
    }
    return value.value as? K.Value
  }

  public mutating func setValue<K>(_ value: K.Value, for kind: K) where K: ComponentKind {
    elements.updateValue(knownSafeCast(value, to: Elements.Value.self), forKey: kind.any)
  }

  public mutating func removeValue<K>(for kind: K) -> K.Value? where K: ComponentKind {
    guard let removed = elements.removeValue(forKey: kind.any) else {
      return nil
    }
    return knownSafeCast(removed, to: K.Value.self)
  }

  public subscript<K>(_ kind: K) -> K.Value? where K: ComponentKind {
    get { valueIfPresent(for: kind) }
    set {
      if let newValue {
        setValue(newValue, for: kind)
      } else {
        _ = removeValue(for: kind)
      }
    }
  }

}

extension ComponentSet: ComponentBuildable {

  public static var requiredComponentKinds: Set<AnyComponentKind> { [] }

  public init(components: some ComponentContainer) {
    let componentValues = components.values(for: Self.requiredComponentKinds.map(\.wrapped))
    self.init(componentValues)
  }

}

extension ComponentSet: Collection {

  public typealias Element = Component

  public init() {
    self.elements = [:]
  }

  public var startIndex: Elements.Index { elements.startIndex }
  public var endIndex: Elements.Index { elements.endIndex }
  public func index(after i: Elements.Index) -> Elements.Index { elements.index(after: i) }

  public subscript(index: Elements.Index) -> Component {
    get {
      let entry = elements[index]
      return Component(kind: entry.key, value: knownSafeCast(entry.value, to: type(of: entry.key).Value.self))
    }
    mutating set {
      elements.updateValue(newValue.value, forKey: newValue.kind.any)
    }
  }

}

extension ComponentSet: ExpressibleByArrayLiteral {

  public init(arrayLiteral elements: Component...) {
    self.init(elements)
  }

}

extension Array: ComponentContainer where Element == Component {

  public var availableComponentKinds: Set<AnyComponentKind> { Set(map { AnyComponentKind($0.kind) }) }

  public func valueIfPresent<K>(for kind: K) -> K.Value? where K: ComponentKind {
    guard let component = first(where: { $0.kind.id == kind.id }) else {
      return nil
    }
    return component.value as? K.Value
  }

}
