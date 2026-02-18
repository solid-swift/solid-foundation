//
//  YAMLParser-Documents.swift
//  SolidFoundation
//

extension YAMLParser {

  // MARK: - Directive Parsing

  /// Parses %YAML and %TAG directives, document-end markers, and returns whether any directives were seen.
  /// On return, `index` points at the first non-directive, non-empty, non-document-end line.
  mutating func parseDirectives(
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
  mutating func parseDocumentStartContent(
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

  // MARK: - Document Stream

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

}
