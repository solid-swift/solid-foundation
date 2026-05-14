//
//  YAMLTokenizer.swift
//  SolidFoundation
//
//  Created by Codex on 4/24/26.
//

import Foundation
import SolidData

/// Raw tokenizer output consumed by `YAMLEventReader`.
///
/// This is intentionally YAML-specific: it preserves presentation details
/// needed by the YAML node/event APIs while still carrying scalar bytes as
/// retained `ParseBuffer.Region` values for lazy materialization.
enum YAMLRawToken: Sendable {
  case directive(name: String, value: String?)
  case documentStart(explicit: Bool)
  case documentEnd(explicit: Bool)
  case beginSequence(style: YAMLCollectionStyle)
  case endSequence
  case beginMapping(style: YAMLCollectionStyle)
  case endMapping
  case scalar(YAMLRawScalar)
  case tag(String)
  case anchor(String)
  case alias(String)
}

struct YAMLRawScalar: Sendable {
  let style: YAMLScalarStyle
  let kind: ScalarRef.Kind
  let region: ParseBuffer.Region
}

private func validatedYAMLUTF8String(
  _ bytes: UnsafeBufferPointer<UInt8>,
  in range: Range<Int>
) -> String? {
  String(bytes: UnsafeBufferPointer(rebasing: bytes[range]), encoding: .utf8)
}

private func decodeYAMLTagSuffix(
  _ text: String,
  location: YAML.ParseError.Location
) throws -> String {
  guard text.contains("%") else {
    return text
  }

  var output = ContiguousArray<UInt8>()
  output.reserveCapacity(text.utf8.count)

  var index = text.startIndex
  while index < text.endIndex {
    let char = text[index]
    if char == "%" {
      let next1 = text.index(after: index)
      guard next1 < text.endIndex else {
        throw YAML.ParseError.invalidSyntax("Invalid tag", location: location)
      }
      let next2 = text.index(after: next1)
      guard next2 < text.endIndex,
        let hi = text[next1].hexDigitValue,
        let lo = text[next2].hexDigitValue
      else {
        throw YAML.ParseError.invalidSyntax("Invalid tag", location: location)
      }
      output.append(UInt8((hi << 4) | lo))
      index = text.index(after: next2)
      continue
    }
    output.append(contentsOf: String(char).utf8)
    index = text.index(after: index)
  }

  guard let decoded = String(bytes: output, encoding: .utf8) else {
    throw YAML.ParseError.invalidSyntax("Invalid tag", location: location)
  }
  return decoded
}

/// Incremental byte-level tokenizer for YAML.
///
/// The tokenizer scans retained byte regions from `ParseBuffer`, emits
/// YAML-native raw tokens, and preserves scalar source regions whenever YAML
/// does not require folding, unescaping, or other normalization. Generated
/// side-buffer regions are used only for normalized scalar payloads. Flow-style
/// collections are split into lexical scanning and structural event assembly so
/// only the currently ambiguous node candidate is delayed for lookahead.
struct YAMLTokenizer: ~Copyable, Sendable {

  private enum BlockKind: Sendable {
    case sequence
    case mapping
  }

  private struct BlockContext: Sendable {
    let kind: BlockKind
    let indent: Int
  }

  private struct PendingBlockScalar: Sendable {
    let style: YAMLScalarStyle
    let parentIndent: Int
    var contentIndent: Int?
    var lines: ContiguousArray<PendingBlockScalarLine> = []
    var leadingBlankIndent: Int?
  }

  private struct PendingBlockScalarLine: Sendable {
    let region: ParseBuffer.Region?
    let virtualPrefixSpaces: Int
    let indent: Int
    let generatedBytes: Data?

    var isEmpty: Bool {
      virtualPrefixSpaces == 0 && (generatedBytes?.isEmpty ?? true) && (region?.isEmpty ?? true)
    }

    var byteCount: Int {
      virtualPrefixSpaces + (generatedBytes?.count ?? 0) + (region?.count ?? 0)
    }

    var firstByte: UInt8? {
      if virtualPrefixSpaces > 0 {
        return .space
      }
      if let generatedBytes, let first = generatedBytes.first {
        return first
      }
      return region?.firstByte
    }

    func appendBytes(to output: inout Data) {
      if virtualPrefixSpaces > 0 {
        output.append(contentsOf: repeatElement(UInt8.space, count: virtualPrefixSpaces))
      }
      if let generatedBytes {
        output.append(generatedBytes)
      }
      if let region {
        region.withUnsafeBytes { rawBuffer in
          let typed = rawBuffer.bindMemory(to: UInt8.self)
          guard let baseAddress = typed.baseAddress else { return }
          output.append(baseAddress, count: typed.count)
        }
      }
    }
  }

  private struct PendingFlow: ~Copyable, Sendable {
    var lexer: YAMLFlowLexer
    var adapter: YAMLFlowStructureAdapter
    let opener: UInt8
    let minimumContinuationIndent: Int?
    var nextFeedLeadingNewline: Bool

    var isComplete: Bool { adapter.isComplete }

    mutating func feedEmptyLine(
      line: Int,
      column: Int,
      into queue: inout PendingTokenQueue
    ) throws {
      lexer.feedEmptyLine(line: line, column: column)
      try adapter.consume(from: &lexer, into: &queue)
    }

    mutating func feedLine(
      _ region: ParseBuffer.Region,
      lineEnded: Bool,
      line: Int,
      column: Int,
      into queue: inout PendingTokenQueue
    ) throws {
      lexer.feedLine(region, leadingNewline: nextFeedLeadingNewline, line: line, column: column)
      nextFeedLeadingNewline = lineEnded
      try adapter.consume(from: &lexer, into: &queue)
    }

    mutating func finish(into queue: inout PendingTokenQueue) throws {
      lexer.finish()
      try adapter.consume(from: &lexer, into: &queue)
      try adapter.finish(into: &queue)
    }
  }

  private struct QuotedScalarCompletionState: Sendable {
    let style: YAMLScalarStyle
    private(set) var isComplete = false
    private var doubleQuoteEscaped = false

    init(style: YAMLScalarStyle) {
      self.style = style
    }

    mutating func appendOpeningText(_ text: String) {
      append(text, skippingOpeningQuote: true)
    }

    mutating func appendLineBreak() {
      append(byte: .newline)
    }

    mutating func append(_ text: String, skippingOpeningQuote: Bool = false) {
      guard !isComplete else {
        return
      }
      let bytes = text.utf8
      var start = bytes.startIndex
      if skippingOpeningQuote, start < bytes.endIndex {
        start = bytes.index(after: start)
      }
      append(bytes, startingAt: start)
    }

    private mutating func append(_ bytes: String.UTF8View, startingAt start: String.UTF8View.Index) {
      switch style {
      case .singleQuoted:
        var index = start
        while index < bytes.endIndex {
          if bytes[index] == .singleQuote {
            let next = bytes.index(after: index)
            if next < bytes.endIndex, bytes[next] == .singleQuote {
              index = bytes.index(after: next)
              continue
            }
            isComplete = true
            return
          }
          index = bytes.index(after: index)
        }

      case .doubleQuoted:
        var index = start
        while index < bytes.endIndex {
          append(byte: bytes[index])
          if isComplete {
            return
          }
          index = bytes.index(after: index)
        }

      default:
        isComplete = true
      }
    }

    private mutating func append(byte: UInt8) {
      guard !isComplete else {
        return
      }
      guard case .doubleQuoted = style else {
        return
      }
      if doubleQuoteEscaped {
        doubleQuoteEscaped = false
      } else if byte == .backslash {
        doubleQuoteEscaped = true
      } else if byte == .doubleQuote {
        isComplete = true
      }
    }
  }

  private struct PendingQuotedScalar: Sendable {
    var text: String
    let style: YAMLScalarStyle
    let location: YAML.ParseError.Location
    let minimumContinuationIndent: Int?
    var completion: QuotedScalarCompletionState

    var isComplete: Bool {
      completion.isComplete
    }

    mutating func appendLineBreak() {
      text.append("\n")
      completion.appendLineBreak()
    }
  }

  private struct PendingPlainScalarLine: Sendable {
    let region: ParseBuffer.Region?
    let bytes: Data
    let indent: Int

    var isEmpty: Bool {
      if let region {
        return region.isEmpty
      }
      return bytes.isEmpty
    }

    func appendBytes(to output: inout Data) {
      if let region {
        region.withUnsafeBytes { rawBuffer in
          let typed = rawBuffer.bindMemory(to: UInt8.self)
          guard let baseAddress = typed.baseAddress else { return }
          output.append(baseAddress, count: typed.count)
        }
      } else {
        output.append(bytes)
      }
    }
  }

  private struct PendingPlainScalar: Sendable {
    var lines: ContiguousArray<PendingPlainScalarLine> = []
    let initialIndent: Int
    let minIndent: Int
    let location: YAML.ParseError.Location
    let originalRegion: ParseBuffer.Region?
  }

  private struct PendingBlockValue: Sendable {
    let indent: Int
    let acceptsExplicitValueLine: Bool
    var closesNestedBlocksBeforeEmptyValue = false
    var hasDecoratedEmptyScalar = false
    var finishDecoratedEmptyBeforeSameIndentSequence = false
  }

  private struct PendingSequenceEntry: Sendable {
    let indent: Int
  }

  private struct PendingExplicitKey: Sendable {
    let indent: Int
    var sawNode: Bool
  }

  struct PendingTokenQueue: Sendable {
    private var tokens: ContiguousArray<YAMLRawToken?> = []
    private var head = 0

    var isEmpty: Bool {
      head == tokens.count
    }

    mutating func append(_ token: YAMLRawToken) {
      tokens.append(token)
    }

    mutating func popFirst() -> YAMLRawToken {
      precondition(!isEmpty)
      guard let token = tokens[head] else {
        preconditionFailure("Pending token queue slot was already consumed")
      }
      tokens[head] = nil
      head += 1
      if isEmpty {
        tokens.removeAll(keepingCapacity: tokens.capacity <= 64)
        head = 0
      } else if head >= 64, head * 2 >= tokens.count {
        tokens.removeFirst(head)
        head = 0
      }
      return token
    }
  }

  private struct YAMLLineBytes: Sendable {
    let region: ParseBuffer.Region

    func strippingSeparatedComment() -> (region: ParseBuffer.Region, hadComment: Bool) {
      region.withUnsafeBytes { rawBuffer in
        let bytes = rawBuffer.bindMemory(to: UInt8.self)
        var inSingleQuote = false
        var inDoubleQuote = false
        var escapingDoubleQuote = false
        var offset = 0

        while offset < bytes.count {
          let byte = bytes[offset]

          if inDoubleQuote {
            if escapingDoubleQuote {
              escapingDoubleQuote = false
            } else if byte == .backslash {
              escapingDoubleQuote = true
            } else if byte == .doubleQuote {
              inDoubleQuote = false
            }
            offset += 1
            continue
          }

          if inSingleQuote {
            if byte == .singleQuote {
              let next = offset + 1
              if next < bytes.count, bytes[next] == .singleQuote {
                offset += 2
                continue
              }
              inSingleQuote = false
            }
            offset += 1
            continue
          }

          if byte == .singleQuote {
            inSingleQuote = true
          } else if byte == .doubleQuote {
            inDoubleQuote = true
          } else if byte == .comment, commentHasSeparation(in: bytes, at: offset) {
            return (region.subregion(0..<trimTrailingHorizontalWhitespace(in: bytes, before: offset)), true)
          }

          offset += 1
        }

        return (region, false)
      }
    }

    private func commentHasSeparation(in bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
      guard offset > 0 else {
        return true
      }
      let previous = bytes[offset - 1]
      return previous == .space || previous == .tab
    }

    private func trimTrailingHorizontalWhitespace(in bytes: UnsafeBufferPointer<UInt8>, before offset: Int) -> Int {
      var end = offset
      while end > 0 {
        let previous = bytes[end - 1]
        guard previous == .space || previous == .tab else {
          break
        }
        end -= 1
      }
      return end
    }
  }

  private struct YAMLLineSlice: Sendable {
    let line: Int
    let indent: Int
    let originalRegion: ParseBuffer.Region
    let contentRegion: ParseBuffer.Region
    let trimmedRegion: ParseBuffer.Region
    let lineHadComment: Bool
    let hasLeadingIndentTab: Bool
    let quotedTrailingWhitespace: YAMLQuotedTrailingWhitespace

    var location: YAML.ParseError.Location {
      YAML.ParseError.Location(line: line, column: indent + 1)
    }

    var indentationErrorLocation: YAML.ParseError.Location {
      YAML.ParseError.Location(
        line: line,
        column: indent + (hasLeadingIndentTab ? 2 : 1)
      )
    }
  }

  private struct YAMLQuotedTrailingWhitespace: Sendable {
    let region: ParseBuffer.Region?

    static let empty = YAMLQuotedTrailingWhitespace(region: nil)

    var isEmpty: Bool {
      region?.isEmpty ?? true
    }

    var firstByte: UInt8? {
      region?.firstByte
    }

    func string() throws -> String {
      guard let region else {
        return ""
      }
      return try region.string()
    }

    func stringDroppingFirstByte() throws -> String {
      guard let region, region.count > 1 else {
        return ""
      }
      return try region.subregion(1..<region.count).string()
    }
  }

  private struct YAMLRegionMappingSplit: Sendable {
    let key: ParseBuffer.Region
    let value: ParseBuffer.Region
  }

  private struct YAMLRegionDecorators: Sendable {
    var tokens: ContiguousArray<YAMLRawToken>
    let remainder: ParseBuffer.Region
    let isAlias: Bool
  }

  private struct YAMLDirectiveParts: Sendable {
    let name: String
    let value: String?
  }

  private var buffer = ParseBuffer()
  private var pendingTokens = PendingTokenQueue()
  private var blockStack: ContiguousArray<BlockContext> = []
  private var pendingBlockScalar: PendingBlockScalar?
  private var pendingBlockValue: PendingBlockValue?
  private var pendingSequenceEntry: PendingSequenceEntry?
  private var pendingExplicitKey: PendingExplicitKey?
  private var pendingFlow: PendingFlow?
  private var pendingQuotedScalar: PendingQuotedScalar?
  private var pendingPlainScalar: PendingPlainScalar?
  private var finalReceived = false
  private var finished = false
  private var documentOpen = false
  private var documentHasContent = false
  private var currentLine = 1
  private static let defaultTagHandles: [String: String] = [
    "!": "!",
    "!!": "tag:yaml.org,2002:",
  ]
  private var tagHandles = YAMLTokenizer.defaultTagHandles
  private var pendingTagHandles = YAMLTokenizer.defaultTagHandles
  private var allowDirectives = true
  private var pendingDirectiveWithoutDocument = false
  private var pendingYAMLDirective = false

  init() {}

  mutating func feedInput(_ data: consuming Data, isFinal: Bool) {
    if !data.isEmpty {
      buffer.append(data)
    }
    if isFinal {
      finalReceived = true
    }
  }

  mutating func readToken() throws -> YAMLRawToken? {
    while pendingTokens.isEmpty {
      guard !finished else { return nil }
      if try readLineToken() {
        continue
      }
      if finalReceived {
        try closeAllBlocks()
        if !pendingTokens.isEmpty {
          continue
        }
        if pendingDirectiveWithoutDocument {
          throw YAML.ParseError.invalidSyntax(
            "Directive without document",
            location: .init(line: currentLine, column: 1)
          )
        }
        if documentOpen {
          appendEmptyDocumentContentIfNeeded()
          pendingTokens.append(.documentEnd(explicit: false))
          documentOpen = false
          finished = true
          continue
        }
        finished = true
        return nil
      }
      return nil
    }

    return pendingTokens.popFirst()
  }

  // MARK: - Lines

