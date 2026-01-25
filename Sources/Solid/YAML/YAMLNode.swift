//
//  YAMLNode.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidNumeric

enum YAMLScalarStyle: Sendable {
  case plain
  case singleQuoted
  case doubleQuoted
  case literal(chomp: YAMLScalarChomp, indent: Int?)
  case folded(chomp: YAMLScalarChomp, indent: Int?)
}

enum YAMLScalarChomp: Sendable {
  case clip
  case strip
  case keep
}

struct YAMLScalar: Sendable {
  let text: String
  let style: YAMLScalarStyle
}

enum YAMLNode: Sendable {
  case scalar(YAMLScalar, tag: String?, anchor: String?)
  case sequence([YAMLNode], tag: String?, anchor: String?)
  case mapping([(YAMLNode, YAMLNode)], tag: String?, anchor: String?)
  case alias(String)
}

struct YAMLScalarResolver {

  func resolve(_ scalar: YAMLScalar, explicitTag: String?, wrapTag: Bool = true) -> Value {
    let resolved: Value

    if let tag = explicitTag {
      resolved = resolveExplicit(tag: tag, scalar: scalar)
    } else {
      resolved = resolveImplicit(scalar)
    }

    if wrapTag, let tag = explicitTag {
      return .tagged(tag: .string(tag), value: resolved)
    }

    return resolved
  }

  private func resolveExplicit(tag: String, scalar: YAMLScalar) -> Value {
    let normalized = normalizeTag(tag)
    switch normalized {
    case "tag:yaml.org,2002:null", "!!null":
      return .null
    case "tag:yaml.org,2002:bool", "!!bool":
      return resolveBool(scalar.text) ?? .string(scalar.text)
    case "tag:yaml.org,2002:int", "!!int":
      return resolveNumber(scalar.text) ?? .string(scalar.text)
    case "tag:yaml.org,2002:float", "!!float":
      return resolveNumber(scalar.text, allowSpecial: true) ?? .string(scalar.text)
    case "tag:yaml.org,2002:str", "!!str":
      return .string(scalar.text)
    case "tag:yaml.org,2002:binary", "!!binary":
      if let data = Data(base64Encoded: scalar.text) {
        return .bytes(data)
      }
      return .string(scalar.text)
    default:
      return .tagged(tag: .string(tag), value: resolveImplicit(scalar))
    }
  }

  private func resolveImplicit(_ scalar: YAMLScalar) -> Value {
    switch scalar.style {
    case .literal, .folded:
      return .string(scalar.text)
    default:
      break
    }

    if let bool = resolveBool(scalar.text) {
      return bool
    }

    if let number = resolveNumber(scalar.text) {
      return number
    }

    if isNull(scalar.text) {
      return .null
    }

    return .string(scalar.text)
  }

  private func resolveBool(_ text: String) -> Value? {
    switch text.lowercased() {
    case "true", "yes", "y", "on":
      return .bool(true)
    case "false", "no", "n", "off":
      return .bool(false)
    default:
      return nil
    }
  }

  private func isNull(_ text: String) -> Bool {
    let lowered = text.lowercased()
    return lowered == "null" || lowered == "~" || lowered.isEmpty
  }

  private func resolveNumber(_ text: String, allowSpecial: Bool = false) -> Value? {
    if allowSpecial {
      let lowered = text.lowercased()
      if lowered == ".nan" {
        return .number(Value.TextNumber(decimal: .nan))
      }
      if lowered == ".inf" || lowered == "+.inf" || lowered == "+inf" || lowered == "inf" {
        return .number(Value.TextNumber(decimal: .infinity))
      }
      if lowered == "-.inf" || lowered == "-inf" {
        return .number(Value.TextNumber(decimal: -.infinity))
      }
    }

    let trimmed = text.replacingOccurrences(of: "_", with: "")
    if trimmed.isEmpty {
      return nil
    }

    if let decimal = BigDecimal(trimmed) {
      if decimal.isInteger {
        return .number(Value.TextNumber(decimal: decimal))
      }
      return .number(Value.TextNumber(decimal: decimal))
    }

    return nil
  }

  private func normalizeTag(_ tag: String) -> String {
    if tag.hasPrefix("!!") {
      return "tag:yaml.org,2002:\(tag.dropFirst(2))"
    }
    return tag
  }
}

extension YAMLNode {

  func toValue(resolver: YAMLScalarResolver = YAMLScalarResolver(), anchors: inout [String: Value], wrapTag: Bool = true) throws -> Value {
    switch self {
    case .alias(let name):
      guard let value = anchors[name] else {
        throw YAML.Error.unresolvedAlias(name)
      }
      return value

    case .scalar(let scalar, let tag, let anchor):
      let value = resolver.resolve(scalar, explicitTag: tag, wrapTag: wrapTag)
      if let anchor {
        if anchors[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        anchors[anchor] = value
      }
      return value

    case .sequence(let items, let tag, let anchor):
      let array = try items.map { try $0.toValue(resolver: resolver, anchors: &anchors, wrapTag: wrapTag) }
      var value: Value = .array(array)
      if wrapTag, let tag {
        value = .tagged(tag: .string(tag), value: value)
      }
      if let anchor {
        if anchors[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        anchors[anchor] = value
      }
      return value

    case .mapping(let pairs, let tag, let anchor):
      var object = Value.Object()
      for (rawKey, rawValue) in pairs {
        let key = try rawKey.toValue(resolver: resolver, anchors: &anchors, wrapTag: wrapTag)
        let val = try rawValue.toValue(resolver: resolver, anchors: &anchors, wrapTag: wrapTag)
        object[key] = val
      }
      var value: Value = .object(object)
      if wrapTag, let tag {
        value = .tagged(tag: .string(tag), value: value)
      }
      if let anchor {
        if anchors[anchor] != nil {
          throw YAML.Error.duplicateAnchor(anchor)
        }
        anchors[anchor] = value
      }
      return value
    }
  }
}
