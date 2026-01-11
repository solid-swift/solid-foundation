//
//  Schema-Annotation.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/12/25.
//

import SolidData
import SolidURI

extension Schema {

  public struct Annotation {
    public var keyword: Keyword
    public var value: Value
    public var instanceLocation: Pointer
    public var keywordLocation: Pointer
    public var absoluteKeywordLocation: URI?

    public init(
      keyword: Keyword,
      value: Value,
      instanceLocation: Pointer,
      keywordLocation: Pointer,
      absoluteKeywordLocation: URI?
    ) {
      self.keyword = keyword
      self.value = value
      self.instanceLocation = instanceLocation
      self.keywordLocation = keywordLocation
      self.absoluteKeywordLocation = absoluteKeywordLocation
    }
  }

}

extension Schema.Annotation: Sendable {}

extension Schema.Annotation: Hashable {

  public func hash(into hasher: inout Hasher) {
    hasher.combine(keyword)
    hasher.combine(value)
    hasher.combine(instanceLocation)
    hasher.combine(keywordLocation)
    hasher.combine(absoluteKeywordLocation)
  }

}

extension Schema.Annotation: Equatable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.keyword == rhs.keyword && lhs.value == rhs.value && lhs.instanceLocation == rhs.instanceLocation
      && lhs.keywordLocation == rhs.keywordLocation && lhs.absoluteKeywordLocation == rhs.absoluteKeywordLocation
  }

}

extension Schema.Annotation: CustomStringConvertible {

  public var description: String {
    """
    Keyword: \(keyword)
    Value: \(value)
    Instance Location: '\(instanceLocation == .root ? "" : instanceLocation.description)'
    Absolute Keyword Location: \(keywordLocation)\(
      absoluteKeywordLocation.map { "\nAbsolute Keyword Location: \($0)" } ?? ""
    )
    """
  }

}

extension Schema.Annotation {

  public func array<T>(of: KeyPath<Value, Optional<T>>) -> [T] {
    guard case .array(let array) = self.value else {
      fatalError("Annotation must be an array")
    }
    return array.map {
      guard let item = $0[keyPath: of] else {
        fatalError("Annotation array items must be \(T.self)s")
      }
      return item
    }
  }

  public func bool() -> Bool {
    guard case .bool(let bool) = self.value else {
      fatalError("Annotation must be a boolean")
    }
    return bool
  }

  public func int() -> Int {
    guard let int = value.int else {
      fatalError("Annotation must be an integer")
    }
    return int
  }

}

extension Optional where Wrapped == Schema.Annotation {

  public func array<T>(of: KeyPath<Value, Optional<T>>) -> [T] {
    guard let ann = self else {
      return []
    }
    guard case .array(let array) = ann.value else {
      fatalError("Value must be an array")
    }
    return array.map {
      guard let item = $0[keyPath: of] else {
        fatalError("Array item must be a \(T.self)")
      }
      return item
    }
  }

  public func bool() -> Bool {
    guard let ann = self else {
      return false
    }
    guard case .bool(let bool) = ann.value else {
      fatalError("Annotation must be a boolean")
    }
    return bool
  }

  public func bool(default def: Bool) -> Bool {
    guard let ann = self else {
      return def
    }
    guard case .bool(let bool) = ann.value else {
      fatalError("Annotation must be a boolean")
    }
    return bool
  }

  public func int() -> Int? {
    guard let ann = self else {
      return nil
    }
    guard let int = ann.value.int else {
      fatalError("Annotation must be an integer")
    }
    return int
  }

  public func int(default def: Int) -> Int {
    guard let ann = self else {
      return def
    }
    guard let int = ann.value.int else {
      fatalError("Annotation must be an integer")
    }
    return int
  }

  public func `true`() -> Bool {
    bool(default: false) == true
  }

  public func maxIndex() -> Int {
    int(default: -1)
  }

  public func indices() -> Set<Int> {
    Set(array(of: \.int))
  }

  public func propertyKeys() -> Set<String> {
    Set(array(of: \.string))
  }

}

extension Array where Element == Schema.Annotation {

  public func anyTrue() -> Bool {
    self.contains { $0.bool() }
  }

  public func maxIndex() -> Int {
    map { $0.int() }.max() ?? -1
  }

  public func indices() -> Set<Int> {
    Set(flatMap { $0.array(of: \.int) })
  }

  public func propertyKeys() -> Set<String> {
    Set(flatMap { $0.array(of: \.string) })
  }

}