  private mutating func readLineToken() throws -> Bool {
    let lineStart = buffer.mark()
    let lineNumber = currentLine
    var contentStart: ParseBuffer.Position?
    var contentEnd: ParseBuffer.Position?
    var previousWasWhitespace = true
    var lineStartsQuotedScalar = false
    var quotedTrailingStart: ParseBuffer.Position?
    var quotedTrailingEnd: ParseBuffer.Position?
    var hasLeadingIndentTab = false
    var inSingleQuote = false
    var inDoubleQuote = false
    var doubleQuoteEscaped = false
    var sawByte = false
    var indent = 0

    while let byte = buffer.peekByte() {
      let before = buffer.mark()
      _ = try buffer.readByte()

      if byte == .newline {
        defer { currentLine += 1 }
        return try processLine(
          line: lineNumber,
          indent: indent,
          contentStart: contentStart,
          contentEnd: contentEnd,
          lineHadComment: false,
          hasLeadingIndentTab: hasLeadingIndentTab,
          quotedTrailingWhitespace: quotedTrailingWhitespace(from: quotedTrailingStart, to: quotedTrailingEnd)
        )
      }

      if byte == .carriageReturn {
        continue
      }

      sawByte = true

      if contentStart == nil, byte == .tab,
        pendingFlow == nil,
        pendingBlockScalar == nil,
        pendingQuotedScalar == nil
      {
        hasLeadingIndentTab = true
      }
      if byte == .comment, previousWasWhitespace,
        pendingFlow == nil,
        pendingBlockScalar == nil,
        pendingQuotedScalar == nil,
        !inSingleQuote,
        !inDoubleQuote
      {
        let consumedNewline = try consumeThroughLineBreak()
        defer {
          if consumedNewline {
            currentLine += 1
          }
        }
        return try processLine(
          line: lineNumber,
          indent: indent,
          contentStart: contentStart,
          contentEnd: contentEnd,
          lineHadComment: true
        )
      }

      if !byte.isYAMLHorizontalWhitespace {
        if contentStart == nil {
          contentStart = before
        lineStartsQuotedScalar = byte == .singleQuote || byte == .doubleQuote
        }
        contentEnd = buffer.mark()
        quotedTrailingStart = nil
        quotedTrailingEnd = nil
        previousWasWhitespace = false
      } else {
        if contentStart == nil,
          pendingFlow != nil,
          pendingFlow?.nextFeedLeadingNewline == false
        {
          contentStart = before
          contentEnd = buffer.mark()
        }
        if contentStart == nil, byte == .space {
          indent += 1
        }
        if pendingBlockScalar != nil {
          if contentStart == nil, byte == .tab {
            contentStart = before
          }
          if contentStart != nil {
            contentEnd = buffer.mark()
          }
        } else if contentStart != nil, pendingQuotedScalar != nil || lineStartsQuotedScalar {
          if quotedTrailingStart == nil {
            quotedTrailingStart = before
          }
          quotedTrailingEnd = buffer.mark()
        }
        previousWasWhitespace = true
      }

      if contentStart != nil, pendingFlow == nil, pendingBlockScalar == nil,
        pendingQuotedScalar == nil
      {
        updateInlineQuoteState(
          byte: byte,
          inSingleQuote: &inSingleQuote,
          inDoubleQuote: &inDoubleQuote,
          doubleQuoteEscaped: &doubleQuoteEscaped
        )
      }
    }

    if !finalReceived,
      let contentStart,
      let contentEnd
    {
      let region = buffer.region(from: contentStart, to: contentEnd).trimmedHorizontalWhitespace()
      if pendingFlow != nil || region.startsFlowCollection {
        let processed = try processLine(
          line: lineNumber,
          indent: indent,
          contentStart: contentStart,
          contentEnd: contentEnd,
          lineHadComment: false,
          hasLeadingIndentTab: hasLeadingIndentTab,
          quotedTrailingWhitespace: quotedTrailingWhitespace(from: quotedTrailingStart, to: quotedTrailingEnd),
          lineEnded: false
        )
        pendingFlow?.nextFeedLeadingNewline = false
        return processed
      }
    }

    guard finalReceived else {
      buffer.restore(lineStart)
      return false
    }

    guard sawByte || contentStart != nil else {
      return false
    }
    return try processLine(
      line: lineNumber,
      indent: indent,
      contentStart: contentStart,
      contentEnd: contentEnd,
      lineHadComment: false,
      hasLeadingIndentTab: hasLeadingIndentTab,
      quotedTrailingWhitespace: quotedTrailingWhitespace(from: quotedTrailingStart, to: quotedTrailingEnd),
      lineEnded: false
    )
  }

  private mutating func quotedTrailingWhitespace(
    from start: ParseBuffer.Position?,
    to end: ParseBuffer.Position?
  ) -> YAMLQuotedTrailingWhitespace {
    guard let start, let end else {
      return .empty
    }
    return YAMLQuotedTrailingWhitespace(region: buffer.region(from: start, to: end))
  }

  private mutating func consumeThroughLineBreak() throws -> Bool {
    while let byte = buffer.peekByte() {
      _ = try buffer.readByte()
      if byte == .newline {
        return true
      }
    }
    return false
  }

  private func updateInlineQuoteState(
    byte: UInt8,
    inSingleQuote: inout Bool,
    inDoubleQuote: inout Bool,
    doubleQuoteEscaped: inout Bool
  ) {
    if inDoubleQuote {
      if doubleQuoteEscaped {
        doubleQuoteEscaped = false
      } else if byte == .backslash {
        doubleQuoteEscaped = true
      } else if byte == .doubleQuote {
        inDoubleQuote = false
      }
      return
    }

    if inSingleQuote {
      if byte == .singleQuote {
        inSingleQuote = false
      }
      return
    }

    if byte == .singleQuote {
      inSingleQuote = true
    } else if byte == .doubleQuote {
      inDoubleQuote = true
    }
  }

  private mutating func lineSlice(
    line: Int,
    indent: Int,
    contentStart: ParseBuffer.Position?,
    contentEnd: ParseBuffer.Position?,
    lineHadComment: Bool,
    hasLeadingIndentTab: Bool,
    quotedTrailingWhitespace: YAMLQuotedTrailingWhitespace
  ) -> YAMLLineSlice? {
    guard let contentStart, let contentEnd else {
      return nil
    }
    let originalRegion = buffer.region(from: contentStart, to: contentEnd)
    let stripped =
      quotedTrailingWhitespace.isEmpty
      ? YAMLLineBytes(region: originalRegion).strippingSeparatedComment()
      : (region: originalRegion, hadComment: false)
    let contentRegion = stripped.region
    return YAMLLineSlice(
      line: line,
      indent: indent,
      originalRegion: originalRegion,
      contentRegion: contentRegion,
      trimmedRegion: contentRegion.trimmedHorizontalWhitespace(),
      lineHadComment: lineHadComment || stripped.hadComment,
      hasLeadingIndentTab: hasLeadingIndentTab,
      quotedTrailingWhitespace: quotedTrailingWhitespace
    )
  }

  private mutating func processLine(
    line: Int,
    indent: Int,
    contentStart: ParseBuffer.Position?,
    contentEnd: ParseBuffer.Position?,
    lineHadComment: Bool,
    hasLeadingIndentTab: Bool = false,
    quotedTrailingWhitespace: YAMLQuotedTrailingWhitespace = .empty,
    lineEnded: Bool = true
  ) throws -> Bool {
    if pendingPlainScalar != nil {
      guard let contentStart, let contentEnd else {
        if lineHadComment {
          finishPendingPlainScalar()
        } else {
          pendingPlainScalar?.lines.append(PendingPlainScalarLine(region: nil, bytes: Data(), indent: indent))
        }
        return true
      }

      guard let lineSlice = lineSlice(
        line: line,
        indent: indent,
        contentStart: contentStart,
        contentEnd: contentEnd,
        lineHadComment: lineHadComment,
        hasLeadingIndentTab: hasLeadingIndentTab,
        quotedTrailingWhitespace: quotedTrailingWhitespace
      ) else {
        return true
      }
      let region = lineSlice.contentRegion
      if hasLeadingIndentTab, mappingSplit(in: lineSlice.trimmedRegion) != nil {
        throw YAML.ParseError.invalidIndentation(
          location: .init(line: line, column: indent + 1)
        )
      }
      if let pending = pendingPlainScalar,
        indent > pending.initialIndent,
        mappingSplit(in: lineSlice.trimmedRegion) != nil
      {
        throw YAML.ParseError.invalidSyntax(
          "Invalid mapping in plain scalar",
          location: .init(line: line, column: indent + 1)
        )
      }
      if shouldContinuePendingPlainScalar(indent: indent, region: region) {
        pendingPlainScalar?.lines.append(PendingPlainScalarLine(
          region: region.trimmedTrailingHorizontalWhitespace(),
          bytes: Data(),
          indent: indent
        ))
        if lineSlice.lineHadComment {
          finishPendingPlainScalar()
        }
        return true
      }

      finishPendingPlainScalar()
      return try processLine(
        line: line,
        indent: indent,
        contentStart: contentStart,
        contentEnd: contentEnd,
        lineHadComment: lineHadComment,
        hasLeadingIndentTab: hasLeadingIndentTab,
        quotedTrailingWhitespace: quotedTrailingWhitespace
      )
    }

    if pendingQuotedScalar != nil {
      guard let contentStart, let contentEnd else {
        pendingQuotedScalar?.appendLineBreak()
        return true
      }

      let region = buffer.region(from: contentStart, to: contentEnd)
      if indent == 0,
        isDocumentBoundaryAfterQuotedTrailingWhitespace(
          region: region,
          quotedTrailingWhitespace: quotedTrailingWhitespace
        )
      {
        throw YAML.ParseError.invalidSyntax(
          "Document marker is not allowed in quoted scalar",
          location: .init(line: line, column: indent + 1)
        )
      }

      guard var quoted = pendingQuotedScalar else {
        return true
      }
      if let minimumContinuationIndent = quoted.minimumContinuationIndent,
        indent < minimumContinuationIndent
      {
        throw YAML.ParseError.invalidIndentation(location: .init(line: line, column: indent + 1))
      }

      quoted.appendLineBreak()
      let rawText = try region.string()
      var lineCompletion = quoted.completion
      lineCompletion.append(rawText)
      let adjusted = try appendQuotedTrailingWhitespace(
        quotedTrailingWhitespace,
        to: rawText,
        style: quoted.style,
        scalarIsComplete: lineCompletion.isComplete
      )
      quoted.text.append(adjusted.text)
      if let incompleteSuffix = adjusted.incompleteSuffix {
        lineCompletion.append(incompleteSuffix)
      }
      quoted.completion = lineCompletion

      if quoted.isComplete {
        pendingQuotedScalar = nil
        try appendCompletedQuotedScalar(quoted)
      } else {
        pendingQuotedScalar = quoted
      }
      return true
    }

    if pendingFlow != nil {
      guard let contentStart, let contentEnd else {
        try pendingFlow?.feedEmptyLine(line: line, column: 1, into: &pendingTokens)
        return true
      }

      let region = buffer.region(from: contentStart, to: contentEnd)
      if let minimumContinuationIndent = pendingFlow?.minimumContinuationIndent,
        indent < minimumContinuationIndent,
        !isFlowCloseLine(region, opener: pendingFlow?.opener ?? .leftSquare)
      {
        throw YAML.ParseError.invalidIndentation(
          location: .init(line: line, column: indent + 1)
        )
      }
      try pendingFlow?.feedLine(
        region,
        lineEnded: lineEnded,
        line: line,
        column: indent + 1,
        into: &pendingTokens
      )
      if pendingFlow?.isComplete == true {
        try pendingFlow?.finish(into: &pendingTokens)
        pendingFlow = nil
        markDocumentContent()
      }
      return true
    }

    if pendingBlockScalar != nil {
      guard let contentStart, let contentEnd else {
        if lineHadComment {
          if let block = pendingBlockScalar,
            block.contentIndent == nil,
            (block.leadingBlankIndent ?? 0) > block.parentIndent
          {
            throw YAML.ParseError.invalidIndentation(
              location: .init(line: line, column: indent + 1)
            )
          }
          finishPendingBlockScalar()
          return true
        }
        if let block = pendingBlockScalar, let contentIndent = block.contentIndent, indent > contentIndent {
          pendingBlockScalar?.lines.append(PendingBlockScalarLine(
            region: nil,
            virtualPrefixSpaces: indent - contentIndent,
            indent: indent,
            generatedBytes: nil
          ))
        } else {
          if pendingBlockScalar?.contentIndent == nil, indent > 0 {
            let leadingBlankIndent = max(pendingBlockScalar?.leadingBlankIndent ?? 0, indent)
            pendingBlockScalar?.leadingBlankIndent = leadingBlankIndent
          }
          pendingBlockScalar?.lines.append(PendingBlockScalarLine(
            region: nil,
            virtualPrefixSpaces: 0,
            indent: indent,
            generatedBytes: nil
          ))
        }
        return true
      }

      let region = buffer.region(from: contentStart, to: contentEnd)
      if let block = pendingBlockScalar {
        if block.contentIndent == nil, indent <= block.parentIndent {
          finishPendingBlockScalar()
          return try processLine(
            line: line,
            indent: indent,
            contentStart: contentStart,
            contentEnd: contentEnd,
            lineHadComment: lineHadComment,
            hasLeadingIndentTab: hasLeadingIndentTab,
            quotedTrailingWhitespace: quotedTrailingWhitespace
          )
        }
        if indent == 0, isDocumentBoundary(region.trimmedHorizontalWhitespace()) {
          finishPendingBlockScalar()
          return try processLine(
            line: line,
            indent: indent,
            contentStart: contentStart,
            contentEnd: contentEnd,
            lineHadComment: lineHadComment,
            hasLeadingIndentTab: hasLeadingIndentTab,
            quotedTrailingWhitespace: quotedTrailingWhitespace
          )
        }
        let requiredIndent = block.contentIndent ?? indent
        if block.contentIndent == nil,
          let leadingBlankIndent = block.leadingBlankIndent,
          indent < leadingBlankIndent
        {
          throw YAML.ParseError.invalidIndentation(
            location: .init(line: line, column: indent + 1)
          )
        }
        if region.firstNonWhitespaceByte == .comment, indent < requiredIndent {
          finishPendingBlockScalar()
          return true
        }
        guard indent >= requiredIndent else {
          finishPendingBlockScalar()
          return try processLine(
            line: line,
            indent: indent,
            contentStart: contentStart,
            contentEnd: contentEnd,
            lineHadComment: lineHadComment,
            hasLeadingIndentTab: hasLeadingIndentTab,
            quotedTrailingWhitespace: quotedTrailingWhitespace
          )
        }
        if block.contentIndent == nil {
          pendingBlockScalar?.contentIndent = requiredIndent
        }
        pendingBlockScalar?.lines.append(PendingBlockScalarLine(
          region: region,
          virtualPrefixSpaces: Swift.max(0, indent - requiredIndent),
          indent: indent,
          generatedBytes: nil
        ))
        return true
      }
    }

    guard let contentStart, let contentEnd else {
      return true
    }

    guard let lineSlice = lineSlice(
      line: line,
      indent: indent,
      contentStart: contentStart,
      contentEnd: contentEnd,
      lineHadComment: lineHadComment,
      hasLeadingIndentTab: hasLeadingIndentTab,
      quotedTrailingWhitespace: quotedTrailingWhitespace
    ) else {
      return true
    }
    return try processRegionLine(lineSlice)
  }

