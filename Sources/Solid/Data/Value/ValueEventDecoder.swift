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

  private enum Container {
    case array([Value], tags: [Value])
    case object(Value.Object, expectingKey: Bool, currentKey: Value?, tags: [Value])
  }

  private var stack: [Container] = []
  private var pendingTags: [Value] = []
  private var pendingAnchor: String?
  private var anchors: [String: Value] = [:]
  private var root: Value?

  public init() {}

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

    case .beginArray:
      let tags = pendingTags
      pendingTags.removeAll()
      stack.append(.array([], tags: tags))

    case .endArray:
      guard case .array(let values, let tags) = stack.popLast() else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      try appendValue(applyTags(.array(values), tags: tags))

    case .beginObject:
      let tags = pendingTags
      pendingTags.removeAll()
      stack.append(.object(Value.Object(), expectingKey: true, currentKey: nil, tags: tags))

    case .endObject:
      guard case .object(let object, let expectingKey, _, let tags) = stack.popLast() else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      try appendValue(applyTags(.object(object), tags: tags))

    case .key(let key):
      guard case .object(let object, let expectingKey, let currentKey, let tags) = stack.popLast() else {
        throw Error.invalidEventSequence("Unexpected key")
      }
      guard expectingKey, currentKey == nil else {
        throw Error.invalidEventSequence("Unexpected key position")
      }
      let taggedKey = applyTags(key, tags: pendingTags)
      pendingTags.removeAll()
      if let anchor = pendingAnchor {
        anchors[anchor] = taggedKey
        pendingAnchor = nil
      }
      stack.append(.object(object, expectingKey: false, currentKey: taggedKey, tags: tags))
    }
  }

  public mutating func finish() throws -> Value {
    guard stack.isEmpty, pendingTags.isEmpty, pendingAnchor == nil, let root else {
      throw Error.incompleteValue
    }
    return root
  }

  private func applyTags(_ value: Value, tags: [Value]) -> Value {
    var tagged = value
    for tag in tags.reversed() {
      tagged = .tagged(tag: tag, value: tagged)
    }
    return tagged
  }

  private mutating func appendValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll()
    if let anchor = pendingAnchor {
      anchors[anchor] = taggedValue
      pendingAnchor = nil
    }

    guard let container = stack.popLast() else {
      guard root == nil else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      root = taggedValue
      return
    }

    switch container {
    case .array(var values, let tags):
      values.append(taggedValue)
      stack.append(.array(values, tags: tags))

    case .object(var object, let expectingKey, let currentKey, let tags):
      guard !expectingKey, let key = currentKey else {
        throw Error.invalidEventSequence("Missing key for value")
      }
      object[key] = taggedValue
      stack.append(.object(object, expectingKey: true, currentKey: nil, tags: tags))
    }
  }

  private mutating func appendAliasValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll()
    if let anchor = pendingAnchor {
      anchors[anchor] = taggedValue
      pendingAnchor = nil
    }

    guard let container = stack.popLast() else {
      guard root == nil else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      root = taggedValue
      return
    }

    switch container {
    case .array(var values, let tags):
      values.append(taggedValue)
      stack.append(.array(values, tags: tags))

    case .object(var object, let expectingKey, let currentKey, let tags):
      if expectingKey {
        stack.append(.object(object, expectingKey: false, currentKey: taggedValue, tags: tags))
      } else {
        guard let key = currentKey else {
          throw Error.invalidEventSequence("Missing key for value")
        }
        object[key] = taggedValue
        stack.append(.object(object, expectingKey: true, currentKey: nil, tags: tags))
      }
    }
  }
}
