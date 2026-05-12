//
//  ParseEventDecoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation

/// Decodes a stream of ``ParseEvent`` values into a single ``Value``.
///
/// Materializes ``ScalarRef`` values on demand using the provided ``ScalarResolver``.
/// Tracks key/value alternation for objects internally — after ``ParseEvent/beginObject(count:)``,
/// the first scalar is a key, the next is its value, etc.
public struct ParseEventDecoder {

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteValue
  }

  /// Reference-type container to avoid ARC churn from enum pop/push cycles.
  private final class Container {
    enum Kind { case array, object }

    let kind: Kind
    var values: Value.Array
    var object: Value.Object
    let tags: [Value]
    let anchor: String?
    var currentKey: Value?

    private init(
      kind: Kind,
      values: Value.Array,
      object: Value.Object,
      tags: [Value],
      anchor: String?
    ) {
      self.kind = kind
      self.values = values
      self.object = object
      self.tags = tags
      self.anchor = anchor
      self.currentKey = nil
    }

    static func array(capacity: Int?, tags: [Value], anchor: String?) -> Container {
      var values: Value.Array = []
      if let capacity {
        values.reserveCapacity(capacity)
      }
      return Container(kind: .array, values: values, object: [:], tags: tags, anchor: anchor)
    }

    static func object(capacity: Int?, tags: [Value], anchor: String?) -> Container {
      var object = Value.Object()
      if let capacity {
        object.reserveCapacity(capacity)
      }
      return Container(kind: .object, values: [], object: object, tags: tags, anchor: anchor)
    }
  }

  private let resolver: any ScalarResolver
  private let metadataResolver: (any ScalarMetadataResolver)?
  private let regionResolver: (any RegionScalarResolver)?
  private var containers = ContainerStack()
  private var stack: [Container] = []
  private var pendingTags: [Value] = []
  private var pendingAnchor: String?
  private var anchors: [String: Value] = [:]
  private var root: Value?

  public init(resolver: any ScalarResolver) {
    self.resolver = resolver
    self.metadataResolver = resolver as? any ScalarMetadataResolver
    self.regionResolver = resolver as? any RegionScalarResolver
  }

  /// Convenience initializer for consuming pre-materialized events.
  ///
  /// When all ``ScalarRef`` values are pre-materialized (created via
  /// ``ScalarRef/materialized(_:)``), no resolver is needed.
  public init() {
    self.resolver = _PassthroughScalarResolver()
    self.metadataResolver = nil
    self.regionResolver = nil
  }

  public var isComplete: Bool {
    root != nil && stack.isEmpty && containers.isEmpty && pendingTags.isEmpty && pendingAnchor == nil
  }

  public mutating func append(_ event: ParseEvent) throws {
    switch event {
    case .style:
      break

    case .tag(let ref):
      let tagValue = try ref.materialize(
        using: resolver,
        metadataResolver: metadataResolver,
        regionResolver: regionResolver
      )
      pendingTags.append(tagValue)

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
      try appendResolvedValue(value)

    case .scalar(let ref):
      let value = try ref.materialize(
        using: resolver,
        metadataResolver: metadataResolver,
        regionResolver: regionResolver
      )
      try appendValue(value)

    case .beginArray(let count):
      let tags = pendingTags
      let anchor = pendingAnchor
      pendingTags.removeAll(keepingCapacity: true)
      pendingAnchor = nil
      stack.append(.array(capacity: count, tags: tags, anchor: anchor))
      containers.pushArray(count: count)

    case .endArray:
      guard case .array = containers.current else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      _ = try containers.pop()
      guard let container = stack.popLast(), container.kind == .array else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      try appendCompletedContainerValue(
        applyTags(.array(container.values), tags: container.tags),
        anchor: container.anchor
      )

    case .beginObject(let count):
      let tags = pendingTags
      let anchor = pendingAnchor
      pendingTags.removeAll(keepingCapacity: true)
      pendingAnchor = nil
      stack.append(.object(capacity: count, tags: tags, anchor: anchor))
      containers.pushObject(count: count)

    case .endObject:
      guard case .object(_, let expectingKey) = containers.current, expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      _ = try containers.pop()
      guard let container = stack.popLast(), container.kind == .object, container.currentKey == nil else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      try appendCompletedContainerValue(
        applyTags(.object(container.object), tags: container.tags),
        anchor: container.anchor
      )
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

    try appendToContainer(taggedValue, completedBy: .scalar)
  }

  private mutating func appendResolvedValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll(keepingCapacity: true)
    if let anchor = pendingAnchor {
      anchors[anchor] = taggedValue
      pendingAnchor = nil
    }

    try appendToContainer(taggedValue, completedBy: .scalar)
  }

  private mutating func appendCompletedContainerValue(_ value: Value, anchor: String?) throws {
    if let anchor {
      anchors[anchor] = value
    }
    try appendToContainer(value, completedBy: .container)
  }

  private enum CompletedValueKind {
    case scalar
    case container
  }

  private mutating func appendToContainer(_ taggedValue: Value, completedBy kind: CompletedValueKind) throws {
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
      guard case .object(_, let expectingKey) = containers.current else {
        throw Error.invalidEventSequence("Object state mismatch")
      }
      if expectingKey {
        // This value is a key
        container.currentKey = taggedValue
      } else {
        // This value is the value for the current key
        guard let key = container.currentKey else {
          throw Error.invalidEventSequence("Missing key for value")
        }
        container.object[key] = taggedValue
        container.currentKey = nil
      }
    }

    switch kind {
    case .scalar:
      containers.didFinishScalarValue()
    case .container:
      containers.didFinishContainerValue()
    }
  }
}

/// Resolver for pre-materialized ScalarRef values that should never be called.
private struct _PassthroughScalarResolver: ScalarResolver {
  func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    preconditionFailure("resolver should never be called for pre-materialized ScalarRef values")
  }
}