  private mutating func processRegionLine(_ line: YAMLLineSlice) throws -> Bool {
    let trimmed = line.trimmedRegion
    let location = line.location
    let indentationErrorLocation = line.indentationErrorLocation

    if line.hasLeadingIndentTab, line.indent == 0, pendingBlockValue != nil,
      mappingSplit(in: trimmed) != nil
    {
      throw YAML.ParseError.invalidIndentation(location: indentationErrorLocation)
    }
    if line.hasLeadingIndentTab, pendingFlow == nil, pendingBlockScalar == nil,
      pendingQuotedScalar == nil, pendingPlainScalar == nil, pendingBlockValue == nil,
      !trimmed.startsFlowCollection
    {
      throw YAML.ParseError.invalidIndentation(location: indentationErrorLocation)
    }
    let pendingSequenceEntryIndent = pendingSequenceEntry?.indent
    preparePendingSequenceEntry(for: line.indent)
    let isSameIndentPendingSequenceValue =
      pendingBlockValue.map { line.indent == $0.indent && trimmed.isSequenceIndicator } ?? false
    let pendingBlockValueIndent = pendingBlockValue?.indent
    let consumesPendingExplicitValue = preparePendingBlockValue(for: line.indent, region: trimmed)
    let consumedPendingBlockValueIndent =
      pendingBlockValueIndent.map { line.indent > $0 && pendingBlockValue == nil ? $0 : nil } ?? nil

    if trimmed.isExactly("---") || startsDocumentStartWithNode(trimmed) {
      try closeAllBlocks()
      if documentOpen {
        appendEmptyDocumentContentIfNeeded()
        pendingTokens.append(.documentEnd(explicit: false))
      }
      tagHandles = pendingTagHandles
      pendingTagHandles = YAMLTokenizer.defaultTagHandles
      pendingDirectiveWithoutDocument = false
      pendingYAMLDirective = false
      allowDirectives = false
      pendingTokens.append(.documentStart(explicit: true))
      documentOpen = true
      documentHasContent = false
      let node = documentStartTrailingNode(in: trimmed)
      if !node.isEmpty {
        let startDecorated = try parseDecorators(in: node, location: location)
        if !startDecorated.tokens.isEmpty,
          !startDecorated.remainder.isEmpty,
          mappingSplit(in: startDecorated.remainder) != nil
        {
          throw YAML.ParseError.invalidSyntax("Invalid document start content", location: location)
        }
        try appendNodeRegion(
          node,
          location: location,
          originalRegion: node,
          parentIndent: node.isBlockScalarIndicator ? nil : line.indent,
          lineHadComment: line.lineHadComment,
          quotedTrailingWhitespace: line.quotedTrailingWhitespace
        )
      }
      return true
    }

    if startsDocumentEndWithNode(trimmed) {
      throw YAML.ParseError.invalidSyntax(
        "Unexpected content after document end marker",
        location: location
      )
    }

    if trimmed.isExactly("...") {
      try closeAllBlocks()
      if !documentOpen {
        if pendingDirectiveWithoutDocument {
          throw YAML.ParseError.invalidSyntax("Directive without document", location: location)
        }
        allowDirectives = true
        return true
      }
      appendEmptyDocumentContentIfNeeded()
      pendingTokens.append(.documentEnd(explicit: true))
      documentOpen = false
      allowDirectives = true
      return true
    }

    if trimmed.firstByte == UInt8(ascii: "%") {
      guard allowDirectives else {
        throw YAML.ParseError.invalidSyntax("Directive without document end marker", location: location)
      }
      let directive = try parseDirective(trimmed)
      try applyDirective(name: directive.name, value: directive.value, location: location)
      pendingDirectiveWithoutDocument = true
      pendingTokens.append(.directive(name: directive.name, value: directive.value))
      return true
    }

    let decorated = try parseDecorators(in: trimmed, location: location)
    if decorated.isAlias {
      beginDocumentIfNeeded()
      closeBlocks(for: line.indent, nextKind: nil)
      pendingBlockValue = nil
      markDocumentContent()
      for token in decorated.tokens {
        pendingTokens.append(token)
      }
      return true
    }
    if !decorated.tokens.isEmpty, decorated.remainder.isEmpty {
      if let current = blockStack.last, current.kind == .sequence, current.indent == line.indent {
        throw YAML.ParseError.invalidSyntax("Invalid anchor in block sequence", location: location)
      }
      beginDocumentIfNeeded()
      appendDecorators(decorated.tokens)
      return true
    }

    let active = decorated.remainder.isEmpty ? trimmed : decorated.remainder

    if pendingExplicitKey != nil {
      if active.isMappingValueIndicator {
        let explicitKey = pendingExplicitKey
        beginDocumentIfNeeded()
        closeBlocks(for: line.indent, nextKind: .mapping)
        pendingExplicitKey = nil
        appendDecorators(decorated.tokens)
        if explicitKey?.sawNode == false {
          appendPlainScalar("")
        }
        let remainder = active.droppingFirstByte()
        let value = remainder.trimmedHorizontalWhitespace()
        if invalidTabSeparatedNestedBlockValue(remainder: remainder, value: value) {
          throw YAML.ParseError.invalidSyntax("Invalid tab before nested block value", location: location)
        }
        if value.isEmpty {
          pendingBlockValue = PendingBlockValue(
            indent: line.indent,
            acceptsExplicitValueLine: false,
            closesNestedBlocksBeforeEmptyValue: true
          )
        } else {
          try appendNodeRegion(
            value,
            location: location,
            originalRegion: value,
            parentIndent: compactSequenceParentIndent(
              for: remainder,
              lineIndent: line.indent,
              defaultParentIndent: line.indent
            ),
            requiresMoreIndentForContinuation: true,
            lineHadComment: line.lineHadComment
          )
        }
        return true
      }

      beginDocumentIfNeeded()
      appendDecorators(decorated.tokens)
      if active.isSequenceIndicator {
        openBlockIfNeeded(kind: .sequence, indent: line.indent)
        let remainder = active.droppingFirstByte()
        let value = remainder.trimmedHorizontalWhitespace()
        if value.isEmpty {
          pendingSequenceEntry = PendingSequenceEntry(indent: line.indent)
        } else {
          try appendNodeRegion(
            value,
            location: location,
            originalRegion: value,
            parentIndent: compactSequenceParentIndent(
              for: remainder,
              lineIndent: line.indent,
              defaultParentIndent: line.indent
            ),
            requiresMoreIndentForContinuation: true,
            lineHadComment: line.lineHadComment
          )
        }
      } else {
        try appendNodeRegion(
          active,
          location: location,
          originalRegion: active,
          parentIndent: line.indent,
          requiresMoreIndentForContinuation: true,
          lineHadComment: line.lineHadComment
        )
      }
      pendingExplicitKey?.sawNode = true
      return true
    }

    if !decorated.tokens.isEmpty, active.isMappingValueIndicator {
      beginDocumentIfNeeded()
      closeBlocks(for: line.indent, nextKind: .mapping)
      openBlockIfNeeded(kind: .mapping, indent: line.indent)
      appendDecorators(decorated.tokens)
      if !decoratorsEndWithAlias(decorated.tokens) {
        appendPlainScalar("")
      }
      let remainder = active.droppingFirstByte()
      let value = remainder.trimmedHorizontalWhitespace()
      if invalidTabSeparatedNestedBlockValue(remainder: remainder, value: value) {
        throw YAML.ParseError.invalidSyntax("Invalid tab before block sequence indicator", location: location)
      }
      if value.isEmpty {
        pendingBlockValue = PendingBlockValue(
          indent: line.indent,
          acceptsExplicitValueLine: false,
          closesNestedBlocksBeforeEmptyValue: true
        )
      } else {
        try appendNodeRegion(
          value,
          location: location,
          originalRegion: value,
          parentIndent: compactSequenceParentIndent(
            for: remainder,
            lineIndent: line.indent,
            defaultParentIndent: line.indent
          ),
          requiresMoreIndentForContinuation: true,
          lineHadComment: line.lineHadComment
        )
      }
      return true
    }

    if active.isExplicitMappingIndicator {
      beginDocumentIfNeeded()
      closeBlocks(for: line.indent, nextKind: .mapping)
      openBlockIfNeeded(kind: .mapping, indent: line.indent)
      appendDecorators(decorated.tokens)
      let key = active.droppingFirstByte().trimmedHorizontalWhitespace()
      if active.droppingFirstByte().firstByte == .tab
        || (active.containsByte(.tab) && (key.isExactly("-") || key.isExactly("?")))
      {
        throw YAML.ParseError.invalidSyntax("Invalid tab after explicit mapping indicator", location: location)
      }
      let keyDecoratedOnly = (try? parseDecorators(in: key, location: location))
        .map { !$0.tokens.isEmpty && $0.remainder.isEmpty } ?? false
      if key.isEmpty {
        pendingExplicitKey = PendingExplicitKey(indent: line.indent, sawNode: false)
      } else {
        try appendNodeRegion(
          key,
          location: location,
          originalRegion: key,
          parentIndent: line.indent,
          requiresMoreIndentForContinuation: true,
          lineHadComment: line.lineHadComment
        )
        if keyDecoratedOnly {
          finishPendingBlockValue()
        }
      }
      pendingBlockValue = PendingBlockValue(
        indent: line.indent,
        acceptsExplicitValueLine: true,
        closesNestedBlocksBeforeEmptyValue: true
      )
      return true
    }

    if active.isMappingValueIndicator {
      beginDocumentIfNeeded()
      closeBlocks(for: line.indent, nextKind: .mapping)
      openBlockIfNeeded(kind: .mapping, indent: line.indent)
      appendDecorators(decorated.tokens)
      if !consumesPendingExplicitValue {
        appendPlainScalar("")
      }
      let remainder = active.droppingFirstByte()
      let value = remainder.trimmedHorizontalWhitespace()
      if invalidTabSeparatedNestedBlockValue(remainder: remainder, value: value) {
        throw YAML.ParseError.invalidSyntax("Invalid tab before nested block value", location: location)
      }
      if value.isEmpty {
        if consumesPendingExplicitValue {
          pendingBlockValue = PendingBlockValue(
            indent: line.indent,
            acceptsExplicitValueLine: false,
            closesNestedBlocksBeforeEmptyValue: true
          )
        } else {
          appendPlainScalar("")
        }
      } else {
        try appendNodeRegion(
          value,
          location: location,
          originalRegion: value,
          parentIndent: compactSequenceParentIndent(
            for: remainder,
            lineIndent: line.indent,
            defaultParentIndent: line.indent
          ),
          requiresMoreIndentForContinuation: true,
          lineHadComment: line.lineHadComment
        )
      }
      return true
    }

    if active.isSequenceIndicator {
      beginDocumentIfNeeded()
      if !decorated.tokens.isEmpty {
        throw YAML.ParseError.invalidSyntax("Invalid anchor on block sequence entry", location: location)
      }
      let allowsNestedSequenceIndent =
        consumedPendingBlockValueIndent != nil
        || pendingSequenceEntryIndent.map { line.indent > $0 } ?? false
      if let sequenceIndent = nearestOpenSequenceIndent(above: line.indent),
        line.indent > sequenceIndent,
        line.indent < sequenceIndent + 2,
        !allowsNestedSequenceIndent
      {
        throw YAML.ParseError.invalidIndentation(location: location)
      }
      if !isSameIndentPendingSequenceValue {
        closeBlocks(for: line.indent, nextKind: .sequence)
      }
      openBlockIfNeeded(kind: .sequence, indent: line.indent)
      appendDecorators(decorated.tokens)
      let remainder = active.droppingFirstByte()
      let value = remainder.trimmedHorizontalWhitespace()
      if active.containsByte(.tab), value.isExactly("-") {
        throw YAML.ParseError.invalidSyntax("Invalid tab before block sequence indicator", location: location)
      }
      if value.isEmpty {
        pendingSequenceEntry = PendingSequenceEntry(indent: line.indent)
      } else {
        try appendNodeRegion(
          value,
          location: location,
          originalRegion: value,
          parentIndent: compactSequenceParentIndent(
            for: remainder,
            lineIndent: line.indent,
            defaultParentIndent: line.indent
          ),
          requiresMoreIndentForContinuation: true,
          finishDecoratedEmptyBeforeSameIndentSequence: true,
          lineHadComment: line.lineHadComment
        )
      }
      return true
    }

    if let split = mappingSplit(in: active) {
      beginDocumentIfNeeded()
      closeBlocks(for: line.indent, nextKind: .mapping)
      openBlockIfNeeded(kind: .mapping, indent: line.indent)
      appendDecorators(decorated.tokens)
      try appendNodeRegion(
        split.key,
        location: location,
        originalRegion: split.key,
        parentIndent: line.indent,
        allowPlainContinuation: false,
        allowMappingParsing: false,
        lineHadComment: line.lineHadComment
      )
      let value = split.value
      if !value.isEmpty {
        if value.isSequenceIndicator {
          throw YAML.ParseError.invalidSyntax(
            "Block sequence cannot start on the same line as a mapping key",
            location: location
          )
        }
        try appendNodeRegion(
          value,
          location: location,
          originalRegion: value,
          parentIndent: line.indent,
          requiresMoreIndentForContinuation: true,
          allowSameLineNestedMapping: false,
          lineHadComment: line.lineHadComment
        )
      } else {
        pendingBlockValue = PendingBlockValue(
          indent: line.indent,
          acceptsExplicitValueLine: false,
          closesNestedBlocksBeforeEmptyValue: true
        )
      }
      return true
    }

    if active.startsFlowCollection {
      beginDocumentIfNeeded()
      closeBlocks(for: line.indent, nextKind: nil)
      appendDecorators(decorated.tokens)
      try appendNodeRegion(
        active,
        location: location,
        originalRegion: decorated.tokens.isEmpty ? active : active,
        parentIndent: line.indent,
        lineHadComment: line.lineHadComment,
        quotedTrailingWhitespace: line.quotedTrailingWhitespace
      )
      return true
    }

    beginDocumentIfNeeded()
    closeBlocks(for: line.indent, nextKind: nil)
    appendDecorators(decorated.tokens)
    try appendNodeRegion(
      active,
      location: location,
      originalRegion: decorated.tokens.isEmpty ? active : active,
      parentIndent: active.isBlockScalarIndicator
        ? consumedPendingBlockValueIndent
        : line.indent,
      lineHadComment: line.lineHadComment,
      quotedTrailingWhitespace: line.quotedTrailingWhitespace
    )
    return true
  }

  private mutating func beginDocumentIfNeeded() {
    if !documentOpen {
      tagHandles = pendingTagHandles
      pendingTagHandles = YAMLTokenizer.defaultTagHandles
      pendingDirectiveWithoutDocument = false
      pendingYAMLDirective = false
      allowDirectives = false
      pendingTokens.append(.documentStart(explicit: false))
      documentOpen = true
      documentHasContent = false
    }
  }

  private mutating func openBlockIfNeeded(kind: BlockKind, indent: Int) {
    if let current = blockStack.last, current.kind == kind, current.indent == indent {
      return
    }
    markDocumentContent()
    blockStack.append(BlockContext(kind: kind, indent: indent))
    switch kind {
    case .sequence:
      pendingTokens.append(.beginSequence(style: .block))
    case .mapping:
      pendingTokens.append(.beginMapping(style: .block))
    }
  }

  private mutating func closeBlocks(for indent: Int, nextKind: BlockKind?) {
    while let current = blockStack.last {
      if current.indent < indent {
        return
      }
      if current.indent == indent, let nextKind, current.kind == nextKind {
        return
      }
      appendEnd(for: current.kind)
      blockStack.removeLast()
    }
  }

  private func nearestOpenSequenceIndent(above indent: Int) -> Int? {
    for context in blockStack.reversed() where context.kind == .sequence && context.indent < indent {
      return context.indent
    }
    return nil
  }

  private mutating func closeAllBlocks() throws {
    try finishPendingFlow()
    try finishPendingQuotedScalar()
    finishPendingPlainScalar()
    finishPendingBlockScalar()
    finishPendingSequenceEntry()
    finishPendingBlockValue()
    while let current = blockStack.last {
      appendEnd(for: current.kind)
      blockStack.removeLast()
    }
  }

  private mutating func appendEnd(for kind: BlockKind) {
    switch kind {
    case .sequence:
      pendingTokens.append(.endSequence)
    case .mapping:
      pendingTokens.append(.endMapping)
    }
  }

  private mutating func markDocumentContent() {
    if documentOpen {
      documentHasContent = true
    }
  }

  private mutating func appendEmptyDocumentContentIfNeeded() {
    guard documentOpen, !documentHasContent else {
      return
    }
    appendPlainScalar("")
  }

  private mutating func appendPlainScalar(_ text: String) {
    markDocumentContent()
    let region = ParseBuffer.Region(data: Data(text.utf8))
    pendingTokens.append(.scalar(YAMLRawScalar(style: .plain, kind: .number, region: region)))
  }

  private mutating func appendPlainScalar(_ data: Data) {
    markDocumentContent()
    let region = ParseBuffer.Region(data: data)
    pendingTokens.append(.scalar(YAMLRawScalar(style: .plain, kind: .number, region: region)))
  }

  private mutating func appendPlainScalar(_ region: ParseBuffer.Region) {
    markDocumentContent()
    pendingTokens.append(.scalar(YAMLRawScalar(style: .plain, kind: .number, region: region)))
  }

  private mutating func appendStringScalar(_ text: String, style: YAMLScalarStyle) {
    markDocumentContent()
    let region = ParseBuffer.Region(data: Data(text.utf8))
    pendingTokens.append(.scalar(YAMLRawScalar(style: style, kind: .string, region: region)))
  }

  private mutating func appendStringScalar(_ data: Data, style: YAMLScalarStyle) {
    markDocumentContent()
    let region = ParseBuffer.Region(data: data)
    pendingTokens.append(.scalar(YAMLRawScalar(style: style, kind: .string, region: region)))
  }

  private mutating func preparePendingBlockValue(for indent: Int, region: ParseBuffer.Region) -> Bool {
    guard let pending = pendingBlockValue else {
      return false
    }

    let trimmed = region.trimmedHorizontalWhitespace()
    let isExplicitValueLine = trimmed.isMappingValueIndicator
    let isDecoratorOnlyLine = (try? parseDecorators(
      in: trimmed,
      location: .init(line: currentLine, column: indent + 1)
    )).map { !$0.tokens.isEmpty && $0.remainder.isEmpty } ?? false
    if indent > pending.indent {
      if isDecoratorOnlyLine {
        return false
      }
      if pending.acceptsExplicitValueLine {
        return false
      }
      pendingBlockValue = nil
      return false
    }
    if indent == pending.indent, trimmed.isSequenceIndicator {
      if pending.hasDecoratedEmptyScalar, pending.finishDecoratedEmptyBeforeSameIndentSequence {
        finishPendingBlockValue()
      } else {
        pendingBlockValue = nil
      }
      return false
    }
    if pending.acceptsExplicitValueLine, indent == pending.indent, isExplicitValueLine {
      if pending.hasDecoratedEmptyScalar {
        finishPendingBlockValue()
      } else {
        pendingBlockValue = nil
      }
      return true
    }
    if pending.hasDecoratedEmptyScalar, indent <= pending.indent {
      finishPendingBlockValue()
      return false
    }

    finishPendingBlockValue()
    return false
  }

  private mutating func preparePendingSequenceEntry(for indent: Int) {
    guard let pending = pendingSequenceEntry else {
      return
    }
    if indent > pending.indent {
      pendingSequenceEntry = nil
      return
    }
    finishPendingSequenceEntry()
  }

  private mutating func finishPendingSequenceEntry() {
    guard pendingSequenceEntry != nil else {
      return
    }
    pendingSequenceEntry = nil
    appendPlainScalar("")
  }

  private mutating func finishPendingBlockValue() {
    guard let pending = pendingBlockValue else {
      return
    }
    pendingBlockValue = nil
    if pending.closesNestedBlocksBeforeEmptyValue {
      closeBlocks(for: pending.indent, nextKind: .mapping)
    }
    appendPlainScalar("")
  }

  private mutating func finishPendingBlockScalar() {
    guard let block = pendingBlockScalar else {
      return
    }
    pendingBlockScalar = nil

    let data: Data
    switch block.style {
    case .literal(let chomp, _):
      data = joinLiteralLines(block.lines, chomp: chomp)
    case .folded(let chomp, _):
      data = joinFoldedLines(
        block.lines,
        baseIndent: block.contentIndent ?? (block.parentIndent + 1),
        chomp: chomp
      )
    default:
      data = joinPlainBlockLines(block.lines)
    }
    appendStringScalar(data, style: block.style)
  }

