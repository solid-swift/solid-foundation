//
//  YAMLParser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation

struct YAMLParser {

  private struct Line {
    let number: Int
    let indent: Int
    let raw: String

    var content: String {
      String(raw.dropFirst(indent))
    }

    func contentStrippingComment() -> String {
      let withoutComment = Line.stripComment(from: content)
      return withoutComment
    }

    static func stripComment(from text: String) -> String {
      var inSingle = false
      var inDouble = false
      for (idx, char) in text.enumerated() {
        switch char {
        case "'" where !inDouble:
          inSingle.toggle()
        case "\"" where !inSingle:
          inDouble.toggle()
        case "#" where !inSingle && !inDouble:
          let cutIndex = text.index(text.startIndex, offsetBy: idx)
          return String(text[..<cutIndex])
        default:
          continue
        }
      }
      return text
    }
  }

  private var lines: [Line]
  private var index: Int = 0

  init(text: String) throws {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
    var parsed: [Line] = []
    parsed.reserveCapacity(rawLines.count)

    for (idx, rawLine) in rawLines.enumerated() {
      var indent = 0
      for char in rawLine {
        if char == " " {
          indent += 1
        } else if char == "\t" {
          throw YAML.Error.invalidIndentation
        } else {
          break
        }
      }
      parsed.append(Line(number: idx + 1, indent: indent, raw: String(rawLine)))
    }

    self.lines = parsed
  }

  mutating func parseFirstDocument() throws -> YAMLNode {
    let docs = try parseDocuments(limit: 1)
    guard let first = docs.first else {
      throw YAML.Error.invalidSyntax("No YAML content found")
    }
    return first
  }

