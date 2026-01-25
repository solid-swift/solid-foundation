//
//  YAMLValueReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// Synchronous YAML reader that loads into ``Value``.
public struct YAMLValueReader: FormatReader {

  private let text: String

  public init(data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAML.Error.invalidUTF8
    }
    self.text = text
  }

  public init(string: String) {
    self.text = string
  }

  public var format: Format { YAML.format }

  public func read() throws -> Value {
    var parser = try YAMLParser(text: text)
    let node = try parser.parseFirstDocument()
    var anchors: [String: Value] = [:]
    return try node.toValue(anchors: &anchors)
  }
}

/// Synchronous YAML writer that renders ``Value`` instances.
public final class YAMLValueWriter: FormatWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int

    public init(indent: Int = 2) {
      self.indent = indent
    }
  }

  private let options: Options
  private var output = ""

  public init(options: Options = .default) {
    self.options = options
  }

  public var format: Format { YAML.format }

  public func write(_ value: Value) throws {
    output = render(value, indent: 0)
  }

  /// Rendered YAML bytes.
  public func data() -> Data {
    output.data(using: .utf8) ?? Data()
  }

  // MARK: - Rendering

  private func render(_ value: Value, indent: Int) -> String {
    switch value {
    case .tagged(let tag, let inner):
      return "\(formatTag(tag)) \(render(inner, indent: indent))"
    case .array(let array):
      guard !array.isEmpty else { return "[]" }
      var lines: [String] = []
      for item in array {
        if isScalar(item) {
          let content = render(item, indent: indent + options.indent)
          lines.append("\(indentString(indent))- \(content)")
        } else {
          let content = render(item, indent: indent + options.indent)
          lines.append("\(indentString(indent))-\n\(content)")
        }
      }
      return lines.joined(separator: "\n")

    case .object(let object):
      guard !object.isEmpty else { return "{}" }
      var lines: [String] = []
      for (key, val) in object {
        let keyText = renderScalarLike(key, indent: indent)
        if isScalar(val) {
          let valueText = render(val, indent: indent + options.indent)
          lines.append("\(indentString(indent))\(keyText): \(valueText)")
        } else {
          let valueText = render(val, indent: indent + options.indent)
          lines.append("\(indentString(indent))\(keyText):\n\(valueText)")
        }
      }
      return lines.joined(separator: "\n")

    case .string(let string):
      return renderString(string, indent: indent)
    case .bytes(let data):
      return "\"\(data.base64EncodedString())\""
    case .bool(let bool):
      return bool ? "true" : "false"
    case .number(let number):
      return number.description
    case .null:
      return "null"
    }
  }

  private func isScalar(_ value: Value) -> Bool {
    switch value {
    case .array, .object:
      return false
    default:
      return true
    }
  }

  private func renderScalarLike(_ value: Value, indent: Int) -> String {
    switch value {
    case .tagged(let tag, let inner):
      return "\(formatTag(tag)) \(renderScalarLike(inner, indent: indent))"
    case .string:
      return renderString(value.stringified, indent: indent)
    default:
      return render(value, indent: indent)
    }
  }

  private func renderString(_ string: String, indent: Int) -> String {
    if string.contains("\n") {
      var result = "|\n"
      let padding = indentString(indent + options.indent)
      let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
      for line in lines {
        result.append(padding)
        result.append(contentsOf: line)
        result.append("\n")
      }
      return result
    }

    let requiresQuotes = string.isEmpty ||
      string.first?.isWhitespace == true ||
      string.contains(where: { ":{}[],#&*!|>'\"%@`".contains($0) }) ||
      string.contains("\n")

    if !requiresQuotes {
      return string
    }

    var escaped = "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"":
        escaped.append("\\\"")
      case "\\":
        escaped.append("\\\\")
      case "\n":
        escaped.append("\\n")
      case "\r":
        escaped.append("\\r")
      case "\t":
        escaped.append("\\t")
      default:
        escaped.append(String(scalar))
      }
    }
    escaped.append("\"")
    return escaped
  }

  private func indentString(_ indent: Int) -> String {
    String(repeating: " ", count: indent)
  }

  private func formatTag(_ value: Value) -> String {
    let tag = value.stringified
    let simple = tag.allSatisfy { $0.isLetter || $0.isNumber || $0 == ":" || $0 == "-" || $0 == "_" || $0 == "/" || $0 == "." }
    if simple {
      return "!\(tag)"
    }
    return "!<\(tag)>"
  }
}
