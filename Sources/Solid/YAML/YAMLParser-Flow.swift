//
//  YAMLParser-Flow.swift
//  SolidFoundation
//

extension YAMLParser {

  // MARK: - Inline Node Parsing

  mutating func parseInlineNode(
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

  // MARK: - Flow Sequence

  mutating func parseFlowSequence(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
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

  // MARK: - Flow Mapping

  mutating func parseFlowMapping(parser: inout InlineParser, baseIndent: Int) throws -> YAMLNode {
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

  // MARK: - Decorators

  func parseDecorators(
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

  // MARK: - Mapping Entry Splitting

  /// Content is expected to be already trimmed by the caller.
  func splitMappingEntry(_ content: String) -> (key: String, value: String?)? {
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

  // MARK: - Multi-line Text Collection

  func collectFlowText(
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

  func hasClosingQuote(in text: String, quote: Character) -> Bool {
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

  func collectQuotedText(
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

  // MARK: - Inline Text Expansion

  /// Expands multi-line flow collections and quoted strings that span across lines.
  /// Handles `[`/`{` flow collections, `"` double-quoted, and `'` single-quoted scalars.
  func expandInlineText(
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

  func expandDoubleQuotedInlineText(
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

  func expandSingleQuotedInlineText(
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
