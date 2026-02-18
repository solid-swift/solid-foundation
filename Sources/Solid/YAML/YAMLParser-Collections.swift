//
//  YAMLParser-Collections.swift
//  SolidFoundation
//

extension YAMLParser {

  // MARK: - Block Sequence

  mutating func parseBlockSequence(
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

  // MARK: - Block Mapping

  mutating func parseBlockMapping(
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

  // MARK: - Explicit Block Mapping

  mutating func parseExplicitBlockMapping(
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

  // MARK: - Block Mapping Value Resolution

  /// Resolves the value after `:` in a block mapping entry, handling empty values,
  /// block scalars, nested sequences/mappings, inline scalars, and flow collections.
  mutating func resolveBlockMappingValue(
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

  mutating func resolveEmptyValueRemainder(
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

}
