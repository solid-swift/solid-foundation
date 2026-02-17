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
    let hasTabIndent: Bool
    let strippedComment: String
    /// Cached: strippedComment with leading+trailing ASCII whitespace removed.
    let trimmedContent: String

    init(number: Int, indent: Int, raw: String, hasTabIndent: Bool) {
      self.number = number
      self.indent = indent
      self.raw = raw
      self.hasTabIndent = hasTabIndent
      let content = String(raw.dropFirst(indent))
      let stripped = Line.stripComment(from: content)
      self.strippedComment = stripped
      self.trimmedContent = stripped.yamlTrimmed()
    }

    var content: String {
      String(raw.dropFirst(indent))
    }

    func contentStrippingComment() -> String {
      strippedComment
    }

    static func stripComment(from text: String) -> String {
      // Fast path: no '#' means no comment possible
      guard text.utf8.contains(UInt8(ascii: "#")) else { return text }

      var inSingle = false
      var inDouble = false
      var prevWasWhitespace = true
      var scalarIdx = text.startIndex
      for char in text {
        switch char {
        case "'" where !inDouble:
          inSingle.toggle()
        case "\"" where !inSingle:
          inDouble.toggle()
        case "#" where !inSingle && !inDouble && prevWasWhitespace:
          return String(text[..<scalarIdx])
        default:
          break
        }
        prevWasWhitespace = char.isWhitespace
        scalarIdx = text.index(after: scalarIdx)
      }
      return text
    }
  }

  private var lines: [Line]
  private var index: Int = 0
  private static let defaultTagHandles: [String: String] = [
    "!": "!",
    "!!": "tag:yaml.org,2002:",
  ]
  private var tagHandles: [String: String] = YAMLParser.defaultTagHandles
  private var allowDirectives: Bool
  private var requireDocumentStart: Bool
  private let allowIncompleteInput: Bool

  init(
    text: String,
    allowIncompleteInput: Bool = false,
    allowDirectives: Bool = true,
    requireDocumentStart: Bool = false
  ) throws {
    let normalized = Self.normalizeCRLF(text)
    let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
    var parsed: [Line] = []
    parsed.reserveCapacity(rawLines.count)

    for (idx, rawLine) in rawLines.enumerated() {
      var indent = 0
      var hasTabIndent = false
      for char in rawLine {
        if char == " " {
          indent += 1
        } else if char == "\t" {
          indent += 1
          hasTabIndent = true
        } else {
          break
        }
      }
      parsed.append(Line(number: idx + 1, indent: indent, raw: String(rawLine), hasTabIndent: hasTabIndent))
    }

    self.lines = parsed
    self.allowIncompleteInput = allowIncompleteInput
    self.allowDirectives = allowDirectives
    self.requireDocumentStart = requireDocumentStart
  }

  /// Single-pass CRLF normalization: handles both `\r\n` and lone `\r`.
  private static func normalizeCRLF(_ text: String) -> String {
    guard text.utf8.contains(UInt8(ascii: "\r")) else { return text }
    var result = ""
    result.reserveCapacity(text.count)
    var iterator = text.makeIterator()
    while let ch = iterator.next() {
      if ch == "\r" {
        result.append("\n")
        // Skip the \n in a \r\n pair
        var peeked = iterator.next()
        if let next = peeked, next != "\n" {
          result.append(next)
        }
        if peeked == nil { break }
      } else {
        result.append(ch)
      }
    }
    return result
  }

  private func lineNumber(for lineIndex: Int) -> Int {
    guard !lines.isEmpty else { return 1 }
    if lineIndex >= 0 && lineIndex < lines.count {
      return lines[lineIndex].number
    }
    return lines.last?.number ?? 1
  }

  private func defaultColumn(for lineIndex: Int) -> Int {
    guard !lines.isEmpty else { return 1 }
    if lineIndex >= 0 && lineIndex < lines.count {
      return max(1, lines[lineIndex].indent + 1)
    }
    if let last = lines.last {
      return max(1, last.raw.count + 1)
    }
    return 1
  }

  private func location(lineIndex: Int, column: Int? = nil) -> YAML.ParseError.Location {
    YAML.ParseError.Location(
      line: lineNumber(for: lineIndex),
      column: column ?? defaultColumn(for: lineIndex)
    )
  }

  private func syntaxError(_ message: String, lineIndex: Int? = nil, column: Int? = nil) -> YAML.ParseError {
    let targetIndex = lineIndex ?? index
    return .invalidSyntax(message, location: location(lineIndex: targetIndex, column: column))
  }

  private func indentationError(lineIndex: Int? = nil, column: Int? = nil) -> YAML.ParseError {
    let targetIndex = lineIndex ?? index
    return .invalidIndentation(location: location(lineIndex: targetIndex, column: column))
  }

  private func incompleteError(lineIndex: Int? = nil, column: Int? = nil) -> YAML.ParseError {
    let targetIndex = lineIndex ?? index
    return .incompleteInput(location: location(lineIndex: targetIndex, column: column))
  }

  private func trimLeadingWhitespace(_ text: String) -> (trimmed: String, offset: Int) {
    var cursor = text.startIndex
    var offset = 0
    while cursor < text.endIndex, text[cursor].isWhitespace {
      text.formIndex(after: &cursor)
      offset += 1
    }
    return (String(text[cursor...]), offset)
  }

  mutating func parseFirstDocument() throws -> YAMLNode {
    let docs = try parseDocuments()
    if let first = docs.first {
      return first
    }
    return .emptyPlainScalar
  }

  mutating func parseDocuments(limit: Int? = nil) throws -> [YAMLNode] {
    try parseDocumentStream(limit: limit).map { $0.node }
  }

  // MARK: - Directive Parsing

  /// Parses %YAML and %TAG directives, document-end markers, and returns whether any directives were seen.
  /// On return, `index` points at the first non-directive, non-empty, non-document-end line.
  private mutating func parseDirectives(
    allowDirectives: inout Bool,
    requireDocumentStart: Bool,
    pendingTagHandles: inout [String: String]
  ) throws -> Bool {
    var sawDirective = false
    var sawYamlDirective = false
    skipEmptyLines()
    if requireDocumentStart, index < lines.count {
      let trimmed = lines[index].trimmedContent
      if !isDocumentStart(lines[index]), !isDocumentEnd(lines[index]), !trimmed.hasPrefix("%") {
        throw syntaxError("Missing document start marker")
      }
    }
    while index < lines.count {
      let content = lines[index].trimmedContent
      if content.hasPrefix("...") && content != "..." {
        let idx = content.index(content.startIndex, offsetBy: 3)
        if idx < content.endIndex, content[idx].isWhitespace {
          throw syntaxError("Invalid document end marker")
        }
      }
      if isDocumentEnd(lines[index]) {
        allowDirectives = true
        index += 1
        skipEmptyLines()
        continue
      }
      if content.hasPrefix("%") {
        if !allowDirectives {
          throw syntaxError("Directive without document end marker")
        }
        sawDirective = true
        let directive = lines[index].trimmedContent
        let parts = directive.split(whereSeparator: { $0.isWhitespace })
        if let name = parts.first, name == "%YAML" {
          if sawYamlDirective {
            throw syntaxError("Duplicate %YAML directive")
          }
          if parts.count != 2 || parts[0] != "%YAML" {
            throw syntaxError("Invalid %YAML directive")
          }
          let version = parts[1]
          let versionParts = version.split(separator: ".")
          if versionParts.count != 2
            || versionParts.contains(where: { $0.isEmpty || $0.contains(where: { !$0.isNumber }) })
          {
            throw syntaxError("Invalid %YAML directive")
          }
          sawYamlDirective = true
        } else if let name = parts.first, name == "%TAG" {
          if parts.count != 3 || parts[0] != "%TAG" {
            throw syntaxError("Invalid %TAG directive")
          }
          let handle = String(parts[1])
          let prefix = String(parts[2])
          if handle != "!" {
            if !handle.hasPrefix("!") || !handle.hasSuffix("!") || handle.count < 2 {
              throw syntaxError("Invalid %TAG directive")
            }
          }
          if prefix.isEmpty {
            throw syntaxError("Invalid %TAG directive")
          }
          pendingTagHandles[handle] = prefix
        }
        index += 1
        continue
      }
      break
    }
    skipEmptyLines()
    return sawDirective
  }

  /// Parses the content that appears after `---` on a document start line.
  /// Returns the parsed node, or nil if the remainder was empty (caller should fall through to parseNode).
  private mutating func parseDocumentStartContent(
    explicitStart: Bool,
    pendingTagHandles: inout [String: String]
  ) throws -> YAMLNode? {
    let line = lines[index]
    let content = line.contentStrippingComment()
    var cursor = content.startIndex
    while cursor < content.endIndex, content[cursor].isWhitespace {
      content.formIndex(after: &cursor)
    }
    if content[cursor...].hasPrefix("---") {
      cursor = content.index(cursor, offsetBy: 3)
    }
    while cursor < content.endIndex, content[cursor].isWhitespace {
      content.formIndex(after: &cursor)
    }
    let remainder = String(content[cursor...])
    let remainderColumn = line.indent + 1 + content.distance(from: content.startIndex, to: cursor)

    if !remainder.isEmpty {
      let decorated = try parseDecorators(from: remainder, lineIndex: index, baseColumn: remainderColumn)
      let trimmedLeading = trimLeadingWhitespace(decorated.remainder)
      let trimmed = trimmedLeading.trimmed.yamlTrimmed()
      let trimmedColumn = decorated.remainderColumn + trimmedLeading.offset
      if trimmed.isEmpty {
        index += 1
        skipEmptyLines()
        guard index < lines.count else {
          throw allowIncompleteInput ? incompleteError() : syntaxError("Unexpected end of document")
        }
        let indent = lines[index].indent
        var node = try parseNode(expectedIndent: indent)
        node = try attach(node, tag: decorated.decorators.tag, anchor: decorated.decorators.anchor)
        return node
      }
      if splitMappingEntry(trimmed) != nil {
        throw syntaxError("Invalid document start content")
      }
      if trimmed.hasPrefix("|") || trimmed.hasPrefix(">") {
        let node = try parseBlockScalar(content: trimmed, decorators: decorated.decorators, baseIndent: -1)
        return node
      }
      let startIndex = index
      var inlineText = trimmed
      var extraLines = 0
      var lineStartColumns = [trimmedColumn]
      if inlineText.first == "[" || inlineText.first == "{" {
        let flow = try collectFlowText(
          startIndex: startIndex,
          firstContent: decorated.remainder,
          firstColumn: decorated.remainderColumn,
          minimumIndent: leadingSpaceCount(lines[startIndex].raw)
        )
        inlineText = flow.text
        extraLines = flow.linesConsumed - 1
        lineStartColumns = flow.lineStartColumns
      } else if inlineText.first == "\"" {
        let expanded = try expandDoubleQuotedInlineText(
          inlineText,
          startIndex: startIndex,
          parentIndent: 0,
          firstColumn: trimmedColumn
        )
        inlineText = expanded.text
        extraLines = expanded.extraLines
        lineStartColumns = expanded.lineStartColumns
      } else if inlineText.first == "'" {
        let expanded = try expandSingleQuotedInlineText(
          inlineText,
          startIndex: startIndex,
          parentIndent: 0,
          firstColumn: trimmedColumn
        )
        inlineText = expanded.text
        extraLines = expanded.extraLines
        lineStartColumns = expanded.lineStartColumns
      }
      var inlineParser = InlineParser(
        text: inlineText,
        baseLine: line.number,
        lineStartColumns: lineStartColumns
      )
      let inlineStart = inlineParser.location()
      var node = try parseInlineNode(parser: &inlineParser, baseIndent: 0)
      node = try attach(node, tag: decorated.decorators.tag, anchor: decorated.decorators.anchor)
      inlineParser.skipWhitespaceAndComments()
      if inlineParser.peek != nil {
        throw inlineParser.syntaxError("Unexpected trailing content")
      }
      var linesConsumed = 1 + extraLines
      if case .scalar(let scalar, let tag, let anchor) = node,
        case .plain = scalar.style
      {
        try validatePlainScalarText(scalar.text, location: inlineStart)
        let folded = foldPlainScalarFromInline(initial: scalar.text, startIndex: startIndex, contextIndent: 0)
        if folded.linesConsumed > 0 {
          try validatePlainScalarText(folded.text, location: inlineStart)
          let updated = YAMLScalar(text: folded.text, style: .plain)
          node = .scalar(updated, tag: tag, anchor: anchor)
          linesConsumed += folded.linesConsumed
        }
      }
      index += linesConsumed
      return node
    }

    // Empty remainder after `---`
    index += 1
    skipEmptyLines()
    if index >= lines.count || isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
      return .emptyPlainScalar
    }
    return nil
  }

  // MARK: - Document Parsing

  mutating func parseDocumentStream(limit: Int? = nil) throws -> [YAMLDocument] {
    var documents: [YAMLDocument] = []
    var allowDirectives = true
    var requireDocumentStart = false
    var pendingTagHandles = YAMLParser.defaultTagHandles

    func hasExplicitDocumentEnd(after index: Int) -> Bool {
      guard let nextIndex = nextNonEmptyLineIndex(from: index) else {
        return false
      }
      return isDocumentEnd(lines[nextIndex])
    }

    func appendDocument(_ node: YAMLNode, explicitStart: Bool) {
      let explicitEnd = hasExplicitDocumentEnd(after: index)
      documents.append(.init(node: node, explicitStart: explicitStart, explicitEnd: explicitEnd))
    }

    while index < lines.count && limit.map({ documents.count < $0 }) ?? true {
      pendingTagHandles = YAMLParser.defaultTagHandles
      let sawDirective = try parseDirectives(
        allowDirectives: &allowDirectives,
        requireDocumentStart: requireDocumentStart,
        pendingTagHandles: &pendingTagHandles
      )
      guard index < lines.count else {
        if sawDirective {
          throw syntaxError("Directive without document")
        }
        break
      }

      let trimmed = lines[index].trimmedContent
      if trimmed.hasPrefix("...") && trimmed != "..." {
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if idx < trimmed.endIndex, trimmed[idx].isWhitespace {
          throw syntaxError("Invalid document end marker")
        }
      }
      if isDocumentEnd(lines[index]) {
        allowDirectives = true
        index += 1
        continue
      }

      tagHandles = pendingTagHandles
      pendingTagHandles = YAMLParser.defaultTagHandles
      allowDirectives = false
      let explicitStart = isDocumentStart(lines[index])
      if explicitStart {
        if let node = try parseDocumentStartContent(
          explicitStart: explicitStart,
          pendingTagHandles: &pendingTagHandles
        ) {
          appendDocument(node, explicitStart: explicitStart)
          tagHandles = YAMLParser.defaultTagHandles
          requireDocumentStart = true
          continue
        }
      }

      guard index < lines.count else { break }
      let indent = lines[index].indent
      let node = try parseNode(expectedIndent: indent)
      appendDocument(node, explicitStart: explicitStart)
      tagHandles = YAMLParser.defaultTagHandles
      requireDocumentStart = true

      while index < lines.count {
        if isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
          break
        }
        if !lines[index].trimmedContent.isEmpty {
          break
        }
        index += 1
      }
    }

    return documents
  }

  mutating func parseNextDocument() throws -> YAMLDocument? {
    var pendingTagHandles = YAMLParser.defaultTagHandles

    func hasExplicitDocumentEnd(after index: Int) -> Bool {
      guard let nextIndex = nextNonEmptyLineIndex(from: index) else {
        return false
      }
      return isDocumentEnd(lines[nextIndex])
    }

    func buildDocument(_ node: YAMLNode, explicitStart: Bool) -> YAMLDocument {
      let explicitEnd = hasExplicitDocumentEnd(after: index)
      return YAMLDocument(node: node, explicitStart: explicitStart, explicitEnd: explicitEnd)
    }

    while index < lines.count {
      pendingTagHandles = YAMLParser.defaultTagHandles
      var localAllowDirectives = allowDirectives
      let sawDirective = try parseDirectives(
        allowDirectives: &localAllowDirectives,
        requireDocumentStart: requireDocumentStart,
        pendingTagHandles: &pendingTagHandles
      )
      allowDirectives = localAllowDirectives
      guard index < lines.count else {
        if sawDirective {
          throw allowIncompleteInput ? incompleteError() : syntaxError("Directive without document")
        }
        return nil
      }

      let trimmed = lines[index].trimmedContent
      if trimmed.hasPrefix("...") && trimmed != "..." {
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if idx < trimmed.endIndex, trimmed[idx].isWhitespace {
          throw syntaxError("Invalid document end marker")
        }
      }
      if isDocumentEnd(lines[index]) {
        allowDirectives = true
        index += 1
        continue
      }

      tagHandles = pendingTagHandles
      pendingTagHandles = YAMLParser.defaultTagHandles
      allowDirectives = false
      let explicitStart = isDocumentStart(lines[index])
      if explicitStart {
        if let node = try parseDocumentStartContent(
          explicitStart: explicitStart,
          pendingTagHandles: &pendingTagHandles
        ) {
          let document = buildDocument(node, explicitStart: explicitStart)
          tagHandles = YAMLParser.defaultTagHandles
          requireDocumentStart = true
          skipEmptyLines()
          return document
        }
      }

      guard index < lines.count else { break }
      let indent = lines[index].indent
      let node = try parseNode(expectedIndent: indent)
      let document = buildDocument(node, explicitStart: explicitStart)
      tagHandles = YAMLParser.defaultTagHandles
      requireDocumentStart = true

      while index < lines.count {
        if isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
          break
        }
        if !lines[index].trimmedContent.isEmpty {
          break
        }
        index += 1
      }
      return document
    }

    return nil
  }

  func remainingText() -> String {
    guard index < lines.count else {
      return ""
    }
    let remaining = lines[index...].map { $0.raw }
    return remaining.joined(separator: "\n")
  }

  var allowsDirectives: Bool { allowDirectives }
  var requiresDocumentStart: Bool { requireDocumentStart }

  // MARK: - Core Parsing

  private mutating func parseNode(expectedIndent: Int) throws -> YAMLNode {
    guard index < lines.count else {
      throw allowIncompleteInput ? incompleteError() : syntaxError("Unexpected end of document")
    }

    let line = lines[index]
    let trimmedLine = line.trimmedContent

    if line.indent < expectedIndent {
      throw indentationError()
    }

    if line.indent == 0 && trimmedLine.hasPrefix("%") {
      throw syntaxError("Directive without document end marker")
    }

    // Capture decorators before deciding shape.
    let decorated = try parseDecorators(
      from: line.contentStrippingComment(),
      lineIndex: index,
      baseColumn: line.indent + 1
    )
    let decorators = decorated.decorators
    let rawContent = decorated.remainder
    let rawContentColumn = decorated.remainderColumn
    let trimmedContent = rawContent.yamlTrimmed()
    let tabIndentCheck = expectedIndent > 0 ? expectedIndent : 1
    if hasTabInIndent(line, requiredIndent: tabIndentCheck),
      !trimmedLine.isEmpty,
      !isFlowCollectionIndicator(trimmedContent)
    {
      throw indentationError()
    }

    if trimmedContent.isEmpty, decorators.tag != nil || decorators.anchor != nil {
      index += 1
      skipEmptyLines()
      if index >= lines.count || isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
        let node = YAMLNode.emptyPlainScalar
        return try attach(node, tag: decorators.tag, anchor: decorators.anchor)
      }
      let nextLine = lines[index]
      let nextContent = nextLine.trimmedContent
      if nextLine.indent < expectedIndent, isSequenceIndicator(nextContent) {
        let nested = try parseBlockSequence(
          decorators: Decorators(tag: nil, anchor: nil),
          expectedIndent: nextLine.indent,
          firstRemainder: nextLine.contentStrippingComment()
        )
        let decorated = try attach(nested, tag: decorators.tag, anchor: decorators.anchor)
        return decorated
      }
      var node = try parseNode(expectedIndent: expectedIndent)
      node = try attach(node, tag: decorators.tag, anchor: decorators.anchor)
      return node
    }

    if isSequenceIndicator(rawContent), (decorators.tag != nil || decorators.anchor != nil) {
      throw syntaxError("Sequence entry cannot be preceded by tag or anchor")
    }

    if isSequenceIndicator(rawContent) && line.indent >= expectedIndent {
      return try parseBlockSequence(
        decorators: decorators,
        expectedIndent: line.indent,
        firstRemainder: decorated.remainder
      )
    }

    if splitMappingEntry(rawContent) != nil, line.indent >= expectedIndent {
      return try parseBlockMapping(
        decorators: Decorators(tag: nil, anchor: nil),
        expectedIndent: line.indent,
        firstRemainder: line.contentStrippingComment()
      )
    }

    if isExplicitMappingIndicator(rawContent) && line.indent >= expectedIndent {
      return try parseBlockMapping(
        decorators: decorators,
        expectedIndent: line.indent,
        firstRemainder: line.contentStrippingComment()
      )
    }

    if trimmedContent.hasPrefix("[") || trimmedContent.hasPrefix("{") {
      let flow = try collectFlowText(
        startIndex: index,
        firstContent: decorated.remainder,
        firstColumn: rawContentColumn,
        minimumIndent: leadingSpaceCount(lines[index].raw)
      )
      var inline = InlineParser(
        text: flow.text,
        baseLine: line.number,
        lineStartColumns: flow.lineStartColumns
      )
      var node = try parseInlineNode(parser: &inline, baseIndent: expectedIndent)
      if decorators.tag != nil || decorators.anchor != nil {
        node = try attach(node, tag: decorators.tag, anchor: decorators.anchor)
      }
      inline.skipWhitespaceAndComments()
      if inline.peek != nil {
        throw inline.syntaxError("Unexpected trailing content")
      }
      index += flow.linesConsumed
      return node
    }

    if trimmedContent.hasPrefix("|") || trimmedContent.hasPrefix(">") {
      let baseIndent = expectedIndent - 1
      let node = try parseBlockScalar(content: trimmedContent, decorators: decorators, baseIndent: baseIndent)
      return node
    }

    let expanded = try expandInlineText(
      rawContent,
      startIndex: index,
      parentIndent: expectedIndent,
      firstColumn: rawContentColumn,
      minimumFlowIndent: 0
    )
    var inlineParser = InlineParser(
      text: expanded.text,
      baseLine: line.number,
      lineStartColumns: expanded.lineStartColumns
    )
    var node = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent)
    if decorators.tag != nil || decorators.anchor != nil {
      node = try attach(node, tag: decorators.tag, anchor: decorators.anchor)
    }
    var linesConsumed = 1 + expanded.extraLines
    let folded = try foldPlainScalarIfNeeded(node, startIndex: index)
    node = folded.node
    linesConsumed += folded.linesConsumed
    index += linesConsumed
    return node
  }

  private mutating func parseBlockSequence(
    decorators: Decorators,
    expectedIndent: Int,
    firstRemainder: String?,
    consumeFirstLine: Bool = true
  ) throws -> YAMLNode {
    var items: [YAMLNode] = []
    items.reserveCapacity(min(lines.count - index, 256))
    var initialRemainder = firstRemainder
    var consumeFirst = consumeFirstLine
    var sequenceIndent = expectedIndent
    var allowIndentIncrease = !consumeFirstLine

    while index < lines.count {
      let line = lines[index]
      if initialRemainder == nil {
        let trimmed = line.trimmedContent
        if trimmed.isEmpty {
          index += 1
          continue
        }
      }
      let skipAdvance = initialRemainder != nil && !consumeFirst
      let entryLineIndex = skipAdvance ? max(index - 1, 0) : index
      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let baseColumn = lines[entryLineIndex].indent + 1
      let decorated = try parseDecorators(
        from: sourceContent,
        lineIndex: entryLineIndex,
        baseColumn: baseColumn
      )
      let currentDecorators = decorated.decorators
      let content = decorated.remainder
      let effectiveIndent: Int
      if skipAdvance {
        effectiveIndent = sequenceIndent
      } else {
        if allowIndentIncrease, line.indent > sequenceIndent, isSequenceIndicator(content) {
          sequenceIndent = line.indent
        }
        allowIndentIncrease = false
        effectiveIndent = line.indent
      }
      if !skipAdvance {
        let trimmedSource = sourceContent.yamlTrimmed()
        let tabIndentCheck = sequenceIndent > 0 ? sequenceIndent : 1
        if hasTabInIndent(line, requiredIndent: tabIndentCheck),
          !trimmedSource.isEmpty,
          !isFlowCollectionIndicator(content)
        {
          throw indentationError()
        }
      }
      if effectiveIndent != sequenceIndent || !isSequenceIndicator(content) {
        break
      }

      let trimmed = content.yamlTrimmed()
      guard trimmed.first == "-" else { break }
      let tabSeparated = hasTabAfterIndicator(content, indicator: "-")
      let afterDash = trimmed[trimmed.index(after: trimmed.startIndex)...]
      let remainder = String(afterDash).yamlTrimmed()
      if tabSeparated {
        if isSequenceIndicator(remainder) || isExplicitMappingIndicator(remainder)
          || splitMappingEntry(remainder) != nil
        {
          throw indentationError()
        }
      }
      if !skipAdvance {
        index += 1
      }

      if remainder.isEmpty {
        if let nextIndex = nextNonEmptyLineIndex(from: index),
          lines[nextIndex].indent > sequenceIndent
        {
          skipEmptyLines()
          let node = try parseNode(expectedIndent: sequenceIndent + 1)
          let decoratedNode = try attach(node, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
        } else {
          let emptyNode = YAMLNode.emptyPlainScalar
          let decoratedNode = try attach(emptyNode, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
        }
      } else {
        if isSequenceIndicator(remainder) {
          let nested = try parseBlockSequence(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: sequenceIndent + 2,
            firstRemainder: remainder,
            consumeFirstLine: false
          )
          let decoratedNode = try attach(nested, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
          initialRemainder = nil
          consumeFirst = true
          continue
        }
        if isExplicitMappingIndicator(remainder) {
          let nested = try parseBlockMapping(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: sequenceIndent + 2,
            firstRemainder: remainder,
            consumeFirstLine: false
          )
          let decoratedNode = try attach(nested, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
          initialRemainder = nil
          consumeFirst = true
          continue
        }
        if splitMappingEntry(remainder) != nil {
          let nested = try parseBlockMapping(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: sequenceIndent + 2,
            firstRemainder: remainder,
            consumeFirstLine: false
          )
          let decoratedNode = try attach(nested, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
          initialRemainder = nil
          consumeFirst = true
          continue
        }
        let contentColumn = decorated.remainderColumn
        var inline = InlineParser(
          text: remainder,
          baseLine: lines[entryLineIndex].number,
          lineStartColumns: [contentColumn]
        )
        let rawValueDecorators = try inline.parseDecorators()
        let resolvedValueTag = try resolveTag(rawValueDecorators.tag)
        let valueDecorators = Decorators(tag: resolvedValueTag, anchor: rawValueDecorators.anchor)
        inline.skipWhitespaceAndComments()
        if inline.peek == nil {
          if let nextIndex = nextNonEmptyLineIndex(from: index),
            lines[nextIndex].indent > sequenceIndent
          {
            skipEmptyLines()
            var node = try parseNode(expectedIndent: sequenceIndent + 1)
            node = try attach(
              node,
              tag: valueDecorators.tag ?? currentDecorators.tag,
              anchor: valueDecorators.anchor ?? currentDecorators.anchor
            )
            items.append(node)
          } else {
            let emptyNode = YAMLNode.emptyPlainScalar
            let decoratedNode = try attach(
              emptyNode,
              tag: valueDecorators.tag ?? currentDecorators.tag,
              anchor: valueDecorators.anchor ?? currentDecorators.anchor
            )
            items.append(decoratedNode)
          }
        } else {
          let remainderContent = inline.remaining.yamlTrimmed()
          if remainderContent.hasPrefix("|") || remainderContent.hasPrefix(">") {
            let savedIndex = index
            index = entryLineIndex
            let node = try parseBlockScalar(
              content: remainderContent,
              decorators: valueDecorators,
              baseIndent: sequenceIndent
            )
            items.append(node)
            index = max(index, savedIndex)
            initialRemainder = nil
            consumeFirst = true
            continue
          }
          let expanded = try expandInlineText(
            inline.remaining,
            startIndex: entryLineIndex,
            parentIndent: sequenceIndent + 1,
            firstColumn: contentColumn,
            minimumFlowIndent: leadingSpaceCount(lines[entryLineIndex].raw) + 1
          )
          var valueParser = InlineParser(
            text: expanded.text,
            baseLine: lines[entryLineIndex].number,
            lineStartColumns: expanded.lineStartColumns
          )
          var node = try parseInlineNode(parser: &valueParser, baseIndent: sequenceIndent + 2)
          node = try attach(
            node,
            tag: valueDecorators.tag ?? currentDecorators.tag,
            anchor: valueDecorators.anchor ?? currentDecorators.anchor
          )
          if skipAdvance && allowIndentIncrease, index < lines.count {
            let nextLine = lines[index]
            if nextLine.indent > sequenceIndent,
              isSequenceIndicator(nextLine.trimmedContent)
            {
              sequenceIndent = nextLine.indent
              allowIndentIncrease = false
            }
          }
          let folded = try foldPlainScalarIfNeeded(node, startIndex: entryLineIndex, contextIndent: sequenceIndent)
          node = folded.node
          if folded.linesConsumed > 0 {
            index += folded.linesConsumed
          }
          if expanded.extraLines > 0 {
            index += expanded.extraLines
          }
          valueParser.skipWhitespaceAndComments()
          if valueParser.peek != nil {
            throw valueParser.syntaxError("Unexpected trailing content")
          }
          items.append(node)
        }
      }
      initialRemainder = nil
      consumeFirst = true
    }

    return try attach(
      .sequence(items, style: .block, tag: nil, anchor: nil),
      tag: decorators.tag,
      anchor: decorators.anchor
    )
  }

  private mutating func parseBlockMapping(
    decorators: Decorators,
    expectedIndent: Int,
    firstRemainder: String?,
    consumeFirstLine: Bool = true
  ) throws -> YAMLNode {
    var pairs: [(YAMLNode, YAMLNode)] = []
    pairs.reserveCapacity(min(lines.count - index, 256))
    var initialRemainder = firstRemainder
    var consumeFirst = consumeFirstLine

    while index < lines.count {
      let line = lines[index]
      if initialRemainder == nil {
        let trimmed = line.trimmedContent
        if trimmed.isEmpty {
          index += 1
          continue
        }
      }
      let skipAdvance = initialRemainder != nil && !consumeFirst
      let entryLineIndex = skipAdvance ? max(index - 1, 0) : index
      let effectiveIndent = skipAdvance ? expectedIndent : line.indent
      if effectiveIndent != expectedIndent {
        break
      }

      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let baseColumn = lines[entryLineIndex].indent + 1
      let decorated = try parseDecorators(
        from: sourceContent,
        lineIndex: entryLineIndex,
        baseColumn: baseColumn
      )
      let contentColumn = decorated.remainderColumn
      if !skipAdvance {
        let trimmedSource = sourceContent.yamlTrimmed()
        let tabIndentCheck = expectedIndent > 0 ? expectedIndent : 1
        if hasTabInIndent(line, requiredIndent: tabIndentCheck), !trimmedSource.isEmpty {
          let remainder = decorated.remainder.yamlTrimmed()
          if !remainder.isEmpty && !isFlowCollectionIndicator(remainder) {
            throw indentationError()
          }
        }
      }
      let entryDecorators = decorated.decorators
      let content = decorated.remainder
      if isExplicitMappingIndicator(content) {
        let tabSeparated = hasTabAfterIndicator(content, indicator: "?")
        var explicitContent = content
        explicitContent.removeFirst()
        let keyContent = explicitContent.yamlTrimmed()
        let keyLineIndex = entryLineIndex
        let baseAdvance = skipAdvance ? 0 : 1
        if tabSeparated {
          if isSequenceIndicator(keyContent) || isExplicitMappingIndicator(keyContent)
            || splitMappingEntry(keyContent) != nil
          {
            throw indentationError()
          }
        }

        var keyNode: YAMLNode
        if keyContent.isEmpty {
          if baseAdvance > 0 {
            index += baseAdvance
          }
          skipEmptyLines()
          guard index < lines.count else {
            throw syntaxError("Missing explicit mapping key")
          }
          let nextIndent = min(expectedIndent + 1, lines[index].indent)
          keyNode = try parseNode(expectedIndent: nextIndent)
        } else if keyContent.hasPrefix("|") || keyContent.hasPrefix(">") {
          keyNode = try parseBlockScalar(
            content: keyContent,
            decorators: Decorators(tag: nil, anchor: nil),
            baseIndent: expectedIndent
          )
        } else if isSequenceIndicator(keyContent) {
          if baseAdvance > 0 {
            index += baseAdvance
          }
          keyNode = try parseBlockSequence(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: expectedIndent + 2,
            firstRemainder: keyContent,
            consumeFirstLine: false
          )
        } else if splitMappingEntry(keyContent) != nil || isExplicitMappingIndicator(keyContent) {
          if baseAdvance > 0 {
            index += baseAdvance
          }
          keyNode = try parseBlockMapping(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: expectedIndent + 2,
            firstRemainder: keyContent,
            consumeFirstLine: false
          )
        } else if keyContent.hasPrefix("[") || keyContent.hasPrefix("{") {
          let flow = try collectFlowText(
            startIndex: keyLineIndex,
            firstContent: keyContent,
            firstColumn: contentColumn,
            minimumIndent: leadingSpaceCount(lines[keyLineIndex].raw) + 1
          )
          var inline = InlineParser(
            text: flow.text,
            baseLine: lines[keyLineIndex].number,
            lineStartColumns: flow.lineStartColumns
          )
          keyNode = try parseInlineNode(parser: &inline, baseIndent: expectedIndent + 1)
          if flow.linesConsumed > 1 {
            index += baseAdvance + (flow.linesConsumed - 1)
          } else {
            if baseAdvance > 0 {
              index += baseAdvance
            }
          }
        } else {
          var keyParser = InlineParser(
            text: keyContent,
            baseLine: lines[keyLineIndex].number,
            lineStartColumns: [contentColumn]
          )
          keyNode = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
          keyParser.skipWhitespaceAndComments()
          if keyParser.peek != nil {
            throw keyParser.syntaxError("Unexpected trailing content")
          }
          if baseAdvance > 0 {
            index += baseAdvance
          }
          let foldedKey = try foldPlainScalarIfNeeded(keyNode, startIndex: keyLineIndex, contextIndent: expectedIndent)
          keyNode = foldedKey.node
          if foldedKey.linesConsumed > 0 {
            index += foldedKey.linesConsumed
          }
        }

        keyNode = try attach(keyNode, tag: entryDecorators.tag, anchor: entryDecorators.anchor)

        let valueNode = try resolveBlockMappingValue(
          expectedIndent: expectedIndent,
          allowNestedMapping: true
        )

        pairs.append((keyNode, valueNode))
        initialRemainder = nil
        consumeFirst = true
        continue
      }

      guard let entry = splitMappingEntry(content) else { break }

      let trimmedKey = entry.key.yamlTrimmed()
      let keyNode: YAMLNode
      let entryLine = lines[entryLineIndex]
      let entryBaseColumn = entryLine.indent + 1
      if trimmedKey.isEmpty {
        keyNode = .emptyPlainScalar
      } else {
        var keyParser = InlineParser(
          text: trimmedKey,
          baseLine: entryLine.number,
          lineStartColumns: [entryBaseColumn]
        )
        let parsedKey = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
        keyParser.skipWhitespaceAndComments()
        if keyParser.peek != nil {
          throw keyParser.syntaxError("Unexpected trailing content")
        }
        keyNode = parsedKey
      }
      let decoratedKeyNode = try attach(keyNode, tag: entryDecorators.tag, anchor: entryDecorators.anchor)

      if !skipAdvance {
        index += 1
      }

      let inlineValue = entry.value?.yamlTrimmed() ?? ""
      if inlineValue.isEmpty {
        if let nextIndex = nextNonEmptyLineIndex(from: index) {
          let nextLine = lines[nextIndex]
          if nextLine.indent > expectedIndent {
            skipEmptyLines()
            let valueNode = try parseNode(expectedIndent: expectedIndent + 1)
            pairs.append((decoratedKeyNode, valueNode))
          } else if nextLine.indent == expectedIndent,
            isSequenceIndicator(nextLine.trimmedContent)
          {
            skipEmptyLines()
            let nested = try parseBlockSequence(
              decorators: Decorators(tag: nil, anchor: nil),
              expectedIndent: expectedIndent,
              firstRemainder: lines[index].contentStrippingComment()
            )
            pairs.append((decoratedKeyNode, nested))
          } else {
            let emptyNode = YAMLNode.emptyPlainScalar
            pairs.append((decoratedKeyNode, emptyNode))
          }
        } else {
          let emptyNode = YAMLNode.emptyPlainScalar
          pairs.append((decoratedKeyNode, emptyNode))
        }
      } else {
        var valueParser = InlineParser(
          text: inlineValue,
          baseLine: entryLine.number,
          lineStartColumns: [entryBaseColumn]
        )
        let rawValueDecorators = try valueParser.parseDecorators()
        let resolvedValueTag = try resolveTag(rawValueDecorators.tag)
        let valueDecorators = Decorators(tag: resolvedValueTag, anchor: rawValueDecorators.anchor)
        valueParser.skipWhitespaceAndComments()
        let remainder = valueParser.remaining.yamlTrimmed()
        if remainder.isEmpty {
          if let nextIndex = nextNonEmptyLineIndex(from: index) {
            let nextLine = lines[nextIndex]
            if nextLine.indent > expectedIndent {
              skipEmptyLines()
              let node = try parseNode(expectedIndent: expectedIndent + 1)
              let decoratedNode = try attach(node, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
              pairs.append((decoratedKeyNode, decoratedNode))
            } else if nextLine.indent == expectedIndent,
              isSequenceIndicator(nextLine.trimmedContent)
            {
              skipEmptyLines()
              let nested = try parseBlockSequence(
                decorators: Decorators(tag: nil, anchor: nil),
                expectedIndent: expectedIndent,
                firstRemainder: lines[index].contentStrippingComment()
              )
              let decoratedNode = try attach(nested, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
              pairs.append((decoratedKeyNode, decoratedNode))
            } else {
              let emptyNode = YAMLNode.emptyPlainScalar
              let decoratedNode = try attach(emptyNode, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
              pairs.append((decoratedKeyNode, decoratedNode))
            }
          } else {
            let emptyNode = YAMLNode.emptyPlainScalar
            let decoratedNode = try attach(emptyNode, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
            pairs.append((decoratedKeyNode, decoratedNode))
          }
        } else {
          if remainder.hasPrefix("|") || remainder.hasPrefix(">") {
            let savedIndex = index
            index = entryLineIndex
            let node = try parseBlockScalar(content: remainder, decorators: valueDecorators, baseIndent: expectedIndent)
            index = max(index, savedIndex)
            pairs.append((decoratedKeyNode, node))
            initialRemainder = nil
            consumeFirst = true
            continue
          }
          if isSequenceIndicator(remainder) {
            throw syntaxError("Sequence value must start on a new line")
          }
          let expanded = try expandInlineText(
            valueParser.remaining,
            startIndex: entryLineIndex,
            parentIndent: expectedIndent + 1,
            firstColumn: entryBaseColumn,
            minimumFlowIndent: leadingSpaceCount(lines[entryLineIndex].raw) + 1
          )
          var inlineParser = InlineParser(
            text: expanded.text,
            baseLine: entryLine.number,
            lineStartColumns: expanded.lineStartColumns
          )
          var valueNode = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent + 1)
          valueNode = try attach(valueNode, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
          let folded = try foldPlainScalarIfNeeded(valueNode, startIndex: entryLineIndex, contextIndent: expectedIndent)
          valueNode = folded.node
          if folded.linesConsumed > 0 {
            index += folded.linesConsumed
          }
          if expanded.extraLines > 0 {
            index += expanded.extraLines
          }
          inlineParser.skipWhitespaceAndComments()
          if inlineParser.peek != nil {
            throw inlineParser.syntaxError("Unexpected trailing content")
          }
          pairs.append((decoratedKeyNode, valueNode))
        }
      }
      initialRemainder = nil
      consumeFirst = true
    }

    return try attach(
      .mapping(pairs, style: .block, tag: nil, anchor: nil),
      tag: decorators.tag,
      anchor: decorators.anchor
    )
  }

  private mutating func parseExplicitBlockMapping(
    decorators: Decorators,
    expectedIndent: Int,
    firstRemainder: String?
  ) throws -> YAMLNode {
    var pairs: [(YAMLNode, YAMLNode)] = []
    var initialRemainder = firstRemainder

    while index < lines.count {
      let line = lines[index]
      if line.indent != expectedIndent {
        break
      }

      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let entryLineIndex = index
      let baseColumn = line.indent + 1
      let decorated = try parseDecorators(
        from: sourceContent,
        lineIndex: entryLineIndex,
        baseColumn: baseColumn
      )
      let contentColumn = decorated.remainderColumn
      let trimmedSource = sourceContent.yamlTrimmed()
      let tabIndentCheck = expectedIndent > 0 ? expectedIndent : 1
      if hasTabInIndent(line, requiredIndent: tabIndentCheck), !trimmedSource.isEmpty {
        let remainder = decorated.remainder.yamlTrimmed()
        if !remainder.isEmpty && !isFlowCollectionIndicator(remainder) {
          throw indentationError()
        }
      }
      var content = decorated.remainder.yamlTrimmed()
      guard isExplicitMappingIndicator(content) else { break }
      let tabSeparated = hasTabAfterIndicator(content, indicator: "?")

      // Trim leading '?' and whitespace.
      content.removeFirst()
      let keyContent = content.yamlTrimmed()
      let keyLineIndex = index
      if tabSeparated {
        if isSequenceIndicator(keyContent) || isExplicitMappingIndicator(keyContent)
          || splitMappingEntry(keyContent) != nil
        {
          throw indentationError()
        }
      }

      var keyNode: YAMLNode
      if keyContent.isEmpty {
        index += 1
        skipEmptyLines()
        guard index < lines.count else {
          throw syntaxError("Missing explicit mapping key")
        }
        keyNode = try parseNode(expectedIndent: lines[index].indent)
      } else if keyContent.hasPrefix("|") || keyContent.hasPrefix(">") {
        keyNode = try parseBlockScalar(
          content: keyContent,
          decorators: Decorators(tag: nil, anchor: nil),
          baseIndent: expectedIndent
        )
      } else if keyContent.hasPrefix("[") || keyContent.hasPrefix("{") {
        let flow = try collectFlowText(
          startIndex: keyLineIndex,
          firstContent: keyContent,
          firstColumn: contentColumn,
          minimumIndent: leadingSpaceCount(lines[keyLineIndex].raw) + 1
        )
        var inline = InlineParser(
          text: flow.text,
          baseLine: lines[keyLineIndex].number,
          lineStartColumns: flow.lineStartColumns
        )
        keyNode = try parseInlineNode(parser: &inline, baseIndent: expectedIndent + 1)
        if flow.linesConsumed > 1 {
          index += flow.linesConsumed
        } else {
          index += 1
        }
      } else {
        var keyParser = InlineParser(
          text: keyContent,
          baseLine: lines[keyLineIndex].number,
          lineStartColumns: [contentColumn]
        )
        keyNode = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
        keyParser.skipWhitespaceAndComments()
        if keyParser.peek != nil {
          throw keyParser.syntaxError("Unexpected trailing content")
        }
        index += 1
        let foldedKey = try foldPlainScalarIfNeeded(keyNode, startIndex: keyLineIndex, contextIndent: expectedIndent)
        keyNode = foldedKey.node
        if foldedKey.linesConsumed > 0 {
          index += foldedKey.linesConsumed
        }
      }

      keyNode = try attach(keyNode, tag: decorated.decorators.tag, anchor: decorated.decorators.anchor)

      let valueNode = try resolveBlockMappingValue(
        expectedIndent: expectedIndent,
        allowNestedMapping: false
      )

      pairs.append((keyNode, valueNode))
      initialRemainder = nil
    }

    return try attach(
      .mapping(pairs, style: .block, tag: nil, anchor: nil),
      tag: decorators.tag,
      anchor: decorators.anchor
    )
  }

  private mutating func parseBlockScalar(content: String, decorators: Decorators, baseIndent: Int) throws -> YAMLNode {
    guard let indicator = content.first else {
      throw syntaxError("Invalid block scalar indicator on line \(lines[index].number)")
    }

    var chomp: YAMLScalarChomp = .clip
    var indentIndicator: Int?
    var sawChomp = false
    var sawIndent = false
    var idx = content.index(after: content.startIndex)
    while idx < content.endIndex {
      let char = content[idx]
      if char == "+" {
        if sawChomp {
          throw syntaxError("Invalid block scalar chomping indicator")
        }
        sawChomp = true
        chomp = .keep
        idx = content.index(after: idx)
      } else if char == "-" {
        if sawChomp {
          throw syntaxError("Invalid block scalar chomping indicator")
        }
        sawChomp = true
        chomp = .strip
        idx = content.index(after: idx)
      } else if char.isWholeNumber {
        if sawIndent {
          throw syntaxError("Invalid block scalar indentation indicator")
        }
        sawIndent = true
        if char == "0" {
          throw syntaxError("Invalid block scalar indentation indicator")
        }
        indentIndicator = Int(String(char))
        idx = content.index(after: idx)
      } else if char == " " {
        idx = content.index(after: idx)
      } else {
        break
      }
    }
    if idx < content.endIndex {
      var sawSpace = false
      var cursor = idx
      while cursor < content.endIndex {
        let char = content[cursor]
        if char == " " {
          sawSpace = true
          cursor = content.index(after: cursor)
          continue
        }
        if char == "#" {
          if !sawSpace {
            throw syntaxError("Invalid block scalar header")
          }
          break
        }
        throw syntaxError("Invalid block scalar header")
      }
    }

    let requiredIndent: Int = try {
      if let indentIndicator {
        return baseIndent + indentIndicator
      }
      var cursor = index + 1
      var maxBlankIndent: Int?
      while cursor < lines.count {
        let line = lines[cursor]
        let trimmed = line.raw.yamlTrimmed()
        let spaceIndent = leadingSpaceCount(line.raw)
        if trimmed.isEmpty {
          if !line.raw.isEmpty {
            if let current = maxBlankIndent {
              maxBlankIndent = max(current, spaceIndent)
            } else {
              maxBlankIndent = spaceIndent
            }
          }
          cursor += 1
          continue
        }
        if spaceIndent <= baseIndent {
          // Non-empty line without required indentation.
          return baseIndent + 1
        }
        if let maxBlankIndent, spaceIndent < maxBlankIndent {
          throw indentationError(lineIndex: cursor)
        }
        return spaceIndent
      }
      if let maxBlankIndent, maxBlankIndent > baseIndent {
        return maxBlankIndent
      }
      return baseIndent + 1
    }()
    index += 1

    var captured: [(line: String, indent: Int)] = []
    while index < lines.count {
      let line = lines[index]
      let raw = line.raw
      let trimmed = raw.yamlTrimmed()
      let spaceIndent = leadingSpaceCount(raw)
      if hasTabInIndent(line, requiredIndent: requiredIndent) {
        throw indentationError()
      }
      if spaceIndent < requiredIndent {
        if trimmed.isEmpty {
          if index == lines.count - 1 && line.raw.isEmpty {
            break
          }
          captured.append(("", spaceIndent))
          index += 1
          continue
        }
        break
      }
      if requiredIndent == 0 && spaceIndent == 0 {
        let marker = line.trimmedContent
        if marker == "..." || isDocumentStart(line) {
          break
        }
      }
      let start = indexAfterIndent(raw, requiredIndent: requiredIndent)
      let text = String(raw[start...])
      if text.isEmpty {
        captured.append(("", spaceIndent))
      } else {
        captured.append((text, spaceIndent))
      }
      index += 1
    }

    let scalarText: String
    switch indicator {
    case "|":
      scalarText = joinLiteralLines(captured, chomp: chomp)
    case ">":
      scalarText = joinFoldedLines(captured, baseIndent: requiredIndent, chomp: chomp)
    default:
      throw syntaxError("Unknown block scalar indicator on line \(lines[index].number)")
    }

    let style: YAMLScalarStyle =
      indicator == "|"
      ? .literal(chomp: chomp, indent: indentIndicator) : .folded(chomp: chomp, indent: indentIndicator)
    let scalar = YAMLScalar(text: scalarText, style: style)
    return try attach(.scalar(scalar, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
  }

  // MARK: - Inline Parsing

  private mutating func parseInlineNode(
    parser: inout InlineParser,
    baseIndent: Int,
    stopAtColon: Bool = false,
    flowContext: Bool = false
  ) throws -> YAMLNode {
    parser.skipWhitespaceAndComments()
    let rawDecorators = try parser.parseDecorators(flowContext: flowContext)
    let resolvedTag = try resolveTag(rawDecorators.tag)
    let decorators = Decorators(tag: resolvedTag, anchor: rawDecorators.anchor)

    parser.skipWhitespaceAndComments()
    guard let current = parser.peek else {
      let node = YAMLNode.emptyPlainScalar
      return try attach(node, tag: decorators.tag, anchor: decorators.anchor)
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
      let scalarStart = parser.location()
      let text = parser.parsePlainScalar(stopAtColon: stopAtColon, flowContext: flowContext)
      try validatePlainScalarText(text, location: scalarStart)
      node = .scalar(.init(text: text, style: .plain), tag: nil, anchor: nil)
    }

    return try attach(node, tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseFlowSequence(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    func syntaxError(_ message: String) -> YAML.ParseError {
      parser.syntaxError(message)
    }
    guard parser.consumeIf("[") else {
      throw syntaxError("Expected flow sequence start")
    }
    parser.skipWhitespaceAndComments()

    var items: [YAMLNode] = []
    var closed = false
    while let current = parser.peek {
      if current == "]" {
        parser.consume(expected: "]")
        closed = true
        break
      }

      if current == "?" {
        let nextIndex = parser.text.index(after: parser.index)
        let hasExplicitIndicator = nextIndex >= parser.text.endIndex || parser.text[nextIndex].isWhitespace
        if hasExplicitIndicator {
          parser.consume(expected: "?")
          parser.skipWhitespaceAndComments()
          let keyStart = parser.index
          var keyParser = parser
          var keyNode = try parseInlineNode(
            parser: &keyParser,
            baseIndent: baseIndent,
            stopAtColon: true,
            flowContext: true
          )
          if keyParser.index == keyStart {
            guard keyParser.peek == ":" || keyParser.peek == "," || keyParser.peek == "]" else {
              throw syntaxError("Invalid explicit flow mapping key")
            }
            keyNode = .emptyPlainScalar
          }
          keyParser.skipWhitespaceAndComments()
          let hadColon = keyParser.consumeIf(":")
          keyParser.skipWhitespaceAndComments()
          let valueNode: YAMLNode
          if !hadColon {
            guard keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "]" else {
              throw syntaxError("Explicit flow mapping entry missing ':'")
            }
            valueNode = .emptyPlainScalar
          } else if keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "]" {
            valueNode = .emptyPlainScalar
          } else {
            let valueStart = keyParser.index
            var valueParser = keyParser
            let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
            if valueParser.index == valueStart {
              throw syntaxError("Invalid flow mapping value")
            }
            keyParser = valueParser
            valueNode = value
          }
          parser = keyParser
          items.append(.mapping([(keyNode, valueNode)], style: .flow, tag: nil, anchor: nil))
          parser.skipWhitespaceAndComments()
          if parser.consumeIf(",") {
            parser.skipWhitespaceAndComments()
            continue
          }
          if parser.consumeIf("]") {
            closed = true
            break
          }
          throw syntaxError("Expected ',' or ']' in flow sequence")
        }
      }

      let entryStart = parser.index
      var entryParser = parser
      var keyNode = try parseInlineNode(
        parser: &entryParser,
        baseIndent: baseIndent,
        stopAtColon: true,
        flowContext: true
      )
      if entryParser.index == entryStart {
        guard entryParser.peek == ":" else {
          throw syntaxError("Invalid flow sequence entry")
        }
        keyNode = .emptyPlainScalar
      }
      let keySlice = entryParser.text[entryStart..<entryParser.index]
      let keyHasLineBreak = keySlice.contains(where: { $0.isNewline })
      let whitespaceStart = entryParser.index
      entryParser.skipWhitespaceAndComments()
      let skipped = entryParser.text[whitespaceStart..<entryParser.index]
      let sawLineBreak = skipped.contains(where: { $0.isNewline })
      if entryParser.consumeIf(":") {
        if keyHasLineBreak || sawLineBreak {
          throw syntaxError("Implicit flow mapping key must be on one line")
        }
        entryParser.skipWhitespaceAndComments()
        let valueStart = entryParser.index
        var valueParser = entryParser
        let valueNode = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
        if valueParser.index == valueStart {
          throw syntaxError("Invalid flow sequence entry")
        }
        parser = valueParser
        items.append(.mapping([(keyNode, valueNode)], style: .flow, tag: nil, anchor: nil))
      } else {
        parser = entryParser
        if case .scalar(let scalar, _, _) = keyNode,
          case .plain = scalar.style,
          scalar.text == "-"
        {
          throw syntaxError("Invalid flow sequence entry")
        }
        items.append(keyNode)
      }

      parser.skipWhitespaceAndComments()
      if parser.consumeIf(",") {
        parser.skipWhitespaceAndComments()
        continue
      }
      if parser.consumeIf("]") {
        closed = true
        break
      }
      throw syntaxError("Expected ',' or ']' in flow sequence")
    }
    if !closed {
      throw syntaxError("Unterminated flow sequence")
    }

    return .sequence(items, style: .flow, tag: nil, anchor: nil)
  }

  private mutating func parseFlowMapping(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    func syntaxError(_ message: String) -> YAML.ParseError {
      parser.syntaxError(message)
    }
    guard parser.consumeIf("{") else {
      throw syntaxError("Expected flow mapping start")
    }
    parser.skipWhitespaceAndComments()
    var pairs: [(YAMLNode, YAMLNode)] = []
    var closed = false

    while let current = parser.peek {
      if current == "}" {
        parser.consume(expected: "}")
        closed = true
        break
      }

      if current == "?" {
        let nextIndex = parser.text.index(after: parser.index)
        let hasExplicitIndicator = nextIndex >= parser.text.endIndex || parser.text[nextIndex].isWhitespace
        if hasExplicitIndicator {
          parser.consume(expected: "?")
          parser.skipWhitespaceAndComments()
          let keyStart = parser.index
          var keyParser = parser
          var key = try parseInlineNode(
            parser: &keyParser,
            baseIndent: baseIndent,
            stopAtColon: true,
            flowContext: true
          )
          if keyParser.index == keyStart {
            guard keyParser.peek == ":" || keyParser.peek == "," || keyParser.peek == "}" else {
              throw syntaxError("Invalid explicit flow mapping key")
            }
            key = .emptyPlainScalar
          }
          keyParser.skipWhitespaceAndComments()
          let hadColon = keyParser.consumeIf(":")
          keyParser.skipWhitespaceAndComments()
          let valueNode: YAMLNode
          if !hadColon {
            guard keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "}" else {
              throw syntaxError("Explicit flow mapping entry missing ':'")
            }
            valueNode = .emptyPlainScalar
          } else if keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "}" {
            valueNode = .emptyPlainScalar
          } else {
            let valueStart = keyParser.index
            var valueParser = keyParser
            let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
            if valueParser.index == valueStart {
              throw syntaxError("Invalid flow mapping value")
            }
            keyParser = valueParser
            valueNode = value
          }
          parser = keyParser
          pairs.append((key, valueNode))
          parser.skipWhitespaceAndComments()
          if parser.consumeIf(",") {
            parser.skipWhitespaceAndComments()
            continue
          }
          if parser.consumeIf("}") {
            closed = true
            break
          }
          throw syntaxError("Expected ',' or '}' in flow mapping")
        }
      }

      let keyStart = parser.index
      var keyParser = parser
      var key = try parseInlineNode(parser: &keyParser, baseIndent: baseIndent, stopAtColon: true, flowContext: true)
      parser = keyParser
      if parser.index == keyStart {
        guard parser.peek == ":" else {
          throw syntaxError("Invalid flow mapping key")
        }
        key = .emptyPlainScalar
      }
      parser.skipWhitespaceAndComments()
      if parser.consumeIf(":") {
        parser.skipWhitespaceAndComments()

        if parser.peek == "," || parser.peek == "}" || parser.peek == nil {
          pairs.append((key, .emptyPlainScalar))
        } else {
          let valueStart = parser.index
          var valueParser = parser
          let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
          parser = valueParser
          if parser.index == valueStart {
            throw syntaxError("Invalid flow mapping value")
          }
          pairs.append((key, value))
        }
      } else {
        pairs.append((key, .emptyPlainScalar))
      }

      parser.skipWhitespaceAndComments()
      if parser.consumeIf(",") {
        parser.skipWhitespaceAndComments()
        continue
      }
      if parser.consumeIf("}") {
        closed = true
        break
      }
      throw syntaxError("Expected ',' or '}' in flow mapping")
    }
    if !closed {
      throw syntaxError("Unterminated flow mapping")
    }

    return .mapping(pairs, style: .flow, tag: nil, anchor: nil)
  }

  // MARK: - Utilities

  private func joinLiteralLines(_ lines: [(line: String, indent: Int)], chomp: YAMLScalarChomp) -> String {
    var activeLines = lines
    if chomp != .keep {
      while let last = activeLines.last, last.line.isEmpty {
        activeLines.removeLast()
      }
    }
    var text = activeLines.map { $0.line }.joined(separator: "\n")
    switch chomp {
    case .clip:
      if !text.isEmpty {
        text.append("\n")
      }
    case .keep:
      if activeLines.isEmpty {
        return ""
      }
      text.append("\n")
    case .strip:
      while text.last == "\n" {
        text.removeLast()
      }
    }
    return text
  }

  private func joinFoldedLines(_ lines: [(line: String, indent: Int)], baseIndent: Int, chomp: YAMLScalarChomp)
    -> String
  {
    var activeLines = lines
    if chomp != .keep {
      while let last = activeLines.last, last.line.isEmpty {
        activeLines.removeLast()
      }
    }
    var result = ""
    var hasContent = false
    var previousIndented = false
    var previousEmpty = false

    for entry in activeLines {
      let line = entry.line
      let isIndented = entry.indent > baseIndent || line.first == "\t"
      if !hasContent {
        if line.isEmpty {
          result.append("\n")
          previousEmpty = true
          continue
        }
        result.append(line)
        hasContent = true
        previousEmpty = false
        previousIndented = isIndented
        continue
      }

      if line.isEmpty {
        result.append("\n")
        previousEmpty = true
        continue
      }

      if previousEmpty {
        if isIndented || previousIndented {
          result.append("\n")
        }
      } else if previousIndented || isIndented {
        result.append("\n")
      } else {
        result.append(" ")
      }

      result.append(line)
      previousEmpty = false
      previousIndented = isIndented
    }

    switch chomp {
    case .clip:
      if !result.isEmpty {
        result.append("\n")
      }
    case .keep:
      if activeLines.isEmpty {
        return ""
      }
      result.append("\n")
    case .strip:
      while result.last == "\n" {
        result.removeLast()
      }
    }

    return result
  }

  private func trimTrailingWhitespace(_ text: String) -> String {
    var end = text.endIndex
    while end > text.startIndex {
      let prev = text.index(before: end)
      let char = text[prev]
      guard char == " " || char == "\t" else {
        break
      }
      end = prev
    }
    return String(text[..<end])
  }

  private func leadingSpaceCount(_ raw: String) -> Int {
    var count = 0
    for char in raw {
      guard char == " " else {
        break
      }
      count += 1
    }
    return count
  }

  private func indexAfterIndent(_ raw: String, requiredIndent: Int) -> String.Index {
    var count = 0
    var cursor = raw.startIndex
    while cursor < raw.endIndex && count < requiredIndent {
      let char = raw[cursor]
      if char == " " {
        count += 1
        cursor = raw.index(after: cursor)
        continue
      }
      break
    }
    return cursor
  }

  private func hasTabInIndent(_ line: Line, requiredIndent: Int) -> Bool {
    guard requiredIndent > 0 else { return false }
    var count = 0
    for char in line.raw {
      if count >= requiredIndent {
        break
      }
      if char == " " {
        count += 1
        continue
      }
      if char == "\t" {
        return true
      }
      break
    }
    return false
  }

  private func foldPlainScalarIfNeeded(
    _ node: YAMLNode,
    startIndex: Int,
    contextIndent: Int? = nil
  ) throws -> (node: YAMLNode, linesConsumed: Int) {
    guard case .scalar(let scalar, let tag, let anchor) = node,
      case .plain = scalar.style
    else {
      return (node, 0)
    }

    let baseLocation = location(lineIndex: startIndex)
    try validatePlainScalarText(scalar.text, location: baseLocation)

    let initialRaw = lines[startIndex].content
    let initialStripped = lines[startIndex].contentStrippingComment()
    if initialRaw != initialStripped {
      return (node, 0)
    }

    let folded = foldPlainScalar(initial: scalar.text, startIndex: startIndex, contextIndent: contextIndent)
    if folded.linesConsumed == 0 {
      return (node, 0)
    }
    try validatePlainScalarText(folded.text, location: baseLocation)
    let updated = YAMLScalar(text: folded.text, style: .plain)
    return (.scalar(updated, tag: tag, anchor: anchor), folded.linesConsumed)
  }

  private func foldPlainScalar(
    initial: String,
    startIndex: Int,
    contextIndent: Int?
  ) -> (text: String, linesConsumed: Int) {
    let initialLine = lines[startIndex]
    let initialIndent = contextIndent ?? initialLine.indent
    let initialContent = initialLine.trimmedContent
    var requireMoreIndent = false
    if isSequenceIndicator(initialContent) {
      requireMoreIndent = true
    } else if let entry = splitMappingEntry(initialContent),
      let value = entry.value,
      !value.yamlTrimmed().isEmpty
    {
      requireMoreIndent = true
    }
    let minIndent = requireMoreIndent ? initialIndent + 1 : initialIndent
    var collected: [(line: String, indent: Int)] = []
    var cursor = startIndex + 1
    var baseIndent: Int?

    while cursor < lines.count {
      let line = lines[cursor]
      let trimmed = line.trimmedContent
      if trimmed.isEmpty {
        // Check if raw line has non-whitespace (comment-only line)
        if !line.raw.yamlTrimmed().isEmpty {
          break
        }
        collected.append((line: "", indent: line.indent))
        cursor += 1
        continue
      }
      if line.indent < minIndent {
        break
      }
      if trimmed == "..." {
        break
      }
      if trimmed.hasPrefix("---") {
        let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if markerIndex == trimmed.endIndex || trimmed[markerIndex].isWhitespace {
          break
        }
      }
      if trimmed.hasPrefix("...") {
        let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if markerIndex == trimmed.endIndex || trimmed[markerIndex].isWhitespace {
          break
        }
      }
      if line.indent == initialIndent {
        if isSequenceIndicator(trimmed) || splitMappingEntry(trimmed) != nil || isExplicitMappingIndicator(trimmed) {
          break
        }
      }
      if baseIndent == nil {
        baseIndent = line.indent
      }
      let content = line.contentStrippingComment()
      collected.append((line: content, indent: line.indent))
      if line.content != content {
        cursor += 1
        break
      }
      cursor += 1
    }

    guard let baseIndent else {
      return (initial, 0)
    }

    var linesToFold: [(line: String, indent: Int)] = []
    linesToFold.reserveCapacity(collected.count + 1)
    linesToFold.append((line: initial, indent: baseIndent))
    linesToFold.append(contentsOf: collected)

    var folded = foldPlainLines(linesToFold, baseIndent: baseIndent)
    while folded.last == "\n" {
      folded.removeLast()
    }
    return (folded, collected.count)
  }

  private func foldPlainScalarFromInline(
    initial: String,
    startIndex: Int,
    contextIndent: Int
  ) -> (text: String, linesConsumed: Int) {
    let initialIndent = contextIndent
    let initialContent = initial.yamlTrimmed()
    var requireMoreIndent = false
    if isSequenceIndicator(initialContent) {
      requireMoreIndent = true
    } else if let entry = splitMappingEntry(initialContent),
      let value = entry.value,
      !value.yamlTrimmed().isEmpty
    {
      requireMoreIndent = true
    }
    let minIndent = requireMoreIndent ? initialIndent + 1 : initialIndent
    var collected: [(line: String, indent: Int)] = []
    var cursor = startIndex + 1
    var baseIndent: Int?

    while cursor < lines.count {
      let line = lines[cursor]
      let trimmed = line.trimmedContent
      if trimmed.isEmpty {
        // Check if raw line has non-whitespace (comment-only line)
        if !line.raw.yamlTrimmed().isEmpty {
          break
        }
        collected.append((line: "", indent: line.indent))
        cursor += 1
        continue
      }
      if line.indent < minIndent {
        break
      }
      if trimmed == "..." {
        break
      }
      if trimmed.hasPrefix("---") {
        let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if markerIndex == trimmed.endIndex || trimmed[markerIndex].isWhitespace {
          break
        }
      }
      if trimmed.hasPrefix("...") {
        let markerIndex = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if markerIndex == trimmed.endIndex || trimmed[markerIndex].isWhitespace {
          break
        }
      }
      if line.indent == initialIndent {
        if isSequenceIndicator(trimmed) || splitMappingEntry(trimmed) != nil || isExplicitMappingIndicator(trimmed) {
          break
        }
      }
      if baseIndent == nil {
        baseIndent = line.indent
      }
      let content = line.contentStrippingComment()
      collected.append((line: content, indent: line.indent))
      if line.content != content {
        cursor += 1
        break
      }
      cursor += 1
    }

    guard let baseIndent else {
      return (initial, 0)
    }

    var linesToFold: [(line: String, indent: Int)] = []
    linesToFold.reserveCapacity(collected.count + 1)
    linesToFold.append((line: initial, indent: baseIndent))
    linesToFold.append(contentsOf: collected)

    var folded = foldPlainLines(linesToFold, baseIndent: baseIndent)
    while folded.last == "\n" {
      folded.removeLast()
    }
    return (folded, collected.count)
  }

  private func foldPlainLines(_ lines: [(line: String, indent: Int)], baseIndent: Int) -> String {
    var result = ""
    var first = true
    var previousEmpty = false

    for entry in lines {
      let line = trimTrailingWhitespace(entry.line)
      if first {
        result.append(line)
        first = false
        previousEmpty = line.isEmpty
        continue
      }

      if line.isEmpty {
        result.append("\n")
        previousEmpty = true
        continue
      }

      if previousEmpty {
        if !result.hasSuffix("\n") {
          result.append("\n")
        }
      } else {
        result.append(" ")
      }
      result.append(line)
      previousEmpty = false
    }

    return result
  }

  private mutating func skipEmptyLines() {
    while index < lines.count {
      let content = lines[index].trimmedContent
      guard content.isEmpty else {
        break
      }
      index += 1
    }
  }

  private func nextNonEmptyLineIndex(from start: Int) -> Int? {
    var cursor = start
    while cursor < lines.count {
      let content = lines[cursor].trimmedContent
      if !content.isEmpty {
        return cursor
      }
      cursor += 1
    }
    return nil
  }

  private func isDocumentStart(_ line: Line) -> Bool {
    let trimmed = line.trimmedContent
    guard trimmed.hasPrefix("---") else { return false }
    if trimmed == "---" {
      return true
    }
    let index = trimmed.index(trimmed.startIndex, offsetBy: 3)
    return index < trimmed.endIndex && trimmed[index].isWhitespace
  }

  private func isDocumentEnd(_ line: Line) -> Bool {
    line.trimmedContent == "..."
  }

  /// Checks if content starts with "- " or is just "-".
  /// Content is expected to be already trimmed.
  private func isSequenceIndicator(_ content: String) -> Bool {
    guard let first = content.utf8.first, first == UInt8(ascii: "-") else { return false }
    let utf8 = content.utf8
    if utf8.count == 1 { return true }
    let second = utf8[utf8.index(after: utf8.startIndex)]
    return second == 0x20 || second == 0x09  // space or tab
  }

  /// Checks if content starts with "? " or is just "?".
  /// Content is expected to be already trimmed.
  private func isExplicitMappingIndicator(_ content: String) -> Bool {
    guard let first = content.utf8.first, first == UInt8(ascii: "?") else { return false }
    let utf8 = content.utf8
    if utf8.count == 1 { return true }
    let second = utf8[utf8.index(after: utf8.startIndex)]
    return second == 0x20 || second == 0x09
  }

  /// Checks if content starts with "[" or "{".
  /// Content is expected to be already trimmed.
  private func isFlowCollectionIndicator(_ content: String) -> Bool {
    guard let first = content.utf8.first else { return false }
    return first == UInt8(ascii: "[") || first == UInt8(ascii: "{")
  }

  struct Decorators {
    let tag: String?
    let anchor: String?
  }

  private func parseDecorators(
    from content: String,
    lineIndex: Int,
    baseColumn: Int
  ) throws -> (decorators: Decorators, remainder: String, remainderColumn: Int) {
    let lineNumber = lineNumber(for: lineIndex)
    var scanner = InlineParser(text: content, baseLine: lineNumber, lineStartColumns: [baseColumn])
    let rawDecorators = try scanner.parseDecorators()
    let resolvedTag = try resolveTag(rawDecorators.tag)
    let decorators = Decorators(tag: resolvedTag, anchor: rawDecorators.anchor)
    scanner.skipWhitespaceAndComments()
    let remainder = scanner.remaining
    let remainderOffset = content.distance(from: content.startIndex, to: scanner.index)
    let remainderColumn = baseColumn + remainderOffset
    return (decorators, remainder, remainderColumn)
  }

  private func hasTabAfterIndicator(_ content: String, indicator: Character) -> Bool {
    guard let first = content.first, first == indicator else { return false }
    var cursor = content.index(after: content.startIndex)
    while cursor < content.endIndex {
      let ch = content[cursor]
      if ch == "\t" {
        return true
      }
      if ch == " " {
        content.formIndex(after: &cursor)
        continue
      }
      break
    }
    return false
  }

  private func validatePlainScalarText(_ text: String, location: YAML.ParseError.Location) throws {
    guard !text.isEmpty else { return }
    var cursor = text.startIndex
    var currentLine = location.line
    var currentColumn = location.column
    while cursor < text.endIndex {
      let char = text[cursor]
      if char == ":" {
        let nextIndex = text.index(after: cursor)
        if nextIndex < text.endIndex, text[nextIndex].isWhitespace {
          throw YAML.ParseError.invalidSyntax(
            "Invalid plain scalar",
            location: .init(line: currentLine, column: currentColumn)
          )
        }
      }
      if char.isNewline {
        currentLine += 1
        currentColumn = 1
      } else {
        currentColumn += 1
      }
      text.formIndex(after: &cursor)
    }
  }

  private func decodeTagSuffix(_ text: String) throws -> String {
    guard text.contains("%") else { return text }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.utf8.count)
    var index = text.startIndex

    func hexValue(_ char: Character) -> UInt8? {
      guard let scalar = char.unicodeScalars.first else { return nil }
      switch scalar.value {
      case 48...57:
        return UInt8(scalar.value - 48)
      case 65...70:
        return UInt8(scalar.value - 55)
      case 97...102:
        return UInt8(scalar.value - 87)
      default:
        return nil
      }
    }

    while index < text.endIndex {
      let char = text[index]
      if char == "%" {
        let next1 = text.index(after: index)
        guard next1 < text.endIndex else {
          throw syntaxError("Invalid tag")
        }
        let next2 = text.index(after: next1)
        guard next2 < text.endIndex else {
          throw syntaxError("Invalid tag")
        }
        guard let hi = hexValue(text[next1]), let lo = hexValue(text[next2]) else {
          throw syntaxError("Invalid tag")
        }
        bytes.append((hi << 4) | lo)
        index = text.index(after: next2)
        continue
      }
      bytes.append(contentsOf: String(char).utf8)
      text.formIndex(after: &index)
    }

    return String(decoding: bytes, as: UTF8.self)
  }

  private func resolveTag(_ tag: String?) throws -> String? {
    guard let tag else { return nil }
    if tag.hasPrefix("!<"), tag.hasSuffix(">"), tag.count > 3 {
      let start = tag.index(tag.startIndex, offsetBy: 2)
      let end = tag.index(before: tag.endIndex)
      return String(tag[start..<end])
    }
    if tag == "!" {
      return tag
    }

    if tag.hasPrefix("!!") {
      let suffix = try decodeTagSuffix(String(tag.dropFirst(2)))
      let prefix = tagHandles["!!"] ?? YAMLParser.defaultTagHandles["!!", default: "tag:yaml.org,2002:"]
      return suffix.isEmpty ? prefix : "\(prefix)\(suffix)"
    }

    guard tag.hasPrefix("!") else {
      return tag
    }

    let afterBang = tag.index(after: tag.startIndex)
    if let handleEnd = tag[afterBang...].firstIndex(of: "!") {
      let handle = String(tag[..<tag.index(after: handleEnd)])
      let suffix = try decodeTagSuffix(String(tag[tag.index(after: handleEnd)...]))
      guard let prefix = tagHandles[handle] else {
        throw syntaxError("Unknown tag handle")
      }
      return "\(prefix)\(suffix)"
    }

    guard let prefix = tagHandles["!"] else {
      throw syntaxError("Unknown tag handle")
    }
    let suffix = try decodeTagSuffix(String(tag.dropFirst()))
    if suffix.isEmpty {
      return "!"
    }
    if prefix == "!" {
      return "!\(suffix)"
    }
    return "\(prefix)\(suffix)"
  }

  private func attach(_ node: YAMLNode, tag: String?, anchor: String?) throws -> YAMLNode {
    guard tag != nil || anchor != nil else { return node }
    switch node {
    case .scalar(let scalar, let existingTag, let existingAnchor):
      if tag != nil, existingTag != nil {
        throw syntaxError("Multiple tags on node")
      }
      if anchor != nil, existingAnchor != nil {
        throw syntaxError("Multiple anchors on node")
      }
      return .scalar(scalar, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .sequence(let array, let style, let existingTag, let existingAnchor):
      if tag != nil, existingTag != nil {
        throw syntaxError("Multiple tags on node")
      }
      if anchor != nil, existingAnchor != nil {
        throw syntaxError("Multiple anchors on node")
      }
      return .sequence(array, style: style, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .mapping(let map, let style, let existingTag, let existingAnchor):
      if tag != nil, existingTag != nil {
        throw syntaxError("Multiple tags on node")
      }
      if anchor != nil, existingAnchor != nil {
        throw syntaxError("Multiple anchors on node")
      }
      return .mapping(map, style: style, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .alias:
      if tag != nil || anchor != nil {
        throw syntaxError("Alias cannot have tag or anchor")
      }
      return node
    }
  }

  /// Content is expected to be already trimmed by the caller.
  private func splitMappingEntry(_ content: String) -> (key: String, value: String?)? {
    if (content.first == "*" || content.first == "&"),
      !content.contains(where: { $0.isWhitespace }),
      content.hasSuffix(":")
    {
      return nil
    }
    var inSingle = false
    var inDouble = false
    var depth = 0
    var escapeDouble = false
    var skipSingle = false
    func isQuoteStart(at index: Int) -> Bool {
      if index == 0 {
        return true
      }
      let prev = content[content.index(content.startIndex, offsetBy: index - 1)]
      return prev.isWhitespace || prev == "[" || prev == "{" || prev == ","
    }
    for (idx, char) in content.enumerated() {
      if skipSingle {
        skipSingle = false
        continue
      }
      if inDouble {
        if escapeDouble {
          escapeDouble = false
          continue
        }
        if char == "\\" {
          escapeDouble = true
          continue
        }
        if char == "\"" {
          inDouble = false
        }
        continue
      }
      if inSingle {
        if char == "'" {
          let nextIndex = content.index(content.startIndex, offsetBy: idx + 1)
          if nextIndex < content.endIndex, content[nextIndex] == "'" {
            skipSingle = true
          } else {
            inSingle = false
          }
        }
        continue
      }
      switch char {
      case "'":
        if isQuoteStart(at: idx) {
          inSingle = true
        }
      case "\"":
        if isQuoteStart(at: idx) {
          inDouble = true
        }
      case "[" where !inSingle && !inDouble:
        depth += 1
      case "]" where !inSingle && !inDouble:
        depth = max(0, depth - 1)
      case "{" where !inSingle && !inDouble:
        depth += 1
      case "}" where !inSingle && !inDouble:
        depth = max(0, depth - 1)
      case ":" where !inSingle && !inDouble && depth == 0:
        let nextIndex = content.index(content.startIndex, offsetBy: idx + 1)
        if nextIndex < content.endIndex, !content[nextIndex].isWhitespace {
          continue
        }
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

  private func collectFlowText(
    startIndex: Int,
    firstContent: String,
    firstColumn: Int,
    minimumIndent: Int
  ) throws -> (text: String, linesConsumed: Int, lineStartColumns: [Int]) {
    var pieces: [String] = []
    pieces.reserveCapacity(4)
    var lineStartColumns: [Int] = [firstColumn]

    var inSingle = false
    var inDouble = false
    var escape = false
    var depth = 0
    var invalidClosure = false

    func scan(_ text: String) -> Bool {
      for char in text {
        if inDouble {
          if escape {
            escape = false
            continue
          }
          if char == "\\" {
            escape = true
            continue
          }
          if char == "\"" {
            inDouble = false
          }
          continue
        }
        if inSingle {
          if char == "'" {
            inSingle = false
          }
          continue
        }

        switch char {
        case "\"":
          inDouble = true
        case "'":
          inSingle = true
        case "[", "{":
          depth += 1
        case "]", "}":
          depth -= 1
          if depth < 0 {
            invalidClosure = true
            return true
          }
          if depth == 0 {
            return true
          }
        default:
          continue
        }
      }
      return false
    }

    pieces.append(firstContent)
    var linesConsumed = 1
    if scan(firstContent) && depth == 0 {
      if invalidClosure {
        throw syntaxError("Unexpected flow collection terminator")
      }
      return (pieces.joined(separator: "\n"), linesConsumed, lineStartColumns)
    }

    var cursor = startIndex + 1
    while cursor < lines.count {
      let line = lines[cursor]
      if line.indent == 0 {
        let trimmedLine = line.trimmedContent
        if trimmedLine.hasPrefix("---") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw syntaxError("Document marker inside flow collection", lineIndex: cursor)
          }
        }
        if trimmedLine.hasPrefix("...") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw syntaxError("Document marker inside flow collection", lineIndex: cursor)
          }
        }
      }
      let content = line.contentStrippingComment()
      let trimmed = content.yamlTrimmed()
      if !trimmed.isEmpty {
        let spaceIndent = leadingSpaceCount(line.raw)
        if spaceIndent < minimumIndent {
          throw indentationError(lineIndex: cursor)
        }
      }
      pieces.append(content)
      lineStartColumns.append(line.indent + 1)
      linesConsumed += 1
      if scan(content) && depth == 0 {
        if invalidClosure {
          throw syntaxError("Unexpected flow collection terminator")
        }
        return (pieces.joined(separator: "\n"), linesConsumed, lineStartColumns)
      }
      cursor += 1
    }

    throw syntaxError("Unterminated flow collection")
  }

  private func hasClosingQuote(in text: String, quote: Character) -> Bool {
    var escape = false
    var cursor = text.startIndex
    if cursor < text.endIndex, text[cursor] == quote {
      text.formIndex(after: &cursor)
    }
    while cursor < text.endIndex {
      let char = text[cursor]
      if quote == "\"" {
        if escape {
          escape = false
        } else if char == "\\" {
          escape = true
        } else if char == quote {
          return true
        }
        text.formIndex(after: &cursor)
      } else {
        if char == quote {
          let nextIndex = text.index(after: cursor)
          if nextIndex < text.endIndex, text[nextIndex] == quote {
            cursor = text.index(after: nextIndex)
            continue
          }
          return true
        }
        text.formIndex(after: &cursor)
      }
    }
    return false
  }

  private func collectQuotedText(
    startIndex: Int,
    firstContent: String,
    quote: Character,
    parentIndent: Int,
    firstColumn: Int
  ) throws -> (text: String, linesConsumed: Int, lineStartColumns: [Int]) {
    var pieces: [String] = []
    pieces.reserveCapacity(4)
    var lineStartColumns: [Int] = [firstColumn]
    pieces.append(firstContent)
    var linesConsumed = 1
    var escape = false

    func scan(_ text: String, startAt: String.Index) -> Bool {
      var cursor = startAt
      while cursor < text.endIndex {
        let char = text[cursor]
        if quote == "\"" {
          if escape {
            escape = false
          } else if char == "\\" {
            escape = true
          } else if char == quote {
            return true
          }
          text.formIndex(after: &cursor)
        } else {
          if char == quote {
            let nextIndex = text.index(after: cursor)
            if nextIndex < text.endIndex, text[nextIndex] == quote {
              cursor = text.index(after: nextIndex)
              continue
            }
            return true
          }
          text.formIndex(after: &cursor)
        }
      }
      return false
    }

    var firstStart = firstContent.startIndex
    if firstStart < firstContent.endIndex, firstContent[firstStart] == quote {
      firstContent.formIndex(after: &firstStart)
    }
    if scan(firstContent, startAt: firstStart) {
      return (pieces.joined(separator: "\n"), linesConsumed, lineStartColumns)
    }

    var cursor = startIndex + 1
    while cursor < lines.count {
      let line = lines[cursor]
      if line.indent == 0 {
        let trimmedLine = line.trimmedContent
        if trimmedLine.hasPrefix("---") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw syntaxError("Document marker inside quoted scalar", lineIndex: cursor)
          }
        }
        if trimmedLine.hasPrefix("...") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw syntaxError("Document marker inside quoted scalar", lineIndex: cursor)
          }
        }
      }
      let trimmed = line.content.yamlTrimmed()
      if trimmed.isEmpty {
        pieces.append("")
        lineStartColumns.append(line.indent + 1)
        linesConsumed += 1
        cursor += 1
        continue
      }
      if line.indent < parentIndent {
        break
      }
      if hasTabInIndent(line, requiredIndent: parentIndent) {
        throw indentationError(lineIndex: cursor)
      }
      let content = line.content
      pieces.append(content)
      lineStartColumns.append(line.indent + 1)
      linesConsumed += 1
      if scan(content, startAt: content.startIndex) {
        return (pieces.joined(separator: "\n"), linesConsumed, lineStartColumns)
      }
      cursor += 1
    }

    let quoteDescription = quote == "'" ? "single-quoted" : "double-quoted"
    throw syntaxError("Unterminated \(quoteDescription) scalar", lineIndex: cursor)
  }

  /// Expands multi-line flow collections and quoted strings that span across lines.
  /// Handles `[`/`{` flow collections, `"` double-quoted, and `'` single-quoted scalars.
  private func expandInlineText(
    _ text: String,
    startIndex: Int,
    parentIndent: Int,
    firstColumn: Int,
    minimumFlowIndent: Int
  ) throws -> (text: String, extraLines: Int, lineStartColumns: [Int]) {
    if text.first == "[" || text.first == "{" {
      let flow = try collectFlowText(
        startIndex: startIndex,
        firstContent: text,
        firstColumn: firstColumn,
        minimumIndent: minimumFlowIndent
      )
      return (flow.text, flow.linesConsumed - 1, flow.lineStartColumns)
    }
    if text.first == "\"" {
      return try expandDoubleQuotedInlineText(
        text, startIndex: startIndex, parentIndent: parentIndent, firstColumn: firstColumn
      )
    }
    if text.first == "'" {
      return try expandSingleQuotedInlineText(
        text, startIndex: startIndex, parentIndent: parentIndent, firstColumn: firstColumn
      )
    }
    return (text, 0, [firstColumn])
  }

  private func expandDoubleQuotedInlineText(
    _ text: String,
    startIndex: Int,
    parentIndent: Int,
    firstColumn: Int
  ) throws -> (text: String, extraLines: Int, lineStartColumns: [Int]) {
    guard text.first == "\"", !hasClosingQuote(in: text, quote: "\"") else {
      return (text, 0, [firstColumn])
    }
    let collected = try collectQuotedText(
      startIndex: startIndex,
      firstContent: text,
      quote: "\"",
      parentIndent: parentIndent,
      firstColumn: firstColumn
    )
    return (collected.text, collected.linesConsumed - 1, collected.lineStartColumns)
  }

  /// Resolves the value after `:` in a block mapping entry, handling empty values,
  /// block scalars, nested sequences/mappings, inline scalars, and flow collections.
  private mutating func resolveBlockMappingValue(
    expectedIndent: Int,
    allowNestedMapping: Bool
  ) throws -> YAMLNode {
    guard let valueIndex = nextNonEmptyLineIndex(from: index),
      lines[valueIndex].indent == expectedIndent
    else {
      return .emptyPlainScalar
    }

    let valueLine = lines[valueIndex]
    let valueDecorated = try parseDecorators(
      from: valueLine.contentStrippingComment(),
      lineIndex: valueIndex,
      baseColumn: valueLine.indent + 1
    )
    var valueContent = valueDecorated.remainder.yamlTrimmed()
    guard valueContent.hasPrefix(":") else {
      return .emptyPlainScalar
    }

    let tabSeparated = hasTabAfterIndicator(valueContent, indicator: ":")
    valueContent.removeFirst()
    let remainder = valueContent.yamlTrimmed()
    if tabSeparated {
      if isSequenceIndicator(remainder) || isExplicitMappingIndicator(remainder)
        || splitMappingEntry(remainder) != nil
      {
        throw indentationError()
      }
    }

    index = valueIndex + 1

    if remainder.isEmpty {
      return try resolveEmptyValueRemainder(
        expectedIndent: expectedIndent,
        decorators: valueDecorated.decorators
      )
    }

    if remainder.hasPrefix("|") || remainder.hasPrefix(">") {
      let savedIndex = index
      index = valueIndex
      let node = try parseBlockScalar(
        content: remainder,
        decorators: valueDecorated.decorators,
        baseIndent: expectedIndent
      )
      index = max(index, savedIndex)
      return node
    }

    if isSequenceIndicator(remainder) {
      let nested = try parseBlockSequence(
        decorators: Decorators(tag: nil, anchor: nil),
        expectedIndent: expectedIndent + 2,
        firstRemainder: remainder,
        consumeFirstLine: false
      )
      return try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
    }

    if allowNestedMapping,
      splitMappingEntry(remainder) != nil || isExplicitMappingIndicator(remainder)
    {
      let nested = try parseBlockMapping(
        decorators: Decorators(tag: nil, anchor: nil),
        expectedIndent: expectedIndent + 2,
        firstRemainder: remainder,
        consumeFirstLine: false
      )
      return try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
    }

    let expanded = try expandInlineText(
      remainder,
      startIndex: valueIndex,
      parentIndent: expectedIndent + 1,
      firstColumn: valueDecorated.remainderColumn,
      minimumFlowIndent: leadingSpaceCount(lines[valueIndex].raw) + 1
    )
    var inlineParser = InlineParser(
      text: expanded.text,
      baseLine: valueLine.number,
      lineStartColumns: expanded.lineStartColumns
    )
    var valueNode = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent + 1)
    valueNode = try attach(
      valueNode,
      tag: valueDecorated.decorators.tag,
      anchor: valueDecorated.decorators.anchor
    )
    let folded = try foldPlainScalarIfNeeded(valueNode, startIndex: valueIndex, contextIndent: expectedIndent)
    valueNode = folded.node
    if folded.linesConsumed > 0 {
      index += folded.linesConsumed
    }
    if expanded.extraLines > 0 {
      index += expanded.extraLines
    }
    inlineParser.skipWhitespaceAndComments()
    if inlineParser.peek != nil {
      throw inlineParser.syntaxError("Unexpected trailing content")
    }
    return valueNode
  }

  private mutating func resolveEmptyValueRemainder(
    expectedIndent: Int,
    decorators: Decorators
  ) throws -> YAMLNode {
    guard let nextIndex = nextNonEmptyLineIndex(from: index) else {
      return try attach(.emptyPlainScalar, tag: decorators.tag, anchor: decorators.anchor)
    }
    let nextLine = lines[nextIndex]
    if nextLine.indent > expectedIndent {
      skipEmptyLines()
      let node = try parseNode(expectedIndent: expectedIndent + 1)
      return try attach(node, tag: decorators.tag, anchor: decorators.anchor)
    }
    if nextLine.indent == expectedIndent, isSequenceIndicator(nextLine.trimmedContent) {
      skipEmptyLines()
      let nested = try parseBlockSequence(
        decorators: Decorators(tag: nil, anchor: nil),
        expectedIndent: expectedIndent,
        firstRemainder: lines[index].contentStrippingComment()
      )
      return try attach(nested, tag: decorators.tag, anchor: decorators.anchor)
    }
    return try attach(.emptyPlainScalar, tag: decorators.tag, anchor: decorators.anchor)
  }

  private func expandSingleQuotedInlineText(
    _ text: String,
    startIndex: Int,
    parentIndent: Int,
    firstColumn: Int
  ) throws -> (text: String, extraLines: Int, lineStartColumns: [Int]) {
    guard text.first == "'", !hasClosingQuote(in: text, quote: "'") else {
      return (text, 0, [firstColumn])
    }
    let collected = try collectQuotedText(
      startIndex: startIndex,
      firstContent: text,
      quote: "'",
      parentIndent: parentIndent,
      firstColumn: firstColumn
    )
    return (collected.text, collected.linesConsumed - 1, collected.lineStartColumns)
  }
}

