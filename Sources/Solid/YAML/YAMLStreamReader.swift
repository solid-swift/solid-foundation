//
//  YAMLStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// Synchronous YAML stream reader that produces ``ValueEvent`` values.
public struct YAMLStreamReader: FormatStreamReader {

  private var eventIterator: YAMLNodeEventIterator?
  private var remainingText = ""
  private var allowDirectives = true
  private var requireDocumentStart = false
  private var finished = false

  public init() {}

  public var format: Format { YAML.format }

  public mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ValueEvent>
  ) throws -> FormatStreamReadStatus {
    guard !finished else { return .endOfStream }

    if !input.isEmpty {
      guard let chunk = String(data: input, encoding: .utf8) else {
        throw YAML.DataError.invalidEncoding(.utf8)
      }
      remainingText += chunk
    }

    var produced = false

    while !output.isFull {
      if var iterator = eventIterator {
        if let event = try iterator.next() {
          output.append(event)
          produced = true
          eventIterator = iterator
          continue
        }
        eventIterator = nil
        continue
      }

      guard let document = try readNextDocument(isFinal: isFinal) else {
        if isFinal {
          finished = true
          return produced ? .producedOutput : .endOfStream
        }
        return produced ? .producedOutput : .needMoreInput
      }
      eventIterator = YAMLNodeEventIterator(node: document.node)
    }

    return .producedOutput
  }

  private mutating func readNextDocument(isFinal: Bool) throws -> YAMLDocument? {
    guard !remainingText.isEmpty else {
      return nil
    }

    var parser = try YAMLParser(
      text: remainingText,
      allowIncompleteInput: !isFinal,
      allowDirectives: allowDirectives,
      requireDocumentStart: requireDocumentStart
    )
    guard let document = try parser.parseNextDocument() else {
      return nil
    }
    allowDirectives = parser.allowsDirectives
    requireDocumentStart = parser.requiresDocumentStart
    remainingText = parser.remainingText()
    return document
  }
}

private struct YAMLNodeEventIterator {

  private enum Action {
    case emitNode(YAMLNode)
    case emitTag(String)
    case emitScalar(Value)
    case emitKeyNode(YAMLNode)
    case beginArray
    case endArray
    case beginObject
    case endObject
    case registerAnchor(String, YAMLNode)
  }

  private var actions: [Action]
  private var resolver = YAMLScalarResolver()
  private var anchorNodes: [String: YAMLNode] = [:]
  private var valueAnchors: [String: Value] = [:]

  init(node: YAMLNode) {
    actions = [.emitNode(node)]
  }

  mutating func next() throws -> ValueEvent? {
    while let action = actions.popLast() {
      switch action {
      case .emitNode(let node):
        try expand(node)
        continue
      case .emitTag(let tag):
        return .tag(.string(tag))
      case .emitScalar(let value):
        return .scalar(value)
      case .emitKeyNode(let node):
        let keyValue = try buildValue(from: node, includeTags: false)
        if let anchor = nodeAnchor(node) {
          anchorNodes[anchor] = node
        }
        return .key(keyValue)
      case .beginArray:
        return .beginArray(count: nil)
      case .endArray:
        return .endArray
      case .beginObject:
        return .beginObject(count: nil)
      case .endObject:
        return .endObject
      case .registerAnchor(let name, let node):
        let value = try buildValue(from: node, includeTags: false)
        valueAnchors[name] = value
        continue
      }
    }
    return nil
  }

  private mutating func expand(_ node: YAMLNode) throws {
    switch node {
    case .alias(let name):
      guard let target = anchorNodes[name] else {
        throw YAML.ParseError.unresolvedAlias(name)
      }
      actions.append(.emitNode(target))

    case .scalar(let scalar, let tag, let anchor):
      if let anchor {
        anchorNodes[anchor] = node
      }
      let value = resolver.resolve(scalar, explicitTag: tag, wrapTag: false)
      if let anchor {
        valueAnchors[anchor] = value
      }
      actions.append(.emitScalar(value))
      if let tag {
        actions.append(.emitTag(tag))
      }

    case .sequence(let items, _, let tag, let anchor):
      // Reserve capacity: endArray + items + beginArray + optional tag + optional anchor
      actions.reserveCapacity(actions.count + items.count + 4)
      if let anchor {
        anchorNodes[anchor] = node
        actions.append(.registerAnchor(anchor, node))
      }
      actions.append(.endArray)
      for item in items.reversed() {
        actions.append(.emitNode(item))
      }
      actions.append(.beginArray)
      if let tag {
        actions.append(.emitTag(tag))
      }

    case .mapping(let pairs, _, let tag, let anchor):
      // Reserve capacity: endObject + pairs*(value+key+optionalTag) + beginObject + optional tag + optional anchor
      actions.reserveCapacity(actions.count + pairs.count * 3 + 4)
      if let anchor {
        anchorNodes[anchor] = node
        actions.append(.registerAnchor(anchor, node))
      }
      actions.append(.endObject)
      for (keyNode, valueNode) in pairs.reversed() {
        actions.append(.emitNode(valueNode))
        // Inline emitKeyActions to avoid temporary array allocation
        if let tag = nodeTag(keyNode) {
          actions.append(.emitTag(tag))
        }
        actions.append(.emitKeyNode(keyNode))
      }
      actions.append(.beginObject)
      if let tag {
        actions.append(.emitTag(tag))
      }
    }
  }

  private func nodeTag(_ node: YAMLNode) -> String? {
    switch node {
    case .scalar(_, let tag, _):
      return tag
    case .sequence(_, _, let tag, _):
      return tag
    case .mapping(_, _, let tag, _):
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
        throw YAML.ParseError.unresolvedAlias(name)
      }
      let value = try buildValue(from: target, includeTags: includeTags)
      valueAnchors[name] = value
      return value

    case .scalar(let scalar, let tag, _):
      var value = resolver.resolve(scalar, explicitTag: tag, wrapTag: false)
      if includeTags, let tag {
        value = .tagged(tags: [.string(tag)], value: value)
      }
      if let anchor = nodeAnchor(node) {
        valueAnchors[anchor] = value
      }
      return value

    case .sequence(let items, _, let tag, _):
      let values = try items.map { try buildValue(from: $0, includeTags: true) }
      var value: Value = .array(values)
      if includeTags, let tag {
        value = .tagged(tags: [.string(tag)], value: value)
      }
      if let anchor = nodeAnchor(node) {
        valueAnchors[anchor] = value
      }
      return value

    case .mapping(let pairs, _, let tag, _):
      var object = Value.Object()
      for (keyNode, valueNode) in pairs {
        let keyValue = try buildValue(from: keyNode, includeTags: true)
        let value = try buildValue(from: valueNode, includeTags: true)
        object[keyValue] = value
      }
      var value: Value = .object(object)
      if includeTags, let tag {
        value = .tagged(tags: [.string(tag)], value: value)
      }
      if let anchor = nodeAnchor(node) {
        valueAnchors[anchor] = value
      }
      return value
    }
  }

  private func nodeAnchor(_ node: YAMLNode) -> String? {
    switch node {
    case .scalar(_, _, let anchor):
      return anchor
    case .sequence(_, _, _, let anchor):
      return anchor
    case .mapping(_, _, _, let anchor):
      return anchor
    case .alias:
      return nil
    }
  }
}
