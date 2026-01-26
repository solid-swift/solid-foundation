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
          if idx > 0 {
            let prevIndex = text.index(text.startIndex, offsetBy: idx - 1)
            if !text[prevIndex].isWhitespace {
              continue
            }
          }
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
  private static let defaultTagHandles: [String: String] = [
    "!": "!",
    "!!": "tag:yaml.org,2002:",
  ]
  private var tagHandles: [String: String] = YAMLParser.defaultTagHandles

  init(text: String) throws {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
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
  }

  mutating func parseFirstDocument() throws -> YAMLNode {
    let docs = try parseDocuments()
    if let first = docs.first {
      return first
    }
    let emptyScalar = YAMLScalar(text: "", style: .plain)
    return .scalar(emptyScalar, tag: nil, anchor: nil)
  }

  mutating func parseDocuments(limit: Int? = nil) throws -> [YAMLNode] {
    try parseDocumentStream(limit: limit).map { $0.node }
  }

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

    while index < lines.count && (limit == nil || documents.count < limit!) {
      var sawDirective = false
      var sawYamlDirective = false
      pendingTagHandles = YAMLParser.defaultTagHandles
      skipEmptyLines()
      if requireDocumentStart, index < lines.count {
        let trimmed = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
        if !isDocumentStart(lines[index]),
           !isDocumentEnd(lines[index]),
           !trimmed.hasPrefix("%") {
          throw YAML.Error.invalidSyntax("Missing document start marker")
        }
      }
      while index < lines.count {
        let content = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("...") && content != "..." {
          let index = content.index(content.startIndex, offsetBy: 3)
          if index < content.endIndex, content[index].isWhitespace {
            throw YAML.Error.invalidSyntax("Invalid document end marker")
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
            throw YAML.Error.invalidSyntax("Directive without document end marker")
          }
          sawDirective = true
          let directive = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
          let parts = directive.split(whereSeparator: { $0.isWhitespace })
          if let name = parts.first, name == "%YAML" {
            if sawYamlDirective {
              throw YAML.Error.invalidSyntax("Duplicate %YAML directive")
            }
            if parts.count != 2 || parts[0] != "%YAML" {
              throw YAML.Error.invalidSyntax("Invalid %YAML directive")
            }
            let version = parts[1]
            let versionParts = version.split(separator: ".")
            if versionParts.count != 2 || versionParts.contains(where: { $0.isEmpty || $0.contains(where: { !$0.isNumber }) }) {
              throw YAML.Error.invalidSyntax("Invalid %YAML directive")
            }
            sawYamlDirective = true
          } else if let name = parts.first, name == "%TAG" {
            if parts.count != 3 || parts[0] != "%TAG" {
              throw YAML.Error.invalidSyntax("Invalid %TAG directive")
            }
            let handle = String(parts[1])
            let prefix = String(parts[2])
            if handle != "!" {
              if !handle.hasPrefix("!") || !handle.hasSuffix("!") || handle.count < 2 {
                throw YAML.Error.invalidSyntax("Invalid %TAG directive")
              }
            }
            if prefix.isEmpty {
              throw YAML.Error.invalidSyntax("Invalid %TAG directive")
            }
            pendingTagHandles[handle] = prefix
          }
          index += 1
          continue
        }
        break
      }
      skipEmptyLines()
      guard index < lines.count else {
        if sawDirective {
          throw YAML.Error.invalidSyntax("Directive without document")
        }
        break
      }

      let trimmed = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("...") && trimmed != "..." {
        let index = trimmed.index(trimmed.startIndex, offsetBy: 3)
        if index < trimmed.endIndex, trimmed[index].isWhitespace {
          throw YAML.Error.invalidSyntax("Invalid document end marker")
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
        let content = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
        let remainder: String
        if content.hasPrefix("---") {
          remainder = String(content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else {
          remainder = content
        }
        if !remainder.isEmpty {
          let decorated = try parseDecorators(from: remainder)
          let trimmed = decorated.remainder.trimmingCharacters(in: .whitespaces)
          if trimmed.isEmpty {
            index += 1
            skipEmptyLines()
            guard index < lines.count else {
              throw YAML.Error.invalidSyntax("Unexpected end of document")
            }
            let indent = lines[index].indent
            var node = try parseNode(expectedIndent: indent)
            node = try attach(node, tag: decorated.decorators.tag, anchor: decorated.decorators.anchor)
            appendDocument(node, explicitStart: explicitStart)
            tagHandles = YAMLParser.defaultTagHandles
            requireDocumentStart = true
            continue
          }
          if splitMappingEntry(trimmed) != nil {
            throw YAML.Error.invalidSyntax("Invalid document start content")
          }
          if trimmed.hasPrefix("|") || trimmed.hasPrefix(">") {
            let node = try parseBlockScalar(content: trimmed, decorators: decorated.decorators, baseIndent: -1)
            appendDocument(node, explicitStart: explicitStart)
            tagHandles = YAMLParser.defaultTagHandles
            requireDocumentStart = true
            continue
          }
          let startIndex = index
          var inlineText = trimmed
          var extraLines = 0
          if inlineText.first == "[" || inlineText.first == "{" {
            let flow = try collectFlowText(
              startIndex: startIndex,
              firstContent: decorated.remainder,
              minimumIndent: leadingSpaceCount(lines[startIndex].raw))
            inlineText = flow.text
            extraLines = flow.linesConsumed - 1
          } else if inlineText.first == "\"" {
            let expanded = try expandDoubleQuotedInlineText(
              inlineText,
              startIndex: startIndex,
              parentIndent: 0)
            inlineText = expanded.text
            extraLines = expanded.extraLines
          } else if inlineText.first == "'" {
            let expanded = try expandSingleQuotedInlineText(
              inlineText,
              startIndex: startIndex,
              parentIndent: 0)
            inlineText = expanded.text
            extraLines = expanded.extraLines
          }
          var inlineParser = InlineParser(text: inlineText)
          var node = try parseInlineNode(parser: &inlineParser, baseIndent: 0)
          node = try attach(node, tag: decorated.decorators.tag, anchor: decorated.decorators.anchor)
          inlineParser.skipWhitespaceAndComments()
          if inlineParser.peek != nil {
            throw YAML.Error.invalidSyntax("Unexpected trailing content")
          }
          var linesConsumed = 1 + extraLines
          if case .scalar(let scalar, let tag, let anchor) = node,
             case .plain = scalar.style {
            try validatePlainScalarText(scalar.text)
            let folded = foldPlainScalarFromInline(initial: scalar.text, startIndex: startIndex, contextIndent: 0)
            if folded.linesConsumed > 0 {
              try validatePlainScalarText(folded.text)
              let updated = YAMLScalar(text: folded.text, style: .plain)
              node = .scalar(updated, tag: tag, anchor: anchor)
              linesConsumed += folded.linesConsumed
            }
          }
          index += linesConsumed
          appendDocument(node, explicitStart: explicitStart)
          tagHandles = YAMLParser.defaultTagHandles
          requireDocumentStart = true
          continue
        }
        index += 1
        skipEmptyLines()
        if index >= lines.count || isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          appendDocument(.scalar(emptyScalar, tag: nil, anchor: nil), explicitStart: explicitStart)
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
    let trimmedLine = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)

    if line.indent < expectedIndent {
      throw YAML.Error.invalidIndentation
    }

    if line.indent == 0 && trimmedLine.hasPrefix("%") {
      throw YAML.Error.invalidSyntax("Directive without document end marker")
    }

    // Capture decorators before deciding shape.
    let decorated = try parseDecorators(from: line.contentStrippingComment())
    let decorators = decorated.decorators
    let rawContent = decorated.remainder
    let trimmedContent = rawContent.trimmingCharacters(in: .whitespaces)
    let tabIndentCheck = expectedIndent > 0 ? expectedIndent : 1
    if hasTabInIndent(line, requiredIndent: tabIndentCheck),
       !trimmedLine.isEmpty,
       !isFlowCollectionIndicator(trimmedContent) {
      throw YAML.Error.invalidIndentation
    }

    if trimmedContent.isEmpty, decorators.tag != nil || decorators.anchor != nil {
      index += 1
      skipEmptyLines()
      if index >= lines.count || isDocumentStart(lines[index]) || isDocumentEnd(lines[index]) {
        let emptyScalar = YAMLScalar(text: "", style: .plain)
        let node = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
        return try attach(node, tag: decorators.tag, anchor: decorators.anchor)
      }
      let nextLine = lines[index]
      let nextContent = nextLine.contentStrippingComment().trimmingCharacters(in: .whitespaces)
      if nextLine.indent < expectedIndent, isSequenceIndicator(nextContent) {
        let nested = try parseBlockSequence(
          decorators: Decorators(tag: nil, anchor: nil),
          expectedIndent: nextLine.indent,
          firstRemainder: nextLine.contentStrippingComment())
        let decorated = try attach(nested, tag: decorators.tag, anchor: decorators.anchor)
        return decorated
      }
      var node = try parseNode(expectedIndent: expectedIndent)
      node = try attach(node, tag: decorators.tag, anchor: decorators.anchor)
      return node
    }

    if isSequenceIndicator(rawContent), (decorators.tag != nil || decorators.anchor != nil) {
      throw YAML.Error.invalidSyntax("Sequence entry cannot be preceded by tag or anchor")
    }

    if isSequenceIndicator(rawContent) && line.indent >= expectedIndent {
      return try parseBlockSequence(decorators: decorators, expectedIndent: line.indent, firstRemainder: decorated.remainder)
    }

    if splitMappingEntry(rawContent) != nil, line.indent >= expectedIndent {
      return try parseBlockMapping(
        decorators: Decorators(tag: nil, anchor: nil),
        expectedIndent: line.indent,
        firstRemainder: line.contentStrippingComment())
    }

    if isExplicitMappingIndicator(rawContent) && line.indent >= expectedIndent {
      return try parseBlockMapping(
        decorators: decorators,
        expectedIndent: line.indent,
        firstRemainder: line.contentStrippingComment())
    }

    if trimmedContent.hasPrefix("[") || trimmedContent.hasPrefix("{") {
      let flow = try collectFlowText(
        startIndex: index,
        firstContent: decorated.remainder,
        minimumIndent: leadingSpaceCount(lines[index].raw))
      var inline = InlineParser(text: flow.text)
      var node = try parseInlineNode(parser: &inline, baseIndent: expectedIndent)
      if decorators.tag != nil || decorators.anchor != nil {
        node = try attach(node, tag: decorators.tag, anchor: decorators.anchor)
      }
      inline.skipWhitespaceAndComments()
      if inline.peek != nil {
        throw YAML.Error.invalidSyntax("Unexpected trailing content")
      }
      index += flow.linesConsumed
      return node
    }

    if trimmedContent.hasPrefix("|") || trimmedContent.hasPrefix(">") {
      let baseIndent = expectedIndent - 1
      let node = try parseBlockScalar(content: trimmedContent, decorators: decorators, baseIndent: baseIndent)
      return node
    }

    var inlineText = rawContent
    var extraLines = 0
    if inlineText.first == "\"" {
      let expanded = try expandDoubleQuotedInlineText(inlineText, startIndex: index, parentIndent: expectedIndent)
      inlineText = expanded.text
      extraLines = expanded.extraLines
    } else if inlineText.first == "'" {
      let expanded = try expandSingleQuotedInlineText(inlineText, startIndex: index, parentIndent: expectedIndent)
      inlineText = expanded.text
      extraLines = expanded.extraLines
    }
    var inlineParser = InlineParser(text: inlineText)
    var node = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent)
    if decorators.tag != nil || decorators.anchor != nil {
      node = try attach(node, tag: decorators.tag, anchor: decorators.anchor)
    }
    var linesConsumed = 1 + extraLines
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
    var initialRemainder = firstRemainder
    var consumeFirst = consumeFirstLine
    var sequenceIndent = expectedIndent
    var allowIndentIncrease = !consumeFirstLine

    while index < lines.count {
      let line = lines[index]
      if initialRemainder == nil {
        let trimmed = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
          index += 1
          continue
        }
      }
      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let decorated = try parseDecorators(from: sourceContent)
      let currentDecorators = decorated.decorators
      let content = decorated.remainder
      let skipAdvance = initialRemainder != nil && !consumeFirst
      let entryLineIndex = skipAdvance ? max(index - 1, 0) : index
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
        let trimmedSource = sourceContent.trimmingCharacters(in: .whitespaces)
        let tabIndentCheck = sequenceIndent > 0 ? sequenceIndent : 1
        if hasTabInIndent(line, requiredIndent: tabIndentCheck),
           !trimmedSource.isEmpty,
           !isFlowCollectionIndicator(content) {
          throw YAML.Error.invalidIndentation
        }
      }
      if effectiveIndent != sequenceIndent || !isSequenceIndicator(content) {
        break
      }

      // Move past '-'
      let trimmed = content.trimmingCharacters(in: .whitespaces)
      guard trimmed.first == "-" else { break }
      let tabSeparated = hasTabAfterIndicator(content, indicator: "-")
      let afterDash = trimmed[trimmed.index(after: trimmed.startIndex)...]
      let remainder = String(afterDash).trimmingCharacters(in: .whitespaces)
      if tabSeparated {
        if isSequenceIndicator(remainder) || isExplicitMappingIndicator(remainder) || splitMappingEntry(remainder) != nil {
          throw YAML.Error.invalidIndentation
        }
      }
      if !skipAdvance {
        index += 1
      }

      if remainder.isEmpty {
        if let nextIndex = nextNonEmptyLineIndex(from: index),
           lines[nextIndex].indent > sequenceIndent {
          skipEmptyLines()
          let node = try parseNode(expectedIndent: sequenceIndent + 1)
          let decoratedNode = try attach(node, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
        } else {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
          let decoratedNode = try attach(emptyNode, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
        }
      } else {
        if isSequenceIndicator(remainder) {
          let nested = try parseBlockSequence(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: sequenceIndent + 2,
            firstRemainder: remainder,
            consumeFirstLine: false)
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
            consumeFirstLine: false)
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
            consumeFirstLine: false)
          let decoratedNode = try attach(nested, tag: currentDecorators.tag, anchor: currentDecorators.anchor)
          items.append(decoratedNode)
          initialRemainder = nil
          consumeFirst = true
          continue
        }
        var inline = InlineParser(text: remainder)
        let rawValueDecorators = try inline.parseDecorators()
        let resolvedValueTag = try resolveTag(rawValueDecorators.tag)
        let valueDecorators = Decorators(tag: resolvedValueTag, anchor: rawValueDecorators.anchor)
        inline.skipWhitespaceAndComments()
        if inline.peek == nil {
          if let nextIndex = nextNonEmptyLineIndex(from: index),
             lines[nextIndex].indent > sequenceIndent {
            skipEmptyLines()
            var node = try parseNode(expectedIndent: sequenceIndent + 1)
            node = try attach(node, tag: valueDecorators.tag ?? currentDecorators.tag, anchor: valueDecorators.anchor ?? currentDecorators.anchor)
            items.append(node)
          } else {
            let emptyScalar = YAMLScalar(text: "", style: .plain)
            let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
            let decoratedNode = try attach(
              emptyNode,
              tag: valueDecorators.tag ?? currentDecorators.tag,
              anchor: valueDecorators.anchor ?? currentDecorators.anchor)
            items.append(decoratedNode)
          }
        } else {
          let remainderContent = inline.remaining.trimmingCharacters(in: .whitespaces)
          if remainderContent.hasPrefix("|") || remainderContent.hasPrefix(">") {
            let savedIndex = index
            index = entryLineIndex
            let node = try parseBlockScalar(content: remainderContent, decorators: valueDecorators, baseIndent: sequenceIndent)
            items.append(node)
            index = max(index, savedIndex)
            initialRemainder = nil
            consumeFirst = true
            continue
          }
          var inlineText = inline.remaining
          var extraLines = 0
          if inlineText.first == "[" || inlineText.first == "{" {
            let flow = try collectFlowText(
              startIndex: entryLineIndex,
              firstContent: inlineText,
              minimumIndent: leadingSpaceCount(lines[entryLineIndex].raw) + 1)
            inlineText = flow.text
            extraLines = max(extraLines, flow.linesConsumed - 1)
          }
          if inlineText.first == "\"" {
            let expanded = try expandDoubleQuotedInlineText(
              inlineText,
              startIndex: entryLineIndex,
              parentIndent: sequenceIndent + 1)
            inlineText = expanded.text
            extraLines = expanded.extraLines
          } else if inlineText.first == "'" {
            let expanded = try expandSingleQuotedInlineText(
              inlineText,
              startIndex: entryLineIndex,
              parentIndent: sequenceIndent + 1)
            inlineText = expanded.text
            extraLines = expanded.extraLines
          }
          var valueParser = InlineParser(text: inlineText)
          var node = try parseInlineNode(parser: &valueParser, baseIndent: sequenceIndent + 2)
          node = try attach(
            node,
            tag: valueDecorators.tag ?? currentDecorators.tag,
            anchor: valueDecorators.anchor ?? currentDecorators.anchor)
          if skipAdvance && allowIndentIncrease, index < lines.count {
            let nextLine = lines[index]
            if nextLine.indent > sequenceIndent,
               isSequenceIndicator(nextLine.contentStrippingComment()) {
              sequenceIndent = nextLine.indent
              allowIndentIncrease = false
            }
          }
          let folded = try foldPlainScalarIfNeeded(node, startIndex: entryLineIndex, contextIndent: sequenceIndent)
          node = folded.node
          if folded.linesConsumed > 0 {
            index += folded.linesConsumed
          }
          if extraLines > 0 {
            index += extraLines
          }
          valueParser.skipWhitespaceAndComments()
          if valueParser.peek != nil {
            throw YAML.Error.invalidSyntax("Unexpected trailing content")
          }
          items.append(node)
        }
      }
      initialRemainder = nil
      consumeFirst = true
    }

    return try attach(.sequence(items, style: .block, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseBlockMapping(
    decorators: Decorators,
    expectedIndent: Int,
    firstRemainder: String?,
    consumeFirstLine: Bool = true
  ) throws -> YAMLNode {
    var pairs: [(YAMLNode, YAMLNode)] = []
    var initialRemainder = firstRemainder
    var consumeFirst = consumeFirstLine

    while index < lines.count {
      let line = lines[index]
      if initialRemainder == nil {
        let trimmed = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
          index += 1
          continue
        }
      }
      let skipAdvance = initialRemainder != nil && !consumeFirst
      let effectiveIndent = skipAdvance ? expectedIndent : line.indent
      if effectiveIndent != expectedIndent {
        break
      }

      let sourceContent = initialRemainder ?? line.contentStrippingComment()
      let decorated = try parseDecorators(from: sourceContent)
      if !skipAdvance {
        let trimmedSource = sourceContent.trimmingCharacters(in: .whitespaces)
        let tabIndentCheck = expectedIndent > 0 ? expectedIndent : 1
        if hasTabInIndent(line, requiredIndent: tabIndentCheck), !trimmedSource.isEmpty {
          let remainder = decorated.remainder.trimmingCharacters(in: .whitespaces)
          if !remainder.isEmpty && !isFlowCollectionIndicator(remainder) {
            throw YAML.Error.invalidIndentation
          }
        }
      }
      let entryDecorators = decorated.decorators
      let content = decorated.remainder
      if isExplicitMappingIndicator(content) {
        let tabSeparated = hasTabAfterIndicator(content, indicator: "?")
        var explicitContent = content
        explicitContent.removeFirst()
        let keyContent = explicitContent.trimmingCharacters(in: .whitespaces)
        let keyLineIndex = skipAdvance ? max(index - 1, 0) : index
        let baseAdvance = skipAdvance ? 0 : 1
        if tabSeparated {
          if isSequenceIndicator(keyContent) || isExplicitMappingIndicator(keyContent) || splitMappingEntry(keyContent) != nil {
            throw YAML.Error.invalidIndentation
          }
        }

        var keyNode: YAMLNode
        if keyContent.isEmpty {
          if baseAdvance > 0 {
            index += baseAdvance
          }
          skipEmptyLines()
          guard index < lines.count else {
            throw YAML.Error.invalidSyntax("Missing explicit mapping key")
          }
          let nextIndent = min(expectedIndent + 1, lines[index].indent)
          keyNode = try parseNode(expectedIndent: nextIndent)
        } else if keyContent.hasPrefix("|") || keyContent.hasPrefix(">") {
          keyNode = try parseBlockScalar(
            content: keyContent,
            decorators: Decorators(tag: nil, anchor: nil),
            baseIndent: expectedIndent)
        } else if isSequenceIndicator(keyContent) {
          if baseAdvance > 0 {
            index += baseAdvance
          }
          keyNode = try parseBlockSequence(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: expectedIndent + 2,
            firstRemainder: keyContent,
            consumeFirstLine: false)
        } else if splitMappingEntry(keyContent) != nil || isExplicitMappingIndicator(keyContent) {
          if baseAdvance > 0 {
            index += baseAdvance
          }
          keyNode = try parseBlockMapping(
            decorators: Decorators(tag: nil, anchor: nil),
            expectedIndent: expectedIndent + 2,
            firstRemainder: keyContent,
            consumeFirstLine: false)
        } else if keyContent.hasPrefix("[") || keyContent.hasPrefix("{") {
          let flow = try collectFlowText(
            startIndex: keyLineIndex,
            firstContent: keyContent,
            minimumIndent: leadingSpaceCount(lines[keyLineIndex].raw) + 1)
          var inline = InlineParser(text: flow.text)
          keyNode = try parseInlineNode(parser: &inline, baseIndent: expectedIndent + 1)
          if flow.linesConsumed > 1 {
            index += baseAdvance + (flow.linesConsumed - 1)
          } else {
            if baseAdvance > 0 {
              index += baseAdvance
            }
          }
        } else {
          var keyParser = InlineParser(text: keyContent)
          keyNode = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
          keyParser.skipWhitespaceAndComments()
          if keyParser.peek != nil {
            throw YAML.Error.invalidSyntax("Unexpected trailing content")
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

        var valueNode: YAMLNode
        if let valueIndex = nextNonEmptyLineIndex(from: index),
           lines[valueIndex].indent == expectedIndent {
          let valueLine = lines[valueIndex]
          let valueDecorated = try parseDecorators(from: valueLine.contentStrippingComment())
          var valueContent = valueDecorated.remainder.trimmingCharacters(in: .whitespaces)
          if valueContent.hasPrefix(":") {
            let tabSeparated = hasTabAfterIndicator(valueContent, indicator: ":")
            valueContent.removeFirst()
            let remainder = valueContent.trimmingCharacters(in: .whitespaces)
            if tabSeparated {
              if isSequenceIndicator(remainder) || isExplicitMappingIndicator(remainder) || splitMappingEntry(remainder) != nil {
                throw YAML.Error.invalidIndentation
              }
            }
            index = valueIndex + 1
            if remainder.isEmpty {
              if let nextIndex = nextNonEmptyLineIndex(from: index) {
                let nextLine = lines[nextIndex]
                if nextLine.indent > expectedIndent {
                  skipEmptyLines()
                  let node = try parseNode(expectedIndent: expectedIndent + 1)
                  valueNode = try attach(node, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
                } else if nextLine.indent == expectedIndent,
                          isSequenceIndicator(nextLine.contentStrippingComment()) {
                  skipEmptyLines()
                  let nested = try parseBlockSequence(
                    decorators: Decorators(tag: nil, anchor: nil),
                    expectedIndent: expectedIndent,
                    firstRemainder: lines[index].contentStrippingComment())
                  valueNode = try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
                } else {
                  let emptyScalar = YAMLScalar(text: "", style: .plain)
                  let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
                  valueNode = try attach(emptyNode, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
                }
              } else {
                let emptyScalar = YAMLScalar(text: "", style: .plain)
                let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
                valueNode = try attach(emptyNode, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
              }
            } else if remainder.hasPrefix("|") || remainder.hasPrefix(">") {
              let savedIndex = index
              index = valueIndex
              let node = try parseBlockScalar(
                content: remainder,
                decorators: valueDecorated.decorators,
                baseIndent: expectedIndent)
              valueNode = node
              index = max(index, savedIndex)
            } else if isSequenceIndicator(remainder) {
              let nested = try parseBlockSequence(
                decorators: Decorators(tag: nil, anchor: nil),
                expectedIndent: expectedIndent + 2,
                firstRemainder: remainder,
                consumeFirstLine: false)
              valueNode = try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
            } else if splitMappingEntry(remainder) != nil || isExplicitMappingIndicator(remainder) {
              let nested = try parseBlockMapping(
                decorators: Decorators(tag: nil, anchor: nil),
                expectedIndent: expectedIndent + 2,
                firstRemainder: remainder,
                consumeFirstLine: false)
              valueNode = try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
            } else {
              var inlineText = remainder
              var extraLines = 0
              if inlineText.first == "[" || inlineText.first == "{" {
                let flow = try collectFlowText(
                  startIndex: valueIndex,
                  firstContent: inlineText,
                  minimumIndent: leadingSpaceCount(lines[valueIndex].raw) + 1)
                inlineText = flow.text
                extraLines = max(extraLines, flow.linesConsumed - 1)
              }
              if inlineText.first == "\"" {
                let expanded = try expandDoubleQuotedInlineText(
                  inlineText,
                  startIndex: valueIndex,
                  parentIndent: expectedIndent + 1)
                inlineText = expanded.text
                extraLines = expanded.extraLines
              } else if inlineText.first == "'" {
                let expanded = try expandSingleQuotedInlineText(
                  inlineText,
                  startIndex: valueIndex,
                  parentIndent: expectedIndent + 1)
                inlineText = expanded.text
                extraLines = expanded.extraLines
              }
              var inlineParser = InlineParser(text: inlineText)
              valueNode = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent + 1)
              valueNode = try attach(valueNode, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
              let folded = try foldPlainScalarIfNeeded(valueNode, startIndex: valueIndex, contextIndent: expectedIndent)
              valueNode = folded.node
              if folded.linesConsumed > 0 {
                index += folded.linesConsumed
              }
              if extraLines > 0 {
                index += extraLines
              }
              inlineParser.skipWhitespaceAndComments()
              if inlineParser.peek != nil {
                throw YAML.Error.invalidSyntax("Unexpected trailing content")
              }
            }
          } else {
            let emptyScalar = YAMLScalar(text: "", style: .plain)
            valueNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
          }
        } else {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          valueNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
        }

        pairs.append((keyNode, valueNode))
        initialRemainder = nil
        consumeFirst = true
        continue
      }

      guard let entry = splitMappingEntry(content) else { break }

      let trimmedKey = entry.key.trimmingCharacters(in: .whitespaces)
      let keyNode: YAMLNode
      if trimmedKey.isEmpty {
        let emptyScalar = YAMLScalar(text: "", style: .plain)
        keyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
      } else {
        var keyParser = InlineParser(text: trimmedKey)
        let parsedKey = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
        keyParser.skipWhitespaceAndComments()
        if keyParser.peek != nil {
          throw YAML.Error.invalidSyntax("Unexpected trailing content")
        }
        keyNode = parsedKey
      }
      let decoratedKeyNode = try attach(keyNode, tag: entryDecorators.tag, anchor: entryDecorators.anchor)

      let entryLineIndex = skipAdvance ? max(index - 1, 0) : index
      if !skipAdvance {
        index += 1
      }

      let inlineValue = entry.value?.trimmingCharacters(in: .whitespaces) ?? ""
      if inlineValue.isEmpty {
        if let nextIndex = nextNonEmptyLineIndex(from: index) {
          let nextLine = lines[nextIndex]
          if nextLine.indent > expectedIndent {
            skipEmptyLines()
            let valueNode = try parseNode(expectedIndent: expectedIndent + 1)
            pairs.append((decoratedKeyNode, valueNode))
          } else if nextLine.indent == expectedIndent,
                    isSequenceIndicator(nextLine.contentStrippingComment()) {
            skipEmptyLines()
            let nested = try parseBlockSequence(
              decorators: Decorators(tag: nil, anchor: nil),
              expectedIndent: expectedIndent,
              firstRemainder: lines[index].contentStrippingComment())
            pairs.append((decoratedKeyNode, nested))
          } else {
            let emptyScalar = YAMLScalar(text: "", style: .plain)
            let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
            pairs.append((decoratedKeyNode, emptyNode))
          }
        } else {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
          pairs.append((decoratedKeyNode, emptyNode))
        }
      } else {
        var valueParser = InlineParser(text: inlineValue)
        let rawValueDecorators = try valueParser.parseDecorators()
        let resolvedValueTag = try resolveTag(rawValueDecorators.tag)
        let valueDecorators = Decorators(tag: resolvedValueTag, anchor: rawValueDecorators.anchor)
        valueParser.skipWhitespaceAndComments()
        let remainder = valueParser.remaining.trimmingCharacters(in: .whitespaces)
        if remainder.isEmpty {
          if let nextIndex = nextNonEmptyLineIndex(from: index) {
            let nextLine = lines[nextIndex]
            if nextLine.indent > expectedIndent {
              skipEmptyLines()
              let node = try parseNode(expectedIndent: expectedIndent + 1)
              let decoratedNode = try attach(node, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
              pairs.append((decoratedKeyNode, decoratedNode))
            } else if nextLine.indent == expectedIndent,
                      isSequenceIndicator(nextLine.contentStrippingComment()) {
              skipEmptyLines()
              let nested = try parseBlockSequence(
                decorators: Decorators(tag: nil, anchor: nil),
                expectedIndent: expectedIndent,
                firstRemainder: lines[index].contentStrippingComment())
              let decoratedNode = try attach(nested, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
              pairs.append((decoratedKeyNode, decoratedNode))
            } else {
              let emptyScalar = YAMLScalar(text: "", style: .plain)
              let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
              let decoratedNode = try attach(emptyNode, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
              pairs.append((decoratedKeyNode, decoratedNode))
            }
          } else {
            let emptyScalar = YAMLScalar(text: "", style: .plain)
            let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
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
            throw YAML.Error.invalidSyntax("Sequence value must start on a new line")
          }
          var inlineText = valueParser.remaining
          var extraLines = 0
          if inlineText.first == "[" || inlineText.first == "{" {
            let flow = try collectFlowText(
              startIndex: entryLineIndex,
              firstContent: inlineText,
              minimumIndent: leadingSpaceCount(lines[entryLineIndex].raw) + 1)
            inlineText = flow.text
            extraLines = max(extraLines, flow.linesConsumed - 1)
          }
          if inlineText.first == "\"" {
            let expanded = try expandDoubleQuotedInlineText(
              inlineText,
              startIndex: entryLineIndex,
              parentIndent: expectedIndent + 1)
            inlineText = expanded.text
            extraLines = expanded.extraLines
          } else if inlineText.first == "'" {
            let expanded = try expandSingleQuotedInlineText(
              inlineText,
              startIndex: entryLineIndex,
              parentIndent: expectedIndent + 1)
            inlineText = expanded.text
            extraLines = expanded.extraLines
          }
          var inlineParser = InlineParser(text: inlineText)
          var valueNode = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent + 1)
          valueNode = try attach(valueNode, tag: valueDecorators.tag, anchor: valueDecorators.anchor)
          let folded = try foldPlainScalarIfNeeded(valueNode, startIndex: entryLineIndex, contextIndent: expectedIndent)
          valueNode = folded.node
          if folded.linesConsumed > 0 {
            index += folded.linesConsumed
          }
          if extraLines > 0 {
            index += extraLines
          }
          inlineParser.skipWhitespaceAndComments()
          if inlineParser.peek != nil {
            throw YAML.Error.invalidSyntax("Unexpected trailing content")
          }
          pairs.append((decoratedKeyNode, valueNode))
        }
      }
      initialRemainder = nil
      consumeFirst = true
    }

    return try attach(.mapping(pairs, style: .block, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
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
      let decorated = try parseDecorators(from: sourceContent)
      let trimmedSource = sourceContent.trimmingCharacters(in: .whitespaces)
      let tabIndentCheck = expectedIndent > 0 ? expectedIndent : 1
      if hasTabInIndent(line, requiredIndent: tabIndentCheck), !trimmedSource.isEmpty {
        let remainder = decorated.remainder.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty && !isFlowCollectionIndicator(remainder) {
          throw YAML.Error.invalidIndentation
        }
      }
      var content = decorated.remainder.trimmingCharacters(in: .whitespaces)
      guard isExplicitMappingIndicator(content) else { break }
      let tabSeparated = hasTabAfterIndicator(content, indicator: "?")

      // Trim leading '?' and whitespace.
      content.removeFirst()
      let keyContent = content.trimmingCharacters(in: .whitespaces)
      let keyLineIndex = index
      if tabSeparated {
        if isSequenceIndicator(keyContent) || isExplicitMappingIndicator(keyContent) || splitMappingEntry(keyContent) != nil {
          throw YAML.Error.invalidIndentation
        }
      }

      var keyNode: YAMLNode
      if keyContent.isEmpty {
        index += 1
        skipEmptyLines()
        guard index < lines.count else {
          throw YAML.Error.invalidSyntax("Missing explicit mapping key")
        }
        keyNode = try parseNode(expectedIndent: lines[index].indent)
      } else if keyContent.hasPrefix("|") || keyContent.hasPrefix(">") {
        keyNode = try parseBlockScalar(content: keyContent, decorators: Decorators(tag: nil, anchor: nil), baseIndent: expectedIndent)
      } else if keyContent.hasPrefix("[") || keyContent.hasPrefix("{") {
        let flow = try collectFlowText(
          startIndex: keyLineIndex,
          firstContent: keyContent,
          minimumIndent: leadingSpaceCount(lines[keyLineIndex].raw) + 1)
        var inline = InlineParser(text: flow.text)
        keyNode = try parseInlineNode(parser: &inline, baseIndent: expectedIndent + 1)
        if flow.linesConsumed > 1 {
          index += flow.linesConsumed
        } else {
          index += 1
        }
      } else {
        var keyParser = InlineParser(text: keyContent)
        keyNode = try parseInlineNode(parser: &keyParser, baseIndent: expectedIndent + 1)
        keyParser.skipWhitespaceAndComments()
        if keyParser.peek != nil {
          throw YAML.Error.invalidSyntax("Unexpected trailing content")
        }
        index += 1
        let foldedKey = try foldPlainScalarIfNeeded(keyNode, startIndex: keyLineIndex, contextIndent: expectedIndent)
        keyNode = foldedKey.node
        if foldedKey.linesConsumed > 0 {
          index += foldedKey.linesConsumed
        }
      }

      keyNode = try attach(keyNode, tag: decorated.decorators.tag, anchor: decorated.decorators.anchor)

      var valueNode: YAMLNode
      if let valueIndex = nextNonEmptyLineIndex(from: index),
         lines[valueIndex].indent == expectedIndent {
        let valueLine = lines[valueIndex]
        let valueDecorated = try parseDecorators(from: valueLine.contentStrippingComment())
        var valueContent = valueDecorated.remainder.trimmingCharacters(in: .whitespaces)
        if valueContent.hasPrefix(":") {
          let tabSeparated = hasTabAfterIndicator(valueContent, indicator: ":")
          valueContent.removeFirst()
          let remainder = valueContent.trimmingCharacters(in: .whitespaces)
          if tabSeparated {
            if isSequenceIndicator(remainder) || isExplicitMappingIndicator(remainder) || splitMappingEntry(remainder) != nil {
              throw YAML.Error.invalidIndentation
            }
          }
          index = valueIndex + 1
          if remainder.isEmpty {
            if let nextIndex = nextNonEmptyLineIndex(from: index) {
              let nextLine = lines[nextIndex]
              if nextLine.indent > expectedIndent {
                skipEmptyLines()
                let node = try parseNode(expectedIndent: expectedIndent + 1)
                valueNode = try attach(node, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
              } else if nextLine.indent == expectedIndent,
                        isSequenceIndicator(nextLine.contentStrippingComment()) {
                skipEmptyLines()
                let nested = try parseBlockSequence(
                  decorators: Decorators(tag: nil, anchor: nil),
                  expectedIndent: expectedIndent,
                  firstRemainder: lines[index].contentStrippingComment())
                valueNode = try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
              } else {
                let emptyScalar = YAMLScalar(text: "", style: .plain)
                let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
                valueNode = try attach(emptyNode, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
              }
            } else {
              let emptyScalar = YAMLScalar(text: "", style: .plain)
              let emptyNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
              valueNode = try attach(emptyNode, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
            }
          } else if remainder.hasPrefix("|") || remainder.hasPrefix(">") {
            let savedIndex = index
            index = valueIndex
            let node = try parseBlockScalar(
              content: remainder,
              decorators: valueDecorated.decorators,
              baseIndent: expectedIndent)
            valueNode = node
            index = max(index, savedIndex)
          } else if isSequenceIndicator(remainder) {
            let nested = try parseBlockSequence(
              decorators: Decorators(tag: nil, anchor: nil),
              expectedIndent: expectedIndent + 2,
              firstRemainder: remainder,
              consumeFirstLine: false)
            valueNode = try attach(nested, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
          } else {
            var inlineText = remainder
            var extraLines = 0
            if inlineText.first == "[" || inlineText.first == "{" {
              let flow = try collectFlowText(
                startIndex: valueIndex,
                firstContent: inlineText,
                minimumIndent: leadingSpaceCount(lines[valueIndex].raw) + 1)
              inlineText = flow.text
              extraLines = max(extraLines, flow.linesConsumed - 1)
            }
            if inlineText.first == "\"" {
              let expanded = try expandDoubleQuotedInlineText(
                inlineText,
                startIndex: valueIndex,
                parentIndent: expectedIndent + 1)
              inlineText = expanded.text
              extraLines = expanded.extraLines
            } else if inlineText.first == "'" {
              let expanded = try expandSingleQuotedInlineText(
                inlineText,
                startIndex: valueIndex,
                parentIndent: expectedIndent + 1)
              inlineText = expanded.text
              extraLines = expanded.extraLines
            }
            var inlineParser = InlineParser(text: inlineText)
            valueNode = try parseInlineNode(parser: &inlineParser, baseIndent: expectedIndent + 1)
            valueNode = try attach(valueNode, tag: valueDecorated.decorators.tag, anchor: valueDecorated.decorators.anchor)
            let folded = try foldPlainScalarIfNeeded(valueNode, startIndex: valueIndex, contextIndent: expectedIndent)
            valueNode = folded.node
            if folded.linesConsumed > 0 {
              index += folded.linesConsumed
            }
            if extraLines > 0 {
              index += extraLines
            }
            inlineParser.skipWhitespaceAndComments()
            if inlineParser.peek != nil {
              throw YAML.Error.invalidSyntax("Unexpected trailing content")
            }
          }
        } else {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          valueNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
        }
      } else {
        let emptyScalar = YAMLScalar(text: "", style: .plain)
        valueNode = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
      }

      pairs.append((keyNode, valueNode))
      initialRemainder = nil
    }

    return try attach(.mapping(pairs, style: .block, tag: nil, anchor: nil), tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseBlockScalar(content: String, decorators: Decorators, baseIndent: Int) throws -> YAMLNode {
    guard let indicator = content.first else {
      throw YAML.Error.invalidSyntax("Invalid block scalar indicator on line \(lines[index].number)")
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
          throw YAML.Error.invalidSyntax("Invalid block scalar chomping indicator")
        }
        sawChomp = true
        chomp = .keep
        idx = content.index(after: idx)
      } else if char == "-" {
        if sawChomp {
          throw YAML.Error.invalidSyntax("Invalid block scalar chomping indicator")
        }
        sawChomp = true
        chomp = .strip
        idx = content.index(after: idx)
      } else if char.isWholeNumber {
        if sawIndent {
          throw YAML.Error.invalidSyntax("Invalid block scalar indentation indicator")
        }
        sawIndent = true
        if char == "0" {
          throw YAML.Error.invalidSyntax("Invalid block scalar indentation indicator")
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
            throw YAML.Error.invalidSyntax("Invalid block scalar header")
          }
          break
        }
        throw YAML.Error.invalidSyntax("Invalid block scalar header")
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
        let trimmed = line.raw.trimmingCharacters(in: .whitespaces)
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
          throw YAML.Error.invalidIndentation
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
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      let spaceIndent = leadingSpaceCount(raw)
      if hasTabInIndent(line, requiredIndent: requiredIndent) {
        throw YAML.Error.invalidIndentation
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
        let marker = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)
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
      throw YAML.Error.invalidSyntax("Unknown block scalar indicator on line \(lines[index].number)")
    }

    let style: YAMLScalarStyle = indicator == "|" ? .literal(chomp: chomp, indent: indentIndicator) : .folded(chomp: chomp, indent: indentIndicator)
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
      let emptyScalar = YAMLScalar(text: "", style: .plain)
      let node = YAMLNode.scalar(emptyScalar, tag: nil, anchor: nil)
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
      let text = parser.parsePlainScalar(stopAtColon: stopAtColon, flowContext: flowContext)
      try validatePlainScalarText(text)
      node = .scalar(.init(text: text, style: .plain), tag: nil, anchor: nil)
    }

    return try attach(node, tag: decorators.tag, anchor: decorators.anchor)
  }

  private mutating func parseFlowSequence(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    guard parser.consumeIf("[") else {
      throw YAML.Error.invalidSyntax("Expected flow sequence start")
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
            flowContext: true)
          if keyParser.index == keyStart {
            if keyParser.peek == ":" || keyParser.peek == "," || keyParser.peek == "]" {
              let emptyScalar = YAMLScalar(text: "", style: .plain)
              keyNode = .scalar(emptyScalar, tag: nil, anchor: nil)
            } else {
              throw YAML.Error.invalidSyntax("Invalid explicit flow mapping key")
            }
          }
          keyParser.skipWhitespaceAndComments()
          let hadColon = keyParser.consumeIf(":")
          keyParser.skipWhitespaceAndComments()
          let valueNode: YAMLNode
          if !hadColon {
            if keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "]" {
              let emptyScalar = YAMLScalar(text: "", style: .plain)
              valueNode = .scalar(emptyScalar, tag: nil, anchor: nil)
            } else {
              throw YAML.Error.invalidSyntax("Explicit flow mapping entry missing ':'")
            }
          } else if keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "]" {
            let emptyScalar = YAMLScalar(text: "", style: .plain)
            valueNode = .scalar(emptyScalar, tag: nil, anchor: nil)
          } else {
            let valueStart = keyParser.index
            var valueParser = keyParser
            let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
            if valueParser.index == valueStart {
              throw YAML.Error.invalidSyntax("Invalid flow mapping value")
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
          throw YAML.Error.invalidSyntax("Expected ',' or ']' in flow sequence")
        }
      }

      let entryStart = parser.index
      var entryParser = parser
      var keyNode = try parseInlineNode(
        parser: &entryParser,
        baseIndent: baseIndent,
        stopAtColon: true,
        flowContext: true)
      if entryParser.index == entryStart {
        if entryParser.peek == ":" {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          keyNode = .scalar(emptyScalar, tag: nil, anchor: nil)
        } else {
          throw YAML.Error.invalidSyntax("Invalid flow sequence entry")
        }
      }
      let keySlice = entryParser.text[entryStart..<entryParser.index]
      let keyHasLineBreak = keySlice.contains(where: { $0.isNewline })
      let whitespaceStart = entryParser.index
      entryParser.skipWhitespaceAndComments()
      let skipped = entryParser.text[whitespaceStart..<entryParser.index]
      let sawLineBreak = skipped.contains(where: { $0.isNewline })
      if entryParser.consumeIf(":") {
        if keyHasLineBreak || sawLineBreak {
          throw YAML.Error.invalidSyntax("Implicit flow mapping key must be on one line")
        }
        entryParser.skipWhitespaceAndComments()
        let valueStart = entryParser.index
        var valueParser = entryParser
        let valueNode = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
        if valueParser.index == valueStart {
          throw YAML.Error.invalidSyntax("Invalid flow sequence entry")
        }
        parser = valueParser
        items.append(.mapping([(keyNode, valueNode)], style: .flow, tag: nil, anchor: nil))
      } else {
        parser = entryParser
        if case .scalar(let scalar, _, _) = keyNode,
           case .plain = scalar.style,
           scalar.text == "-" {
          throw YAML.Error.invalidSyntax("Invalid flow sequence entry")
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
      throw YAML.Error.invalidSyntax("Expected ',' or ']' in flow sequence")
    }
    if !closed {
      throw YAML.Error.invalidSyntax("Unterminated flow sequence")
    }

    return .sequence(items, style: .flow, tag: nil, anchor: nil)
  }

  private mutating func parseFlowMapping(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
    guard parser.consumeIf("{") else {
      throw YAML.Error.invalidSyntax("Expected flow mapping start")
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
            flowContext: true)
          if keyParser.index == keyStart {
            if keyParser.peek == ":" || keyParser.peek == "," || keyParser.peek == "}" {
              let emptyScalar = YAMLScalar(text: "", style: .plain)
              key = .scalar(emptyScalar, tag: nil, anchor: nil)
            } else {
              throw YAML.Error.invalidSyntax("Invalid explicit flow mapping key")
            }
          }
          keyParser.skipWhitespaceAndComments()
          let hadColon = keyParser.consumeIf(":")
          keyParser.skipWhitespaceAndComments()
          let valueNode: YAMLNode
          if !hadColon {
            if keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "}" {
              let emptyScalar = YAMLScalar(text: "", style: .plain)
              valueNode = .scalar(emptyScalar, tag: nil, anchor: nil)
            } else {
              throw YAML.Error.invalidSyntax("Explicit flow mapping entry missing ':'")
            }
          } else if keyParser.peek == nil || keyParser.peek == "," || keyParser.peek == "}" {
            let emptyScalar = YAMLScalar(text: "", style: .plain)
            valueNode = .scalar(emptyScalar, tag: nil, anchor: nil)
          } else {
            let valueStart = keyParser.index
            var valueParser = keyParser
            let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
            if valueParser.index == valueStart {
              throw YAML.Error.invalidSyntax("Invalid flow mapping value")
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
          throw YAML.Error.invalidSyntax("Expected ',' or '}' in flow mapping")
        }
      }

      let keyStart = parser.index
      var keyParser = parser
      var key = try parseInlineNode(parser: &keyParser, baseIndent: baseIndent, stopAtColon: true, flowContext: true)
      parser = keyParser
      if parser.index == keyStart {
        if parser.peek == ":" {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          key = .scalar(emptyScalar, tag: nil, anchor: nil)
        } else {
          throw YAML.Error.invalidSyntax("Invalid flow mapping key")
        }
      }
      parser.skipWhitespaceAndComments()
      if parser.consumeIf(":") {
        parser.skipWhitespaceAndComments()

        if parser.peek == "," || parser.peek == "}" || parser.peek == nil {
          let emptyScalar = YAMLScalar(text: "", style: .plain)
          pairs.append((key, .scalar(emptyScalar, tag: nil, anchor: nil)))
        } else {
          let valueStart = parser.index
          var valueParser = parser
          let value = try parseInlineNode(parser: &valueParser, baseIndent: baseIndent, flowContext: true)
          parser = valueParser
          if parser.index == valueStart {
            throw YAML.Error.invalidSyntax("Invalid flow mapping value")
          }
          pairs.append((key, value))
        }
      } else {
        let emptyScalar = YAMLScalar(text: "", style: .plain)
        pairs.append((key, .scalar(emptyScalar, tag: nil, anchor: nil)))
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
      throw YAML.Error.invalidSyntax("Expected ',' or '}' in flow mapping")
    }
    if !closed {
      throw YAML.Error.invalidSyntax("Unterminated flow mapping")
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

  private func joinFoldedLines(_ lines: [(line: String, indent: Int)], baseIndent: Int, chomp: YAMLScalarChomp) -> String {
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
      if char == " " || char == "\t" {
        end = prev
      } else {
        break
      }
    }
    return String(text[..<end])
  }

  private func leadingSpaceCount(_ raw: String) -> Int {
    var count = 0
    for char in raw {
      if char == " " {
        count += 1
      } else {
        break
      }
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

    try validatePlainScalarText(scalar.text)

    let initialRaw = lines[startIndex].content
    let initialStripped = lines[startIndex].contentStrippingComment()
    if initialRaw != initialStripped {
      return (node, 0)
    }

    let folded = foldPlainScalar(initial: scalar.text, startIndex: startIndex, contextIndent: contextIndent)
    if folded.linesConsumed == 0 {
      return (node, 0)
    }
    try validatePlainScalarText(folded.text)
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
    let initialContent = initialLine.contentStrippingComment().trimmingCharacters(in: .whitespaces)
    var requireMoreIndent = false
    if isSequenceIndicator(initialContent) {
      requireMoreIndent = true
    } else if let entry = splitMappingEntry(initialContent),
              let value = entry.value,
              !value.trimmingCharacters(in: .whitespaces).isEmpty {
      requireMoreIndent = true
    }
    let minIndent = requireMoreIndent ? initialIndent + 1 : initialIndent
    var collected: [(line: String, indent: Int)] = []
    var cursor = startIndex + 1
    var baseIndent: Int?

    while cursor < lines.count {
      let line = lines[cursor]
      let rawTrimmed = line.raw.trimmingCharacters(in: .whitespaces)
      let content = line.contentStrippingComment()
      let trimmed = content.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        if !rawTrimmed.isEmpty {
          break
        }
        collected.append((line: "", indent: line.indent))
        cursor += 1
        continue
      }
      if line.indent < minIndent {
        break
      }
      let stripped = content.trimmingCharacters(in: .whitespaces)
      if stripped == "..." {
        break
      }
      if stripped.hasPrefix("---") {
        let markerIndex = stripped.index(stripped.startIndex, offsetBy: 3)
        if markerIndex == stripped.endIndex || stripped[markerIndex].isWhitespace {
          break
        }
      }
      if stripped.hasPrefix("...") {
        let markerIndex = stripped.index(stripped.startIndex, offsetBy: 3)
        if markerIndex == stripped.endIndex || stripped[markerIndex].isWhitespace {
          break
        }
      }
      if line.indent == initialIndent {
        if isSequenceIndicator(stripped) || splitMappingEntry(stripped) != nil || isExplicitMappingIndicator(stripped) {
          break
        }
      }
      if baseIndent == nil {
        baseIndent = line.indent
      }
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
    let initialContent = initial.trimmingCharacters(in: .whitespaces)
    var requireMoreIndent = false
    if isSequenceIndicator(initialContent) {
      requireMoreIndent = true
    } else if let entry = splitMappingEntry(initialContent),
              let value = entry.value,
              !value.trimmingCharacters(in: .whitespaces).isEmpty {
      requireMoreIndent = true
    }
    let minIndent = requireMoreIndent ? initialIndent + 1 : initialIndent
    var collected: [(line: String, indent: Int)] = []
    var cursor = startIndex + 1
    var baseIndent: Int?

    while cursor < lines.count {
      let line = lines[cursor]
      let rawTrimmed = line.raw.trimmingCharacters(in: .whitespaces)
      let content = line.contentStrippingComment()
      let trimmed = content.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        if !rawTrimmed.isEmpty {
          break
        }
        collected.append((line: "", indent: line.indent))
        cursor += 1
        continue
      }
      if line.indent < minIndent {
        break
      }
      let stripped = content.trimmingCharacters(in: .whitespaces)
      if stripped == "..." {
        break
      }
      if stripped.hasPrefix("---") {
        let markerIndex = stripped.index(stripped.startIndex, offsetBy: 3)
        if markerIndex == stripped.endIndex || stripped[markerIndex].isWhitespace {
          break
        }
      }
      if stripped.hasPrefix("...") {
        let markerIndex = stripped.index(stripped.startIndex, offsetBy: 3)
        if markerIndex == stripped.endIndex || stripped[markerIndex].isWhitespace {
          break
        }
      }
      if line.indent == initialIndent {
        if isSequenceIndicator(stripped) || splitMappingEntry(stripped) != nil || isExplicitMappingIndicator(stripped) {
          break
        }
      }
      if baseIndent == nil {
        baseIndent = line.indent
      }
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
      let content = lines[index].contentStrippingComment().trimmingCharacters(in: .whitespaces)
      if content.isEmpty {
        index += 1
      } else {
        break
      }
    }
  }

  private func nextNonEmptyLineIndex(from start: Int) -> Int? {
    var cursor = start
    while cursor < lines.count {
      let content = lines[cursor].contentStrippingComment().trimmingCharacters(in: .whitespaces)
      if !content.isEmpty {
        return cursor
      }
      cursor += 1
    }
    return nil
  }

  private func isDocumentStart(_ line: Line) -> Bool {
    let trimmed = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("---") else { return false }
    if trimmed == "---" {
      return true
    }
    let index = trimmed.index(trimmed.startIndex, offsetBy: 3)
    return index < trimmed.endIndex && trimmed[index].isWhitespace
  }

  private func isDocumentEnd(_ line: Line) -> Bool {
    line.contentStrippingComment().trimmingCharacters(in: .whitespaces) == "..."
  }

  private func isSequenceIndicator(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespaces)
    guard trimmed.first == "-" else { return false }
    if trimmed.count == 1 {
      return true
    }
    let next = trimmed[trimmed.index(after: trimmed.startIndex)]
    return next.isWhitespace
  }

  private func isExplicitMappingIndicator(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespaces)
    guard trimmed.first == "?" else { return false }
    if trimmed.count == 1 {
      return true
    }
    let next = trimmed[trimmed.index(after: trimmed.startIndex)]
    return next.isWhitespace
  }

  private func isFlowCollectionIndicator(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("[") || trimmed.hasPrefix("{")
  }

  fileprivate struct Decorators {
    let tag: String?
    let anchor: String?
  }

  private func parseDecorators(from content: String) throws -> (decorators: Decorators, remainder: String) {
    var scanner = InlineParser(text: content)
    let rawDecorators = try scanner.parseDecorators()
    let resolvedTag = try resolveTag(rawDecorators.tag)
    let decorators = Decorators(tag: resolvedTag, anchor: rawDecorators.anchor)
    scanner.skipWhitespaceAndComments()
    let remainder = scanner.remaining
    return (decorators, remainder)
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

  private func validatePlainScalarText(_ text: String) throws {
    guard !text.isEmpty else { return }
    var cursor = text.startIndex
    while cursor < text.endIndex {
      if text[cursor] == ":" {
        let nextIndex = text.index(after: cursor)
        if nextIndex < text.endIndex, text[nextIndex].isWhitespace {
          throw YAML.Error.invalidSyntax("Invalid plain scalar")
        }
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
          throw YAML.Error.invalidSyntax("Invalid tag")
        }
        let next2 = text.index(after: next1)
        guard next2 < text.endIndex else {
          throw YAML.Error.invalidSyntax("Invalid tag")
        }
        guard let hi = hexValue(text[next1]), let lo = hexValue(text[next2]) else {
          throw YAML.Error.invalidSyntax("Invalid tag")
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
        throw YAML.Error.invalidSyntax("Unknown tag handle")
      }
      return "\(prefix)\(suffix)"
    }

    guard let prefix = tagHandles["!"] else {
      throw YAML.Error.invalidSyntax("Unknown tag handle")
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
        throw YAML.Error.invalidSyntax("Multiple tags on node")
      }
      if anchor != nil, existingAnchor != nil {
        throw YAML.Error.invalidSyntax("Multiple anchors on node")
      }
      return .scalar(scalar, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .sequence(let array, let style, let existingTag, let existingAnchor):
      if tag != nil, existingTag != nil {
        throw YAML.Error.invalidSyntax("Multiple tags on node")
      }
      if anchor != nil, existingAnchor != nil {
        throw YAML.Error.invalidSyntax("Multiple anchors on node")
      }
      return .sequence(array, style: style, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .mapping(let map, let style, let existingTag, let existingAnchor):
      if tag != nil, existingTag != nil {
        throw YAML.Error.invalidSyntax("Multiple tags on node")
      }
      if anchor != nil, existingAnchor != nil {
        throw YAML.Error.invalidSyntax("Multiple anchors on node")
      }
      return .mapping(map, style: style, tag: tag ?? existingTag, anchor: anchor ?? existingAnchor)
    case .alias:
      if tag != nil || anchor != nil {
        throw YAML.Error.invalidSyntax("Alias cannot have tag or anchor")
      }
      return node
    }
  }

  private func splitMappingEntry(_ content: String) -> (key: String, value: String?)? {
    let trimmedContent = content.trimmingCharacters(in: .whitespaces)
    if (trimmedContent.first == "*" || trimmedContent.first == "&"),
       !trimmedContent.contains(where: { $0.isWhitespace }),
       trimmedContent.hasSuffix(":") {
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
    minimumIndent: Int
  ) throws -> (text: String, linesConsumed: Int) {
    var pieces: [String] = []
    pieces.reserveCapacity(4)

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
        throw YAML.Error.invalidSyntax("Unexpected flow collection terminator")
      }
      return (pieces.joined(separator: "\n"), linesConsumed)
    }

    var cursor = startIndex + 1
    while cursor < lines.count {
      let line = lines[cursor]
      if line.indent == 0 {
        let trimmedLine = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("---") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw YAML.Error.invalidSyntax("Document marker inside flow collection")
          }
        }
        if trimmedLine.hasPrefix("...") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw YAML.Error.invalidSyntax("Document marker inside flow collection")
          }
        }
      }
      let content = line.contentStrippingComment()
      let trimmed = content.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty {
        let spaceIndent = leadingSpaceCount(line.raw)
        if spaceIndent < minimumIndent {
          throw YAML.Error.invalidIndentation
        }
      }
      pieces.append(content)
      linesConsumed += 1
      if scan(content) && depth == 0 {
        if invalidClosure {
          throw YAML.Error.invalidSyntax("Unexpected flow collection terminator")
        }
        return (pieces.joined(separator: "\n"), linesConsumed)
      }
      cursor += 1
    }

    throw YAML.Error.invalidSyntax("Unterminated flow collection")
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
    parentIndent: Int
  ) throws -> (text: String, linesConsumed: Int) {
    var pieces: [String] = []
    pieces.reserveCapacity(4)
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
      return (pieces.joined(separator: "\n"), linesConsumed)
    }

    var cursor = startIndex + 1
    while cursor < lines.count {
      let line = lines[cursor]
      if line.indent == 0 {
        let trimmedLine = line.contentStrippingComment().trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("---") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw YAML.Error.invalidSyntax("Document marker inside quoted scalar")
          }
        }
        if trimmedLine.hasPrefix("...") {
          let markerIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: 3)
          if markerIndex == trimmedLine.endIndex || trimmedLine[markerIndex].isWhitespace {
            throw YAML.Error.invalidSyntax("Document marker inside quoted scalar")
          }
        }
      }
      let trimmed = line.content.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        pieces.append("")
        linesConsumed += 1
        cursor += 1
        continue
      }
      if line.indent < parentIndent {
        break
      }
      if hasTabInIndent(line, requiredIndent: parentIndent) {
        throw YAML.Error.invalidIndentation
      }
      let content = line.content
      pieces.append(content)
      linesConsumed += 1
      if scan(content, startAt: content.startIndex) {
        return (pieces.joined(separator: "\n"), linesConsumed)
      }
      cursor += 1
    }

    let quoteDescription = quote == "'" ? "single-quoted" : "double-quoted"
    throw YAML.Error.invalidSyntax("Unterminated \(quoteDescription) scalar")
  }

  private func expandDoubleQuotedInlineText(
    _ text: String,
    startIndex: Int,
    parentIndent: Int
  ) throws -> (text: String, extraLines: Int) {
    guard text.first == "\"", !hasClosingQuote(in: text, quote: "\"") else {
      return (text, 0)
    }
    let collected = try collectQuotedText(
      startIndex: startIndex,
      firstContent: text,
      quote: "\"",
      parentIndent: parentIndent
    )
    return (collected.text, collected.linesConsumed - 1)
  }

  private func expandSingleQuotedInlineText(
    _ text: String,
    startIndex: Int,
    parentIndent: Int
  ) throws -> (text: String, extraLines: Int) {
    guard text.first == "'", !hasClosingQuote(in: text, quote: "'") else {
      return (text, 0)
    }
    let collected = try collectQuotedText(
      startIndex: startIndex,
      firstContent: text,
      quote: "'",
      parentIndent: parentIndent
    )
    return (collected.text, collected.linesConsumed - 1)
  }
}

// MARK: - Inline Parser

private struct InlineParser {

  private(set) var text: String
  fileprivate var index: String.Index

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
        if index == text.startIndex {
          // comment to end of line
          index = text.endIndex
          break
        }
        let prevIndex = text.index(before: index)
        if text[prevIndex].isWhitespace {
          // comment to end of line
          index = text.endIndex
          break
        }
        break
      } else if char.isWhitespace {
        text.formIndex(after: &index)
        continue
      } else {
        break
      }
    }
  }

  mutating func parseDecorators(flowContext: Bool = false) throws -> YAMLParser.Decorators {
    skipWhitespaceAndComments()
    var tag: String?
    var anchor: String?

    while let current = peek {
      if current == "!" {
        if tag != nil {
          throw YAML.Error.invalidSyntax("Multiple tags on node")
        }
        tag = try parseTag(flowContext: flowContext)
      } else if current == "&" {
        if anchor != nil {
          throw YAML.Error.invalidSyntax("Multiple anchors on node")
        }
        anchor = parseAnchor()
      } else {
        break
      }
      skipWhitespaceAndComments()
    }

    return YAMLParser.Decorators(tag: tag, anchor: anchor)
  }

  mutating func parseTag(flowContext: Bool) throws -> String {
    consume(expected: "!")
    var buffer = "!"
    if peek == "<" {
      buffer.append("<")
      text.formIndex(after: &index)
      var closed = false
      while let current = peek {
        buffer.append(current)
        text.formIndex(after: &index)
        if current == ">" {
          closed = true
          break
        }
      }
      if !closed || buffer.count < 3 {
        throw YAML.Error.invalidSyntax("Invalid tag")
      }
      return buffer
    }

    while let current = peek {
      if current.isWhitespace {
        break
      }
      if current == "," || current == "]" || current == "}" {
        if !flowContext {
          throw YAML.Error.invalidSyntax("Invalid tag")
        }
        break
      }
      if current == ":" {
        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex, text[nextIndex].isWhitespace {
          break
        }
      }
      buffer.append(current)
      text.formIndex(after: &index)
    }
    if buffer.contains("{") || buffer.contains("}") {
      throw YAML.Error.invalidSyntax("Invalid tag")
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
    var outputCount = 0
    var escapedTabPosition: Int?
    while let current = peek {
      text.formIndex(after: &index)
      if current == "\"" {
        return output
      }
      if current.isNewline {
        var breakCount = 0
        while let next = peek {
          if next.isNewline {
            breakCount += 1
            text.formIndex(after: &index)
            continue
          }
          if next == " " || next == "\t" {
            text.formIndex(after: &index)
            continue
          }
          break
        }
        while let last = output.last, last == " " {
          output.removeLast()
          outputCount -= 1
          if let pos = escapedTabPosition, outputCount < pos {
            escapedTabPosition = nil
          }
        }
        let lastIsEscapedTab = output.last == "\t" && escapedTabPosition == outputCount
        if !lastIsEscapedTab {
          while let last = output.last, last == "\t" {
            output.removeLast()
            outputCount -= 1
            if let pos = escapedTabPosition, outputCount < pos {
              escapedTabPosition = nil
            }
          }
        }
        if breakCount == 0 {
          output.append(" ")
          outputCount += 1
        } else {
          output.append(String(repeating: "\n", count: breakCount))
          outputCount += breakCount
        }
        continue
      }
      if current == "\\" {
        guard let escaped = peek else { throw YAML.Error.invalidSyntax("Invalid escape sequence") }
        if escaped.isNewline {
          text.formIndex(after: &index)
          while let next = peek, next == " " || next == "\t" {
            text.formIndex(after: &index)
          }
          continue
        }
        text.formIndex(after: &index)
        let decoded = try decodeEscape(escaped)
        output.append(decoded)
        outputCount += 1
        if decoded == "\t" {
          escapedTabPosition = outputCount
        }
      } else {
        output.append(current)
        outputCount += 1
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
      if current.isNewline {
        while let last = output.last, last == " " {
          output.removeLast()
        }
        var breakCount = 0
        while let next = peek {
          if next.isNewline {
            breakCount += 1
            text.formIndex(after: &index)
            continue
          }
          if next == " " || next == "\t" {
            text.formIndex(after: &index)
            continue
          }
          break
        }
        if breakCount == 0 {
          output.append(" ")
        } else {
          output.append(String(repeating: "\n", count: breakCount))
        }
        continue
      }
      output.append(current)
    }
    throw YAML.Error.invalidSyntax("Unterminated single-quoted scalar")
  }

  mutating func parsePlainScalar(stopAtColon: Bool = false, flowContext: Bool = false) -> String {
    var output = ""
    while let current = peek {
      if flowContext && (current == "," || current == "]" || current == "}") {
        break
      }
      if current == "#" {
        if output.isEmpty || output.last?.isWhitespace == true {
          break
        }
      }
      if stopAtColon && current == ":" {
        let nextIndex = text.index(after: index)
        if nextIndex >= text.endIndex {
          break
        }
        let nextChar = text[nextIndex]
        if nextChar.isWhitespace || nextChar == "," || nextChar == "]" || nextChar == "}" {
          break
        }
      }
      if current.isNewline {
        if flowContext {
          var lookahead = text.index(after: index)
          var sawContent = false
          while lookahead < text.endIndex {
            let ch = text[lookahead]
            if ch.isNewline {
              break
            }
            if ch == " " || ch == "\t" {
              text.formIndex(after: &lookahead)
              continue
            }
            sawContent = true
            break
          }
          if !sawContent {
            break
          }
          if lookahead < text.endIndex, text[lookahead].isNewline {
            break
          }
          text.formIndex(after: &index)
          while let next = peek, next == " " || next == "\t" {
            text.formIndex(after: &index)
          }
          if !output.isEmpty && output.last?.isWhitespace != true {
            output.append(" ")
          }
          continue
        }
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
    case " ": return " "
    case "\t": return "\t"
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
