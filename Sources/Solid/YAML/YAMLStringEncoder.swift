//
//  YAMLStringEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/14/26.
//

import Foundation
import SolidData

struct YAMLStringEncoder {

  private static let resolver = YAMLScalarResolver()

  private static let lineBreakScalars: Set<UnicodeScalar> = [
    "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}",
  ]

  static func render(
    _ string: String,
    indent: Int,
    indentSize: Int,
    allowBlock: Bool,
    preferredStyle: ValueScalarStyle? = nil,
    allowImplicitTyping: Bool = true,
    forceIndentIndicator: Bool = false,
    allowDocumentMarkerPrefix: Bool = false
  ) -> String {
    if let preferredStyle {
      return renderPreferred(
        string,
        indent: indent,
        indentSize: indentSize,
        allowBlock: allowBlock,
        style: preferredStyle,
        allowImplicitTyping: allowImplicitTyping,
        forceIndentIndicator: forceIndentIndicator,
        allowDocumentMarkerPrefix: allowDocumentMarkerPrefix
      )
    }
    if allowBlock, shouldUseBlock(string) {
      return renderBlockLiteral(
        string,
        indent: indent,
        indentSize: indentSize,
        indicator: "|",
        forceIndentIndicator: forceIndentIndicator
      )
    }
    if needsQuotes(
      string,
      allowImplicitTyping: allowImplicitTyping,
      allowDocumentMarkerPrefix: allowDocumentMarkerPrefix
    ) {
      return renderDoubleQuoted(string, indent: indent, indentSize: indentSize)
    }
    return string
  }

  private static func renderPreferred(
    _ string: String,
    indent: Int,
    indentSize: Int,
    allowBlock: Bool,
    style: ValueScalarStyle,
    allowImplicitTyping: Bool,
    forceIndentIndicator: Bool,
    allowDocumentMarkerPrefix: Bool
  ) -> String {
    switch style {
    case .plain:
      if string.isEmpty {
        return ""
      }
      if allowBlock, containsLineBreak(string) {
        return renderPlainMultiline(string, indent: indent, indentSize: indentSize)
      }
      if needsQuotes(
        string,
        allowImplicitTyping: allowImplicitTyping,
        allowDocumentMarkerPrefix: allowDocumentMarkerPrefix
      ) {
        if containsNonAscii(string) {
          return renderDoubleQuoted(string, indent: indent, indentSize: indentSize)
        }
        return renderSingleQuoted(string, indent: indent, indentSize: indentSize)
      }
      return string
    case .singleQuoted:
      return renderSingleQuoted(string, indent: indent, indentSize: indentSize)
    case .doubleQuoted:
      return renderDoubleQuoted(string, indent: indent, indentSize: indentSize)
    case .literal:
      if string.isEmpty {
        return "\"\""
      }
      if shouldPreferQuotedLiteral(string) {
        return renderDoubleQuoted(string, indent: indent, indentSize: indentSize)
      }
      guard allowBlock, isBlockRenderable(string) else {
        return renderDoubleQuoted(string, indent: indent, indentSize: indentSize)
      }
      return renderBlockLiteral(
        string,
        indent: indent,
        indentSize: indentSize,
        indicator: "|",
        forceIndentIndicator: forceIndentIndicator
      )
    case .folded:
      guard allowBlock, isBlockRenderable(string) else {
        return renderDoubleQuoted(string, indent: indent, indentSize: indentSize)
      }
      return renderBlockFolded(
        string,
        indent: indent,
        indentSize: indentSize,
        forceIndentIndicator: forceIndentIndicator
      )
    }
  }

  private static func shouldUseBlock(_ string: String) -> Bool {
    guard string.contains("\n") else { return false }
    guard let firstContent = firstContentLine(in: string) else {
      return false
    }
    if firstContent.first?.isWhitespace == true {
      return false
    }
    if containsTrailingWhitespace(string) {
      return false
    }
    return !containsBlockUnsafeScalar(string)
  }

  private static func isBlockRenderable(_ string: String) -> Bool {
    if containsBlockUnsafeScalar(string) {
      return false
    }
    return true
  }