  private mutating func finishPendingFlow() throws {
    guard pendingFlow != nil else {
      return
    }
    try pendingFlow!.finish(into: &pendingTokens)
    pendingFlow = nil
    markDocumentContent()
  }

  private mutating func finishPendingQuotedScalar() throws {
    guard let quoted = pendingQuotedScalar else {
      return
    }
    pendingQuotedScalar = nil
    guard quoted.isComplete else {
      throw YAML.ParseError.incompleteInput(location: quoted.location)
    }
    try appendCompletedQuotedScalar(quoted)
  }

  private mutating func finishPendingPlainScalar() {
    guard let scalar = pendingPlainScalar else {
      return
    }
    pendingPlainScalar = nil

    if scalar.lines.count == 1, let originalRegion = scalar.originalRegion {
      markDocumentContent()
      pendingTokens.append(.scalar(YAMLRawScalar(style: .plain, kind: .number, region: originalRegion)))
      return
    }

    let folded = foldPlainLines(scalar.lines)
    appendPlainScalar(folded)
  }

  private mutating func appendNodeRegion(
    _ region: ParseBuffer.Region,
    location: YAML.ParseError.Location,
    originalRegion: ParseBuffer.Region? = nil,
    parentIndent: Int? = nil,
    allowPlainContinuation: Bool = true,
    allowMappingParsing: Bool = true,
    requiresMoreIndentForContinuation: Bool = false,
    allowSameLineNestedMapping: Bool = true,
    finishDecoratedEmptyBeforeSameIndentSequence: Bool = false,
    lineHadComment: Bool = false,
    quotedTrailingWhitespace: YAMLQuotedTrailingWhitespace = .empty
  ) throws {
    let trimmed = region.trimmedHorizontalWhitespace()
    guard !trimmed.isEmpty else {
      appendPlainScalar("")
      return
    }

    if trimmed.isSequenceIndicator {
      if !allowPlainContinuation, !requiresMoreIndentForContinuation {
        throw YAML.ParseError.invalidSyntax("Unexpected block sequence", location: location)
      }
      let nestedSequenceIndent =
        requiresMoreIndentForContinuation ? parentIndent.map { $0 + 2 } : nil
      if requiresMoreIndentForContinuation, let parentIndent {
        openBlockIfNeeded(kind: .sequence, indent: parentIndent + 2)
      } else {
        markDocumentContent()
        pendingTokens.append(.beginSequence(style: .block))
      }
      let remainder = trimmed.droppingFirstByte()
      let value = remainder.trimmedHorizontalWhitespace()
      if trimmed.containsByte(.tab), value.isExactly("-") {
        throw YAML.ParseError.invalidSyntax("Invalid tab before block sequence indicator", location: location)
      }
      if value.isEmpty {
        appendPlainScalar("")
      } else {
        try appendNodeRegion(
          value,
          location: location,
          originalRegion: value,
          parentIndent: nestedSequenceIndent ?? parentIndent,
          requiresMoreIndentForContinuation: requiresMoreIndentForContinuation,
          lineHadComment: lineHadComment
        )
      }
      if !requiresMoreIndentForContinuation || parentIndent == nil {
        pendingTokens.append(.endSequence)
      }
      return
    }

    if allowMappingParsing,
      (trimmed.firstByte == .singleQuote || trimmed.firstByte == .doubleQuote),
      let split = mappingSplit(in: trimmed)
    {
      try appendBlockMapping(
        trimmed,
        split: split,
        location: location,
        parentIndent: parentIndent,
        allowPlainContinuation: allowPlainContinuation,
        requiresMoreIndentForContinuation: requiresMoreIndentForContinuation,
        allowSameLineNestedMapping: allowSameLineNestedMapping,
        lineHadComment: lineHadComment
      )
      return
    }

    if trimmed.firstByte == .singleQuote {
      let rawText = try trimmed.string()
      var completion = quotedScalarCompletionState(forOpeningText: rawText, style: .singleQuoted)
      let adjusted = try appendQuotedTrailingWhitespace(
        quotedTrailingWhitespace,
        to: rawText,
        style: .singleQuoted,
        scalarIsComplete: completion.isComplete
      )
      if let incompleteSuffix = adjusted.incompleteSuffix {
        completion.append(incompleteSuffix)
      }
      let text = adjusted.text
      if completion.isComplete {
        appendStringScalar(try parseSingleQuoted(text, location: location), style: .singleQuoted)
      } else {
        pendingQuotedScalar = PendingQuotedScalar(
          text: text,
          style: .singleQuoted,
          location: locationAtEnd(of: text, from: location),
          minimumContinuationIndent: continuationIndent(
            parentIndent: parentIndent,
            location: location,
            requiresMoreIndent: requiresMoreIndentForContinuation
          ),
          completion: completion
        )
      }
      return
    }

    if trimmed.firstByte == .doubleQuote {
      let rawText = try trimmed.string()
      var completion = quotedScalarCompletionState(forOpeningText: rawText, style: .doubleQuoted)
      let adjusted = try appendQuotedTrailingWhitespace(
        quotedTrailingWhitespace,
        to: rawText,
        style: .doubleQuoted,
        scalarIsComplete: completion.isComplete
      )
      if let incompleteSuffix = adjusted.incompleteSuffix {
        completion.append(incompleteSuffix)
      }
      let text = adjusted.text
      if completion.isComplete {
        appendStringScalar(try parseDoubleQuoted(text, location: location), style: .doubleQuoted)
      } else {
        pendingQuotedScalar = PendingQuotedScalar(
          text: text,
          style: .doubleQuoted,
          location: locationAtEnd(of: text, from: location),
          minimumContinuationIndent: continuationIndent(
            parentIndent: parentIndent,
            location: location,
            requiresMoreIndent: requiresMoreIndentForContinuation
          ),
          completion: completion
        )
      }
      return
    }

    if let header = try parseBlockScalarHeader(trimmed, location: location) {
      let parent = parentIndent ?? -1
      let explicitIndentBase = parentIndent ?? 0
      let contentIndent = header.indent.map { explicitIndentBase + $0 }
      pendingBlockScalar = PendingBlockScalar(
        style: header.style,
        parentIndent: parent,
        contentIndent: contentIndent
      )
      return
    }

    if trimmed.isExplicitMappingIndicator {
      if !allowPlainContinuation, !requiresMoreIndentForContinuation {
        throw YAML.ParseError.invalidSyntax("Unexpected explicit mapping in scalar", location: location)
      }
      let mappingIndent =
        requiresMoreIndentForContinuation ? parentIndent.map { $0 + 2 } : parentIndent
      if let mappingIndent {
        openBlockIfNeeded(kind: .mapping, indent: mappingIndent)
      } else {
        markDocumentContent()
        pendingTokens.append(.beginMapping(style: .block))
      }
      let key = trimmed.droppingFirstByte().trimmedHorizontalWhitespace()
      if trimmed.droppingFirstByte().firstByte == .tab
        || (trimmed.containsByte(.tab) && (key.isSequenceIndicator || key.isExplicitMappingIndicator))
      {
        throw YAML.ParseError.invalidSyntax("Invalid tab after explicit mapping indicator", location: location)
      }
      let keyDecoratedOnly = (try? parseDecorators(in: key, location: location))
        .map { !$0.tokens.isEmpty && $0.remainder.isEmpty } ?? false
      if key.isEmpty {
        appendPlainScalar("")
      } else {
        try appendNodeRegion(
          key,
          location: location,
          originalRegion: key,
          parentIndent: mappingIndent ?? parentIndent,
          lineHadComment: lineHadComment
        )
        if keyDecoratedOnly {
          finishPendingBlockValue()
        }
      }
      pendingBlockValue = PendingBlockValue(
        indent: mappingIndent ?? parentIndent ?? location.column - 1,
        acceptsExplicitValueLine: true,
        closesNestedBlocksBeforeEmptyValue: true
      )
      if mappingIndent == nil {
        pendingTokens.append(.endMapping)
      }
      return
    }

    let decorated = try parseDecorators(in: trimmed, location: location)
    if !decorated.tokens.isEmpty {
      if decorated.remainder.firstByte == .comma {
        throw YAML.ParseError.invalidSyntax("Unexpected comma after tag", location: location)
      }
      if decorated.remainder.isMappingValueIndicator {
        markDocumentContent()
        pendingTokens.append(.beginMapping(style: .block))
        appendDecorators(decorated.tokens)
        if !decoratorsEndWithAlias(decorated.tokens) {
          appendPlainScalar("")
        }
        let value = decorated.remainder.droppingFirstByte().trimmedHorizontalWhitespace()
        if value.isEmpty {
          pendingBlockValue = PendingBlockValue(
            indent: parentIndent ?? location.column - 1,
            acceptsExplicitValueLine: false,
            closesNestedBlocksBeforeEmptyValue: true
          )
        } else {
          let decoratedValue = try parseDecorators(in: value, location: location)
          if !decoratedValue.tokens.isEmpty, decoratedValue.remainder.isEmpty {
            appendDecorators(decoratedValue.tokens)
            appendPlainScalar("")
          } else {
            try appendNodeRegion(
              value,
              location: location,
              originalRegion: value,
              parentIndent: parentIndent,
              allowPlainContinuation: false,
              lineHadComment: lineHadComment
            )
          }
        }
        pendingTokens.append(.endMapping)
        return
      }
      appendDecorators(decorated.tokens)
      if decorated.isAlias {
        markDocumentContent()
        return
      }
      if decorated.remainder.isEmpty {
        if requiresMoreIndentForContinuation, let parentIndent {
          pendingBlockValue = PendingBlockValue(
            indent: parentIndent,
            acceptsExplicitValueLine: false,
            hasDecoratedEmptyScalar: true,
            finishDecoratedEmptyBeforeSameIndentSequence:
              finishDecoratedEmptyBeforeSameIndentSequence
          )
        }
        return
      }
      try appendNodeRegion(
        decorated.remainder,
        location: location,
        originalRegion: decorated.remainder,
        parentIndent: parentIndent,
        allowPlainContinuation: allowPlainContinuation,
        allowMappingParsing: allowMappingParsing,
        requiresMoreIndentForContinuation: requiresMoreIndentForContinuation,
        allowSameLineNestedMapping: allowSameLineNestedMapping,
        lineHadComment: lineHadComment
      )
      return
    }

    if allowMappingParsing, let split = mappingSplit(in: trimmed) {
      try appendBlockMapping(
        trimmed,
        split: split,
        location: location,
        parentIndent: parentIndent,
        allowPlainContinuation: allowPlainContinuation,
        requiresMoreIndentForContinuation: requiresMoreIndentForContinuation,
        allowSameLineNestedMapping: allowSameLineNestedMapping,
        lineHadComment: lineHadComment
      )
      return
    }

    if trimmed.startsFlowCollection {
      if let originalRegion, originalRegion.count == trimmed.count {
        try appendFlowTokens(
          originalRegion,
          location: location,
          minimumContinuationIndent: continuationIndent(
            parentIndent: parentIndent,
            location: location,
            requiresMoreIndent: requiresMoreIndentForContinuation
          )
        )
      } else {
        try appendFlowTokens(
          trimmed,
          location: location,
          minimumContinuationIndent: continuationIndent(
            parentIndent: parentIndent,
            location: location,
            requiresMoreIndent: requiresMoreIndentForContinuation
          )
        )
      }
      return
    }

    if allowPlainContinuation, !lineHadComment {
      let initialIndent = parentIndent ?? location.column - 1
      let minIndent = requiresMoreIndentForContinuation ? initialIndent + 1 : initialIndent
      startPendingPlainScalar(
        region: trimmed,
        indent: initialIndent,
        minIndent: minIndent,
        location: location
      )
    } else if let originalRegion, originalRegion.count == trimmed.count {
      appendPlainScalar(originalRegion)
    } else {
      appendPlainScalar(trimmed)
    }
  }

  private mutating func appendBlockMapping(
    _ trimmed: ParseBuffer.Region,
    split: YAMLRegionMappingSplit,
    location: YAML.ParseError.Location,
    parentIndent: Int?,
    allowPlainContinuation: Bool,
    requiresMoreIndentForContinuation: Bool,
    allowSameLineNestedMapping: Bool,
    lineHadComment: Bool
  ) throws {
    if !allowPlainContinuation, !requiresMoreIndentForContinuation {
      throw YAML.ParseError.invalidSyntax("Unexpected mapping in scalar", location: location)
    }
    if requiresMoreIndentForContinuation, !allowSameLineNestedMapping {
      throw YAML.ParseError.invalidSyntax("Unexpected mapping in scalar", location: location)
    }
    let nestedMappingIndent =
      requiresMoreIndentForContinuation ? parentIndent.map { $0 + 2 } : parentIndent
    if requiresMoreIndentForContinuation, let nestedMappingIndent {
      openBlockIfNeeded(kind: .mapping, indent: nestedMappingIndent)
    } else {
      markDocumentContent()
      pendingTokens.append(.beginMapping(style: .block))
    }
    try appendNodeRegion(
      split.key,
      location: location,
      originalRegion: split.key,
      parentIndent: parentIndent,
      allowPlainContinuation: false,
      allowMappingParsing: false,
      lineHadComment: lineHadComment
    )
    let value = split.value
    if value.isEmpty {
      if requiresMoreIndentForContinuation, let nestedMappingIndent {
        pendingBlockValue = PendingBlockValue(
          indent: nestedMappingIndent,
          acceptsExplicitValueLine: false,
          closesNestedBlocksBeforeEmptyValue: true
        )
      } else {
        appendPlainScalar("")
      }
    } else if value.isSequenceIndicator {
      throw YAML.ParseError.invalidSyntax(
        "Block sequence cannot start on the same line as a mapping key",
        location: location
      )
    } else {
      let decoratedValue = try parseDecorators(in: value, location: location)
      if !decoratedValue.tokens.isEmpty, decoratedValue.remainder.isEmpty {
        appendDecorators(decoratedValue.tokens)
        appendPlainScalar("")
      } else {
        try appendNodeRegion(
          value,
          location: location,
          originalRegion: value,
          parentIndent: nestedMappingIndent ?? parentIndent,
          allowPlainContinuation: false,
          allowSameLineNestedMapping: false,
          lineHadComment: lineHadComment
        )
      }
    }
    if !requiresMoreIndentForContinuation || parentIndent == nil {
      pendingTokens.append(.endMapping)
    }
  }

  private mutating func startPendingPlainScalar(
    region: ParseBuffer.Region,
    indent: Int,
    minIndent: Int,
    location: YAML.ParseError.Location
  ) {
    var pending = PendingPlainScalar(
      initialIndent: indent,
      minIndent: minIndent,
      location: location,
      originalRegion: region
    )
    pending.lines.append(PendingPlainScalarLine(
      region: region.trimmedTrailingHorizontalWhitespace(),
      bytes: Data(),
      indent: indent
    ))
    pendingPlainScalar = pending
  }

  private func shouldContinuePendingPlainScalar(indent: Int, region: ParseBuffer.Region) -> Bool {
    guard let pending = pendingPlainScalar else {
      return false
    }
    let trimmed = region.trimmedHorizontalWhitespace()
    if trimmed.isEmpty {
      return true
    }
    if indent < pending.minIndent {
      return false
    }
    if isDocumentBoundary(trimmed) {
      return false
    }
    if indent == pending.initialIndent {
      if trimmed.isSequenceIndicator || trimmed.isExplicitMappingIndicator || mappingSplit(in: trimmed) != nil {
        return false
      }
    }
    return true
  }

  private mutating func appendDecorators(_ tokens: ContiguousArray<YAMLRawToken>) {
    for token in tokens {
      pendingTokens.append(token)
    }
  }

  private func decoratorsEndWithAlias(_ tokens: ContiguousArray<YAMLRawToken>) -> Bool {
    guard let last = tokens.last else {
      return false
    }
    if case .alias = last {
      return true
    }
    return false
  }

  private func continuationIndent(
    parentIndent: Int?,
    location: YAML.ParseError.Location,
    requiresMoreIndent: Bool
  ) -> Int? {
    guard requiresMoreIndent else {
      return nil
    }
    return (parentIndent ?? (location.column - 1)) + 1
  }

