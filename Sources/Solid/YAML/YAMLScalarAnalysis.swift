//
//  YAMLScalarAnalysis.swift
//  SolidFoundation
//
//  Created by Codex on 5/11/26.
//

import SolidData


struct YAMLScalarAnalysis: Sendable {

  let isEmpty: Bool
  let hasLineBreak: Bool
  let hasLineFeed: Bool
  let hasNonAscii: Bool
  let hasNonPrintable: Bool
  let hasBlockUnsafeScalar: Bool
  let hasLineTrailingWhitespace: Bool
  let hasTrailingWhitespace: Bool
  let startsWithDocumentMarker: Bool
  let containsCommentIndicator: Bool
  let containsKeySeparator: Bool
  let endsWithColon: Bool
  let trailingColonRequiresQuotes: Bool
  let firstByteRequiresQuotes: Bool
  let leadingWhitespaceRequiresQuotes: Bool
  let hasContentLine: Bool
  let firstContentLineStartsWithWhitespace: Bool
  let resolvesToNonString: Bool
  let isOnlyNewlines: Bool

  var needsQuotes: Bool {
    isEmpty ||
      hasLineBreak ||
      hasNonPrintable ||
      hasTrailingWhitespace ||
      startsWithDocumentMarker ||
      containsCommentIndicator ||
      containsKeySeparator ||
      trailingColonRequiresQuotes ||
      firstByteRequiresQuotes ||
      leadingWhitespaceRequiresQuotes ||
      resolvesToNonString
  }

  var canUseBlockScalar: Bool {
    hasLineFeed &&
      hasContentLine &&
      !firstContentLineStartsWithWhitespace &&
      !hasLineTrailingWhitespace &&
      !hasBlockUnsafeScalar
  }

  static func analyze(
    _ string: String,
    allowImplicitTyping: Bool,
    allowDocumentMarkerPrefix: Bool,
    quoteTrailingColon: Bool
  ) -> Self {
    guard !string.isEmpty else {
      return Self(
        isEmpty: true,
        hasLineBreak: false,
        hasLineFeed: false,
        hasNonAscii: false,
        hasNonPrintable: false,
        hasBlockUnsafeScalar: false,
        hasLineTrailingWhitespace: false,
        hasTrailingWhitespace: false,
        startsWithDocumentMarker: false,
        containsCommentIndicator: false,
        containsKeySeparator: false,
        endsWithColon: false,
        trailingColonRequiresQuotes: false,
        firstByteRequiresQuotes: false,
        leadingWhitespaceRequiresQuotes: false,
        hasContentLine: false,
        firstContentLineStartsWithWhitespace: false,
        resolvesToNonString: !allowImplicitTyping,
        isOnlyNewlines: false
      )
    }

    let utf8 = string.utf8
    let first = utf8[utf8.startIndex]
    let last = utf8[utf8.index(before: utf8.endIndex)]

    var hasLineBreak = false
    var hasLineFeed = false
    var hasNonAscii = false
    var hasNonPrintable = false
    var hasBlockUnsafeScalar = false
    var hasLineTrailingWhitespace = false
    var containsCommentIndicator = false
    var containsKeySeparator = false
    var isOnlyNewlines = true
    var firstContentLineStartsWithWhitespace = false
    var foundFirstContentLine = false
    var atLineStart = true
    var previous = first
    var index = utf8.startIndex

    while index < utf8.endIndex {
      let byte = utf8[index]

      if atLineStart, byte != 0x0A, !foundFirstContentLine {
        foundFirstContentLine = true
        firstContentLineStartsWithWhitespace = byte == 0x20 || byte == 0x09
      }

      if byte < 0x80 {
        switch byte {
        case 0x09:
          hasNonPrintable = true
          isOnlyNewlines = false
        case 0x0A:
          hasLineBreak = true
          hasLineFeed = true
          hasLineTrailingWhitespace = hasLineTrailingWhitespace || previous == 0x20 || previous == 0x09
          atLineStart = true
          previous = byte
          utf8.formIndex(after: &index)
          continue
        case 0x0D:
          hasLineBreak = true
          hasBlockUnsafeScalar = true
        case 0x00..<0x20, 0x7F:
          hasNonPrintable = true
          hasBlockUnsafeScalar = true
          isOnlyNewlines = false
        default:
          isOnlyNewlines = false
        }

        if byte == 0x23 && (previous == 0x20 || previous == 0x09) {
          containsCommentIndicator = true
        }
        if previous == 0x3A && (byte == 0x20 || byte == 0x09) {
          containsKeySeparator = true
        }

        atLineStart = false
        previous = byte
        utf8.formIndex(after: &index)
      } else {
        hasNonAscii = true
        let scalar = string.unicodeScalars[index]
        let scalarIsLineBreak = scalar.value == 0x85 || scalar.value == 0x2028 || scalar.value == 0x2029
        if scalarIsLineBreak {
          hasLineBreak = true
          hasBlockUnsafeScalar = true
        } else {
          isOnlyNewlines = false
        }
        if !isPrintable(scalar) {
          hasNonPrintable = true
          hasBlockUnsafeScalar = true
        }
        let next = string.unicodeScalars.index(after: index)
        previous = utf8[utf8.index(before: next)]
        atLineStart = false
        index = next
      }
    }

    let hasTrailingWhitespace = last == 0x20 || last == 0x09 || last == 0x0A || last == 0x0D
    if last == 0x20 || last == 0x09 {
      hasLineTrailingWhitespace = true
    }
    let endsWithColon = last == 0x3A
    let leadingWhitespaceRequiresQuotes = first == 0x20 || first == 0x09 || first == 0x0A || first == 0x0D
    let resolvesToNonString = !allowImplicitTyping && resolvesToNonStringFast(string)

    return Self(
      isEmpty: false,
      hasLineBreak: hasLineBreak,
      hasLineFeed: hasLineFeed,
      hasNonAscii: hasNonAscii,
      hasNonPrintable: hasNonPrintable,
      hasBlockUnsafeScalar: hasBlockUnsafeScalar,
      hasLineTrailingWhitespace: hasLineTrailingWhitespace,
      hasTrailingWhitespace: hasTrailingWhitespace,
      startsWithDocumentMarker: documentMarkerRequiresQuotes(
        utf8: utf8,
        allowDocumentMarkerPrefix: allowDocumentMarkerPrefix
      ),
      containsCommentIndicator: containsCommentIndicator,
      containsKeySeparator: containsKeySeparator,
      endsWithColon: endsWithColon,
      trailingColonRequiresQuotes: quoteTrailingColon && endsWithColon,
      firstByteRequiresQuotes: leadingIndicatorRequiresQuotes(first: first, utf8: utf8),
      leadingWhitespaceRequiresQuotes: leadingWhitespaceRequiresQuotes,
      hasContentLine: foundFirstContentLine,
      firstContentLineStartsWithWhitespace: firstContentLineStartsWithWhitespace,
      resolvesToNonString: resolvesToNonString,
      isOnlyNewlines: hasLineFeed && isOnlyNewlines
    )
  }

