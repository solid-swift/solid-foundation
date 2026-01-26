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
      throw YAML.DataError.invalidEncoding(.utf8)
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

  /// Write a value into a new in-memory `Data` buffer.
  public static func write(_ value: Value, options: Options = .default) throws -> Data {
    let writer = YAMLValueWriter(options: options)
    try writer.write(value)
    return writer.data()
  }

  public init(options: Options = .default) {
    self.options = options
  }

  public var format: Format { YAML.format }

  public func write(_ value: Value) throws {
    output = render(value, indent: 0, allowBlock: true)
  }

  /// Rendered YAML bytes.
  public func data() -> Data {
    Data(output.utf8)
  }

  // MARK: - Rendering

  private func render(_ value: Value, indent: Int, allowBlock: Bool) -> String {
    switch value {
    case .tagged(let tag, let inner):
      let innerText = render(inner, indent: indent, allowBlock: allowBlock)
      if allowBlock, innerText.contains("\n"), !isScalar(inner) {
        let tagLine = "\(indentString(indent))\(formatTag(tag))"
        return "\(tagLine)\n\(innerText)"
      }
      return "\(formatTag(tag)) \(innerText)"
    case .array(let array):
      guard !array.isEmpty else { return "[]" }
      if !allowBlock {
        let contents = array.map { render($0, indent: indent, allowBlock: false) }
        return "[\(contents.joined(separator: ", "))]"
      }
      var result = ""
      for (index, item) in array.enumerated() {
        let itemIndent = isScalar(item) ? indent : (indent + options.indent)
        let content = render(item, indent: itemIndent, allowBlock: true)
        let line =
          isScalar(item)
          ? "\(indentString(indent))- \(content)"
          : "\(indentString(indent))-\n\(content)"
        if index > 0, !result.hasSuffix("\n") {
          result.append("\n")
        }
        result.append(line)
      }
      return result

    case .object(let object):
      guard !object.isEmpty else { return "{}" }
      if !allowBlock {
        let contents = object.map { key, val in
          let keyText = render(key, indent: indent, allowBlock: false)
          let valueText = render(val, indent: indent, allowBlock: false)
          return "\(keyText): \(valueText)"
        }
        return "{\(contents.joined(separator: ", "))}"
      }
      var result = ""
      var index = 0
      for (key, val) in object {
        let keyText = render(key, indent: indent, allowBlock: false)
        let valueIndent = isScalar(val) ? indent : (indent + options.indent)
        let valueText = render(val, indent: valueIndent, allowBlock: true)
        let line =
          isScalar(val)
          ? "\(indentString(indent))\(keyText): \(valueText)"
          : "\(indentString(indent))\(keyText):\n\(valueText)"
        if index > 0, !result.hasSuffix("\n") {
          result.append("\n")
        }
        result.append(line)
        index += 1
      }
      return result

    case .string(let string):
      return renderString(string, indent: indent, allowBlock: allowBlock)
    case .bytes(let data):
      let encoded = renderString(data.base64EncodedString(), indent: indent, allowBlock: allowBlock)
      let tag = formatTag(.string("tag:yaml.org,2002:binary"))
      return "\(tag) \(encoded)"
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
    case .tagged(_, let inner):
      return isScalar(inner)
    case .array(let array):
      return array.isEmpty
    case .object(let object):
      return object.isEmpty
    default:
      return true
    }
  }

  private func renderString(_ string: String, indent: Int, allowBlock: Bool) -> String {
    YAMLStringEncoder.render(
      string,
      indent: indent,
      indentSize: options.indent,
      allowBlock: allowBlock,
      allowImplicitTyping: false
    )
  }

  private func indentString(_ indent: Int) -> String {
    String(repeating: " ", count: indent)
  }

  private func formatTag(_ value: Value) -> String {
    let tag = value.stringified
    if tag == "!" {
      return "!"
    }
    let corePrefix = "tag:yaml.org,2002:"
    if tag.hasPrefix(corePrefix) {
      let suffix = String(tag.dropFirst(corePrefix.count))
      if isSimpleTagText(suffix) {
        return "!!\(suffix)"
      }
    }
    if isSimpleTagText(tag) {
      return "!\(tag)"
    }
    return "!<\(tag)>"
  }

  private func isSimpleTagText(_ text: String) -> Bool {
    text.allSatisfy { $0.isLetter || $0.isNumber || $0 == ":" || $0 == "-" || $0 == "_" || $0 == "/" || $0 == "." }
  }
}