  private func invalidTabSeparatedNestedBlockValue(
    remainder: ParseBuffer.Region,
    value: ParseBuffer.Region
  ) -> Bool {
    var sawTabInSeparation = false
    remainder.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var index = 0
      while index < bytes.count {
        let byte = bytes[index]
        guard byte == .space || byte == .tab else {
          break
        }
        if byte == .tab {
          sawTabInSeparation = true
        }
        index += 1
      }
    }
    guard sawTabInSeparation else {
      return false
    }
    return value.isExactly("-") || value.isExactly("?") || mappingSplit(in: value) != nil
  }

  private func compactSequenceParentIndent(
    for remainder: ParseBuffer.Region,
    lineIndent: Int,
    defaultParentIndent: Int
  ) -> Int {
    var separatorWidth = 0
    var startsNestedSequence = false
    remainder.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var index = 0
      while index < bytes.count {
        let byte = bytes[index]
        guard byte == .space || byte == .tab else {
          break
        }
        separatorWidth += 1
        index += 1
      }
      startsNestedSequence = index < bytes.count && bytes[index] == .dash
    }
    guard startsNestedSequence else {
      return defaultParentIndent
    }
    return max(defaultParentIndent, lineIndent + separatorWidth - 1)
  }

  private func mappingSplit(in region: ParseBuffer.Region) -> YAMLRegionMappingSplit? {
    region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var index = 0
      var inSingleQuote = false
      var inDoubleQuote = false
      var escaped = false
      var flowStack: ContiguousArray<UInt8> = []
      var atNodeStart = true

      while index < bytes.count {
        let byte = bytes[index]

        if inSingleQuote {
          if byte == .singleQuote {
            let next = index + 1
            if next < bytes.count, bytes[next] == .singleQuote {
              index += 2
              continue
            }
            inSingleQuote = false
          }
          index += 1
          continue
        }

        if inDoubleQuote {
          if escaped {
            escaped = false
          } else if byte == .backslash {
            escaped = true
          } else if byte == .doubleQuote {
            inDoubleQuote = false
          }
          index += 1
          continue
        }

        if byte == .singleQuote, atNodeStart {
          inSingleQuote = true
        } else if byte == .doubleQuote, atNodeStart {
          inDoubleQuote = true
        } else if byte == .leftSquare, atNodeStart || !flowStack.isEmpty {
          flowStack.append(.rightSquare)
        } else if byte == .leftBrace, atNodeStart || !flowStack.isEmpty {
          flowStack.append(.rightBrace)
        } else if let expectedClose = flowStack.last, byte == expectedClose {
          flowStack.removeLast()
        } else if byte == .colon {
          let next = index + 1
          if flowStack.isEmpty, next == bytes.count || bytes[next].isYAMLWhitespace {
            return YAMLRegionMappingSplit(
              key: region.subregion(0..<index),
              value: region.subregion(next..<bytes.count).trimmedHorizontalWhitespace()
            )
          }
        }

        if !byte.isYAMLWhitespace {
          atNodeStart = false
        }
        index += 1
      }
      return nil
    }
  }

  private func isDocumentBoundary(_ region: ParseBuffer.Region) -> Bool {
    region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.count >= 3 else {
        return false
      }
      if bytes[0] == .dash, bytes[1] == .dash, bytes[2] == .dash {
        return bytes.count == 3 || bytes[3].isYAMLHorizontalWhitespace
      }
      if bytes[0] == UInt8(ascii: "."), bytes[1] == UInt8(ascii: "."), bytes[2] == UInt8(ascii: ".") {
        return bytes.count == 3 || bytes[3].isYAMLHorizontalWhitespace
      }
      return false
    }
  }

  private func isDocumentBoundaryAfterQuotedTrailingWhitespace(
    region: ParseBuffer.Region,
    quotedTrailingWhitespace: YAMLQuotedTrailingWhitespace
  ) -> Bool {
    if quotedTrailingWhitespace.isEmpty {
      return isDocumentBoundary(region.trimmedHorizontalWhitespace())
    }

    return region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var end = bytes.count
      while end > 0, bytes[end - 1].isYAMLHorizontalWhitespace {
        end -= 1
      }
      if end == 3,
        bytes[0] == .dash,
        bytes[1] == .dash,
        bytes[2] == .dash
      {
        return true
      }
      if end == 3,
        bytes[0] == UInt8(ascii: "."),
        bytes[1] == UInt8(ascii: "."),
        bytes[2] == UInt8(ascii: ".")
      {
        return true
      }
      if end > 3,
        bytes[0] == .dash,
        bytes[1] == .dash,
        bytes[2] == .dash,
        bytes[3].isYAMLWhitespace
      {
        return true
      }
      if end > 3,
        bytes[0] == UInt8(ascii: "."),
        bytes[1] == UInt8(ascii: "."),
        bytes[2] == UInt8(ascii: "."),
        bytes[3].isYAMLWhitespace
      {
        return true
      }
      return false
    }
  }

  private func startsDocumentStartWithNode(_ region: ParseBuffer.Region) -> Bool {
    region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.count > 3 else {
        return false
      }
      return bytes[0] == .dash && bytes[1] == .dash && bytes[2] == .dash && bytes[3].isYAMLWhitespace
    }
  }

  private func startsDocumentEndWithNode(_ region: ParseBuffer.Region) -> Bool {
    region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.count > 3 else {
        return false
      }
      return bytes[0] == UInt8(ascii: ".")
        && bytes[1] == UInt8(ascii: ".")
        && bytes[2] == UInt8(ascii: ".")
        && bytes[3].isYAMLWhitespace
    }
  }

  private func documentStartTrailingNode(in region: ParseBuffer.Region) -> ParseBuffer.Region {
    guard region.count > 3 else {
      return region.subregion(0..<0)
    }
    return region.subregion(3..<region.count).trimmedHorizontalWhitespace()
  }

  private func quotedScalarCompletionState(
    forOpeningText text: String,
    style: YAMLScalarStyle
  ) -> QuotedScalarCompletionState {
    var completion = QuotedScalarCompletionState(style: style)
    completion.appendOpeningText(text)
    return completion
  }

  private func appendQuotedTrailingWhitespace(
    _ trailingWhitespace: YAMLQuotedTrailingWhitespace,
    to text: String,
    style: YAMLScalarStyle,
    scalarIsComplete: Bool
  ) throws -> (text: String, incompleteSuffix: String?) {
    guard !trailingWhitespace.isEmpty else {
      return (text, nil)
    }
    let suffix = try trailingWhitespace.string()
    guard case .doubleQuoted = style else {
      return (text + suffix, nil)
    }
    if scalarIsComplete {
      return (text + suffix, nil)
    }
    guard text.hasSuffix("\\"), trailingWhitespace.firstByte == .tab else {
      return (text, nil)
    }
    let incompleteSuffix = "t" + (try trailingWhitespace.stringDroppingFirstByte())
    return (text + incompleteSuffix, incompleteSuffix)
  }

  private func foldPlainLines<Lines: Collection>(_ lines: Lines) -> Data
  where Lines.Element == PendingPlainScalarLine {
    var result = Data()
    var first = true
    var previousEmpty = false

    for entry in lines {
      let lineIsEmpty = entry.isEmpty
      if first {
        entry.appendBytes(to: &result)
        first = false
        previousEmpty = lineIsEmpty
        continue
      }

      if lineIsEmpty {
        result.append(.newline)
        previousEmpty = true
        continue
      }

      if previousEmpty {
        if result.last != .newline {
          result.append(.newline)
        }
      } else {
        result.append(.space)
      }
      entry.appendBytes(to: &result)
      previousEmpty = false
    }

    while result.last == .newline {
      result.removeLast()
    }
    return result
  }

  private func parseDirective(_ region: ParseBuffer.Region) throws -> YAMLDirectiveParts {
    try region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.first == UInt8(ascii: "%") else {
        return YAMLDirectiveParts(name: try region.string(), value: nil)
      }
      var scanner = YAMLByteScanner(bytes)
      _ = scanner.readByte()
      while let byte = scanner.current, !byte.isYAMLWhitespace {
        scanner.advance()
      }
      let split = scanner.position
      let name = try region.subregion(1..<split).string()
      let valueRegion = region.subregion(split..<bytes.count).trimmedHorizontalWhitespace()
      let value = valueRegion.isEmpty ? nil : try valueRegion.string()
      return YAMLDirectiveParts(name: name, value: value)
    }
  }

  private func parseDecorators(
    in region: ParseBuffer.Region,
    location: YAML.ParseError.Location
  ) throws -> YAMLRegionDecorators {
    var tokens: ContiguousArray<YAMLRawToken> = []
    var remainder = region.trimmedHorizontalWhitespace()

    while true {
      guard let first = remainder.firstByte else {
        return YAMLRegionDecorators(tokens: tokens, remainder: remainder, isAlias: false)
      }
      if first == .exclamation {
        let (token, rest) = try parseDecoratorToken(remainder, location: location)
        tokens.append(.tag(try resolveTagToken(token, location: location)))
        remainder = rest.trimmedHorizontalWhitespace()
        continue
      }
      if first == .ampersand {
        let (token, rest) = try parseDecoratorToken(remainder, location: location)
        tokens.append(.anchor(String(token.dropFirst())))
        remainder = rest.trimmedHorizontalWhitespace()
        continue
      }
      if first == .asterisk {
        let (token, rest) = try parseDecoratorToken(remainder, location: location)
        tokens.append(.alias(String(token.dropFirst())))
        let trailing = rest.trimmedHorizontalWhitespace()
        if !trailing.isEmpty {
          return YAMLRegionDecorators(tokens: tokens, remainder: trailing, isAlias: false)
        }
        return YAMLRegionDecorators(tokens: tokens, remainder: trailing, isAlias: true)
      }
      return YAMLRegionDecorators(tokens: tokens, remainder: remainder, isAlias: false)
    }
  }

  private func parseDecoratorToken(
    _ region: ParseBuffer.Region,
    location: YAML.ParseError.Location
  ) throws -> (token: String, rest: ParseBuffer.Region) {
    try region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard let first = bytes.first else {
        throw YAML.ParseError.invalidSyntax("Expected decorator", location: location)
      }
      var end = 1
      if first == .exclamation, end < bytes.count, bytes[end] == .leftAngle {
        var close: Int?
        var scan = end + 1
        while scan < bytes.count {
          if bytes[scan] == .rightAngle {
            close = scan
            break
          }
          scan += 1
        }
        guard let close else {
          throw YAML.ParseError.invalidSyntax(
            "Invalid tag",
            location: YAML.ParseError.Location(line: location.line, column: location.column + bytes.count)
          )
        }
        end = close + 1
        return (
          try region.subregion(0..<end).string(),
          region.subregion(end..<bytes.count)
        )
      }
      while end < bytes.count, !bytes[end].isYAMLWhitespace {
        let byte = bytes[end]
        if byte == .leftSquare || byte == .rightSquare || byte == .leftBrace || byte == .rightBrace || byte == .comma {
          break
        }
        end += 1
      }
      guard end > 1 || first == .exclamation else {
        throw YAML.ParseError.invalidSyntax("Invalid decorator", location: location)
      }
      return (
        try region.subregion(0..<end).string(),
        region.subregion(end..<bytes.count)
      )
    }
  }

  private func locationAtEnd(
    of text: some StringProtocol,
    from location: YAML.ParseError.Location
  ) -> YAML.ParseError.Location {
    YAML.ParseError.Location(line: location.line, column: location.column + text.count)
  }

  private func normalizeTagToken(_ token: String) -> String {
    if token.hasPrefix("!<"), token.hasSuffix(">") {
      return String(token.dropFirst(2).dropLast())
    }
    return token
  }

  private func isValidYAMLDirectiveVersion(_ value: String) -> Bool {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      return false
    }
    return parts.allSatisfy { part in
      !part.isEmpty && part.allSatisfy(\.isWholeNumber)
    }
  }

  private mutating func applyDirective(
    name: String,
    value: String?,
    location: YAML.ParseError.Location
  ) throws {
    if name == "YAML" {
      guard let value else {
        throw YAML.ParseError.invalidSyntax("Invalid %YAML directive", location: location)
      }
      let parts = value.split(whereSeparator: { $0.isWhitespace })
      guard parts.count == 1, !pendingYAMLDirective else {
        throw YAML.ParseError.invalidSyntax("Invalid %YAML directive", location: location)
      }
      guard isValidYAMLDirectiveVersion(String(parts[0])) else {
        throw YAML.ParseError.invalidSyntax("Invalid %YAML directive", location: location)
      }
      pendingYAMLDirective = true
      return
    }
    guard name == "TAG" else {
      return
    }
    guard let value else {
      throw YAML.ParseError.invalidSyntax("Invalid %TAG directive", location: location)
    }
    let parts = value.split(whereSeparator: { $0.isWhitespace })
    guard parts.count == 2 else {
      throw YAML.ParseError.invalidSyntax("Invalid %TAG directive", location: location)
    }
    let handle = String(parts[0])
    let prefix = String(parts[1])
    if handle != "!", (!handle.hasPrefix("!") || !handle.hasSuffix("!") || handle.count < 2) {
      throw YAML.ParseError.invalidSyntax("Invalid %TAG directive", location: location)
    }
    guard !prefix.isEmpty else {
      throw YAML.ParseError.invalidSyntax("Invalid %TAG directive", location: location)
    }
    pendingTagHandles[handle] = prefix
  }

  private func resolveTagToken(
    _ token: String,
    location: YAML.ParseError.Location
  ) throws -> String {
    let normalized = normalizeTagToken(token)
    if normalized != token {
      return normalized
    }
    if token == "!" {
      return token
    }
    if token.hasPrefix("!!") {
      let suffix = try decodeTagSuffix(String(token.dropFirst(2)), location: location)
      let prefix = tagHandles["!!"] ?? "tag:yaml.org,2002:"
      return suffix.isEmpty ? prefix : "\(prefix)\(suffix)"
    }
    guard token.hasPrefix("!") else {
      return token
    }
    let afterBang = token.index(after: token.startIndex)
    if let handleEnd = token[afterBang...].firstIndex(of: "!") {
      let handle = String(token[..<token.index(after: handleEnd)])
      let suffix = try decodeTagSuffix(String(token[token.index(after: handleEnd)...]), location: location)
      guard let prefix = tagHandles[handle] else {
        throw YAML.ParseError.invalidSyntax("Unknown tag handle", location: location)
      }
      return "\(prefix)\(suffix)"
    }
    let suffix = try decodeTagSuffix(String(token.dropFirst()), location: location)
    guard let prefix = tagHandles["!"] else {
      throw YAML.ParseError.invalidSyntax("Unknown tag handle", location: location)
    }
    if suffix.isEmpty {
      return "!"
    }
    return prefix == "!" ? "!\(suffix)" : "\(prefix)\(suffix)"
  }

  private func decodeTagSuffix(
    _ text: String,
    location: YAML.ParseError.Location
  ) throws -> String {
    try decodeYAMLTagSuffix(text, location: location)
  }

  private func parseSingleQuoted(_ text: String, location: YAML.ParseError.Location) throws -> String {
    guard text.first == "'" else { return text }
    var result = ""
    var index = text.index(after: text.startIndex)
    while index < text.endIndex {
      let ch = text[index]
      if ch == "'" {
        let next = text.index(after: index)
        if next < text.endIndex, text[next] == "'" {
          result.append("'")
          index = text.index(after: next)
          continue
        }
        if !validTrailingQuotedScalarContent(text[next...]) {
          throw YAML.ParseError.invalidSyntax("Unexpected content after quoted scalar", location: location)
        }
        return result
      }
      if ch.isNewline {
        while let last = result.last, last == " " {
          result.removeLast()
        }
        index = text.index(after: index)
        var breakCount = 0
        while index < text.endIndex {
          let next = text[index]
          if next.isNewline {
            breakCount += 1
            index = text.index(after: index)
            continue
          }
          if next == " " || next == "\t" {
            index = text.index(after: index)
            continue
          }
          break
        }
        if breakCount == 0 {
          result.append(" ")
        } else {
          trimTrailingTabs(from: &result)
          result.append(String(repeating: "\n", count: breakCount))
        }
        continue
      }
      result.append(ch)
      index = text.index(after: index)
    }
    throw YAML.ParseError.incompleteInput(location: location)
  }

  private func parseDoubleQuoted(_ text: String, location: YAML.ParseError.Location) throws -> String {
    guard text.first == "\"" else { return text }
    var result = ""
    var index = text.index(after: text.startIndex)
    while index < text.endIndex {
      let ch = text[index]
      if ch == "\"" {
        let next = text.index(after: index)
        if !validTrailingQuotedScalarContent(text[next...]) {
          throw YAML.ParseError.invalidSyntax("Unexpected content after quoted scalar", location: location)
        }
        return result
      }
      if ch.isNewline {
        while let last = result.last, last == " " {
          result.removeLast()
        }
        index = text.index(after: index)
        var breakCount = 0
        while index < text.endIndex {
          let next = text[index]
          if next.isNewline {
            breakCount += 1
            index = text.index(after: index)
            continue
          }
          if next == " " || next == "\t" {
            index = text.index(after: index)
            continue
          }
          break
        }
        if breakCount == 0 {
          result.append(" ")
        } else {
          trimTrailingTabs(from: &result)
          result.append(String(repeating: "\n", count: breakCount))
        }
        continue
      }
      if ch == "\\" {
        index = text.index(after: index)
        guard index < text.endIndex else {
          throw YAML.ParseError.incompleteInput(location: location)
        }
        if text[index].isNewline {
          index = text.index(after: index)
          while index < text.endIndex, text[index] == " " || text[index] == "\t" {
            index = text.index(after: index)
          }
          continue
        }
        let escaped = text[index]
        switch escaped {
        case "0": result.append("\u{0}")
        case "a": result.append("\u{7}")
        case "b": result.append("\u{8}")
        case "t", "\t": result.append("\t")
        case "n": result.append("\n")
        case "v": result.append("\u{B}")
        case "f": result.append("\u{C}")
        case "r": result.append("\r")
        case "e": result.append("\u{1B}")
        case " ": result.append(" ")
        case "\"": result.append("\"")
        case "/": result.append("/")
        case "\\": result.append("\\")
        case "x", "u", "U":
          let count = escaped == "x" ? 2 : (escaped == "u" ? 4 : 8)
          let start = text.index(after: index)
          guard let end = text.index(start, offsetBy: count, limitedBy: text.endIndex) else {
            throw YAML.ParseError.incompleteInput(location: location)
          }
          let hex = String(text[start..<end])
          guard let scalar = UInt32(hex, radix: 16), let unicode = UnicodeScalar(scalar) else {
            throw YAML.ParseError.invalidSyntax("Invalid unicode escape", location: location)
          }
          result.unicodeScalars.append(unicode)
          index = text.index(before: end)
        default:
          throw YAML.ParseError.invalidSyntax("Invalid escape", location: location)
        }
      } else {
        result.append(ch)
      }
      index = text.index(after: index)
    }
    throw YAML.ParseError.incompleteInput(location: location)
  }

  private mutating func appendCompletedQuotedScalar(_ quoted: PendingQuotedScalar) throws {
    switch quoted.style {
    case .singleQuoted:
      appendStringScalar(try parseSingleQuoted(quoted.text, location: quoted.location), style: .singleQuoted)
    case .doubleQuoted:
      appendStringScalar(try parseDoubleQuoted(quoted.text, location: quoted.location), style: .doubleQuoted)
    default:
      throw YAML.ParseError.invalidSyntax("Invalid quoted scalar style", location: quoted.location)
    }
  }

  private func validTrailingQuotedScalarContent(_ trailingContent: Substring) -> Bool {
    let trailing = trailingContent.yamlQuotedTrimmedHorizontalWhitespace
    guard !trailing.isEmpty else {
      return true
    }
    guard trailing.hasPrefix("#") else {
      return false
    }
    guard let first = trailingContent.first else {
      return false
    }
    return first == " " || first == "\t"
  }

  private func trimTrailingTabs(from text: inout String) {
    while text.last == "\t" {
      text.removeLast()
    }
  }

  private mutating func appendFlowTokens(
    _ region: ParseBuffer.Region,
    location: YAML.ParseError.Location,
    minimumContinuationIndent: Int? = nil
  ) throws {
    var lexer = YAMLFlowLexer(region: region, location: location, tagHandles: tagHandles)
    var adapter = YAMLFlowStructureAdapter(location: location)
    try adapter.consume(from: &lexer, into: &pendingTokens)
    if adapter.isComplete {
      lexer.finish()
      try adapter.consume(from: &lexer, into: &pendingTokens)
      try adapter.finish(into: &pendingTokens)
      markDocumentContent()
    } else {
      pendingFlow = PendingFlow(
        lexer: lexer,
        adapter: adapter,
        opener: region.firstByte ?? .leftSquare,
        minimumContinuationIndent: minimumContinuationIndent,
        nextFeedLeadingNewline: true
      )
    }
  }

  private mutating func appendFlowTokens(
    _ data: Data,
    sourceRegion: ParseBuffer.Region?,
    location: YAML.ParseError.Location,
    minimumContinuationIndent: Int? = nil
  ) throws {
    var lexer = YAMLFlowLexer(data: data, sourceRegion: sourceRegion, location: location, tagHandles: tagHandles)
    let opener = lexer.firstByte ?? .leftSquare
    var adapter = YAMLFlowStructureAdapter(location: location)
    try adapter.consume(from: &lexer, into: &pendingTokens)
    if adapter.isComplete {
      lexer.finish()
      try adapter.consume(from: &lexer, into: &pendingTokens)
      try adapter.finish(into: &pendingTokens)
      markDocumentContent()
    } else {
      pendingFlow = PendingFlow(
        lexer: lexer,
        adapter: adapter,
        opener: opener,
        minimumContinuationIndent: minimumContinuationIndent,
        nextFeedLeadingNewline: true
      )
    }
  }

  private func parseBlockScalarHeader(
    _ region: ParseBuffer.Region,
    location: YAML.ParseError.Location
  ) throws -> (style: YAMLScalarStyle, indent: Int?)? {
    try region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard let indicator = bytes.first, indicator == UInt8(ascii: "|") || indicator == UInt8(ascii: ">") else {
        return nil
      }

      var chomp: YAMLScalarChomp = .clip
      var indent: Int?
      var sawChomp = false
      var sawIndent = false
      var scanner = YAMLByteScanner(bytes)
      _ = scanner.readByte()

      while let byte = scanner.current {
        if byte == UInt8(ascii: "+") || byte == .dash {
          guard !sawChomp else {
            throw YAML.ParseError.invalidSyntax("Invalid block scalar chomping indicator", location: location)
          }
          sawChomp = true
          chomp = byte == UInt8(ascii: "+") ? .keep : .strip
        } else if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
          guard !sawIndent, byte != UInt8(ascii: "0") else {
            throw YAML.ParseError.invalidSyntax("Invalid block scalar indentation indicator", location: location)
          }
          sawIndent = true
          indent = Int(byte - UInt8(ascii: "0"))
        } else if byte == .space {
          break
        } else {
          throw YAML.ParseError.invalidSyntax("Invalid block scalar header", location: location)
        }
        scanner.advance()
      }

      let trailing = region.subregion(scanner.position..<bytes.count).trimmedHorizontalWhitespace()
      if !trailing.isEmpty, trailing.firstByte != .comment {
        throw YAML.ParseError.invalidSyntax("Invalid block scalar header", location: location)
      }

      if indicator == UInt8(ascii: "|") {
        return (.literal(chomp: chomp, indent: indent), indent)
      }
      return (.folded(chomp: chomp, indent: indent), indent)
    }
  }

  private func joinPlainBlockLines(
    _ lines: ContiguousArray<PendingBlockScalarLine>
  ) -> Data {
    var result = Data()
    let newlineCount = lines.isEmpty ? 0 : lines.count
    let capacity = lines.reduce(0) { partial, entry in partial + entry.byteCount } + newlineCount
    result.reserveCapacity(capacity)
    for idx in lines.indices {
      if idx > 0 {
        result.append(.newline)
      }
      lines[idx].appendBytes(to: &result)
    }
    result.append(.newline)
    return result
  }

  private func joinLiteralLines(
    _ lines: ContiguousArray<PendingBlockScalarLine>,
    chomp: YAMLScalarChomp
  ) -> Data {
    var endIndex = lines.count
    if chomp != .keep {
      while endIndex > 0, lines[endIndex - 1].isEmpty {
        endIndex -= 1
      }
    }
    var text = Data()
    let newlineCount = max(0, endIndex - 1)
    let capacity = (0..<endIndex).reduce(0) { partial, idx in partial + lines[idx].byteCount }
      + newlineCount + 1
    text.reserveCapacity(capacity)
    for idx in 0..<endIndex {
      if idx > 0 {
        text.append(.newline)
      }
      lines[idx].appendBytes(to: &text)
    }
    switch chomp {
    case .clip:
      if !text.isEmpty {
        text.append(.newline)
      }
    case .keep:
      if endIndex == 0 {
        return Data()
      }
      text.append(.newline)
    case .strip:
      while text.last == .newline {
        text.removeLast()
      }
    }
    return text
  }

  private func joinFoldedLines(
    _ lines: ContiguousArray<PendingBlockScalarLine>,
    baseIndent: Int,
    chomp: YAMLScalarChomp
  ) -> Data {
    var endIndex = lines.count
    if chomp != .keep {
      while endIndex > 0, lines[endIndex - 1].isEmpty {
        endIndex -= 1
      }
    }
    var result = Data()
    let capacity = (0..<endIndex).reduce(0) { partial, idx in partial + lines[idx].byteCount } + endIndex
    result.reserveCapacity(capacity)
    var hasContent = false
    var previousIndented = false
    var previousEmpty = false

    for idx in 0..<endIndex {
      let entry = lines[idx]
      let isIndented = entry.indent > baseIndent || entry.firstByte == .tab
      if !hasContent {
        if entry.isEmpty {
          result.append(.newline)
          previousEmpty = true
          continue
        }
        entry.appendBytes(to: &result)
        hasContent = true
        previousEmpty = false
        previousIndented = isIndented
        continue
      }

      if entry.isEmpty {
        result.append(.newline)
        previousEmpty = true
        continue
      }

      if previousEmpty {
        if isIndented || previousIndented {
          result.append(.newline)
        }
      } else if previousIndented || isIndented {
        result.append(.newline)
      } else {
        result.append(.space)
      }

      entry.appendBytes(to: &result)
      previousEmpty = false
      previousIndented = isIndented
    }

    switch chomp {
    case .clip:
      if !result.isEmpty {
        result.append(.newline)
      }
    case .keep:
      if endIndex == 0 {
        return Data()
      }
      result.append(.newline)
    case .strip:
      while result.last == .newline {
        result.removeLast()
      }
    }

    return result
  }

  private func isFlowCloseLine(_ region: ParseBuffer.Region, opener: UInt8) -> Bool {
    let trimmed = region.trimmedHorizontalWhitespace()
    switch opener {
    case .leftSquare:
      return trimmed.firstByte == .rightSquare
    case .leftBrace:
      return trimmed.firstByte == .rightBrace
    default:
      return false
    }
  }
}

