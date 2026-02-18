//
//  YAMLParser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import SolidData

struct YAMLParser {

  struct Line {
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

  private(set) var lines: [Line]
  var index: Int = 0
  static let defaultTagHandles: [String: String] = [
    "!": "!",
    "!!": "tag:yaml.org,2002:",
  ]
  var tagHandles: [String: String] = YAMLParser.defaultTagHandles
  var allowDirectives: Bool
  var requireDocumentStart: Bool
  let allowIncompleteInput: Bool

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

  // MARK: - Location & Error Helpers

  func lineNumber(for lineIndex: Int) -> Int {
    guard !lines.isEmpty else { return 1 }
    if lineIndex >= 0 && lineIndex < lines.count {
      return lines[lineIndex].number
    }
    return lines.last?.number ?? 1
  }

  func defaultColumn(for lineIndex: Int) -> Int {
    guard !lines.isEmpty else { return 1 }
    if lineIndex >= 0 && lineIndex < lines.count {
      return max(1, lines[lineIndex].indent + 1)
    }
    if let last = lines.last {
      return max(1, last.raw.count + 1)
    }
    return 1
  }

  func location(lineIndex: Int, column: Int? = nil) -> YAML.ParseError.Location {
    YAML.ParseError.Location(
      line: lineNumber(for: lineIndex),
      column: column ?? defaultColumn(for: lineIndex)
    )
  }

  func syntaxError(_ message: String, lineIndex: Int? = nil, column: Int? = nil) -> YAML.ParseError {
    let targetIndex = lineIndex ?? index
    return .invalidSyntax(message, location: location(lineIndex: targetIndex, column: column))
  }

  func indentationError(lineIndex: Int? = nil, column: Int? = nil) -> YAML.ParseError {
    let targetIndex = lineIndex ?? index
    return .invalidIndentation(location: location(lineIndex: targetIndex, column: column))
  }

  func incompleteError(lineIndex: Int? = nil, column: Int? = nil) -> YAML.ParseError {
    let targetIndex = lineIndex ?? index
    return .incompleteInput(location: location(lineIndex: targetIndex, column: column))
  }

  func trimLeadingWhitespace(_ text: String) -> (trimmed: String, offset: Int) {
    var cursor = text.startIndex
    var offset = 0
    while cursor < text.endIndex, text[cursor].isWhitespace {
      text.formIndex(after: &cursor)
      offset += 1
    }
    return (String(text[cursor...]), offset)
  }

  // MARK: - Decorators

  struct Decorators {
    let tag: String?
    let anchor: String?
  }

  // MARK: - Entry Points

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

  // MARK: - Accessors

  func remainingText() -> String {
    guard index < lines.count else {
      return ""
    }
    let remaining = lines[index...].map { $0.raw }
    return remaining.joined(separator: "\n")
  }

  var allowsDirectives: Bool { allowDirectives }
  var requiresDocumentStart: Bool { requireDocumentStart }
}
