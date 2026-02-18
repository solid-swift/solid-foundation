//
//  YAMLInlineParser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import SolidData

// MARK: - Inline Parser

struct InlineParser {

  private(set) var text: String
  var index: String.Index
  private let baseLine: Int
  private let lineStartColumns: [Int]

  init(text: String) {
    self.text = text
    self.index = text.startIndex
    self.baseLine = 1
    self.lineStartColumns = [1]
  }

  init(text: String, baseLine: Int, lineStartColumns: [Int]) {
    self.text = text
    self.index = text.startIndex
    self.baseLine = baseLine
    self.lineStartColumns = lineStartColumns.isEmpty ? [1] : lineStartColumns
  }

  func location(at position: String.Index? = nil) -> YAML.ParseError.Location {
    let target = position ?? index
    var lineOffset = 0
    var columnOffset = 0
    var cursor = text.startIndex
    while cursor < target {
      let char = text[cursor]
      if char.isNewline {
        lineOffset += 1
        columnOffset = 0
      } else {
        columnOffset += 1
      }
      text.formIndex(after: &cursor)
    }
    let startColumn =
      lineStartColumns.indices.contains(lineOffset)
      ? lineStartColumns[lineOffset]
      : (lineStartColumns.first ?? 1)
    return .init(line: baseLine + lineOffset, column: startColumn + columnOffset)
  }

  func syntaxError(_ message: String, at position: String.Index? = nil) -> YAML.ParseError {
    .invalidSyntax(message, location: location(at: position))
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
          index = text.endIndex
          break
        }
        let prevIndex = text.index(before: index)
        if text[prevIndex].isWhitespace {
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
          throw syntaxError("Multiple tags on node")
        }
        tag = try parseTag(flowContext: flowContext)
      } else if current == "&" {
        if anchor != nil {
          throw syntaxError("Multiple anchors on node")
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
        throw syntaxError("Invalid tag")
      }
      return buffer
    }

    while let current = peek {
      if current.isWhitespace {
        break
      }
      if current == "," || current == "]" || current == "}" {
        if !flowContext {
          throw syntaxError("Invalid tag")
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
      throw syntaxError("Invalid tag")
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
      throw syntaxError("Alias without name")
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
        guard let escaped = peek else { throw syntaxError("Invalid escape sequence") }
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
    throw syntaxError("Unterminated double-quoted scalar")
  }

  mutating func parseSingleQuoted() throws -> String {
    consume(expected: "'")
    var output = ""
    while let current = peek {
      text.formIndex(after: &index)
      if current == "'" {
        if peek == "'" {
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
    throw syntaxError("Unterminated single-quoted scalar")
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
    return output.yamlTrimmed()
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
      guard let scalar = UnicodeScalar(code) else { throw syntaxError("Invalid hex escape") }
      return Character(scalar)
    case "u":
      let code = try readHex(count: 4)
      guard let scalar = UnicodeScalar(code) else { throw syntaxError("Invalid unicode escape") }
      return Character(scalar)
    case "U":
      let code = try readHex(count: 8)
      guard let scalar = UnicodeScalar(code) else { throw syntaxError("Invalid unicode escape") }
      return Character(scalar)
    default:
      throw syntaxError("Unknown escape sequence")
    }
  }

  private mutating func readHex(count: Int) throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<count {
      guard let current = peek else {
        throw syntaxError("Incomplete escape sequence")
      }
      guard let digit = current.hexDigitValue else {
        throw syntaxError("Invalid hex digit")
      }
      value = (value << 4) | UInt32(digit)
      text.formIndex(after: &index)
    }
    return value
  }
}

// MARK: - Fast ASCII Whitespace Trimming

extension String {
  /// Faster than `trimmingCharacters(in: .whitespaces)` — avoids Foundation's
  /// CharacterSet and skips allocation when no trimming is needed.
  @inline(__always)
  func yamlTrimmed() -> String {
    let utf8 = self.utf8
    guard !utf8.isEmpty else { return self }

    var start = utf8.startIndex
    while start < utf8.endIndex {
      let byte = utf8[start]
      if byte != 0x20 && byte != 0x09 { break }
      utf8.formIndex(after: &start)
    }

    if start == utf8.endIndex { return "" }

    var end = utf8.index(before: utf8.endIndex)
    while end > start {
      let byte = utf8[end]
      if byte != 0x20 && byte != 0x09 { break }
      utf8.formIndex(before: &end)
    }
    let afterEnd = utf8.index(after: end)

    if start == utf8.startIndex && afterEnd == utf8.endIndex {
      return self
    }

    return String(self[start..<afterEnd])
  }
}

extension Substring {
  /// Trims leading and trailing ASCII whitespace (space and tab only).
  @inline(__always)
  func yamlTrimmed() -> String {
    let utf8 = self.utf8
    guard !utf8.isEmpty else { return "" }

    var start = utf8.startIndex
    while start < utf8.endIndex {
      let byte = utf8[start]
      if byte != 0x20 && byte != 0x09 { break }
      utf8.formIndex(after: &start)
    }

    if start == utf8.endIndex { return "" }

    var end = utf8.index(before: utf8.endIndex)
    while end > start {
      let byte = utf8[end]
      if byte != 0x20 && byte != 0x09 { break }
      utf8.formIndex(before: &end)
    }

    return String(self[start...end])
  }
}