private struct YAMLByteScanner: ~Copyable {
  private let bytes: UnsafeBufferPointer<UInt8>
  private var index: Int

  init(_ bytes: UnsafeBufferPointer<UInt8>) {
    self.bytes = bytes
    self.index = bytes.startIndex
  }

  var isAtEnd: Bool {
    index >= bytes.endIndex
  }

  var current: UInt8? {
    guard !isAtEnd else { return nil }
    return bytes[index]
  }

  var position: Int {
    index
  }

  mutating func advance() {
    guard !isAtEnd else { return }
    index += 1
  }

  mutating func readByte() -> UInt8? {
    guard let byte = current else { return nil }
    advance()
    return byte
  }
}

private enum YAMLFlowLexToken: Sendable {
  case beginSequence(YAML.ParseError.Location)
  case endSequence(YAML.ParseError.Location)
  case beginMapping(YAML.ParseError.Location)
  case endMapping(YAML.ParseError.Location)
  case comma(YAML.ParseError.Location)
  case colon(YAML.ParseError.Location)
  case explicitKey(YAML.ParseError.Location)
  case scalar(YAMLRawScalar, YAML.ParseError.Location)
  case tag(String, YAML.ParseError.Location)
  case anchor(String, YAML.ParseError.Location)
  case alias(String, YAML.ParseError.Location)
  case lineBreak(YAML.ParseError.Location)
  case endOfInput(YAML.ParseError.Location)
  case invalid(String, YAML.ParseError.Location)

  var location: YAML.ParseError.Location {
    switch self {
    case .beginSequence(let location),
      .endSequence(let location),
      .beginMapping(let location),
      .endMapping(let location),
      .comma(let location),
      .colon(let location),
      .explicitKey(let location),
      .scalar(_, let location),
      .tag(_, let location),
      .anchor(_, let location),
      .alias(_, let location),
      .lineBreak(let location),
      .endOfInput(let location),
      .invalid(_, let location):
      return location
    }
  }
}

private struct YAMLFlowLexTokenQueue: Sendable {
  private var storage: ContiguousArray<YAMLFlowLexToken> = []
  private var head = 0

  var isEmpty: Bool { head >= storage.count }

  mutating func append(_ token: YAMLFlowLexToken) {
    storage.append(token)
  }

  mutating func peek() -> YAMLFlowLexToken? {
    guard head < storage.count else { return nil }
    return storage[head]
  }

  mutating func pop() -> YAMLFlowLexToken? {
    guard head < storage.count else { return nil }
    defer {
      head += 1
      compactIfNeeded()
    }
    return storage[head]
  }

  private mutating func compactIfNeeded() {
    guard head > 32, head * 2 > storage.count else { return }
    storage.removeFirst(head)
    head = 0
  }
}

private struct YAMLFlowLexer: ~Copyable, Sendable {
  private struct PendingPlain: Sendable {
    var sourceRegion: ParseBuffer.Region?
    var sourceStart: Int
    var sourceEnd: Int
    var location: YAML.ParseError.Location
    var generatedBytes: Data?

    var hasGeneratedBytes: Bool { generatedBytes != nil }
  }

  private enum QuotedState: Sendable {
    case single(result: Data, blankLineCount: Int, location: YAML.ParseError.Location)
    case double(result: Data, escaped: Bool, blankLineCount: Int, location: YAML.ParseError.Location)
  }

  private var tokens = YAMLFlowLexTokenQueue()
  private var location: YAML.ParseError.Location
  private var tagHandles: [String: String]
  private var pendingPlain: PendingPlain?
  private var pendingColon = false
  private var pendingColonLocation: YAML.ParseError.Location?
  private var canEmitAdjacentColon = false
  private var quotedState: QuotedState?
  private(set) var firstByte: UInt8?

  init(region: ParseBuffer.Region, location: YAML.ParseError.Location, tagHandles: [String: String]) {
    self.location = location
    self.tagHandles = tagHandles
    self.firstByte = region.firstByte
    feedLine(region, leadingNewline: false, line: location.line, column: location.column)
  }

  init(data: Data, sourceRegion: ParseBuffer.Region?, location: YAML.ParseError.Location, tagHandles: [String: String]) {
    self.location = location
    self.tagHandles = tagHandles
    if let sourceRegion {
      self.firstByte = sourceRegion.firstByte
      feedLine(sourceRegion, leadingNewline: false, line: location.line, column: location.column)
    } else {
      self.firstByte = data.first
      feedLine(.init(data: data), leadingNewline: false, line: location.line, column: location.column)
    }
  }

  mutating func feedEmptyLine(line: Int, column: Int) {
    let lineBreakLocation = YAML.ParseError.Location(line: line, column: column)
    tokens.append(.lineBreak(lineBreakLocation))
    if quotedState != nil {
      incrementQuotedBlankLine()
    } else if pendingPlain != nil {
      materializePendingPlainIfNeeded()
      pendingPlain?.generatedBytes?.append(.newline)
    }
  }