  private static func needsQuotes(
    _ string: String,
    allowImplicitTyping: Bool,
    allowDocumentMarkerPrefix: Bool
  ) -> Bool {
    if string.isEmpty {
      return true
    }
    if string.first?.isWhitespace == true || string.last?.isWhitespace == true {
      return true
    }
    if string.contains("\t") {
      return true
    }
    if containsLineBreak(string) {
      return true
    }
    if hasDocumentMarkerPrefix(string, strict: !allowDocumentMarkerPrefix) {
      return true
    }
    if hasDisallowedLeadingIndicator(string) {
      return true
    }
    if containsAmbiguousIndicator(string) {
      return true
    }
    if !allowImplicitTyping, resolvesToNonString(string) {
      return true
    }
    if containsNonPrintable(string) {
      return true
    }
    return false
  }

  private static func containsAmbiguousIndicator(_ string: String) -> Bool {
    if hasLeadingIndicator(string) {
      return true
    }
    if containsKeySeparator(string) {
      return true
    }
    if containsCommentIndicator(string) {
      return true
    }
    return false
  }

  private static func hasLeadingIndicator(_ string: String) -> Bool {
    guard let first = string.first else { return false }
    if first == "-" || first == "?" || first == ":" {
      let nextIndex = string.index(after: string.startIndex)
      if nextIndex == string.endIndex {
        return true
      }
      return string[nextIndex].isWhitespace
    }
    return false
  }

  private static func hasDocumentMarkerPrefix(_ string: String, strict: Bool) -> Bool {
    if string.hasPrefix("---") {
      return strict || hasMarkerTerminator(string, prefixLength: 3)
    }
    if string.hasPrefix("...") {
      return strict || hasMarkerTerminator(string, prefixLength: 3)
    }
    return false
  }

  private static func hasMarkerTerminator(_ string: String, prefixLength: Int) -> Bool {
    let end = string.index(string.startIndex, offsetBy: prefixLength)
    if end == string.endIndex {
      return true
    }
    return string[end].isWhitespace
  }

