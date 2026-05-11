//
//  YAMLTokenEventAdapter.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

import SolidData

/// Converts YAML-specific raw tokens into format-neutral parse events.
struct YAMLTokenEventAdapter: ~Copyable {
  private var containers = ContainerStack()
  private var pendingTags: [String] = []

  init() {}

  mutating func append(_ token: YAMLRawToken, into events: inout [ParseEvent]) throws {
    switch token {
    case .directive, .documentStart, .documentEnd:
      return

    case .tag(let tag):
      events.append(.tag(.materialized(.string(tag))))
      pendingTags.append(tag)

    case .anchor(let anchor):
      events.append(.anchor(anchor))

    case .alias(let alias):
      events.append(.alias(alias))
      pendingTags.removeAll(keepingCapacity: true)
      containers.didFinishScalarValue()

    case .scalar(let scalar):
      events.append(.style(.scalar(mapScalarStyle(scalar.style))))
      events.append(.scalar(try makeScalarRef(scalar)))
      pendingTags.removeAll(keepingCapacity: true)
      containers.didFinishScalarValue()

    case .beginSequence(let style):
      events.append(.style(.collection(mapCollectionStyle(style))))
      events.append(.beginArray(count: nil))
      pendingTags.removeAll(keepingCapacity: true)
      containers.pushArray(count: nil)

    case .endSequence:
      guard case .array = try containers.pop() else {
        throw YAML.ParseError.invalidSyntax("Unexpected sequence end", location: nil)
      }
      events.append(.endArray)
      containers.didFinishContainerValue()

    case .beginMapping(let style):
      events.append(.style(.collection(mapCollectionStyle(style))))
      events.append(.beginObject(count: nil))
      pendingTags.removeAll(keepingCapacity: true)
      containers.pushObject(count: nil)

    case .endMapping:
      guard case .object = try containers.pop() else {
        throw YAML.ParseError.invalidSyntax("Unexpected mapping end", location: nil)
      }
      events.append(.endObject)
      containers.didFinishContainerValue()
    }
  }

  private func mapScalarStyle(_ style: YAMLScalarStyle) -> ValueScalarStyle {
    switch style {
    case .plain:
      return .plain
    case .singleQuoted:
      return .singleQuoted
    case .doubleQuoted:
      return .doubleQuoted
    case .literal:
      return .literal
    case .folded:
      return .folded
    }
  }

  private func mapCollectionStyle(_ style: YAMLCollectionStyle) -> ValueCollectionStyle {
    switch style {
    case .block:
      return .block
    case .flow:
      return .flow
    }
  }

  private func makeScalarRef(_ scalar: YAMLRawScalar) throws -> ScalarRef {
    guard let explicitTag = pendingTags.last else {
      return ScalarRef(kind: scalar.kind, region: scalar.region)
    }
    guard shouldPreResolveExplicitTag(explicitTag) else {
      return ScalarRef(kind: scalar.kind, region: scalar.region)
    }
    let yamlScalar = YAMLScalar(text: try scalar.region.string(), style: scalar.style)
    let value = YAMLTagResolver().resolve(yamlScalar, explicitTag: explicitTag, wrapTag: false)
    return .materialized(value)
  }

  private func shouldPreResolveExplicitTag(_ tag: String) -> Bool {
    switch normalizeTag(tag) {
    case "tag:yaml.org,2002:null",
      "tag:yaml.org,2002:bool",
      "tag:yaml.org,2002:int",
      "tag:yaml.org,2002:float",
      "tag:yaml.org,2002:str",
      "tag:yaml.org,2002:binary",
      "!":
      return true
    default:
      return false
    }
  }

  private func normalizeTag(_ tag: String) -> String {
    if tag.hasPrefix("!!") {
      return "tag:yaml.org,2002:\(tag.dropFirst(2))"
    }
    return tag
  }
}