  mutating func feedLine(
    _ region: ParseBuffer.Region,
    leadingNewline: Bool,
    line: Int,
    column: Int
  ) {
    if pendingColon, leadingNewline {
      finishPendingPlain()
      tokens.append(.colon(pendingColonLocation ?? YAML.ParseError.Location(line: line, column: column)))
      canEmitAdjacentColon = false
      pendingColon = false
      pendingColonLocation = nil
    }
    if leadingNewline {
      tokens.append(.lineBreak(YAML.ParseError.Location(line: line, column: column)))
      if quotedState != nil {
        appendQuotedLineBreak()
      } else if pendingPlain != nil {
        materializePendingPlainIfNeeded()
        pendingPlain?.generatedBytes?.append(.newline)
      }
    }

    region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      if pendingColon, let first = bytes.first {
        if canEmitAdjacentColon || colonCanSeparateBefore(first) {
          finishPendingPlain()
          tokens.append(.colon(pendingColonLocation ?? YAML.ParseError.Location(line: line, column: column)))
          canEmitAdjacentColon = false
        } else {
          appendGeneratedPlainByte(.colon)
        }
        pendingColon = false
        pendingColonLocation = nil
      }
      var index = 0
      while index < bytes.count {
        let byteLocation = tokenLocation(line: line, column: column, offset: index)
        if scanQuoted(bytes: bytes, index: &index) {
          continue
        }
        let byte = bytes[index]
        if pendingPlain == nil, byte.isYAMLHorizontalWhitespace {
          index += 1
          continue
        }
        if byte == .comment, index == 0 || bytes[index - 1].isYAMLWhitespace {
          finishPendingPlain()
          break
        }
        if byte == .comment, pendingPlain == nil {
          tokens.append(.invalid("Unexpected comment in flow", byteLocation))
          break
        }
        if pendingPlain == nil, startsDocumentBoundary(bytes: bytes, at: index) {
          tokens.append(.invalid("Document marker is not allowed in flow style", byteLocation))
          index = bytes.count
          continue
        }

        if byte == .singleQuote, pendingPlain == nil {
          quotedState = .single(result: Data(), blankLineCount: 0, location: byteLocation)
          index += 1
          continue
        }
        if byte == .doubleQuote, pendingPlain == nil {
          quotedState = .double(result: Data(), escaped: false, blankLineCount: 0, location: byteLocation)
          index += 1
          continue
        }
        if byte == .exclamation, pendingPlain == nil {
          if let (tag, nextIndex) = parseTag(bytes: bytes, start: index) {
            if nextIndex < bytes.count, bytes[nextIndex] == .leftBrace || bytes[nextIndex] == .rightBrace {
              tokens.append(.invalid("Invalid tag", byteLocation))
              index = bytes.count
              continue
            }
            tokens.append(.tag(tag, byteLocation))
            canEmitAdjacentColon = false
            index = nextIndex
            continue
          }
        }
        if byte == .ampersand, pendingPlain == nil {
          if let (anchor, nextIndex) = parseDecoratorName(bytes: bytes, start: index + 1) {
            tokens.append(.anchor(anchor, byteLocation))
            canEmitAdjacentColon = false
            index = nextIndex
            continue
          }
        }
        if byte == .asterisk, pendingPlain == nil {
          if let (alias, nextIndex) = parseDecoratorName(bytes: bytes, start: index + 1) {
            tokens.append(.alias(alias, byteLocation))
            canEmitAdjacentColon = true
            index = nextIndex
            continue
          }
        }

        switch byte {
        case .leftSquare where pendingPlain == nil:
          tokens.append(.beginSequence(byteLocation))
          canEmitAdjacentColon = false
          index += 1
        case .leftBrace where pendingPlain == nil:
          tokens.append(.beginMapping(byteLocation))
          canEmitAdjacentColon = false
          index += 1
        case .rightSquare:
          finishPendingPlain()
          tokens.append(.endSequence(byteLocation))
          canEmitAdjacentColon = true
          index += 1
        case .rightBrace:
          finishPendingPlain()
          tokens.append(.endMapping(byteLocation))
          canEmitAdjacentColon = true
          index += 1
        case .comma:
          finishPendingPlain()
          tokens.append(.comma(byteLocation))
          canEmitAdjacentColon = false
          index += 1
        case .colon where pendingPlain == nil && canEmitAdjacentColon:
          tokens.append(.colon(byteLocation))
          canEmitAdjacentColon = false
          index += 1
        case .colon where colonIsMappingSeparator(bytes: bytes, at: index):
          if index == bytes.count - 1 {
            pendingColon = true
            pendingColonLocation = byteLocation
            index += 1
            continue
          }
          finishPendingPlain()
          tokens.append(.colon(byteLocation))
          canEmitAdjacentColon = false
          index += 1
        case .question where pendingPlain == nil && explicitQuestionIsIndicator(bytes: bytes, at: index):
          tokens.append(.explicitKey(byteLocation))
          canEmitAdjacentColon = false
          index += 1
        default:
          appendPlainByte(region: region, bytes: bytes, index: index, location: byteLocation)
          index += 1
        }
      }
    }
  }

  mutating func finish() {
    if pendingColon {
      finishPendingPlain()
      tokens.append(.colon(pendingColonLocation ?? location))
      canEmitAdjacentColon = false
      pendingColon = false
      pendingColonLocation = nil
    }
    finishPendingPlain()
    switch quotedState {
    case .single(_, _, let location), .double(_, _, _, let location):
      tokens.append(.endOfInput(location))
    case nil:
      tokens.append(.endOfInput(location))
    }
  }

  mutating func popToken() -> YAMLFlowLexToken? {
    tokens.pop()
  }

  private func tokenLocation(line: Int, column: Int, offset: Int) -> YAML.ParseError.Location {
    YAML.ParseError.Location(line: line, column: column + offset)
  }

  private mutating func scanQuoted(bytes: UnsafeBufferPointer<UInt8>, index: inout Int) -> Bool {
    guard let state = quotedState else {
      return false
    }

    switch state {
    case .single(var result, let blankLineCount, let location):
      if blankLineCount > 0 {
        result.append(contentsOf: repeatElement(UInt8.newline, count: blankLineCount))
      }
      while index < bytes.count {
        let byte = bytes[index]
        if byte == .singleQuote {
          let next = index + 1
          if next < bytes.count, bytes[next] == .singleQuote {
            result.append(.singleQuote)
            index = next + 1
            continue
          }
          quotedState = nil
          tokens.append(.scalar(.init(style: .singleQuoted, kind: .string, region: .init(data: result)), location))
          canEmitAdjacentColon = true
          index = next
          return true
        }
        result.append(byte)
        index += 1
      }
      quotedState = .single(result: result, blankLineCount: 0, location: location)
      return true

    case .double(var result, var escaped, let blankLineCount, let location):
      if blankLineCount > 0 {
        result.append(contentsOf: repeatElement(UInt8.newline, count: blankLineCount))
      }
      while index < bytes.count {
        let byte = bytes[index]
        if escaped {
          appendDoubleQuotedEscape(byte, bytes: bytes, index: &index, result: &result, location: location)
          escaped = false
          index += 1
          continue
        }
        if byte == .backslash {
          escaped = true
          index += 1
          continue
        }
        if byte == .doubleQuote {
          quotedState = nil
          tokens.append(.scalar(.init(style: .doubleQuoted, kind: .string, region: .init(data: result)), location))
          canEmitAdjacentColon = true
          index += 1
          return true
        }
        result.append(byte)
        index += 1
      }
      quotedState = .double(result: result, escaped: escaped, blankLineCount: 0, location: location)
      return true
    }
  }

  private mutating func appendQuotedLineBreak() {
    switch quotedState {
    case .single(var result, let blankLineCount, let location):
      trimTrailingSpaces(from: &result)
      if blankLineCount == 0 {
        result.append(.space)
      } else {
        result.append(contentsOf: repeatElement(UInt8.newline, count: blankLineCount))
      }
      quotedState = .single(result: result, blankLineCount: 0, location: location)
    case .double(var result, let escaped, let blankLineCount, let location):
      trimTrailingSpaces(from: &result)
      if blankLineCount == 0 {
        result.append(.space)
      } else {
        result.append(contentsOf: repeatElement(UInt8.newline, count: blankLineCount))
      }
      quotedState = .double(result: result, escaped: escaped, blankLineCount: 0, location: location)
    case nil:
      break
    }
  }

  private mutating func incrementQuotedBlankLine() {
    switch quotedState {
    case .single(let result, let blankLineCount, let location):
      quotedState = .single(result: result, blankLineCount: blankLineCount + 1, location: location)
    case .double(let result, let escaped, let blankLineCount, let location):
      quotedState = .double(result: result, escaped: escaped, blankLineCount: blankLineCount + 1, location: location)
    case nil:
      break
    }
  }

  private mutating func appendPlainByte(
    region: ParseBuffer.Region,
    bytes: UnsafeBufferPointer<UInt8>,
    index: Int,
    location: YAML.ParseError.Location
  ) {
    if pendingPlain == nil {
      pendingPlain = PendingPlain(
        sourceRegion: region,
        sourceStart: index,
        sourceEnd: index,
        location: location,
        generatedBytes: nil
      )
    }
    if let sourceRegion = pendingPlain?.sourceRegion,
      pendingPlain?.generatedBytes == nil,
      !sameRetainedRegion(sourceRegion, region)
    {
      materializePendingPlainIfNeeded()
    }
    if pendingPlain?.hasGeneratedBytes == true {
      pendingPlain?.generatedBytes?.append(bytes[index])
    } else {
      pendingPlain?.sourceEnd = index + 1
    }
  }

  private mutating func appendGeneratedPlainByte(_ byte: UInt8) {
    if pendingPlain == nil {
      pendingPlain = PendingPlain(
        sourceRegion: nil,
        sourceStart: 0,
        sourceEnd: 0,
        location: location,
        generatedBytes: Data()
      )
    }
    materializePendingPlainIfNeeded()
    pendingPlain?.generatedBytes?.append(byte)
  }

  private func sameRetainedRegion(_ lhs: ParseBuffer.Region, _ rhs: ParseBuffer.Region) -> Bool {
    if let lhsIndex = lhs.segmentIndex,
      let rhsIndex = rhs.segmentIndex,
      let lhsRange = lhs.segmentRange,
      let rhsRange = rhs.segmentRange
    {
      return lhsIndex == rhsIndex && lhsRange == rhsRange
    }
    return false
  }

  private mutating func materializePendingPlainIfNeeded() {
    guard var pending = pendingPlain, pending.generatedBytes == nil else {
      return
    }
    if let sourceRegion = pending.sourceRegion {
      pending.generatedBytes = sourceRegion.subregion(pending.sourceStart..<pending.sourceEnd).bytes
    } else {
      pending.generatedBytes = Data()
    }
    pending.sourceRegion = nil
    pending.sourceStart = 0
    pending.sourceEnd = 0
    pendingPlain = pending
  }

  private mutating func finishPendingPlain() {
    guard let pending = pendingPlain else {
      return
    }
    pendingPlain = nil
    let region: ParseBuffer.Region
    let hadLineBreak: Bool
    if let data = pending.generatedBytes {
      hadLineBreak = data.contains(.newline) || data.contains(.carriageReturn)
      region = .init(data: foldFlowScalarBytes(data))
    } else if let sourceRegion = pending.sourceRegion {
      hadLineBreak = false
      region = sourceRegion.subregion(trimHorizontalAndNewlineBytes(
        in: pending.sourceStart..<pending.sourceEnd,
        bytes: sourceRegion
      ))
    } else {
      hadLineBreak = false
      region = .init(data: Data())
    }
    guard !region.isEmpty else {
      return
    }
    if region.isExactly("-") || region.isExactly("?") {
      tokens.append(.invalid("Expected flow node", pending.location))
      return
    }
    tokens.append(.scalar(.init(style: .plain, kind: .number, region: region), pending.location))
    if hadLineBreak {
      tokens.append(.lineBreak(pending.location))
    }
    canEmitAdjacentColon = true
  }

  private func parseTag(bytes: UnsafeBufferPointer<UInt8>, start: Int) -> (String, Int)? {
    var index = start + 1
    if index < bytes.count, bytes[index] == .leftAngle {
      let contentStart = index + 1
      while index < bytes.count, bytes[index] != .rightAngle {
        index += 1
      }
      guard index < bytes.count else { return nil }
      guard let tag = validatedYAMLUTF8String(bytes, in: contentStart..<index) else {
        return nil
      }
      return (tag, index + 1)
    }
    while index < bytes.count, isDecoratorByte(bytes[index]) {
      index += 1
    }
    guard let token = validatedYAMLUTF8String(bytes, in: start..<index) else {
      return nil
    }
    return (try? resolveTagToken(token)) .map { ($0, index) }
  }

  private func parseDecoratorName(bytes: UnsafeBufferPointer<UInt8>, start: Int) -> (String, Int)? {
    var index = start
    while index < bytes.count, isDecoratorByte(bytes[index]) {
      index += 1
    }
    guard index > start else {
      return nil
    }
    guard let name = validatedYAMLUTF8String(bytes, in: start..<index) else {
      return nil
    }
    return (name, index)
  }

  private func colonIsMappingSeparator(bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
    let next = index + 1
    return next == bytes.count
      || colonCanSeparateBefore(bytes[next])
  }

  private func colonCanSeparateBefore(_ byte: UInt8) -> Bool {
    byte.isYAMLWhitespace
      || byte == .comma
      || byte == .rightSquare
      || byte == .rightBrace
  }

  private func explicitQuestionIsIndicator(bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
    let next = index + 1
    return next == bytes.count
      || bytes[next].isYAMLWhitespace
      || bytes[next] == .comma
      || bytes[next] == .rightBrace
      || bytes[next] == .rightSquare
  }

  private func startsDocumentBoundary(bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
    func hasPrefix(_ prefix: [UInt8]) -> Bool {
      guard index + prefix.count <= bytes.count else { return false }
      for offset in prefix.indices where bytes[index + offset] != prefix[offset] {
        return false
      }
      let end = index + prefix.count
      return end == bytes.count || bytes[end].isYAMLWhitespace || bytes[end] == .comma
    }
    return hasPrefix([.dash, .dash, .dash]) || hasPrefix([UInt8(ascii: "."), UInt8(ascii: "."), UInt8(ascii: ".")])
  }

  private func isDecoratorByte(_ byte: UInt8) -> Bool {
    !byte.isYAMLWhitespace
      && byte != .comma
      && byte != .leftSquare
      && byte != .rightSquare
      && byte != .leftBrace
      && byte != .rightBrace
  }

  private func resolveTagToken(_ token: String) throws -> String {
    if token.hasPrefix("!<"), token.hasSuffix(">") {
      return String(token.dropFirst(2).dropLast())
    }
    if token == "!" {
      return token
    }
    if token.hasPrefix("!!") {
      let suffix = try decodeTagSuffix(String(token.dropFirst(2)))
      let prefix = tagHandles["!!"] ?? "tag:yaml.org,2002:"
      return suffix.isEmpty ? prefix : "\(prefix)\(suffix)"
    }
    guard token.hasPrefix("!") else {
      return token
    }
    let afterBang = token.index(after: token.startIndex)
    if let handleEnd = token[afterBang...].firstIndex(of: "!") {
      let handle = String(token[..<token.index(after: handleEnd)])
      let suffix = try decodeTagSuffix(String(token[token.index(after: handleEnd)...]))
      guard let prefix = tagHandles[handle] else {
        throw YAML.ParseError.invalidSyntax("Unknown tag handle", location: location)
      }
      return "\(prefix)\(suffix)"
    }
    let suffix = try decodeTagSuffix(String(token.dropFirst()))
    guard let prefix = tagHandles["!"] else {
      throw YAML.ParseError.invalidSyntax("Unknown tag handle", location: location)
    }
    if suffix.isEmpty {
      return "!"
    }
    return prefix == "!" ? "!\(suffix)" : "\(prefix)\(suffix)"
  }

  private func decodeTagSuffix(_ text: String) throws -> String {
    try decodeYAMLTagSuffix(text, location: location)
  }

  private func appendDoubleQuotedEscape(
    _ byte: UInt8,
    bytes: UnsafeBufferPointer<UInt8>,
    index: inout Int,
    result: inout Data,
    location: YAML.ParseError.Location
  ) {
    switch byte {
    case UInt8(ascii: "0"): result.append(0)
    case UInt8(ascii: "a"): result.append(0x07)
    case UInt8(ascii: "b"): result.append(0x08)
    case UInt8(ascii: "n"): result.append(.newline)
    case UInt8(ascii: "r"): result.append(.carriageReturn)
    case UInt8(ascii: "t"): result.append(.tab)
    case UInt8(ascii: "v"): result.append(0x0B)
    case UInt8(ascii: "f"): result.append(0x0C)
    case UInt8(ascii: "e"): result.append(0x1B)
    case .space: result.append(.space)
    case .doubleQuote: result.append(.doubleQuote)
    case .backslash: result.append(.backslash)
    case UInt8(ascii: "/"): result.append(UInt8(ascii: "/"))
    default: result.append(byte)
    }
  }

  private func trimTrailingSpaces(from bytes: inout Data) {
    while bytes.last == .space {
      bytes.removeLast()
    }
  }

  private func trimHorizontalAndNewlineBytes(in range: Range<Int>, bytes region: ParseBuffer.Region) -> Range<Int> {
    region.withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var lower = range.lowerBound
      var upper = range.upperBound
      while lower < upper, bytes[lower].isYAMLWhitespace {
        lower += 1
      }
      while upper > lower, bytes[upper - 1].isYAMLWhitespace {
        upper -= 1
      }
      return lower..<upper
    }
  }

  private func foldFlowScalarBytes(_ bytes: Data) -> Data {
    var result = Data()
    result.reserveCapacity(bytes.count)
    var index = bytes.startIndex
    while index < bytes.endIndex {
      let byte = bytes[index]
      if byte.isYAMLLineBreak {
        while let last = result.last, last == .space || last == .tab {
          result.removeLast()
        }
        index += 1
        var breakCount = 0
        while index < bytes.endIndex {
          let next = bytes[index]
          if next.isYAMLLineBreak {
            breakCount += 1
            index += 1
            continue
          }
          if next == .space || next == .tab {
            index += 1
            continue
          }
          break
        }
        if breakCount == 0 {
          result.append(.space)
        } else {
          result.append(contentsOf: repeatElement(UInt8.newline, count: breakCount))
        }
        continue
      }
      result.append(byte)
      index += 1
    }
    while let last = result.last, last == .space || last == .tab {
      result.removeLast()
    }
    return result
  }
}

private struct YAMLFlowStructureAdapter: ~Copyable, Sendable {
  private enum Kind: Sendable {
    case sequence
    case mapping
  }

  private enum SequenceMode: Sendable {
    case item
    case implicitMappingValue
  }

  private enum MappingMode: Sendable {
    case key
    case value
  }

  private struct Frame: Sendable {
    let kind: Kind
    let isRoot: Bool
    var streamsDirectly: Bool = false
    var collected: ContiguousArray<YAMLRawToken>
    var sequenceMode: SequenceMode = .item
    var sequenceItem: ContiguousArray<YAMLRawToken> = []
    var sequenceKey: ContiguousArray<YAMLRawToken> = []
    var sequenceValue: ContiguousArray<YAMLRawToken> = []
    var sequenceLineBreakBeforeColon = false
    var sequenceExplicitKey = false
    var mappingMode: MappingMode = .key
    var mappingKey: ContiguousArray<YAMLRawToken> = []
    var mappingValue: ContiguousArray<YAMLRawToken> = []
    var mappingExplicitEntry = false
    var mappingValueStreamsDirectly = false
    var mappingValueSawToken = false
    var mappingValueNeedsEmptyScalar = false
  }

  private let location: YAML.ParseError.Location
  private var frames: ContiguousArray<Frame> = []
  private var ready: ContiguousArray<YAMLRawToken> = []
  private(set) var isComplete = false
  private var sawRoot = false

  init(location: YAML.ParseError.Location) {
    self.location = location
  }

  mutating func consume(
    from lexer: inout YAMLFlowLexer,
    into queue: inout YAMLTokenizer.PendingTokenQueue
  ) throws {
    while let token = lexer.popToken() {
      try consume(token, into: &queue)
      drainReady(into: &queue)
    }
  }

  mutating func finish(into queue: inout YAMLTokenizer.PendingTokenQueue) throws {
    guard isComplete else {
      throw YAML.ParseError.incompleteInput(location: location)
    }
    guard frames.isEmpty else {
      throw YAML.ParseError.incompleteInput(location: location)
    }
  }

