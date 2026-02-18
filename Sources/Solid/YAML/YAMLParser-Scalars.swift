//
//  YAMLParser-Scalars.swift
//  SolidFoundation
//

extension YAMLParser {

  mutating func parseBlockScalar(content: String, decorators: Decorators, baseIndent: Int) throws -> YAMLNode {
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

  // MARK: - Block Scalar Line Joining

  func joinLiteralLines(_ lines: [(line: String, indent: Int)], chomp: YAMLScalarChomp) -> String {
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

  func joinFoldedLines(_ lines: [(line: String, indent: Int)], baseIndent: Int, chomp: YAMLScalarChomp)
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

  // MARK: - Plain Scalar Folding

  func trimTrailingWhitespace(_ text: String) -> String {
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

  func foldPlainScalarIfNeeded(
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

  func foldPlainScalar(
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

  func foldPlainScalarFromInline(
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

  func foldPlainLines(_ lines: [(line: String, indent: Int)], baseIndent: Int) -> String {
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

  // MARK: - Validation & Tag Resolution

  func validatePlainScalarText(_ text: String, location: YAML.ParseError.Location) throws {
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

  func decodeTagSuffix(_ text: String) throws -> String {
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

  func resolveTag(_ tag: String?) throws -> String? {
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

  func attach(_ node: YAMLNode, tag: String?, anchor: String?) throws -> YAMLNode {
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

}
