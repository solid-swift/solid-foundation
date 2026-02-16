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

enum YAMLCollectionStyle: Sendable {
  case block
  case flow
}

struct YAMLScalar: Sendable {
  let text: String
  let style: YAMLScalarStyle
}

enum YAMLNode: Sendable {
  case scalar(YAMLScalar, tag: String?, anchor: String?)
  case sequence([YAMLNode], style: YAMLCollectionStyle, tag: String?, anchor: String?)
  case mapping([(YAMLNode, YAMLNode)], style: YAMLCollectionStyle, tag: String?, anchor: String?)
  case alias(String)
}

struct YAMLDocument: Sendable {
  let node: YAMLNode
  let explicitStart: Bool
  let explicitEnd: Bool
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
    case "!":
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
    guard case .plain = scalar.style else {
      return .string(scalar.text)
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
    let utf8 = text.utf8
    if utf8.count == 4 {
      if text.utf8EqualsCaseInsensitiveASCII("true") {
        return .bool(true)
      }
    } else if utf8.count == 5 {
      if text.utf8EqualsCaseInsensitiveASCII("false") {
        return .bool(false)
      }
    }
    return nil
  }

  private func isNull(_ text: String) -> Bool {
    text.isEmpty || text == "~" || text.utf8EqualsCaseInsensitiveASCII("null")
  }

  private func resolveNumber(_ text: String, allowSpecial: Bool = false) -> Value? {
    // Ultra-fast path: simple integer (all ASCII digits, optionally prefixed with - or +)
    // This avoids all the intermediate String allocations for the common case.
    if !text.isEmpty {
      let utf8 = text.utf8
      var idx = utf8.startIndex
      let first = utf8[idx]
      if first == UInt8(ascii: "-") || first == UInt8(ascii: "+") {
        utf8.formIndex(after: &idx)
      }
      if idx < utf8.endIndex {
        var allDigits = true
        var cursor = idx
        while cursor < utf8.endIndex {
          let byte = utf8[cursor]
          if byte < UInt8(ascii: "0") || byte > UInt8(ascii: "9") {
            allDigits = false
            break
          }
          utf8.formIndex(after: &cursor)
        }
        if allDigits {
          if let textNumber = Value.TextNumber(text: text) {
            return .number(textNumber)
          }
        }
      }
    }

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

    // Fast path: skip replacingOccurrences if no underscores
    let trimmed = text.contains("_") ? text.replacingOccurrences(of: "_", with: "") : text
    if trimmed.contains(where: { $0.isWhitespace }) {
      return nil
    }
    if trimmed.isEmpty {
      return nil
    }

    let (sign, digits): (String, String) = {
      if trimmed.hasPrefix("-") {
        return ("-", String(trimmed.dropFirst()))
      }
      if trimmed.hasPrefix("+") {
        return ("", String(trimmed.dropFirst()))
      }
      return ("", trimmed)
    }()

    let loweredDigits = digits.lowercased()
    if loweredDigits.hasPrefix("0x") || loweredDigits.hasPrefix("0o") || loweredDigits.hasPrefix("0b") {
      let radix: Int
      let bodyStart: String.Index
      if loweredDigits.hasPrefix("0x") {
        radix = 16
        bodyStart = digits.index(digits.startIndex, offsetBy: 2)
      } else if loweredDigits.hasPrefix("0o") {
        radix = 8
        bodyStart = digits.index(digits.startIndex, offsetBy: 2)
      } else {
        radix = 2
        bodyStart = digits.index(digits.startIndex, offsetBy: 2)
      }
      let body = String(digits[bodyStart...])
      guard let value = parseRadixInteger(sign: sign, body: body, radix: radix) else {
        return nil
      }
      let decimal = BigDecimal(value)
      return .number(Value.TextNumber(decimal: decimal))
    }

    if let textNumber = Value.TextNumber(text: trimmed) {
      return .number(textNumber)
    }

    return nil
  }

  private func parseRadixInteger(sign: String, body: String, radix: Int) -> BigInt? {
    guard !body.isEmpty else { return nil }
    var value = BigInt.zero
    let base = BigInt(radix)
    for ch in body {
      guard let digit = ch.hexDigitValue, digit < radix else {
        return nil
      }
      value = value * base + BigInt(digit)
    }
    return sign == "-" ? -value : value
  }

  private func normalizeTag(_ tag: String) -> String {
    if tag.hasPrefix("!!") {
      return "tag:yaml.org,2002:\(tag.dropFirst(2))"
    }
    return tag
  }
}

extension YAMLNode {

  func toValue(
    resolver: YAMLScalarResolver = YAMLScalarResolver(),
    anchors: inout [String: Value],
    wrapTag: Bool = true
  ) throws -> Value {
    switch self {
    case .alias(let name):
      guard let value = anchors[name] else {
        throw YAML.ParseError.unresolvedAlias(name)
      }
      return value

    case .scalar(let scalar, let tag, let anchor):
      let value = resolver.resolve(scalar, explicitTag: tag, wrapTag: wrapTag)
      if let anchor {
        anchors[anchor] = value
      }
      return value

    case .sequence(let items, _, let tag, let anchor):
      let array = try items.map { try $0.toValue(resolver: resolver, anchors: &anchors, wrapTag: wrapTag) }
      var value: Value = .array(array)
      if wrapTag, let tag {
        value = .tagged(tag: .string(tag), value: value)
      }
      if let anchor {
        anchors[anchor] = value
      }
      return value

    case .mapping(let pairs, _, let tag, let anchor):
      var object = Value.Object()
      object.reserveCapacity(pairs.count)
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
        anchors[anchor] = value
      }
      return value
    }
  }
}

// MARK: - Fast ASCII Case-Insensitive Comparison

extension String {
  /// Compares against a lowercase ASCII literal without going through Foundation's locale-aware comparison.
  /// The `other` parameter MUST be all-lowercase ASCII.
  @inline(__always)
  func utf8EqualsCaseInsensitiveASCII(_ other: StaticString) -> Bool {
    let selfUTF8 = self.utf8
    return other.withUTF8Buffer { otherUTF8 in
      guard selfUTF8.count == otherUTF8.count else { return false }
      var selfIdx = selfUTF8.startIndex
      for i in 0..<otherUTF8.count {
        var byte = selfUTF8[selfIdx]
        // Fast ASCII lowercase: if byte is A-Z, convert to a-z
        if byte >= 0x41 && byte <= 0x5A {
          byte |= 0x20
        }
        if byte != otherUTF8[i] { return false }
        selfUTF8.formIndex(after: &selfIdx)
      }
      return true
    }
  }
}