  private mutating func consume(
    _ token: YAMLFlowLexToken,
    into queue: inout YAMLTokenizer.PendingTokenQueue
  ) throws {
    if isComplete {
      switch token {
      case .lineBreak, .endOfInput:
        return
      case .invalid(let message, let location):
        throw YAML.ParseError.invalidSyntax(message, location: location)
      default:
        throw YAML.ParseError.invalidSyntax("Unexpected flow content", location: token.location)
      }
    }

    switch token {
    case .lineBreak:
      if let index = frames.indices.last, frames[index].kind == .sequence,
        !frames[index].sequenceItem.isEmpty
      {
        frames[index].sequenceLineBreakBeforeColon = true
      }

    case .endOfInput(let location):
      guard isComplete else {
        throw YAML.ParseError.incompleteInput(location: location)
      }
    case .invalid(let message, let location):
      throw YAML.ParseError.invalidSyntax(message, location: location)

    case .beginSequence:
      try begin(.sequence, token: .beginSequence(style: .flow), into: &queue)
    case .beginMapping:
      try begin(.mapping, token: .beginMapping(style: .flow), into: &queue)
    case .endSequence(let location):
      try end(.sequence, endToken: .endSequence, location: location, into: &queue)
    case .endMapping(let location):
      try end(.mapping, endToken: .endMapping, location: location, into: &queue)
    case .comma(let location):
      try consumeComma(location: location)
    case .colon(let location):
      try consumeColon(location: location)
    case .explicitKey:
      try consumeExplicitKey()
    case .scalar(let scalar, _):
      appendNodeTokens([.scalar(scalar)])
    case .tag(let tag, _):
      appendNodeTokens([.tag(tag)])
    case .anchor(let anchor, _):
      appendNodeTokens([.anchor(anchor)])
    case .alias(let alias, _):
      appendNodeTokens([.alias(alias)])
    }
  }

  private mutating func begin(
    _ kind: Kind,
    token: YAMLRawToken,
    into queue: inout YAMLTokenizer.PendingTokenQueue
  ) throws {
    if frames.isEmpty {
      guard !sawRoot else {
        throw YAML.ParseError.invalidSyntax("Unexpected flow content", location: location)
      }
      sawRoot = true
      queue.append(token)
      frames.append(Frame(kind: kind, isRoot: true, collected: []))
    } else if shouldStreamNewCollectionAsMappingValue() {
      var frame = frames.removeLast()
      markDirectMappingValueSawToken(in: &frame, tokensEndWithDecorator: false)
      appendToFrameSink([token], frame: &frame)
      frames.append(frame)
      frames.append(Frame(kind: kind, isRoot: false, streamsDirectly: true, collected: []))
    } else {
      frames.append(Frame(kind: kind, isRoot: false, collected: [token]))
    }
  }

  private mutating func end(
    _ expected: Kind,
    endToken: YAMLRawToken,
    location: YAML.ParseError.Location,
    into queue: inout YAMLTokenizer.PendingTokenQueue
  ) throws {
    guard var frame = frames.popLast(), frame.kind == expected else {
      throw YAML.ParseError.invalidSyntax("Unexpected flow close", location: location)
    }
    switch frame.kind {
    case .sequence:
      try finishSequenceItem(in: &frame, allowEmptyTrailing: true, location: location)
    case .mapping:
      finishMappingEntry(in: &frame)
    }
    if frame.isRoot {
      drainReady(into: &queue)
      queue.append(endToken)
      isComplete = true
    } else if frame.streamsDirectly {
      drainReady(into: &queue)
      queue.append(endToken)
    } else {
      frame.collected.append(endToken)
      appendNodeTokens(frame.collected)
    }
  }

  private mutating func consumeComma(location: YAML.ParseError.Location) throws {
    guard !frames.isEmpty else {
      throw YAML.ParseError.invalidSyntax("Unexpected ','", location: location)
    }
    var frame = frames.removeLast()
    switch frame.kind {
    case .sequence:
      if frame.sequenceMode == .item, frame.sequenceItem.isEmpty, !frame.sequenceExplicitKey {
        throw YAML.ParseError.invalidSyntax("Expected flow sequence item", location: location)
      }
      try finishSequenceItem(in: &frame, allowEmptyTrailing: false, location: location)
    case .mapping:
      if frame.mappingMode == .key, frame.mappingKey.isEmpty, !frame.mappingExplicitEntry {
        throw YAML.ParseError.invalidSyntax("Expected flow mapping entry", location: location)
      }
      finishMappingEntry(in: &frame)
    }
    frames.append(frame)
  }

  private mutating func consumeColon(location: YAML.ParseError.Location) throws {
    guard !frames.isEmpty else {
      throw YAML.ParseError.invalidSyntax("Unexpected ':'", location: location)
    }
    switch frames[frames.count - 1].kind {
    case .sequence:
      var frame = frames.removeLast()
      if frame.sequenceLineBreakBeforeColon, !frame.sequenceExplicitKey {
        throw YAML.ParseError.invalidSyntax("Invalid multiline flow mapping key", location: location)
      }
      frame.sequenceKey = frame.sequenceItem.isEmpty ? [emptyScalar()] : frame.sequenceItem
      frame.sequenceItem.removeAll(keepingCapacity: true)
      frame.sequenceValue.removeAll(keepingCapacity: true)
      frame.sequenceMode = .implicitMappingValue
      frame.sequenceLineBreakBeforeColon = false
      frames.append(frame)
    case .mapping:
      var frame = frames.removeLast()
      if frame.mappingMode == .key {
        if frame.mappingKey.isEmpty {
          frame.mappingKey.append(emptyScalar())
        }
        appendToFrameSink(normalizedNodeTokens(frame.mappingKey), frame: &frame)
        frame.mappingKey.removeAll(keepingCapacity: true)
        frame.mappingMode = .value
        frame.mappingValueStreamsDirectly = true
        frame.mappingValueSawToken = false
        frame.mappingValueNeedsEmptyScalar = false
      } else {
        appendNodeTokens([.scalar(.init(style: .plain, kind: .number, region: .init(data: Data([.colon]))))])
      }
      frames.append(frame)
    }
  }

  private mutating func consumeExplicitKey() throws {
    guard !frames.isEmpty else {
      throw YAML.ParseError.invalidSyntax("Unexpected explicit key", location: location)
    }
    var frame = frames.removeLast()
    switch frame.kind {
    case .sequence:
      frame.sequenceExplicitKey = true
      frame.sequenceLineBreakBeforeColon = false
    case .mapping:
      if frame.mappingMode == .value || !frame.mappingKey.isEmpty || !frame.mappingValue.isEmpty {
        finishMappingEntry(in: &frame)
      }
      frame.mappingExplicitEntry = true
      frame.mappingMode = .key
    }
    frames.append(frame)
  }

  private mutating func appendNodeTokens(_ tokens: ContiguousArray<YAMLRawToken>) {
    guard !frames.isEmpty else {
      return
    }
    switch frames[frames.count - 1].kind {
    case .sequence:
      switch frames[frames.count - 1].sequenceMode {
      case .item:
        frames[frames.count - 1].sequenceItem.append(contentsOf: tokens)
      case .implicitMappingValue:
        frames[frames.count - 1].sequenceValue.append(contentsOf: tokens)
      }
    case .mapping:
      switch frames[frames.count - 1].mappingMode {
      case .key:
        frames[frames.count - 1].mappingKey.append(contentsOf: tokens)
      case .value:
        if frames[frames.count - 1].mappingValueStreamsDirectly {
          var frame = frames.removeLast()
          markDirectMappingValueSawToken(
            in: &frame,
            tokensEndWithDecorator: tokensEndWithDecorator(tokens)
          )
          appendToFrameSink(tokens, frame: &frame)
          frames.append(frame)
        } else {
          frames[frames.count - 1].mappingValue.append(contentsOf: tokens)
        }
      }
    }
  }

  private mutating func appendNodeTokens(_ tokens: [YAMLRawToken]) {
    appendNodeTokens(ContiguousArray(tokens))
  }

  private mutating func finishSequenceItem(
    in frame: inout Frame,
    allowEmptyTrailing: Bool,
    location: YAML.ParseError.Location
  ) throws {
    switch frame.sequenceMode {
    case .item:
      if frame.sequenceExplicitKey {
        var mapping: ContiguousArray<YAMLRawToken> = [.beginMapping(style: .flow)]
        mapping.append(contentsOf: normalizedNodeTokens(frame.sequenceItem))
        mapping.append(emptyScalar())
        mapping.append(.endMapping)
        appendToFrameSink(mapping, frame: &frame)
      } else if frame.sequenceItem.isEmpty {
        if !allowEmptyTrailing {
          appendToFrameSink([emptyScalar()], frame: &frame)
        }
      } else {
        appendToFrameSink(frame.sequenceItem, frame: &frame)
      }
    case .implicitMappingValue:
      var mapping: ContiguousArray<YAMLRawToken> = [.beginMapping(style: .flow)]
      mapping.append(contentsOf: normalizedNodeTokens(frame.sequenceKey))
      mapping.append(contentsOf: normalizedNodeTokens(frame.sequenceValue))
      mapping.append(.endMapping)
      appendToFrameSink(mapping, frame: &frame)
    }
    frame.sequenceItem.removeAll(keepingCapacity: true)
    frame.sequenceKey.removeAll(keepingCapacity: true)
    frame.sequenceValue.removeAll(keepingCapacity: true)
    frame.sequenceMode = .item
    frame.sequenceLineBreakBeforeColon = false
    frame.sequenceExplicitKey = false
  }

  private mutating func finishMappingEntry(in frame: inout Frame) {
    switch frame.mappingMode {
    case .key:
      if frame.mappingKey.isEmpty, frame.mappingExplicitEntry {
        appendToFrameSink([emptyScalar(), emptyScalar()], frame: &frame)
      } else if frame.mappingKey.isEmpty {
        return
      } else {
        appendToFrameSink(normalizedNodeTokens(frame.mappingKey), frame: &frame)
        appendToFrameSink([emptyScalar()], frame: &frame)
      }
    case .value:
      if frame.mappingValueStreamsDirectly {
        if !frame.mappingValue.isEmpty {
          appendToFrameSink(normalizedNodeTokens(frame.mappingValue), frame: &frame)
        }
        if !frame.mappingValueSawToken || frame.mappingValueNeedsEmptyScalar {
          appendToFrameSink([emptyScalar()], frame: &frame)
        }
      } else {
        appendToFrameSink(normalizedNodeTokens(frame.mappingKey), frame: &frame)
        appendToFrameSink(normalizedNodeTokens(frame.mappingValue), frame: &frame)
      }
    }
    frame.mappingKey.removeAll(keepingCapacity: true)
    frame.mappingValue.removeAll(keepingCapacity: true)
    frame.mappingMode = .key
    frame.mappingExplicitEntry = false
    frame.mappingValueStreamsDirectly = false
    frame.mappingValueSawToken = false
    frame.mappingValueNeedsEmptyScalar = false
  }

  private mutating func appendToFrameSink(_ tokens: ContiguousArray<YAMLRawToken>, frame: inout Frame) {
    if frame.isRoot || frame.streamsDirectly {
      ready.append(contentsOf: tokens)
    } else {
      frame.collected.append(contentsOf: tokens)
    }
  }

  private mutating func appendToFrameSink(_ tokens: [YAMLRawToken], frame: inout Frame) {
    if frame.isRoot || frame.streamsDirectly {
      ready.append(contentsOf: tokens)
    } else {
      frame.collected.append(contentsOf: tokens)
    }
  }

  private mutating func drainReady(into queue: inout YAMLTokenizer.PendingTokenQueue) {
    guard !ready.isEmpty else { return }
    for token in ready {
      queue.append(token)
    }
    ready.removeAll(keepingCapacity: true)
  }

  private func emptyScalar() -> YAMLRawToken {
    .scalar(.init(style: .plain, kind: .number, region: .init(data: Data())))
  }

  private func normalizedNodeTokens(_ tokens: ContiguousArray<YAMLRawToken>) -> ContiguousArray<YAMLRawToken> {
    guard !tokens.isEmpty else {
      return [emptyScalar()]
    }
    switch tokens.last {
    case .tag, .anchor:
      var normalized = tokens
      normalized.append(emptyScalar())
      return normalized
    default:
      return tokens
    }
  }

  private func shouldStreamNewCollectionAsMappingValue() -> Bool {
    guard let frame = frames.last, frame.kind == .mapping else {
      return false
    }
    return frame.mappingMode == .value && frame.mappingValueStreamsDirectly
      && (frame.isRoot || frame.streamsDirectly)
  }

  private mutating func markDirectMappingValueSawToken(
    in frame: inout Frame,
    tokensEndWithDecorator: Bool
  ) {
    frame.mappingValueSawToken = true
    frame.mappingValueNeedsEmptyScalar = tokensEndWithDecorator
  }

  private func tokensEndWithDecorator(_ tokens: ContiguousArray<YAMLRawToken>) -> Bool {
    switch tokens.last {
    case .tag, .anchor:
      return true
    default:
      return false
    }
  }
}

private extension UInt8 {
  static let newline: UInt8 = 0x0A
  static let carriageReturn: UInt8 = 0x0D
  static let comment: UInt8 = 0x23
  static let space: UInt8 = 0x20
  static let tab: UInt8 = 0x09
  static let singleQuote: UInt8 = 0x27
  static let doubleQuote: UInt8 = 0x22
  static let backslash: UInt8 = 0x5C
  static let comma: UInt8 = 0x2C
  static let colon: UInt8 = 0x3A
  static let question: UInt8 = 0x3F
  static let dash: UInt8 = 0x2D
  static let asterisk: UInt8 = 0x2A
  static let ampersand: UInt8 = 0x26
  static let exclamation: UInt8 = 0x21
  static let leftSquare: UInt8 = 0x5B
  static let rightSquare: UInt8 = 0x5D
  static let leftBrace: UInt8 = 0x7B
  static let rightBrace: UInt8 = 0x7D
  static let leftAngle: UInt8 = 0x3C
  static let rightAngle: UInt8 = 0x3E

  var isYAMLHorizontalWhitespace: Bool {
    self == 0x20 || self == 0x09
  }

  var isYAMLWhitespace: Bool {
    isYAMLHorizontalWhitespace || isYAMLLineBreak
  }

  var isYAMLLineBreak: Bool {
    self == 0x0A || self == 0x0D
  }
}

private extension ParseBuffer.Region {
  var firstByte: UInt8? {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      return bytes.first
    }
  }

  var firstNonWhitespaceByte: UInt8? {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var offset = 0
      while offset < bytes.count {
        let byte = bytes[offset]
        guard byte == .space || byte == .tab else {
          return byte
        }
        offset += 1
      }
      return nil
    }
  }

  func trimmedHorizontalWhitespace() -> ParseBuffer.Region {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var start = 0
      var end = bytes.count
      while start < end {
        let byte = bytes[start]
        guard byte == .space || byte == .tab else { break }
        start += 1
      }
      while end > start {
        let previous = bytes[end - 1]
        guard previous == .space || previous == .tab else { break }
        end -= 1
      }
      return subregion(start..<end)
    }
  }

  func trimmedTrailingHorizontalWhitespace() -> ParseBuffer.Region {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      var end = bytes.count
      while end > 0 {
        let previous = bytes[end - 1]
        guard previous == .space || previous == .tab else { break }
        end -= 1
      }
      return subregion(0..<end)
    }
  }

  func hasPrefix(_ prefix: StaticString) -> Bool {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      return prefix.withUTF8Buffer { prefixBytes in
        guard prefixBytes.count <= bytes.count else {
          return false
        }
        for offset in 0..<prefixBytes.count where bytes[offset] != prefixBytes[offset] {
          return false
        }
        return true
      }
    }
  }

  func isExactly(_ text: StaticString) -> Bool {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      return text.withUTF8Buffer { textBytes in
        guard bytes.count == textBytes.count else {
          return false
        }
        for offset in 0..<textBytes.count where bytes[offset] != textBytes[offset] {
          return false
        }
        return true
      }
    }
  }

  func containsByte(_ byte: UInt8) -> Bool {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      for candidate in bytes where candidate == byte {
        return true
      }
      return false
    }
  }

  var isSequenceIndicator: Bool {
    indicatorMatches(.dash)
  }

  var isExplicitMappingIndicator: Bool {
    indicatorMatches(.question)
  }

  var isMappingValueIndicator: Bool {
    indicatorMatches(.colon)
  }

  var isBlockScalarIndicator: Bool {
    firstByte == UInt8(ascii: "|") || firstByte == UInt8(ascii: ">")
  }

  var startsFlowCollection: Bool {
    firstByte == .leftSquare || firstByte == .leftBrace
  }

  private func indicatorMatches(_ indicator: UInt8) -> Bool {
    withUnsafeBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.first == indicator else {
        return false
      }
      return bytes.count == 1 || bytes[1].isYAMLWhitespace
    }
  }

  func droppingFirstByte() -> ParseBuffer.Region {
    guard count > 0 else {
      return subregion(0..<0)
    }
    return subregion(1..<count)
  }
}

private extension StringProtocol {
  var yamlQuotedTrimmedHorizontalWhitespace: String {
    var lower = startIndex
    var upper = endIndex
    while lower < upper {
      let character = self[lower]
      guard character == " " || character == "\t" else { break }
      lower = index(after: lower)
    }
    while upper > lower {
      let previous = index(before: upper)
      let character = self[previous]
      guard character == " " || character == "\t" else { break }
      upper = previous
    }
    return String(self[lower..<upper])
  }
}
