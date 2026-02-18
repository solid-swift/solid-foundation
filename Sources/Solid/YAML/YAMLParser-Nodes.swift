//
//  YAMLParser-Nodes.swift
//  SolidFoundation
//

extension YAMLParser {

  // MARK: - Core Parsing

  mutating func parseNode(expectedIndent: Int) throws -> YAMLNode {
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

}
