//
//  YAMLStringEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/14/26.
//

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

    let utf8 = string.utf8
    let firstByte = utf8[utf8.startIndex]

    // Check leading whitespace (space, tab, and other whitespace bytes)
    if firstByte == 0x20 || firstByte == 0x09 || firstByte == 0x0A || firstByte == 0x0D {
      return true
    }
    // Check trailing whitespace
    let lastByte = utf8[utf8.index(before: utf8.endIndex)]
    if lastByte == 0x20 || lastByte == 0x09 || lastByte == 0x0A || lastByte == 0x0D {
      return true
    }

    // Check disallowed leading indicators (all single-byte ASCII)
    switch firstByte {
    case 0x2C, 0x5B, 0x5D, 0x7B, 0x7D, 0x23, 0x26, 0x2A, 0x21, 0x7C, 0x3E, 0x27, 0x22, 0x25, 0x40, 0x60:
      // , [ ] { } # & * ! | > ' " % @ `
      return true
    case 0x2D, 0x3F, 0x3A: // - ? :
      let nextIdx = utf8.index(after: utf8.startIndex)
      if nextIdx == utf8.endIndex { return true }
      let next = utf8[nextIdx]
      if next == 0x20 || next == 0x09 || next == 0x0A || next == 0x0D { return true }
    default:
      break
    }

    // Check document marker prefix (--- or ...)
    if utf8.count >= 3 {
      let i0 = utf8.startIndex
      let i1 = utf8.index(after: i0)
      let i2 = utf8.index(after: i1)
      let b0 = utf8[i0], b1 = utf8[i1], b2 = utf8[i2]
      if (b0 == 0x2D && b1 == 0x2D && b2 == 0x2D) || // ---
        (b0 == 0x2E && b1 == 0x2E && b2 == 0x2E)
      { // ...
        let strict = !allowDocumentMarkerPrefix
        let i3 = utf8.index(after: i2)
        if strict || i3 == utf8.endIndex ||
          utf8[i3] == 0x20 || utf8[i3] == 0x09
        {
          return true
        }
      }
    }

    // Single pass over UTF-8 bytes: check for tabs, line breaks, non-printable,
    // key separator (": "), comment indicator (" #")
    var prevByte: UInt8 = firstByte
    var idx = utf8.index(after: utf8.startIndex)
    while idx < utf8.endIndex {
      let byte = utf8[idx]

      if byte < 0x80 {
        // ASCII fast path
        if byte == 0x09 { return true } // tab
        if byte == 0x0A || byte == 0x0D { return true } // line break
        if byte < 0x20 { return true } // non-printable control char
        if byte == 0x7F { return true } // DEL

        // Context-sensitive: " #" (comment indicator)
        if byte == 0x23 && (prevByte == 0x20 || prevByte == 0x09) { return true }
        // Context-sensitive: ": " (key separator)
        if prevByte == 0x3A && (byte == 0x20 || byte == 0x09) { return true }

        prevByte = byte
        idx = utf8.index(after: idx)
      } else {
        // Non-ASCII: decode scalar via shared String.Index
        let scalar = string.unicodeScalars[idx]

        // Non-ASCII line breaks: NEL (U+0085), LS (U+2028), PS (U+2029)
        if scalar.value == 0x85 || scalar.value == 0x2028 || scalar.value == 0x2029 {
          return true
        }
        if !isPrintable(scalar) { return true }

        let nextScalarIdx = string.unicodeScalars.index(after: idx)
        prevByte = utf8[utf8.index(before: nextScalarIdx)]
        idx = nextScalarIdx
      }
    }

    if !allowImplicitTyping, resolvesToNonString(string) {
      return true
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
    let utf8 = string.utf8
    // Fast ASCII check for \n and \r (covers vast majority of cases)
    for byte in utf8 {
      if byte == 0x0A || byte == 0x0D { return true }
    }
    // Non-ASCII line breaks: NEL U+0085 (C2 85), LS U+2028 (E2 80 A8), PS U+2029 (E2 80 A9)
    // Only check if their lead bytes are present
    if utf8.contains(where: { $0 == 0xC2 || $0 == 0xE2 }) {
      for scalar in string.unicodeScalars {
        if scalar.value == 0x85 || scalar.value == 0x2028 || scalar.value == 0x2029 {
          return true
        }
      }
    }
    return false
  }

  private static func containsBlockUnsafeScalar(_ string: String) -> Bool {
    let utf8 = string.utf8
    var idx = utf8.startIndex
    while idx < utf8.endIndex {
      let byte = utf8[idx]
      if byte < 0x80 {
        // ASCII: non-\n line break (\r = 0x0D) or non-printable control chars
        if byte == 0x0D { return true }
        if byte < 0x20 && byte != 0x09 && byte != 0x0A { return true }
        if byte == 0x7F { return true }
        idx = utf8.index(after: idx)
      } else {
        let scalar = string.unicodeScalars[idx]
        // Non-\n line breaks: NEL (U+0085), LS (U+2028), PS (U+2029)
        if scalar.value == 0x85 || scalar.value == 0x2028 || scalar.value == 0x2029 {
          return true
        }
        if !isPrintable(scalar) { return true }
        idx = string.unicodeScalars.index(after: idx)
      }
    }
    return false
  }

  private static func firstContentLine(in string: String) -> Substring? {
    let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines where !line.isEmpty {
      return line
    }
    return nil
  }

  private static func containsNonPrintable(_ string: String) -> Bool {
    let utf8 = string.utf8
    var idx = utf8.startIndex
    while idx < utf8.endIndex {
      let byte = utf8[idx]
      if byte < 0x80 {
        // ASCII printability: 0x09, 0x0A, 0x0D, 0x20-0x7E are printable
        if byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D { return true }
        if byte == 0x7F { return true }
        idx = utf8.index(after: idx)
      } else {
        let scalar = string.unicodeScalars[idx]
        if !isPrintable(scalar) { return true }
        idx = string.unicodeScalars.index(after: idx)
      }
    }
    return false
  }

  private static func containsNonAscii(_ string: String) -> Bool {
    for byte in string.utf8 where byte > 0x7E {
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
      guard string[prev] == "\n" else {
        break
      }
      count += 1
      index = prev
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
