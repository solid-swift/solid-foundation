//
//  YAMLParser-Utilities.swift
//  SolidFoundation
//

extension YAMLParser {

  func leadingSpaceCount(_ raw: String) -> Int {
    var count = 0
    for char in raw {
      guard char == " " else {
        break
      }
      count += 1
    }
    return count
  }

  func indexAfterIndent(_ raw: String, requiredIndent: Int) -> String.Index {
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

  func hasTabInIndent(_ line: Line, requiredIndent: Int) -> Bool {
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

  func hasTabAfterIndicator(_ content: String, indicator: Character) -> Bool {
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

  mutating func skipEmptyLines() {
    while index < lines.count {
      let content = lines[index].trimmedContent
      guard content.isEmpty else {
        break
      }
      index += 1
    }
  }

  func nextNonEmptyLineIndex(from start: Int) -> Int? {
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

  func isDocumentStart(_ line: Line) -> Bool {
    let trimmed = line.trimmedContent
    guard trimmed.hasPrefix("---") else { return false }
    if trimmed == "---" {
      return true
    }
    let index = trimmed.index(trimmed.startIndex, offsetBy: 3)
    return index < trimmed.endIndex && trimmed[index].isWhitespace
  }

  func isDocumentEnd(_ line: Line) -> Bool {
    line.trimmedContent == "..."
  }

  /// Checks if content starts with "- " or is just "-".
  /// Content is expected to be already trimmed.
  func isSequenceIndicator(_ content: String) -> Bool {
    guard let first = content.utf8.first, first == UInt8(ascii: "-") else { return false }
    let utf8 = content.utf8
    if utf8.count == 1 { return true }
    let second = utf8[utf8.index(after: utf8.startIndex)]
    return second == 0x20 || second == 0x09  // space or tab
  }

  /// Checks if content starts with "? " or is just "?".
  /// Content is expected to be already trimmed.
  func isExplicitMappingIndicator(_ content: String) -> Bool {
    guard let first = content.utf8.first, first == UInt8(ascii: "?") else { return false }
    let utf8 = content.utf8
    if utf8.count == 1 { return true }
    let second = utf8[utf8.index(after: utf8.startIndex)]
    return second == 0x20 || second == 0x09
  }

  /// Checks if content starts with "[" or "{".
  /// Content is expected to be already trimmed.
  func isFlowCollectionIndicator(_ content: String) -> Bool {
    guard let first = content.utf8.first else { return false }
    return first == UInt8(ascii: "[") || first == UInt8(ascii: "{")
  }

}
