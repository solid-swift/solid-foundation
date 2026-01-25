//
//  YAMLEventEmitter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import SolidData

struct YAMLEventEmitter {

  private var resolver = YAMLScalarResolver()
  private var anchorNodes: [String: YAMLNode] = [:]
  private var valueAnchors: [String: Value] = [:]

  mutating func emit(node: YAMLNode) throws -> [ValueEvent] {
    anchorNodes.removeAll(keepingCapacity: true)
    valueAnchors.removeAll(keepingCapacity: true)
    var events: [ValueEvent] = []
    try emit(node, into: &events)
    return events
  }

  mutating func emit(_ node: YAMLNode, into events: inout [ValueEvent]) throws {
    switch node {
    case .alias(let name):
      guard let target = anchorNodes[name] else {
        throw YAML.Error.unresolvedAlias(name)
      }
      try emit(target, into: &events)

    case .scalar(let scalar, let tag, let anchor):
      if let anchor {
        if anchorNodes[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        anchorNodes[anchor] = node
      }
      if let tag {
        events.append(.tag(.string(tag)))
      }
      let value = resolver.resolve(scalar, explicitTag: tag, wrapTag: false)
      if let anchor {
        if valueAnchors[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        valueAnchors[anchor] = value
      }
      events.append(.scalar(value))

    case .sequence(let items, let tag, let anchor):
      if let anchor {
        if anchorNodes[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        anchorNodes[anchor] = node
      }
      if let tag {
        events.append(.tag(.string(tag)))
      }
      events.append(.beginArray)
      for item in items {
        try emit(item, into: &events)
      }
      events.append(.endArray)
      if let anchor {
        let value = try buildValue(from: node, includeTags: false)
        if valueAnchors[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        valueAnchors[anchor] = value
      }

    case .mapping(let pairs, let tag, let anchor):
      if let anchor {
        if anchorNodes[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        anchorNodes[anchor] = node
      }
      if let tag {
        events.append(.tag(.string(tag)))
      }
      events.append(.beginObject)
      for (keyNode, valueNode) in pairs {
        try emitKey(keyNode, into: &events)
        try emit(valueNode, into: &events)
      }
      events.append(.endObject)
      if let anchor {
        let value = try buildValue(from: node, includeTags: false)
        if valueAnchors[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        valueAnchors[anchor] = value
      }
    }
  }

  private mutating func emitKey(_ node: YAMLNode, into events: inout [ValueEvent]) throws {
    if let tag = nodeTag(node) {
      events.append(.tag(.string(tag)))
    }
    let keyValue = try buildValue(from: node, includeTags: false)
    events.append(.key(keyValue))
  }

  private func nodeTag(_ node: YAMLNode) -> String? {
    switch node {
    case .scalar(_, let tag, _):
      return tag
    case .sequence(_, let tag, _):
      return tag
    case .mapping(_, let tag, _):
      return tag
    case .alias(let name):
      return anchorNodes[name].flatMap { nodeTag($0) }
    }
  }

  private mutating func buildValue(from node: YAMLNode, includeTags: Bool) throws -> Value {
    switch node {
    case .alias(let name):
      if let cached = valueAnchors[name] {
        return cached
      }
      guard let target = anchorNodes[name] else {
        throw YAML.Error.unresolvedAlias(name)
      }
      let value = try buildValue(from: target, includeTags: includeTags)
      valueAnchors[name] = value
      return value

    default:
      var anchors = valueAnchors
      let value = try node.toValue(resolver: resolver, anchors: &anchors, wrapTag: includeTags)
      valueAnchors = anchors
      return value
    }
  }
}