  private static func hasDisallowedLeadingIndicator(_ string: String) -> Bool {
    guard let first = string.first else { return false }
    switch first {
    case "-", "?", ":":
      return hasLeadingIndicator(string)
    case ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`":
      return true
    default:
      return false
    }
  }

  private static func containsKeySeparator(_ string: String) -> Bool {
    var index = string.startIndex
    while index < string.endIndex {
      if string[index] == ":" {
        let next = string.index(after: index)
        if next < string.endIndex, string[next].isWhitespace {
          return true
        }
      }
      index = string.index(after: index)
    }
    return false
  }

  private static func containsCommentIndicator(_ string: String) -> Bool {
    var index = string.startIndex
    while index < string.endIndex {
      if string[index] == "#" {
        if index == string.startIndex {
          return true
        }
        let prev = string.index(before: index)
        if string[prev].isWhitespace {
          return true
        }
      }
      index = string.index(after: index)
    }
    return false
  }

  private static func resolvesToNonString(_ string: String) -> Bool {
    let scalar = YAMLScalar(text: string, style: .plain)
    let value = resolver.resolve(scalar, explicitTag: nil, wrapTag: false)
    if case .string = value {
      return false
    }
    return true
  }

  private static func containsLineBreak(_ string: String) -> Bool {
    for scalar in string.unicodeScalars where lineBreakScalars.contains(scalar) {
      return true
    }
    return false
  }

  private static func containsBlockUnsafeScalar(_ string: String) -> Bool {
    for scalar in string.unicodeScalars {
      if lineBreakScalars.contains(scalar) && scalar != "\n" {
        return true
      }
      if !isPrintable(scalar) {
        return true
      }
    }
    return false
  }

  private static func firstContentLine(in string: String) -> Substring? {
    let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines {
      if !line.isEmpty {
        return line
      }
    }
    return nil
  }

  private static func containsNonPrintable(_ string: String) -> Bool {
    for scalar in string.unicodeScalars where !isPrintable(scalar) {
      return true
    }
    return false
  }

  private static func containsNonAscii(_ string: String) -> Bool {
    for scalar in string.unicodeScalars where scalar.value > 0x7E {
      return true
    }
    return false
  }

  private static func containsTrailingWhitespace(_ string: String) -> Bool {
    let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines {
      guard let last = line.last else {
        continue
      }
      if last == " " || last == "\t" {
        return true
      }
    }
    return false
  }

  private static func shouldPreferQuotedLiteral(_ string: String) -> Bool {
    let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    var hasEmptyLine = false
    for index in lines.indices {
      let line = lines[index]
      if line.isEmpty {
        hasEmptyLine = true
        continue
      }
      if line.allSatisfy({ $0 == " " }) {
        let hasNonEmptyAfter = lines[lines.index(after: index)...].contains { !$0.isEmpty }
        if !hasNonEmptyAfter, !hasEmptyLine {
          return true
        }
      }
    }
    return false
  }

  private static func isPrintable(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x9, 0xA, 0xD:
      return true
    case 0x20...0x7E:
      return true
    case 0x85:
      return true
    case 0xA0...0xD7FF:
      return true
    case 0xE000...0xFFFD:
      return true
    case 0x10000...0x10FFFF:
      return true
    default:
      return false
    }
  }

  private static func renderBlockLiteral(_ string: String, indent: Int, indentSize: Int) -> String {
    renderBlockLiteral(string, indent: indent, indentSize: indentSize, indicator: "|", forceIndentIndicator: false)
  }

  private static func renderBlockLiteral(
    _ string: String,
    indent: Int,
    indentSize: Int,
    indicator: String,
    forceIndentIndicator: Bool
  ) -> String {
    renderBlockScalar(
      string,
      indent: indent,
      indentSize: indentSize,
      indicator: indicator,
      folded: false,
      forceIndentIndicator: forceIndentIndicator
    )
  }

  private static func renderBlockFolded(
    _ string: String,
    indent: Int,
    indentSize: Int,
    forceIndentIndicator: Bool
  ) -> String {
    renderBlockScalar(
      string,
      indent: indent,
      indentSize: indentSize,
      indicator: ">",
      folded: true,
      forceIndentIndicator: forceIndentIndicator
    )
  }

  private static func renderBlockScalar(
    _ string: String,
    indent: Int,
    indentSize: Int,
    indicator: String,
    folded: Bool,
    forceIndentIndicator: Bool
  ) -> String {
    let trailingNewlines = countTrailingNewlines(in: string)
    let body = trimTrailingNewlines(from: string, count: trailingNewlines)
    let chompIndicator: String
    if body.isEmpty, string.contains("\n") {
      chompIndicator = "+"
    } else {
      switch trailingNewlines {
      case 0:
        chompIndicator = "-"
      case 1:
        chompIndicator = ""
      default:
        chompIndicator = "+"
      }
    }

    let lines: [Substring]
    if body.isEmpty {
      lines = [Substring("")]
    } else {
      lines = body.split(separator: "\n", omittingEmptySubsequences: false)
    }

    var outputLines: [String] = []
    if folded {
      outputLines = foldedOutputLines(from: body)
    } else {
      outputLines = lines.map(String.init)
    }

    if trailingNewlines > 1 {
      outputLines.append(contentsOf: Array(repeating: "", count: trailingNewlines - 1))
    }

    let needsIndentIndicator: Bool = {
      for line in outputLines where !line.isEmpty {
        if line.first == " " || line.first == "#" || line.first == "\t" {
          return true
        }
        return false
      }
      return false
    }()
    let indentIndicator = (forceIndentIndicator || needsIndentIndicator) ? "\(indentSize)" : ""
    let header = "\(indicator)\(indentIndicator)\(chompIndicator)"

    let padding = String(repeating: " ", count: indent + indentSize)
    var result = "\(header)\n"
    for line in outputLines {
      if line.isEmpty {
        result.append("\n")
        continue
      }
      result.append(padding)
      result.append(line)
      result.append("\n")
    }
    return result
  }

  private static func renderSingleQuoted(_ string: String, indent: Int, indentSize: Int) -> String {
    let escaped = string.replacingOccurrences(of: "'", with: "''")
    guard escaped.contains("\n") else {
      return "'\(escaped)'"
    }
    let padding = String(repeating: " ", count: indent + indentSize)
    var result = "'"
    var index = escaped.startIndex
    while index < escaped.endIndex {
      if escaped[index] == "\n" {
        var run = 0
        while index < escaped.endIndex, escaped[index] == "\n" {
          run += 1
          index = escaped.index(after: index)
        }
        let emitCount = run + 1
        for _ in 0..<emitCount {
          result.append("\n")
          result.append(padding)
        }
        continue
      }
      result.append(escaped[index])
      index = escaped.index(after: index)
    }
    result.append("'")
    return result
  }

  private static func renderPlainMultiline(_ string: String, indent: Int, indentSize: Int) -> String {
    let lines = plainOutputLines(from: string)
    guard let first = lines.first else {
      return ""
    }
    let padding = String(repeating: " ", count: indent + indentSize)
    var result = first
    for line in lines.dropFirst() {
      result.append("\n")
      if !line.isEmpty {
        result.append(padding)
        result.append(line)
      }
    }
    return result
  }

  private static func foldedOutputLines(from string: String) -> [String] {
    guard !string.isEmpty else {
      return [""]
    }
    let parts = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var output: [String] = []
    var index = 0
    while index < parts.count, parts[index].isEmpty {
      output.append("")
      index += 1
    }
    guard index < parts.count else {
      return output
    }
    var previousLine = parts[index]
    output.append(previousLine)
    index += 1
    while index < parts.count {
      var emptyCount = 0
      while index < parts.count, parts[index].isEmpty {
        emptyCount += 1
        index += 1
      }
      guard index < parts.count else {
        if emptyCount > 0 {
          output.append(contentsOf: Array(repeating: "", count: emptyCount))
        }
        break
      }
      let currentLine = parts[index]
      let previousIndented = previousLine.first == " " || previousLine.first == "\t"
      let currentIndented = currentLine.first == " " || currentLine.first == "\t"
      let extra = (previousIndented || currentIndented) ? 0 : 1
      output.append(contentsOf: Array(repeating: "", count: emptyCount + extra))
      output.append(currentLine)
      previousLine = currentLine
      index += 1
    }
    return output
  }

  private static func plainOutputLines(from string: String) -> [String] {
    guard !string.isEmpty else {
      return [""]
    }
    let parts = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var output: [String] = []
    var index = 0
    while index < parts.count, parts[index].isEmpty {
      output.append("")
      index += 1
    }
    guard index < parts.count else {
      return output
    }
    output.append(parts[index])
    index += 1
    while index < parts.count {
      var emptyCount = 0
      while index < parts.count, parts[index].isEmpty {
        emptyCount += 1
        index += 1
      }
      guard index < parts.count else {
        if emptyCount > 0 {
          output.append(contentsOf: Array(repeating: "", count: emptyCount))
        }
        break
      }
      output.append(contentsOf: Array(repeating: "", count: emptyCount + 1))
      output.append(parts[index])
      index += 1
    }
    return output
  }

  private static func countTrailingNewlines(in string: String) -> Int {
    var count = 0
    var index = string.endIndex
    while index > string.startIndex {
      let prev = string.index(before: index)
      if string[prev] == "\n" {
        count += 1
        index = prev
      } else {
        break
      }
    }
    return count
  }

  private static func trimTrailingNewlines(from string: String, count: Int) -> String {
    guard count > 0 else { return string }
    var index = string.endIndex
    var remaining = count
    while remaining > 0 && index > string.startIndex {
      index = string.index(before: index)
      remaining -= 1
    }
    return String(string[..<index])
  }

  private static func renderDoubleQuoted(_ string: String, indent: Int, indentSize: Int) -> String {
    "\"\(renderDoubleQuotedSegment(string))\""
  }

  private static func renderDoubleQuotedSegment(_ string: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(string.count + 2)
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"":
        escaped.append("\\\"")
      case "\\":
        escaped.append("\\\\")
      case "\u{0}":
        escaped.append("\\0")
      case "\u{8}":
        escaped.append("\\b")
      case "\u{c}":
        escaped.append("\\f")
      case "\n":
        escaped.append("\\n")
      case "\r":
        escaped.append("\\r")
      case "\t":
        escaped.append("\\t")
      default:
        if lineBreakScalars.contains(scalar) {
          escaped.append(escapeScalar(scalar))
        } else if scalar.value > 0x7E {
          escaped.append(escapeScalar(scalar))
        } else if isPrintable(scalar) {
          escaped.append(String(scalar))
        } else {
          escaped.append(escapeScalar(scalar))
        }
      }
    }
    return escaped
  }

  private static func escapeScalar(_ scalar: UnicodeScalar) -> String {
    let value = scalar.value
    if value <= 0xFF {
      return "\\x\(hex(value, width: 2))"
    }
    if value <= 0xFFFF {
      return "\\u\(hex(value, width: 4))"
    }
    return "\\U\(hex(value, width: 8))"
  }

  private static func hex(_ value: UInt32, width: Int) -> String {
    let raw = String(value, radix: 16, uppercase: true)
    if raw.count >= width {
      return raw
    }
    return String(repeating: "0", count: width - raw.count) + raw
  }
}
