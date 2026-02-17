//
//  ValueEventDecoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation

/// Decodes a stream of ``ValueEvent`` values into a single ``Value``.
public struct ValueEventDecoder {

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteValue
  }

  /// Reference-type container to avoid ARC churn from enum pop/push cycles.
  /// Using a class allows in-place mutation of the contained array/object
  /// without destroying and recreating the container on every appended value.
  private final class Container {
    enum Kind { case array, object }

    let kind: Kind
    var values: Value.Array
    var object: Value.Object
    let tags: [Value]
    var expectingKey: Bool
    var currentKey: Value?

    private init(kind: Kind, values: Value.Array, object: Value.Object, tags: [Value], expectingKey: Bool) {
      self.kind = kind
      self.values = values
      self.object = object
      self.tags = tags
      self.expectingKey = expectingKey
      self.currentKey = nil
    }

    static func array(capacity: Int?, tags: [Value]) -> Container {
      var values: Value.Array = []
      if let capacity {
        values.reserveCapacity(capacity)
      }
      return Container(kind: .array, values: values, object: [:], tags: tags, expectingKey: false)
    }

    static func object(capacity: Int?, tags: [Value]) -> Container {
      var object = Value.Object()
      if let capacity {
        object.reserveCapacity(capacity)
      }
      return Container(kind: .object, values: [], object: object, tags: tags, expectingKey: true)
    }
  }

  private var stack: [Container] = []
  private var pendingTags: [Value] = []
  private var pendingAnchor: String?
  private var anchors: [String: Value] = [:]
  private var root: Value?

  public init() {}

  public var isComplete: Bool {
    root != nil && stack.isEmpty && pendingTags.isEmpty && pendingAnchor == nil
  }

  public mutating func append(_ event: ValueEvent) throws {
    switch event {
    case .style:
      break

    case .tag(let tag):
      pendingTags.append(tag)

    case .anchor(let name):
      guard pendingAnchor == nil else {
        throw Error.invalidEventSequence("Anchor without value")
      }
      pendingAnchor = name

    case .alias(let name):
      guard pendingAnchor == nil else {
        throw Error.invalidEventSequence("Alias cannot have an anchor")
      }
      guard let value = anchors[name] else {
        throw Error.invalidEventSequence("Unresolved alias")
      }
      try appendAliasValue(value)

    case .scalar(let value):
      try appendValue(value)

    case .beginArray(let count):
      let tags = pendingTags
      pendingTags.removeAll(keepingCapacity: true)
      stack.append(.array(capacity: count, tags: tags))

    case .endArray:
      guard let container = stack.popLast(), container.kind == .array else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      try appendValue(applyTags(.array(container.values), tags: container.tags))

    case .beginObject(let count):
      let tags = pendingTags
      pendingTags.removeAll(keepingCapacity: true)
      stack.append(.object(capacity: count, tags: tags))

    case .endObject:
      guard let container = stack.popLast(), container.kind == .object else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard container.expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      try appendValue(applyTags(.object(container.object), tags: container.tags))

    case .key(let key):
      guard let container = stack.last, container.kind == .object else {
        throw Error.invalidEventSequence("Unexpected key")
      }
      guard container.expectingKey, container.currentKey == nil else {
        throw Error.invalidEventSequence("Unexpected key position")
      }
      let taggedKey = applyTags(key, tags: pendingTags)
      pendingTags.removeAll(keepingCapacity: true)
      if let anchor = pendingAnchor {
        anchors[anchor] = taggedKey
        pendingAnchor = nil
      }
      container.expectingKey = false
      container.currentKey = taggedKey
    }
  }

  public mutating func finish() throws -> Value {
    guard stack.isEmpty, pendingTags.isEmpty, pendingAnchor == nil, let root else {
      throw Error.incompleteValue
    }
    return root
  }

  private func applyTags(_ value: Value, tags: [Value]) -> Value {
    if tags.isEmpty {
      return value
    }
    return .tagged(tags: tags, value: value)
  }

  private mutating func appendValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll(keepingCapacity: true)
    if let anchor = pendingAnchor {
      anchors[anchor] = taggedValue
      pendingAnchor = nil
    }

    guard let container = stack.last else {
      guard root == nil else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      root = taggedValue
      return
    }

    switch container.kind {
    case .array:
      container.values.append(taggedValue)

    case .object:
      guard !container.expectingKey, let key = container.currentKey else {
        throw Error.invalidEventSequence("Missing key for value")
      }
      container.object[key] = taggedValue
      container.expectingKey = true
      container.currentKey = nil
    }
  }

  private mutating func appendAliasValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll(keepingCapacity: true)
    if let anchor = pendingAnchor {
      anchors[anchor] = taggedValue
      pendingAnchor = nil
    }

    guard let container = stack.last else {
      guard root == nil else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      root = taggedValue
      return
    }

    switch container.kind {
    case .array:
      container.values.append(taggedValue)

    case .object:
      if container.expectingKey {
        container.expectingKey = false
        container.currentKey = taggedValue
      } else {
        guard let key = container.currentKey else {
          throw Error.invalidEventSequence("Missing key for value")
        }
        container.object[key] = taggedValue
        container.expectingKey = true
        container.currentKey = nil
      }
    }
  }
}