  mutating func parseDocuments(limit: Int? = nil) throws -> [YAMLNode] {
    var documents: [YAMLNode] = []

    while index < lines.count && (limit == nil || documents.count < limit!) {
      skipEmptyLines()
      guard index < lines.count else { break }

      if isDocumentEnd(lines[index]) {
        index += 1
        continue
      }

      if isDocumentStart(lines[index]) {
        let content = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
        index += 1
        if !content.isEmpty {
          var inlineParser = InlineParser(text: content)
          let node = try parseInlineNode(parser: &inlineParser, baseIndent: 0)
          documents.append(node)
          continue
        }
      }

      guard index < lines.count else { break }
      let indent = lines[index].indent
      let node = try parseNode(expectedIndent: indent)
      documents.append(node)

      // Skip until the next document marker or end.
      while index < lines.count {
        if isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
          break
        }
        if !lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces).isEmpty {
          break
        }
        index += 1
      }
    }

    return documents
  }

  // MARK: - Core Parsing

  private mutating func parseNode(expectedIndent: Int) throws -> YAMLNode {
    guard index < lines.count else {
      throw YAML.Error.invalidSyntax("Unexpected end of document")
    }

    let line = lines[index]

    if line.indent < expectedIndent {
      throw YAML.Error.invalidIndentation
    }

    // Capture decorators before deciding shape.
    let decorated = parseDecorators(from: line.contentStrippingComment())
    let decorators = decorated.decorators
    let content = decorated.remainder.trimmingCharacters(in: .whitespaces)

    if content.hasPrefix("-") && line.indent == expectedIndent {
      return try parseBlockSequence(decorators: decorators, expectedIndent: expectedIndent, firstRemainder: decorated.remainder)
    }

    if splitMappingEntry(content) != nil, line.indent == expectedIndent {
      return try parseBlockMapping(decorators: decorators, expectedIndent: expectedIndent, firstRemainder: decorated.remainder)
    }

    if content.hasPrefix("[") || content.hasPrefix("{") {
      var inline = InlineParser(text: content)
      var node = try parseInlineNode(parser: &inline, baseIndent: expectedIndent)
      if decorators.tag != nil || decorators.anchor != nil {
        node = attach(node, tag: decorators.tag, anchor: decorators.anchor)
      }
      index += 1
      return node
    }

    if content.hasPrefix("|") || content.hasPrefix(">") {
      let node = try parseBlockScalar(content: content, decorators: decorators, baseIndent: expectedIndent)
      return node
    }

    var inlineParser = InlineParser(text: content)
    var node = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent)
    if decorators.tag != nil || decorators.anchor != nil {
      node = attach(node, tag: decorators.tag, anchor: decorators.anchor)
    }
    index += 1
    return node
  }

  private mutating func parseBlockSequence(decorators: Decorators, expectedIndent: Int, firstRemainder: String?) throws -> YAMLNode {
    var items: [YAMLNode] = []
    var initialRemainder = firstRemainder

    while index < lines.count {
      let line = lines[index]
      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let decorated = parseDecorators(from: sourceContent)
      let currentDecorators = decorated.decorators
      let content = decorated.remainder
      if line.indent != expectedIndent || !content.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
        break
      }

      // Move past '-'
      guard let dashIndex = content.firstIndex(of: "-") else { break }
      let afterDash = content[content.index(after: dashIndex)...]
      let remainder = String(afterDash).trimmingCharacters(in: .whitespaces)
      index += 1

      if remainder.isEmpty {
        skipEmptyLines()
        let node = try parseNode(expectedIndent: expectedIndent + 2)
        let decoratedNode = attach(node, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
        items.append(decoratedNode)
      } else {
        var inline = InlineParser(text: remainder)
        var node = try parseInlineNode(parser: &inline, baseIndent: expectedIndent + 2)
        node = attach(node, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
        items.append(node)
      }
      initialRemainder = nil
    }

    return attach(.sequence(items, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseBlockMapping(decorators: Decorators, expectedIndent: Int, firstRemainder: String?) throws -> YAMLNode {
    var pairs: [(YAMLNode, YAMLNode)] = []
    var initialRemainder = firstRemainder

    while index < lines.count {
      let line = lines[index]
      if line.indent != expectedIndent {
        break
      }

      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let decorated = parseDecorators(from: sourceContent)
      let entryDecorators = decorated.decorators
      let content = decorated.remainder
      guard let entry = splitMappingEntry(content) else { break }

      var keyParser = InlineParser(text: entry.key.trimmingCharacters(in: .whitespaces))
      var keyNode = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
      keyNode = attach(keyNode, tag: entryDecorators.tag, anchor: entryDecorators.anchor)

      index += 1

      if let inlineValue = entry.value, !inlineValue.trimmingCharacters(in: .whitespaces).isEmpty {
        var valueParser = InlineParser(text: inlineValue.trimmingCharacters(in: .whitespaces))
        let valueNode = try parseInlineNode(parser: &valueParser, baseIndent: expectedIndent + 1)
        pairs.append((keyNode, valueNode))
      } else {
        skipEmptyLines()
        let valueNode = try parseNode(expectedIndent: expectedIndent + 2)
        pairs.append((keyNode, valueNode))
      }
      initialRemainder = nil
    }

    return attach(.mapping(pairs, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseBlockScalar(content: String, decorators: Decorators, baseIndent: Int) throws -> YAMLNode {
    guard let indicator = content.first else {
      throw YAML.Error.invalidSyntax("Invalid block scalar indicator on line \(lines[index].number)")
    }

    var chomp: YAMLScalarChomp = .clip
    var indentIndicator: Int?
    var idx = content.index(after: content.startIndex)
    while idx < content.endIndex {
      let char = content[idx]
      if char == "+" {
        chomp = .keep
        idx = content.index(after: idx)
      } else if char == "-" {
        chomp = .strip
        idx = content.index(after: idx)
      } else if char.isWholeNumber {
        indentIndicator = Int(String(char))
        idx = content.index(after: idx)
      } else if char == " " {
        idx = content.index(after: idx)
      } else {
        break
      }
    }

    let requiredIndent = (indentIndicator ?? 0) == 0 ? baseIndent + 1 : baseIndent + (indentIndicator ?? 1)
    index += 1

    var captured: [(line: String, indent: Int)] = []
    while index < lines.count {
      let line = lines[index]
      if line.indent < requiredIndent {
        break
      }
      let raw = line.raw
      let start = raw.index(raw.startIndex, offsetBy: min(requiredIndent, raw.count))
      let text = String(raw[start...])
      captured.append((text, line.indent))
      index += 1
    }

    let scalarText: String
    switch indicator {
    case "|":
      scalarText = joinLiteralLines(captured, chomp: chomp)
    case ">":
      scalarText = joinFoldedLines(captured, baseIndent: requiredIndent, chomp: chomp)
    default:
      throw YAML.Error.invalidSyntax("Unknown block scalar indicator on line \(lines[index].number)")
    }

    let style: YAMLScalarStyle = indicator == "|" ? .literal(chomp: chomp, indent: indentIndicator) : .folded(chomp: chomp, indent: indentIndicator)
    let scalar = YAMLScalar(text: scalarText, style: style)
    return attach(.scalar(scalar, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
  }

  // MARK: - Inline Parsing

  private mutating func parseInlineNode(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    parser.skipWhitespaceAndComments()
    let decorators = parser.parseDecorators()

    parser.skipWhitespaceAndComments()
    guard let current = parser.peek else {
      throw YAML.Error.invalidSyntax("Unexpected end of scalar")
    }

    let node: YAMLNode
    if current == "[" {
      node = try parseFlowSequence(parser: &parser, baseIndent: baseIndent)
    } else if current == "{" {
      node = try parseFlowMapping(parser: &parser, baseIndent: baseIndent)
    } else if current == "\"" {
      let text = try parser.parseDoubleQuoted()
      node = .scalar(.init(text: text, style: .doubleQuoted), tag: nil, anchor: nil)
    } else if current == "'" {
      let text = try parser.parseSingleQuoted()
      node = .scalar(.init(text: text, style: .singleQuoted), tag: nil, anchor: nil)
    } else if current == "*" {
      let alias = try parser.parseAlias()
      node = .alias(alias)
    } else {
      let text = parser.parsePlainScalar()
      node = .scalar(.init(text: text, style: .plain), tag: nil, anchor: nil)
    }

    return attach(node, tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseFlowSequence(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    parser.consume(expected: "[")
    parser.skipWhitespaceAndComments()

    var items: [YAMLNode] = []
    while let current = parser.peek {
      if current == "]" {
        parser.consume(expected: "]")
        break
      }

      var valueParser = parser
      let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent)
      parser = valueParser
      items.append(value)

      parser.skipWhitespaceAndComments()
      if parser.consumeIf(",") {
        parser.skipWhitespaceAndComments()
        continue
      }
      if parser.consumeIf("]") {
        break
      }
    }

    return .sequence(items, tag: nil, anchor: nil)
  }

  private mutating func parseFlowMapping(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    parser.consume(expected: "{")
    parser.skipWhitespaceAndComments()
    var pairs: [(YAMLNode, YAMLNode)] = []

    while let current = parser.peek {
      if current == "}" {
        parser.consume(expected: "}")
        break
      }

      var keyParser = parser
      let key = try parseInlineNode(parser: &keyParser, baseIndent: baseIndent)
      parser = keyParser

      parser.skipWhitespaceAndComments()
      parser.consume(expected: ":")
      parser.skipWhitespaceAndComments()

      var valueParser = parser
      let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent)
      parser = valueParser

      pairs.append((key, value))

      parser.skipWhitespaceAndComments()
      if parser.consumeIf(",") {
        parser.skipWhitespaceAndComments()
        continue
      }
      if parser.consumeIf("}") {
        break
      }
    }

    return .mapping(pairs, tag: nil, anchor: nil)
  }

  // MARK: - Utilities

  private func joinLiteralLines(_ lines: [(line: String, indent: Int)], chomp: YAMLScalarChomp) -> String {
    var text = lines.map { $0.line }.joined(separator: "\n")
    switch chomp {
    case .clip:
      if !text.isEmpty {
        text.append("\n")
      }
    case .keep:
      if !text.hasSuffix("\n") {
        text.append("\n")
      }
    case .strip:
      while text.last == "\n" {
        text.removeLast()
      }
    }
    return text
  }

  private func joinFoldedLines(_ lines: [(line: String, indent: Int)], baseIndent: Int, chomp: YAMLScalarChomp) -> String {
    var result = ""
    var previousIndented = false
    var first = true

    for entry in lines {
      let line = entry.line
      let isIndented = entry.indent > baseIndent
      if first {
        result.append(line)
        first = false
        previousIndented = isIndented
        continue
      }

      if line.isEmpty {
        result.append("\n")
        previousIndented = false
        continue
      }

      if previousIndented || isIndented {
        result.append("\n")
      } else {
        result.append(" ")
      }

      result.append(line)
      previousIndented = isIndented
    }

    switch chomp {
    case .clip:
      if !result.isEmpty {
        result.append("\n")
      }
    case .keep:
      if !result.hasSuffix("\n") {
        result.append("\n")
      }
    case .strip:
      while result.last == "\n" {
        result.removeLast()
      }
    }

    return result
  }

  private mutating func skipEmptyLines() {
    while index < lines.count {
      let content = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
      if content.isEmpty {
        index += 1
      } else {
        break
      }
    }
  }

  private func isDocumentStart(_ line: Line) -> Bool {
    line.contentStrippingComment().trimmingCharacters(in: .whitespaces).hasPrefix("---")
  }

  private func isDocumentEnd(_ line: Line) -> Bool {
    line.contentStrippingComment().trimmingCharacters(in: .whitespaces).hasPrefix("...")
  }

  fileprivate struct Decorators {
    let tag: String?
    let anchor: String?
  }

  private func parseDecorators(from content: String) -> (decorators: Decorators, remainder: String) {
    var scanner = InlineParser(text: content)
    let decorators = scanner.parseDecorators()
    scanner.skipWhitespaceAndComments()
    let remainder = scanner.remaining
    return (decorators, remainder)
  }

  private func attach(_ node: YAMLNode, tag: String?, anchor: String?) -> YAMLNode {
    guard tag != nil || anchor != nil else { return node }
    switch node {
    case .scalar(let scalar, let existingTag, let existingAnchor):
      return .scalar(scalar, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .sequence(let array, let existingTag, let existingAnchor):
      return .sequence(array, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .mapping(let map, let existingTag, let existingAnchor):
      return .mapping(map, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .alias:
      return node
    }
  }

  private func splitMappingEntry(_ content: String) -> (key: String, value: String?)? {
    var inSingle = false
    var inDouble = false
    var depth = 0
    for (idx, char) in content.enumerated() {
      switch char {
      case "'" where !inDouble:
        inSingle.toggle()
      case "\"" where !inSingle:
        inDouble.toggle()
      case "[" where !inSingle && !inDouble:
        depth += 1
      case "]" where !inSingle && !inDouble:
        depth = max(0, depth - 1)
      case "{" where !inSingle && !inDouble:
        depth += 1
      case "}" where !inSingle && !inDouble:
        depth = max(0, depth - 1)
      case ":" where !inSingle && !inDouble && depth == 0:
        let keyPart = String(content.prefix(idx))
        let valueStart = content.index(content.startIndex, offsetBy: idx + 1)
        let valuePart = content[valueStart...]
        return (keyPart, valuePart.isEmpty ? nil : String(valuePart))
      default:
        continue
      }
    }
    return nil
  }
}

// MARK: - Inline Parser

private struct InlineParser {

  private(set) var text: String
  private var index: String.Index

  init(text: String) {
    self.text = text
    self.index = text.startIndex
  }

  var peek: Character? {
    guard index < text.endIndex else { return nil }
    return text[index]
  }

  var remaining: String {
    String(text[index...])
  }

  mutating func skipWhitespaceAndComments() {
    while index < text.endIndex {
      let char = text[index]
      if char == "#" {
        // comment to end of line
        index = text.endIndex
        break
      } else if char.isWhitespace {
        text.formIndex(after: &index)
        continue
      } else {
        break
      }
    }
  }

  mutating func parseDecorators() -> YAMLParser.Decorators {
    skipWhitespaceAndComments()
    var tag: String?
    var anchor: String?

    while let current = peek {
      if current == "!" {
        tag = parseTag()
      } else if current == "&" {
        anchor = parseAnchor()
      } else {
        break
      }
      skipWhitespaceAndComments()
    }

    return YAMLParser.Decorators(tag: tag, anchor: anchor)
  }

  mutating func parseTag() -> String {
    consume(expected: "!")
    var buffer = "!"
    while let current = peek {
      if current.isWhitespace {
        break
      }
      buffer.append(current)
      text.formIndex(after: &index)
    }
    return buffer
  }

  mutating func parseAnchor() -> String {
    consume(expected: "&")
    var buffer = ""
    while let current = peek {
      if current.isWhitespace {
        break
      }
      buffer.append(current)
      text.formIndex(after: &index)
    }
    return buffer
  }

  mutating func parseAlias() throws -> String {
    consume(expected: "*")
    var buffer = ""
    while let current = peek {
      if current.isWhitespace || current == "," || current == "]" || current == "}" {
        break
      }
      buffer.append(current)
      text.formIndex(after: &index)
    }
    if buffer.isEmpty {
      throw YAML.Error.invalidSyntax("Alias without name")
    }
    return buffer
  }

  mutating func parseDoubleQuoted() throws -> String {
    consume(expected: "\"")
    var output = ""
    while let current = peek {
      text.formIndex(after: &index)
      if current == "\"" {
        return output
      }
      if current == "\\" {
        guard let escaped = peek else { throw YAML.Error.invalidSyntax("Invalid escape sequence") }
        output.append(try decodeEscape(escaped))
        text.formIndex(after: &index)
      } else {
        output.append(current)
      }
    }
    throw YAML.Error.invalidSyntax("Unterminated double-quoted scalar")
  }

  mutating func parseSingleQuoted() throws -> String {
    consume(expected: "'")
    var output = ""
    while let current = peek {
      text.formIndex(after: &index)
      if current == "'" {
        if peek == "'" {
          // escaped single quote
          output.append("'")
          text.formIndex(after: &index)
          continue
        }
        return output
      }
      output.append(current)
    }
    throw YAML.Error.invalidSyntax("Unterminated single-quoted scalar")
  }

  mutating func parsePlainScalar() -> String {
    var output = ""
    while let current = peek {
      if current == "," || current == "]" || current == "}" || current == "#" {
        break
      }
      if current.isNewline {
        break
      }
      output.append(current)
      text.formIndex(after: &index)
    }
    return output.trimmingCharacters(in: .whitespaces)
  }

  mutating func consumeIf(_ char: Character) -> Bool {
    guard peek == char else { return false }
    consume(expected: char)
    return true
  }

  mutating func consume(expected: Character) {
    guard peek == expected else { return }
    text.formIndex(after: &index)
  }

  private mutating func decodeEscape(_ char: Character) throws -> Character {
    switch char {
    case "\"": return "\""
    case "\\": return "\\"
    case "/": return "/"
    case "b": return "\u{08}"
    case "f": return "\u{0C}"
    case "n": return "\n"
    case "r": return "\r"
    case "t": return "\t"
    case "0": return "\u{00}"
    case "a": return "\u{07}"
    case "v": return "\u{0B}"
    case "e": return "\u{1B}"
    case "x":
      let code = try readHex(count: 2)
      guard let scalar = UnicodeScalar(code) else { throw YAML.Error.invalidSyntax("Invalid hex escape") }
      return Character(scalar)
    case "u":
      let code = try readHex(count: 4)
      guard let scalar = UnicodeScalar(code) else { throw YAML.Error.invalidSyntax("Invalid unicode escape") }
      return Character(scalar)
    case "U":
      let code = try readHex(count: 8)
      guard let scalar = UnicodeScalar(code) else { throw YAML.Error.invalidSyntax("Invalid unicode escape") }
      return Character(scalar)
    default:
      throw YAML.Error.invalidSyntax("Unknown escape sequence")
    }
  }

  private mutating func readHex(count: Int) throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<count {
      guard let current = peek else {
        throw YAML.Error.invalidSyntax("Incomplete escape sequence")
      }
      guard let digit = current.hexDigitValue else {
        throw YAML.Error.invalidSyntax("Invalid hex digit")
      }
      value = (value << 4) | UInt32(digit)
      text.formIndex(after: &index)
    }
    return value
  }
}
