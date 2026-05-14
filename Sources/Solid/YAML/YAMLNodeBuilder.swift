//
//  YAMLNodeBuilder.swift
//  SolidFoundation
//
//  Created by Codex on 4/24/26.
//

import Foundation
import SolidData

/// Builds raw YAML nodes from `ParseEvent` streams.
///
/// This is the compatibility layer for APIs that still expose `YAMLNode`.
/// Stream parsing can stay event-first while node APIs rebuild the tree from
/// those events.
struct YAMLNodeBuilder {

  enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteDocument
  }

  private enum ContainerKind {
    case sequence
    case mapping
  }

  private enum CompletedNodeKind {
    case scalar
    case container
  }

  private final class Container {
    let kind: ContainerKind
    var items: [YAMLNode] = []
    var pairs: [(YAMLNode, YAMLNode)] = []
    var currentKey: YAMLNode?
    let style: YAMLCollectionStyle
    let tag: String?
    let anchor: String?

    init(kind: ContainerKind, style: YAMLCollectionStyle, tag: String?, anchor: String?) {
      self.kind = kind
      self.style = style
      self.tag = tag
      self.anchor = anchor
    }
  }

  private let resolver = YAMLScalarResolver()
  // Tracks event-position semantics only. `stack` owns the actual YAMLNode
  // accumulation and metadata needed to build the tree.
  private var containers = ContainerStack()
  private var stack: [Container] = []
  private var pendingStyle: ValueStyle?
  private var pendingTag: String?
  private var pendingAnchor: String?
  private var root: YAMLNode?

  var isComplete: Bool {
    root != nil && stack.isEmpty && containers.isEmpty && pendingStyle == nil && pendingTag == nil && pendingAnchor == nil
  }

  mutating func append(_ event: ParseEvent) throws {
    switch event {
    case .style(let style):
      guard pendingStyle == nil else {
        throw Error.invalidEventSequence("Style without value")
      }
      pendingStyle = style

    case .tag(let ref):
      guard pendingTag == nil else {
        throw Error.invalidEventSequence("Multiple tags on node")
      }
      let value = try ref.materialize(using: resolver)
      guard case .string(let tag) = value else {
        throw Error.invalidEventSequence("YAML tag must be a string")
      }
      pendingTag = tag

    case .anchor(let name):
      guard pendingAnchor == nil else {
        throw Error.invalidEventSequence("Multiple anchors on node")
      }
      pendingAnchor = name

    case .alias(let name):
      guard pendingTag == nil, pendingAnchor == nil else {
        throw Error.invalidEventSequence("Alias cannot have tag or anchor")
      }
      try appendCompletedNode(.alias(name), kind: .scalar)

    case .scalar(let ref):
      let scalar = try makeScalar(from: ref)
      let node = YAMLNode.scalar(scalar, tag: consumeTag(), anchor: consumeAnchor())
      pendingStyle = nil
      try appendCompletedNode(node, kind: .scalar)

    case .beginArray:
      let container = Container(
        kind: .sequence,
        style: consumeCollectionStyle(),
        tag: consumeTag(),
        anchor: consumeAnchor()
      )
      stack.append(container)
      containers.pushArray(count: nil)

    case .endArray:
      guard case .array = containers.current else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      _ = try containers.pop()
      guard let container = stack.popLast(), container.kind == .sequence else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      let node = YAMLNode.sequence(
        container.items,
        style: container.style,
        tag: container.tag,
        anchor: container.anchor
      )
      try appendCompletedNode(node, kind: .container)

    case .beginObject:
      let container = Container(
        kind: .mapping,
        style: consumeCollectionStyle(),
        tag: consumeTag(),
        anchor: consumeAnchor()
      )
      stack.append(container)
      containers.pushObject(count: nil)

    case .endObject:
      guard case .object(_, let expectingKey) = containers.current, expectingKey else {
        throw Error.invalidEventSequence("Missing value for mapping key")
      }
      _ = try containers.pop()
      guard let container = stack.popLast(), container.kind == .mapping else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard container.currentKey == nil else {
        throw Error.invalidEventSequence("Missing value for mapping key")
      }
      let node = YAMLNode.mapping(
        container.pairs,
        style: container.style,
        tag: container.tag,
        anchor: container.anchor
      )
      try appendCompletedNode(node, kind: .container)
    }
  }

  mutating func finish() throws -> YAMLNode {
    guard stack.isEmpty, containers.isEmpty, pendingStyle == nil, pendingTag == nil, pendingAnchor == nil, let root else {
      throw Error.incompleteDocument
    }
    return root
  }

  private mutating func appendCompletedNode(_ node: YAMLNode, kind: CompletedNodeKind) throws {
    guard let container = stack.last else {
      guard root == nil else {
        throw Error.invalidEventSequence("Multiple document roots")
      }
      root = node
      return
    }

    switch container.kind {
    case .sequence:
      container.items.append(node)
    case .mapping:
      guard case .object(_, let expectingKey) = containers.current else {
        throw Error.invalidEventSequence("Mapping state mismatch")
      }
      if expectingKey {
        container.currentKey = node
      } else {
        guard let key = container.currentKey else {
          throw Error.invalidEventSequence("Missing mapping key")
        }
        container.pairs.append((key, node))
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

  private mutating func makeScalar(from ref: ScalarRef) throws -> YAMLScalar {
    let style = consumeScalarStyle()
    if let rawData = ref.rawData, let text = String(data: rawData, encoding: .utf8) {
      return YAMLScalar(text: text, style: style)
    }

    let value = try ref.materialize(using: resolver)
    return YAMLScalar(text: scalarText(for: value), style: style)
  }

  private func scalarText(for value: Value) -> String {
    switch value {
    case .null:
      return ""
    case .bool(let bool):
      return bool ? "true" : "false"
    case .number(let number):
      return number.description
    case .string(let string):
      return string
    case .bytes(let data):
      return data.base64EncodedString()
    case .tagged(_, let value):
      return scalarText(for: value)
    default:
      return String(describing: value)
    }
  }

  private mutating func consumeTag() -> String? {
    defer { pendingTag = nil }
    return pendingTag
  }

  private mutating func consumeAnchor() -> String? {
    defer { pendingAnchor = nil }
    return pendingAnchor
  }

  private mutating func consumeScalarStyle() -> YAMLScalarStyle {
    defer { pendingStyle = nil }
    guard case .scalar(let style) = pendingStyle else {
      return .plain
    }
    switch style {
    case .plain: return .plain
    case .singleQuoted: return .singleQuoted
    case .doubleQuoted: return .doubleQuoted
    case .literal: return .literal(chomp: .clip, indent: nil)
    case .folded: return .folded(chomp: .clip, indent: nil)
    }
  }

  private mutating func consumeCollectionStyle() -> YAMLCollectionStyle {
    defer { pendingStyle = nil }
    guard case .collection(let style) = pendingStyle else {
      return .block
    }
    switch style {
    case .block: return .block
    case .flow: return .flow
    }
  }
}

struct YAMLRawTokenNodeBuilder: ~Copyable {

  enum Error: Swift.Error {
    case invalidTokenSequence(String)
    case incompleteDocument
  }

  private enum CompletedNodeKind {
    case scalar
    case container
  }

  private final class Container {
    enum Kind {
      case sequence
      case mapping
    }

    let kind: Kind
    var items: [YAMLNode] = []
    var pairs: [(YAMLNode, YAMLNode)] = []
    var currentKey: YAMLNode?
    let style: YAMLCollectionStyle
    let tag: String?
    let anchor: String?

    init(kind: Kind, style: YAMLCollectionStyle, tag: String?, anchor: String?) {
      self.kind = kind
      self.style = style
      self.tag = tag
      self.anchor = anchor
    }
  }

  // Tracks event-position semantics only. `stack` owns the actual YAMLNode
  // accumulation and metadata needed to build the tree.
  private var containers = ContainerStack()
  private var stack: [Container] = []
  private var pendingTag: String?
  private var pendingAnchor: String?
  private var root: YAMLNode?

  var isEmpty: Bool {
    root == nil && stack.isEmpty && containers.isEmpty && pendingTag == nil && pendingAnchor == nil
  }

  mutating func append(_ token: YAMLRawToken) throws {
    switch token {
    case .directive, .documentStart, .documentEnd:
      break

    case .tag(let tag):
      guard pendingTag == nil else {
        throw Error.invalidTokenSequence("Multiple tags on node")
      }
      pendingTag = tag

    case .anchor(let anchor):
      guard pendingAnchor == nil else {
        throw Error.invalidTokenSequence("Multiple anchors on node")
      }
      pendingAnchor = anchor

    case .alias(let alias):
      guard pendingTag == nil, pendingAnchor == nil else {
        throw Error.invalidTokenSequence("Alias cannot have tag or anchor")
      }
      try appendCompletedNode(.alias(alias), kind: .scalar)

    case .scalar(let scalar):
      let text = try scalar.region.string()
      let node = YAMLNode.scalar(
        YAMLScalar(text: text, style: scalar.style),
        tag: consumeTag(),
        anchor: consumeAnchor()
      )
      try appendCompletedNode(node, kind: .scalar)

    case .beginSequence(let style):
      stack.append(Container(kind: .sequence, style: style, tag: consumeTag(), anchor: consumeAnchor()))
      containers.pushArray(count: nil)

    case .endSequence:
      guard case .array = try containers.pop() else {
        throw Error.invalidTokenSequence("Unexpected sequence end")
      }
      guard let container = stack.popLast(), container.kind == .sequence else {
        throw Error.invalidTokenSequence("Unexpected sequence end")
      }
      let node = YAMLNode.sequence(
        container.items,
        style: container.style,
        tag: container.tag,
        anchor: container.anchor
      )
      try appendCompletedNode(node, kind: .container)

    case .beginMapping(let style):
      stack.append(Container(kind: .mapping, style: style, tag: consumeTag(), anchor: consumeAnchor()))
      containers.pushObject(count: nil)

    case .endMapping:
      guard case .object(_, let expectingKey) = containers.current, expectingKey else {
        throw Error.invalidTokenSequence("Missing value for mapping key")
      }
      guard case .object = try containers.pop() else {
        throw Error.invalidTokenSequence("Unexpected mapping end")
      }
      guard let container = stack.popLast(), container.kind == .mapping, container.currentKey == nil else {
        throw Error.invalidTokenSequence("Unexpected mapping end")
      }
      let node = YAMLNode.mapping(
        container.pairs,
        style: container.style,
        tag: container.tag,
        anchor: container.anchor
      )
      try appendCompletedNode(node, kind: .container)
    }
  }

  mutating func finish() throws -> YAMLNode {
    guard stack.isEmpty, containers.isEmpty, pendingTag == nil, pendingAnchor == nil else {
      throw Error.incompleteDocument
    }
    return root ?? .emptyPlainScalar
  }

  private mutating func appendCompletedNode(_ node: YAMLNode, kind: CompletedNodeKind) throws {
    guard let container = stack.last else {
      guard root == nil else {
        throw Error.invalidTokenSequence("Multiple document roots")
      }
      root = node
      return
    }

    switch container.kind {
    case .sequence:
      container.items.append(node)

    case .mapping:
      guard case .object(_, let expectingKey) = containers.current else {
        throw Error.invalidTokenSequence("Mapping state mismatch")
      }
      if expectingKey {
        container.currentKey = node
      } else {
        guard let key = container.currentKey else {
          throw Error.invalidTokenSequence("Missing mapping key")
        }
        container.pairs.append((key, node))
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

  private mutating func consumeTag() -> String? {
    defer { pendingTag = nil }
    return pendingTag
  }

  private mutating func consumeAnchor() -> String? {
    defer { pendingAnchor = nil }
    return pendingAnchor
  }
}