  private static func leadingIndicatorRequiresQuotes(first: UInt8, utf8: String.UTF8View) -> Bool {
    switch first {
    case 0x2C, 0x5B, 0x5D, 0x7B, 0x7D, 0x23, 0x26, 0x2A, 0x21, 0x7C, 0x3E, 0x27, 0x22, 0x25, 0x40, 0x60:
      return true
    case 0x2D, 0x3F, 0x3A:
      let nextIndex = utf8.index(after: utf8.startIndex)
      guard nextIndex < utf8.endIndex else { return true }
      let next = utf8[nextIndex]
      return next == 0x20 || next == 0x09 || next == 0x0A || next == 0x0D
    default:
      return false
    }
  }

  private static func documentMarkerRequiresQuotes(
    utf8: String.UTF8View,
    allowDocumentMarkerPrefix: Bool
  ) -> Bool {
    guard utf8.count >= 3 else { return false }
    let i0 = utf8.startIndex
    let i1 = utf8.index(after: i0)
    let i2 = utf8.index(after: i1)
    let b0 = utf8[i0]
    let b1 = utf8[i1]
    let b2 = utf8[i2]
    guard (b0 == 0x2D && b1 == 0x2D && b2 == 0x2D) ||
      (b0 == 0x2E && b1 == 0x2E && b2 == 0x2E)
    else {
      return false
    }
    let i3 = utf8.index(after: i2)
    return !allowDocumentMarkerPrefix ||
      i3 == utf8.endIndex ||
      utf8[i3] == 0x20 ||
      utf8[i3] == 0x09
  }

  private static func resolvesToNonStringFast(_ string: String) -> Bool {
    if string == "~" || string.utf8EqualsCaseInsensitiveASCII("null") {
      return true
    }
    if string.utf8EqualsCaseInsensitiveASCII("true") ||
      string.utf8EqualsCaseInsensitiveASCII("false")
    {
      return true
    }
    guard let first = string.utf8.first, isNumericCandidateStart(first) else {
      return false
    }
    let resolved = YAMLTagResolver().resolve(YAMLScalar(text: string, style: .plain), explicitTag: nil, wrapTag: false)
    if case .string = resolved {
      return false
    }
    return true
  }

  private static func isNumericCandidateStart(_ byte: UInt8) -> Bool {
    (byte >= 0x30 && byte <= 0x39) || byte == 0x2B || byte == 0x2D || byte == 0x2E
  }

  private static func isPrintable(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x9, 0xA, 0xD:
      return true
    case 0x20...0x7E:
      return true
    case 0x85:
      return true
    case 0xA0...0xD7FF:
      return true
    case 0xE000...0xFFFD:
      return true
    case 0x10000...0x10FFFF:
      return true
    default:
      return false
    }
  }
}
