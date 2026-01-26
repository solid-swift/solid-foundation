//
//  YAMLTestSuite.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidData
import SolidIO
@testable import SolidJSON
@testable import SolidYAML
import Foundation
import Testing
#if os(Linux)
  import Glibc
#else
  import Darwin
#endif


@Suite("YAML Test Suite")
struct YAMLTestSuite {

  struct Case: Sendable, CustomStringConvertible, Identifiable {
    let id: String
    let title: String
    let directory: URL
    let shouldFail: Bool

    var description: String { "\(id) - \(title)" }
  }

  private static let suiteDirectory =
    URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/yaml-test-suite", isDirectory: true)

  private static let cases: [Case] = {
    let root = suiteDirectory
    var results: [Case] = []
    let fm = FileManager.default
    if let enumerator = fm.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      for case let url as URL in enumerator {
        guard
          (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
          let title = try? String(contentsOf: url.appending(path: "==="), encoding: .utf8)
        else {
          continue
        }
        let relPath =
          url.path().replacingOccurrences(of: root.path(), with: "")
          .trimmingSuffix { $0 == "/" }
          .split(separator: "/")
        let id = relPath.joined(separator: "-")
        let shouldFail = (try? url.appendingPathComponent("error").checkResourceIsReachable()) == true
        results.append(.init(id: id, title: title, directory: url, shouldFail: shouldFail))
      }
    }
    return results.sorted { $0.id < $1.id }
  }()

  private static let filteredCases: [Case] = cases

  private static let defaultMaxResidentBytes: UInt64 = 16 * 1024 * 1024 * 1024
  private static let maxResidentBytes: UInt64? = parseMemoryLimit(from: "YAML_TEST_CASE_MEM_LIMIT")
  private static let debugEmitCaseID = ProcessInfo.processInfo.environment["YAML_EMIT_DEBUG_CASE"]

  @Test("Suite availability")
  func suiteAvailability() {
    #expect(!Self.filteredCases.isEmpty, "No YAML test suite cases discovered")
  }

  // Enable specific expected-fail cases when the parser reports errors reliably.
  private static let failingCases: [Case] = filteredCases.filter { $0.shouldFail }
  private static let passingCases: [Case] = filteredCases.filter {
    !$0.shouldFail && FileManager.default.fileExists(atPath: $0.directory.appendingPathComponent("in.json").path)
  }
  private static let eventCases: [Case] = filteredCases.filter {
    !$0.shouldFail && FileManager.default.fileExists(atPath: $0.directory.appendingPathComponent("test.event").path)
  }
  private static let emitEventCases: [Case] = filteredCases.filter { testCase in
    guard
      !testCase.shouldFail,
      FileManager.default.fileExists(atPath: testCase.directory.appendingPathComponent("test.event").path)
    else {
      return false
    }
    let expectedURL = expectedEmitURL(for: testCase)
    guard FileManager.default.fileExists(atPath: expectedURL.path) else {
      return false
    }
    return true
  }
  private static let emitCases: [Case] = filteredCases.filter { testCase in
    guard
      !testCase.shouldFail,
      FileManager.default.fileExists(atPath: testCase.directory.appendingPathComponent("in.json").path)
    else {
      return false
    }
    let emitURL = testCase.directory.appendingPathComponent("emit.yaml")
    let expectedURL =
      FileManager.default.fileExists(atPath: emitURL.path)
      ? emitURL
      : testCase.directory.appendingPathComponent("in.yaml")
    guard FileManager.default.fileExists(atPath: expectedURL.path) else {
      return false
    }
    return hasSingleDocument(at: expectedURL)
  }

  @Test("Parse against json expectation", arguments: passingCases)
  func parseValue(_ testCase: Case) throws {
    try autoreleasepool {
      let jsonURL = testCase.directory.appendingPathComponent("in.json")
      #expect(FileManager.default.fileExists(atPath: jsonURL.path), "\(testCase.id): missing in.json")

      let yamlURL = testCase.directory.appendingPathComponent("in.yaml")
      let yamlData = try Data(contentsOf: yamlURL)
      let jsonData = try Data(contentsOf: jsonURL)

      let value = try YAMLValueReader(data: yamlData).read()
      let expected: Value
      if jsonData.isEmpty || jsonData.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
        expected = .null
      } else {
        expected = try JSONValueReader(data: jsonData).read()
      }
      let actual = Self.stripTags(from: value)
      #expect(
        Self.equivalent(actual, expected),
        "\(testCase.id): value mismatch (actual: \(actual), expected: \(expected))"
      )
      if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
        try #require(
          bytes <= limit,
          "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in parse \(testCase.id): \(String(format: "%.2f", gb)) GB"
        )
      }
    }
  }

  @Test("Emit against json expectations", .serialized, arguments: emitCases)
  func emitValue(_ testCase: Case) throws {
    try autoreleasepool {
      let jsonURL = testCase.directory.appendingPathComponent("in.json")
      #expect(FileManager.default.fileExists(atPath: jsonURL.path), "\(testCase.id): missing in.json")
      let jsonData = try Data(contentsOf: jsonURL)
      let reader = JSONValueReader(data: jsonData)
      let value = try reader.read()

      let emitURL = testCase.directory.appendingPathComponent("emit.yaml")
      let expectedURL =
        FileManager.default.fileExists(atPath: emitURL.path)
        ? emitURL
        : testCase.directory.appendingPathComponent("in.yaml")
      let expectedData = try Data(contentsOf: expectedURL)
      let writer = YAMLValueWriter(options: .default)
      try writer.write(value)
      let actualData = writer.data()

      let expectedValue = try Self.readSingleDocumentValue(from: expectedData, label: "expected", testCase: testCase)
      let actualValue = try Self.readSingleDocumentValue(from: actualData, label: "actual", testCase: testCase)

      let expected = Self.stripTags(from: expectedValue)
      let actual = Self.stripTags(from: actualValue)
      #expect(
        Self.equivalent(actual, expected),
        "\(testCase.id): value mismatch (actual: \(actual), expected: \(expected))"
      )

      if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
        try #require(
          bytes <= limit,
          "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in emit \(testCase.id): \(String(format: "%.2f", gb)) GB"
        )
      }
    }
  }

  @Test("Parse event stream", arguments: eventCases)
  func parseEvents(_ testCase: Case) throws {
    try autoreleasepool {
      let yamlURL = testCase.directory.appendingPathComponent("in.yaml")
      let eventURL = testCase.directory.appendingPathComponent("test.event")
      let yamlData = try Data(contentsOf: yamlURL)
      let expected = try Self.loadEventLines(from: eventURL)

      guard let yamlText = String(data: yamlData, encoding: .utf8) else {
        throw YAML.DataError.invalidEncoding(.utf8)
      }

      var parser = try YAMLParser(text: yamlText)
      let documents = try parser.parseDocumentStream()
      let actual = Self.renderEventLines(from: documents)

      #expect(actual == expected, "\(testCase.id): event stream mismatch")
      if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
        try #require(
          bytes <= limit,
          "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in events \(testCase.id): \(String(format: "%.2f", gb)) GB"
        )
      }
    }
  }

  @Test("Emit event stream", .serialized, arguments: emitEventCases)
  func emitEvents(_ testCase: Case) async throws {
    let eventURL = testCase.directory.appendingPathComponent("test.event")
    let expectedURL = Self.expectedEmitURL(for: testCase)
    let expectedData = try Data(contentsOf: expectedURL)
    let lines = try Self.loadEventLines(from: eventURL)
    let eventStream = try Self.parseEventStream(from: lines)
    let usesEmitYAML = expectedURL.lastPathComponent == "emit.yaml"
    var renderedDocs: [String] = []
    for document in eventStream.documents {
      let sink = DataSink()
      let writer = YAMLStreamWriter(
        sink: sink,
        options: .init(
          indent: 2,
          allowDocumentMarkerPrefix: !document.explicitStart
        )
      )
      let events = Self.normalizeEmitEvents(
        document.events,
        usesEmitYAML: usesEmitYAML,
        explicitEnd: document.explicitEnd
      )
      for event in events {
        try await writer.write(event)
      }
      try await writer.finish()
      let text = try Self.normalizeYAMLText(String(decoding: sink.data, as: UTF8.self))
      let withMarkers = Self.applyDocumentMarkers(
        to: text,
        explicitStart: document.explicitStart,
        explicitEnd: document.explicitEnd
      )
      renderedDocs.append(withMarkers)
    }

    let actualText = try Self.normalizeYAMLText(renderedDocs.joined(separator: "\n"))
    let expectedText = try Self.normalizeYAMLText(String(decoding: expectedData, as: UTF8.self))
    if let debugID = Self.debugEmitCaseID, debugID == testCase.id {
      print("EmitEvents \(testCase.id) actual:\n\(actualText)")
      print("EmitEvents \(testCase.id) expected:\n\(expectedText)")
      print("EmitEvents \(testCase.id) actual (escaped):\n\(String(reflecting: actualText))")
      print("EmitEvents \(testCase.id) expected (escaped):\n\(String(reflecting: expectedText))")
    }
    let actualDocuments = try Self.parseDocuments(from: actualText)
    let expectedDocuments = try Self.parseDocuments(from: expectedText)
    let actualEvents = Self.normalizeDocumentMarkers(Self.renderEventLines(from: actualDocuments))
    let expectedEvents = Self.normalizeDocumentMarkers(Self.renderEventLines(from: expectedDocuments))
    #expect(actualEvents == expectedEvents, "\(testCase.id): emit event output mismatch")

    if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
      let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
      let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
      try #require(
        bytes <= limit,
        "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in emit events \(testCase.id): \(String(format: "%.2f", gb)) GB"
      )
    }
  }

  @Test("Reject invalid YAML", arguments: failingCases)
  func rejectInvalid(_ testCase: Case) throws {
    try autoreleasepool {
      let yamlURL = testCase.directory.appendingPathComponent("in.yaml")
      let yamlData = try Data(contentsOf: yamlURL)
      #expect(throws: Error.self) {
        _ = try YAMLValueReader(data: yamlData).read()
      }
      if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
        try #require(
          bytes <= limit,
          "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in reject \(testCase.id): \(String(format: "%.2f", gb)) GB"
        )
      }
    }
  }

  private static func parseMemoryLimit(from name: String) -> UInt64? {
    let env = ProcessInfo.processInfo.environment
    guard let raw = env[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return defaultMaxResidentBytes
    }
    let lower = raw.lowercased()
    if lower == "0" || lower == "off" || lower == "none" {
      return nil
    }

    let (number, multiplier): (UInt64?, UInt64) = {
      let units: [(String, UInt64)] = [
        ("kb", 1024),
        ("k", 1024),
        ("mb", 1024 * 1024),
        ("m", 1024 * 1024),
        ("gb", 1024 * 1024 * 1024),
        ("g", 1024 * 1024 * 1024),
      ]
      for (suffix, factor) in units where lower.hasSuffix(suffix) {
        let value = lower.dropLast(suffix.count)
        return (UInt64(value.trimmingCharacters(in: .whitespaces)), factor)
      }
      return (UInt64(lower), 1)
    }()

    guard let number else {
      return defaultMaxResidentBytes
    }
    return number &* multiplier
  }

  private static func currentMaxResidentBytes() -> UInt64? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
      return nil
    }
    #if os(Linux)
      return UInt64(usage.ru_maxrss) * 1024
    #else
      return UInt64(usage.ru_maxrss)
    #endif
  }

  private static func hasSingleDocument(at url: URL) -> Bool {
    guard
      let data = try? Data(contentsOf: url),
      let text = String(data: data, encoding: .utf8),
      var parser = try? YAMLParser(text: text),
      let documents = try? parser.parseDocumentStream()
    else {
      return false
    }
    return documents.count == 1
  }

  private static func readSingleDocumentValue(from data: Data, label: String, testCase: Case) throws -> Value {
    do {
      guard let text = String(data: data, encoding: .utf8) else {
        throw YAML.DataError.invalidEncoding(.utf8)
      }
      var parser = try YAMLParser(text: text)
      let documents = try parser.parseDocumentStream()
      guard documents.count == 1 else {
        throw YAML.ParseError.invalidSyntax("Expected single document for \(label) in \(testCase.id)", location: nil)
      }
      var anchors: [String: Value] = [:]
      return try documents[0].node.toValue(anchors: &anchors)
    } catch {
      throw YAML.ParseError.invalidSyntax("Failed to parse \(label) YAML for \(testCase.id): \(error)", location: nil)
    }
  }

  private static func loadEventLines(from url: URL) throws -> [String] {
    let raw = try String(contentsOf: url, encoding: .utf8)
    return splitEventLines(raw)
  }

  private static func splitEventLines(_ text: String) -> [String] {
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" {
      lines.removeLast()
    }
    return lines
  }

  private static func renderEventLines(from documents: [YAMLDocument]) -> [String] {
    var lines: [String] = []
    lines.append("+STR")
    for document in documents {
      lines.append(document.explicitStart ? "+DOC ---" : "+DOC")
      emitEventLines(for: document.node, into: &lines)
      lines.append(document.explicitEnd ? "-DOC ..." : "-DOC")
    }
    lines.append("-STR")
    return lines
  }

  private static func emitEventLines(for node: YAMLNode, into lines: inout [String]) {
    switch node {
    case .alias(let name):
      lines.append("=ALI *\(name)")
    case .scalar(let scalar, let tag, let anchor):
      lines.append(formatScalarEvent(scalar, tag: tag, anchor: anchor))
    case .sequence(let items, let style, let tag, let anchor):
      lines.append(formatCollectionEvent(kind: "+SEQ", style: style, tag: tag, anchor: anchor))
      for item in items {
        emitEventLines(for: item, into: &lines)
      }
      lines.append("-SEQ")
    case .mapping(let pairs, let style, let tag, let anchor):
      lines.append(formatCollectionEvent(kind: "+MAP", style: style, tag: tag, anchor: anchor))
      for (key, value) in pairs {
        emitEventLines(for: key, into: &lines)
        emitEventLines(for: value, into: &lines)
      }
      lines.append("-MAP")
    }
  }

  private static func formatCollectionEvent(
    kind: String,
    style: YAMLCollectionStyle,
    tag: String?,
    anchor: String?
  ) -> String {
    var parts: [String] = [kind]
    if style == .flow {
      parts.append(kind == "+SEQ" ? "[]" : "{}")
    }
    if let anchor {
      parts.append("&\(anchor)")
    }
    if let tag {
      parts.append(formatEventTag(tag))
    }
    return parts.joined(separator: " ")
  }

  private static func formatScalarEvent(_ scalar: YAMLScalar, tag: String?, anchor: String?) -> String {
    var parts: [String] = ["=VAL"]
    if let anchor {
      parts.append("&\(anchor)")
    }
    if let tag {
      parts.append(formatEventTag(tag))
    }
    let styleToken = scalarStyleToken(scalar.style)
    let value = escapeEventScalarText(scalar.text)
    parts.append("\(styleToken)\(value)")
    return parts.joined(separator: " ")
  }

  private static func scalarStyleToken(_ style: YAMLScalarStyle) -> String {
    switch style {
    case .plain:
      return ":"
    case .singleQuoted:
      return "'"
    case .doubleQuoted:
      return "\""
    case .literal:
      return "|"
    case .folded:
      return ">"
    }
  }

  private static func escapeEventScalarText(_ text: String) -> String {
    var output = ""
    output.reserveCapacity(text.count)
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x5C:
        output.append("\\\\")
      case 0x0A:
        output.append("\\n")
      case 0x09:
        output.append("\\t")
      case 0x0D:
        output.append("\\r")
      case 0x08:
        output.append("\\b")
      case 0x0C:
        output.append("\\f")
      default:
        output.unicodeScalars.append(scalar)
      }
    }
    return output
  }

  private static func formatEventTag(_ tag: String) -> String {
    "<\(tag)>"
  }

  private static func expectedEmitURL(for testCase: Case) -> URL {
    let emitURL = testCase.directory.appendingPathComponent("emit.yaml")
    if FileManager.default.fileExists(atPath: emitURL.path) {
      return emitURL
    }
    return testCase.directory.appendingPathComponent("in.yaml")
  }

  private static func normalizeYAMLText(_ text: String) throws -> String {
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return normalized
  }

  private static func parseDocuments(from text: String) throws -> [YAMLDocument] {
    var parser = try YAMLParser(text: text)
    return try parser.parseDocumentStream()
  }

  private static func normalizeDocumentMarkers(_ lines: [String]) -> [String] {
    lines.map { line in
      if line.hasPrefix("+DOC") {
        return "+DOC"
      }
      if line.hasPrefix("-DOC") {
        return "-DOC"
      }
      if line.hasPrefix("+SEQ") || line.hasPrefix("+MAP") {
        let normalized =
          line
          .replacingOccurrences(of: " []", with: "")
          .replacingOccurrences(of: " {}", with: "")
        let parts = normalized.split(whereSeparator: { $0.isWhitespace })
        guard let head = parts.first else {
          return normalized
        }
        let filtered = parts.dropFirst().filter { $0 != "[]" && $0 != "{}" }
        if filtered.isEmpty {
          return String(head)
        }
        return ([String(head)] + filtered.map(String.init)).joined(separator: " ")
      }
      return line
    }
  }

  private static func normalizeEmitEvents(
    _ events: [ValueEvent],
    usesEmitYAML: Bool,
    explicitEnd: Bool
  ) -> [ValueEvent] {
    guard usesEmitYAML, !explicitEnd, events.count == 2 else {
      return events
    }
    guard case .style(.scalar(.plain)) = events[0] else {
      return events
    }
    guard case .scalar(.string(let text)) = events[1], text.isEmpty else {
      return events
    }
    return [.style(.scalar(.plain)), .scalar(.null)]
  }

  private static func applyDocumentMarkers(
    to text: String,
    explicitStart: Bool,
    explicitEnd: Bool
  ) -> String {
    var output = text
    if explicitStart {
      if output.isEmpty {
        output = "---"
      } else if let newline = output.firstIndex(of: "\n") {
        let firstLine = String(output[..<newline])
        let rest = String(output[output.index(after: newline)...])
        if canInlineHeaderLine(firstLine) {
          output = rest.isEmpty ? "--- \(firstLine)" : "--- \(firstLine)\n\(rest)"
        } else {
          output = "---\n\(output)"
        }
      } else if shouldInlineDocumentStart(for: output) {
        output = "--- \(output)"
      } else {
        output = "---\n\(output)"
      }
    }
    if explicitEnd {
      if !output.isEmpty, !output.hasSuffix("\n") {
        output.append("\n")
      }
      output.append("...")
    }
    return output
  }

  private static func shouldInlineDocumentStart(for text: String) -> Bool {
    guard !text.isEmpty else { return false }
    if text.contains("\n") {
      return false
    }
    if text.hasPrefix("-") || text.hasPrefix("?") {
      return false
    }
    if containsKeySeparator(text) {
      return false
    }
    return true
  }

  private static func canInlineHeaderLine(_ line: String) -> Bool {
    guard let first = line.first else { return false }
    return first == "!" || first == "&" || first == "|" || first == ">" || first == "'" || first == "\""
  }

  private static func containsKeySeparator(_ text: String) -> Bool {
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == ":" {
        let next = text.index(after: index)
        if next == text.endIndex || text[next].isWhitespace {
          return true
        }
      }
      index = text.index(after: index)
    }
    return false
  }

  private struct ParsedEventDocument {
    let explicitStart: Bool
    let explicitEnd: Bool
    let events: [ValueEvent]
  }

  private struct ParsedEventStream {
    let documents: [ParsedEventDocument]
  }

  private static func parseEventStream(from lines: [String]) throws -> ParsedEventStream {
    guard lines.first == "+STR", lines.last == "-STR" else {
      throw YAML.ParseError.invalidSyntax("Invalid event stream boundaries", location: nil)
    }

    var documents: [ParsedEventDocument] = []
    var explicitStart = false
    var builder: EventNodeBuilder? = nil

    var index = 1
    while index < lines.count - 1 {
      let line = lines[index]
      if line.hasPrefix("+DOC") {
        guard builder == nil else {
          throw YAML.ParseError.invalidSyntax("Nested document start", location: nil)
        }
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        explicitStart = parts.contains("---")
        builder = EventNodeBuilder()
        index += 1
        continue
      }
      if line.hasPrefix("-DOC") {
        guard var activeBuilder = builder else {
          throw YAML.ParseError.invalidSyntax("Document end without start", location: nil)
        }
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        let explicitEnd = parts.contains("...")
        let node = try activeBuilder.finish()
        var emitter = EventNodeEmitter()
        let events = try emitter.emit(node: node)
        documents.append(.init(explicitStart: explicitStart, explicitEnd: explicitEnd, events: events))
        builder = nil
        index += 1
        continue
      }

      guard var activeBuilder = builder else {
        throw YAML.ParseError.invalidSyntax("Missing document start", location: nil)
      }

      if line.hasPrefix("+SEQ") {
        let info = try parseCollectionEvent(line: line)
        try activeBuilder.beginSequence(style: info.style, tags: info.tags, anchor: info.anchor)
      } else if line.hasPrefix("-SEQ") {
        try activeBuilder.endSequence()
      } else if line.hasPrefix("+MAP") {
        let info = try parseCollectionEvent(line: line)
        try activeBuilder.beginMapping(style: info.style, tags: info.tags, anchor: info.anchor)
      } else if line.hasPrefix("-MAP") {
        try activeBuilder.endMapping()
      } else if line.hasPrefix("=VAL") {
        let info = try parseScalarEvent(line: line)
        try activeBuilder.scalar(info.scalar, tags: info.tags, anchor: info.anchor)
      } else if line.hasPrefix("=ALI") {
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2, parts[1].first == "*" else {
          throw YAML.ParseError.invalidSyntax("Invalid alias event", location: nil)
        }
        let name = String(parts[1].dropFirst())
        try activeBuilder.alias(name)
      } else if line == "+STR" || line == "-STR" {
        break
      }

      builder = activeBuilder
      index += 1
    }

    guard builder == nil else {
      throw YAML.ParseError.invalidSyntax("Unclosed document", location: nil)
    }

    return ParsedEventStream(documents: documents)
  }

  private struct ParsedScalarEvent {
    let tags: [String]
    let anchor: String?
    let scalar: YAMLScalar
  }

  private struct ParsedCollectionEvent {
    let tags: [String]
    let anchor: String?
    let style: YAMLCollectionStyle
  }

  private static func parseScalarEvent(line: String) throws -> ParsedScalarEvent {
    let prefix = "=VAL"
    guard line.hasPrefix(prefix) else {
      throw YAML.ParseError.invalidSyntax("Invalid scalar event", location: nil)
    }
    var cursor = line.index(line.startIndex, offsetBy: prefix.count)
    skipSpaces(in: line, cursor: &cursor)

    var tags: [String] = []
    var anchor: String?

    while cursor < line.endIndex {
      let ch = line[cursor]
      if isStyleIndicator(ch) {
        break
      }
      if ch == "&" {
        let token = readToken(from: line, start: cursor)
        if anchor != nil {
          throw YAML.ParseError.invalidSyntax("Duplicate anchor", location: nil)
        }
        anchor = String(token.text.dropFirst())
        cursor = token.end
        skipSpaces(in: line, cursor: &cursor)
        continue
      }
      if ch == "<" || ch == "!" {
        let token = readToken(from: line, start: cursor)
        let tagText = normalizeTagToken(token.text)
        tags.append(tagText)
        cursor = token.end
        skipSpaces(in: line, cursor: &cursor)
        continue
      }
      break
    }

    guard cursor < line.endIndex else {
      throw YAML.ParseError.invalidSyntax("Missing scalar style", location: nil)
    }
    let styleChar = line[cursor]
    guard isStyleIndicator(styleChar) else {
      throw YAML.ParseError.invalidSyntax("Invalid scalar style", location: nil)
    }
    cursor = line.index(after: cursor)
    let value = String(line[cursor...])
    let scalarText = unescapeEventScalarText(value)
    let style = scalarStyle(from: styleChar)
    return ParsedScalarEvent(tags: tags, anchor: anchor, scalar: YAMLScalar(text: scalarText, style: style))
  }

  private static func parseCollectionEvent(line: String) throws -> ParsedCollectionEvent {
    let parts = line.split(whereSeparator: { $0.isWhitespace })
    guard let first = parts.first, first == "+SEQ" || first == "+MAP" else {
      throw YAML.ParseError.invalidSyntax("Invalid collection event", location: nil)
    }
    var tags: [String] = []
    var anchor: String?
    var style: YAMLCollectionStyle = .block
    for token in parts.dropFirst() {
      if token == "[]" || token == "{}" {
        style = .flow
        continue
      }
      if token.first == "&" {
        if anchor != nil {
          throw YAML.ParseError.invalidSyntax("Duplicate anchor", location: nil)
        }
        anchor = String(token.dropFirst())
        continue
      }
      if token.first == "<" || token.first == "!" {
        tags.append(normalizeTagToken(String(token)))
        continue
      }
    }
    return ParsedCollectionEvent(tags: tags, anchor: anchor, style: style)
  }

  private static func isStyleIndicator(_ ch: Character) -> Bool {
    ch == ":" || ch == "'" || ch == "\"" || ch == "|" || ch == ">"
  }

  private static func scalarStyle(from ch: Character) -> YAMLScalarStyle {
    switch ch {
    case ":":
      return .plain
    case "'":
      return .singleQuoted
    case "\"":
      return .doubleQuoted
    case "|":
      return .literal(chomp: .clip, indent: nil)
    case ">":
      return .folded(chomp: .clip, indent: nil)
    default:
      return .plain
    }
  }

  private static func skipSpaces(in line: String, cursor: inout String.Index) {
    while cursor < line.endIndex, line[cursor].isWhitespace {
      cursor = line.index(after: cursor)
    }
  }

  private struct TokenSlice {
    let text: String
    let end: String.Index
  }

  private static func readToken(from line: String, start: String.Index) -> TokenSlice {
    var cursor = start
    while cursor < line.endIndex, !line[cursor].isWhitespace {
      cursor = line.index(after: cursor)
    }
    let text = String(line[start..<cursor])
    return TokenSlice(text: text, end: cursor)
  }

  private static func normalizeTagToken(_ token: String) -> String {
    if token.first == "<", token.last == ">" {
      return String(token.dropFirst().dropLast())
    }
    if token.hasPrefix("!!") {
      return "tag:yaml.org,2002:\(token.dropFirst(2))"
    }
    return token
  }

  private static func unescapeEventScalarText(_ text: String) -> String {
    var output = ""
    output.reserveCapacity(text.count)
    var index = text.startIndex
    while index < text.endIndex {
      let ch = text[index]
      if ch == "\\" {
        let next = text.index(after: index)
        guard next < text.endIndex else {
          output.append("\\")
          break
        }
        switch text[next] {
        case "n":
          output.append("\n")
        case "t":
          output.append("\t")
        case "r":
          output.append("\r")
        case "b":
          output.append("\u{8}")
        case "f":
          output.append("\u{c}")
        case "\\":
          output.append("\\")
        default:
          output.append(text[next])
        }
        index = text.index(after: next)
      } else {
        output.append(ch)
        index = text.index(after: index)
      }
    }
    return output
  }

  private struct EventNodeBuilder {
    private enum Container {
      case sequence(items: [YAMLNode], style: YAMLCollectionStyle, tag: String?, anchor: String?)
      case mapping(
        pairs: [(YAMLNode, YAMLNode)],
        expectingKey: Bool,
        currentKey: YAMLNode?,
        style: YAMLCollectionStyle,
        tag: String?,
        anchor: String?
      )
    }

    private var stack: [Container] = []
    private var root: YAMLNode?

    mutating func beginSequence(style: YAMLCollectionStyle, tags: [String], anchor: String?) throws {
      stack.append(.sequence(items: [], style: style, tag: tags.first, anchor: anchor))
    }

    mutating func endSequence() throws {
      guard case .sequence(let items, let style, let tag, let anchor) = stack.popLast() else {
        throw YAML.ParseError.invalidSyntax("Unexpected end of sequence", location: nil)
      }
      try appendNode(.sequence(items, style: style, tag: tag, anchor: anchor))
    }

    mutating func beginMapping(style: YAMLCollectionStyle, tags: [String], anchor: String?) throws {
      stack.append(
        .mapping(
          pairs: [],
          expectingKey: true,
          currentKey: nil,
          style: style,
          tag: tags.first,
          anchor: anchor
        )
      )
    }

    mutating func endMapping() throws {
      guard case .mapping(let pairs, let expectingKey, let currentKey, let style, let tag, let anchor) = stack.popLast()
      else {
        throw YAML.ParseError.invalidSyntax("Unexpected end of mapping", location: nil)
      }
      guard expectingKey, currentKey == nil else {
        throw YAML.ParseError.invalidSyntax("Missing value for key", location: nil)
      }
      try appendNode(.mapping(pairs, style: style, tag: tag, anchor: anchor))
    }

    mutating func scalar(_ scalar: YAMLScalar, tags: [String], anchor: String?) throws {
      try appendNode(.scalar(scalar, tag: tags.first, anchor: anchor))
    }

    mutating func alias(_ name: String) throws {
      try appendNode(.alias(name))
    }

    mutating func finish() throws -> YAMLNode {
      guard stack.isEmpty, let root else {
        throw YAML.ParseError.invalidSyntax("Unclosed collection in event stream", location: nil)
      }
      return root
    }

    private mutating func appendNode(_ node: YAMLNode) throws {
      guard var container = stack.popLast() else {
        guard root == nil else {
          throw YAML.ParseError.invalidSyntax("Multiple root values", location: nil)
        }
        root = node
        return
      }

      switch container {
      case .sequence(var items, let style, let tag, let anchor):
        items.append(node)
        container = .sequence(items: items, style: style, tag: tag, anchor: anchor)

      case .mapping(var pairs, let expectingKey, let currentKey, let style, let tag, let anchor):
        if expectingKey {
          container = .mapping(
            pairs: pairs,
            expectingKey: false,
            currentKey: node,
            style: style,
            tag: tag,
            anchor: anchor
          )
        } else {
          guard let key = currentKey else {
            throw YAML.ParseError.invalidSyntax("Missing key for value", location: nil)
          }
          pairs.append((key, node))
          container = .mapping(
            pairs: pairs,
            expectingKey: true,
            currentKey: nil,
            style: style,
            tag: tag,
            anchor: anchor
          )
        }
      }
      stack.append(container)
    }
  }

  private struct EventNodeEmitter {
    private var events: [ValueEvent] = []
    private var anchors: [String: Value] = [:]

    mutating func emit(node: YAMLNode) throws -> [ValueEvent] {
      events.removeAll(keepingCapacity: true)
      anchors.removeAll(keepingCapacity: true)
      try emitNode(node)
      return events
    }

    private mutating func emitNode(_ node: YAMLNode) throws {
      switch node {
      case .alias(let name):
        events.append(.alias(name))

      case .scalar(let scalar, let tag, let anchor):
        if let tag {
          events.append(.tag(.string(tag)))
        }
        if let anchor {
          events.append(.anchor(anchor))
        }
        events.append(.style(.scalar(mapScalarStyle(scalar.style))))
        events.append(.scalar(resolveScalar(scalar, tag: tag)))
        if let anchor {
          anchors[anchor] = try nodeToValue(node, includeTag: true)
        }

      case .sequence(let items, let style, let tag, let anchor):
        if let tag {
          events.append(.tag(.string(tag)))
        }
        if let anchor {
          events.append(.anchor(anchor))
        }
        events.append(.style(.collection(mapCollectionStyle(style))))
        events.append(.beginArray)
        for item in items {
          try emitNode(item)
        }
        events.append(.endArray)
        if let anchor {
          anchors[anchor] = try nodeToValue(node, includeTag: true)
        }

      case .mapping(let pairs, let style, let tag, let anchor):
        if let tag {
          events.append(.tag(.string(tag)))
        }
        if let anchor {
          events.append(.anchor(anchor))
        }
        events.append(.style(.collection(mapCollectionStyle(style))))
        events.append(.beginObject)
        for (keyNode, valueNode) in pairs {
          try emitKey(keyNode)
          try emitNode(valueNode)
        }
        events.append(.endObject)
        if let anchor {
          anchors[anchor] = try nodeToValue(node, includeTag: true)
        }
      }
    }

    private mutating func emitKey(_ node: YAMLNode) throws {
      if case .alias(let name) = node {
        events.append(.alias(name))
        return
      }
      if let tag = nodeTag(node) {
        events.append(.tag(.string(tag)))
      }
      if let anchor = nodeAnchor(node) {
        events.append(.anchor(anchor))
        anchors[anchor] = try nodeToValue(node, includeTag: true)
      }
      if case .scalar(let scalar, _, _) = node {
        events.append(.style(.scalar(mapScalarStyle(scalar.style))))
      }
      let value = try nodeToValueWithAnchors(node, includeTag: false, includeAnchor: false)
      events.append(.key(value))
    }

    private func nodeTag(_ node: YAMLNode) -> String? {
      switch node {
      case .scalar(_, let tag, _):
        return tag
      case .sequence(_, _, let tag, _):
        return tag
      case .mapping(_, _, let tag, _):
        return tag
      case .alias:
        return nil
      }
    }

    private func nodeAnchor(_ node: YAMLNode) -> String? {
      switch node {
      case .scalar(_, _, let anchor):
        return anchor
      case .sequence(_, _, _, let anchor):
        return anchor
      case .mapping(_, _, _, let anchor):
        return anchor
      case .alias:
        return nil
      }
    }

    private func mapScalarStyle(_ style: YAMLScalarStyle) -> ValueScalarStyle {
      switch style {
      case .plain:
        return .plain
      case .singleQuoted:
        return .singleQuoted
      case .doubleQuoted:
        return .doubleQuoted
      case .literal:
        return .literal
      case .folded:
        return .folded
      }
    }

    private func mapCollectionStyle(_ style: YAMLCollectionStyle) -> ValueCollectionStyle {
      switch style {
      case .block:
        return .block
      case .flow:
        return .flow
      }
    }

    private mutating func nodeToValue(_ node: YAMLNode, includeTag: Bool) throws -> Value {
      switch node {
      case .alias(let name):
        guard let value = anchors[name] else {
          throw YAML.ParseError.unresolvedAlias(name)
        }
        return value

      case .scalar(let scalar, let tag, _):
        var value = resolveScalar(scalar, tag: tag)
        if includeTag, let tag {
          value = .tagged(tag: .string(tag), value: value)
        }
        if let anchor = nodeAnchor(node) {
          anchors[anchor] = value
        }
        return value

      case .sequence(let items, _, let tag, _):
        let values = try items.map { try nodeToValue($0, includeTag: true) }
        var value: Value = .array(values)
        if includeTag, let tag {
          value = .tagged(tag: .string(tag), value: value)
        }
        if let anchor = nodeAnchor(node) {
          anchors[anchor] = value
        }
        return value

      case .mapping(let pairs, _, let tag, _):
        var object = Value.Object()
        for (keyNode, valueNode) in pairs {
          let keyValue = try nodeToValue(keyNode, includeTag: true)
          let value = try nodeToValue(valueNode, includeTag: true)
          object[keyValue] = value
        }
        var value: Value = .object(object)
        if includeTag, let tag {
          value = .tagged(tag: .string(tag), value: value)
        }
        if let anchor = nodeAnchor(node) {
          anchors[anchor] = value
        }
        return value
      }
    }

    private mutating func nodeToValueWithAnchors(
      _ node: YAMLNode,
      includeTag: Bool,
      includeAnchor: Bool
    ) throws -> Value {
      switch node {
      case .alias(let name):
        guard let value = anchors[name] else {
          throw YAML.ParseError.unresolvedAlias(name)
        }
        return value

      case .scalar(let scalar, let tag, let anchor):
        var value = resolveScalar(scalar, tag: tag)
        if includeTag, let tag {
          value = .tagged(tag: .string(tag), value: value)
        }
        let baseValue = value
        if let anchor {
          anchors[anchor] = baseValue
        }
        if includeAnchor, let anchor {
          value = .tagged(tag: .string("\(YAMLStreamWriter.anchorTagPrefix)\(anchor)"), value: baseValue)
        }
        return value

      case .sequence(let items, _, let tag, let anchor):
        let values = try items.map { try nodeToValueWithAnchors($0, includeTag: true, includeAnchor: true) }
        var value: Value = .array(values)
        if includeTag, let tag {
          value = .tagged(tag: .string(tag), value: value)
        }
        let baseValue = value
        if let anchor {
          anchors[anchor] = baseValue
        }
        if includeAnchor, let anchor {
          value = .tagged(tag: .string("\(YAMLStreamWriter.anchorTagPrefix)\(anchor)"), value: baseValue)
        }
        return value

      case .mapping(let pairs, _, let tag, let anchor):
        var object = Value.Object()
        for (keyNode, valueNode) in pairs {
          let keyValue = try nodeToValueWithAnchors(keyNode, includeTag: true, includeAnchor: true)
          let value = try nodeToValueWithAnchors(valueNode, includeTag: true, includeAnchor: true)
          object[keyValue] = value
        }
        var value: Value = .object(object)
        if includeTag, let tag {
          value = .tagged(tag: .string(tag), value: value)
        }
        let baseValue = value
        if let anchor {
          anchors[anchor] = baseValue
        }
        if includeAnchor, let anchor {
          value = .tagged(tag: .string("\(YAMLStreamWriter.anchorTagPrefix)\(anchor)"), value: baseValue)
        }
        return value
      }
    }

    private func resolveScalar(_ scalar: YAMLScalar, tag: String?) -> Value {
      .string(scalar.text)
    }
  }

  private static func stripTags(from value: Value) -> Value {
    switch value {
    case .tagged(_, let inner):
      return stripTags(from: inner)
    case .array(let array):
      return .array(array.map { stripTags(from: $0) })
    case .object(let object):
      var stripped = Value.Object()
      stripped.reserveCapacity(object.count)
      for (key, val) in object {
        stripped[stripTags(from: key)] = stripTags(from: val)
      }
      return .object(stripped)
    case .bytes(let data):
      return .string(data.base64EncodedString())
    default:
      return value
    }
  }

  /// Compare values while ignoring mapping key order to match YAML test suite JSON expectations.
  private static func equivalent(_ lhs: Value, _ rhs: Value) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null):
      return true
    case (.bool(let left), .bool(let right)):
      return left == right
    case (.number(let left), .number(let right)):
      return left.decimal == right.decimal
    case (.string(let left), .string(let right)):
      return left == right
    case (.bytes(let left), .bytes(let right)):
      return left == right
    case (.array(let left), .array(let right)):
      guard left.count == right.count else {
        return false
      }
      for (lValue, rValue) in zip(left, right) where !equivalent(lValue, rValue) {
        return false
      }
      return true
    case (.object(let left), .object(let right)):
      guard left.count == right.count else {
        return false
      }
      for (key, value) in left {
        guard let other = right[key], equivalent(value, other) else {
          return false
        }
      }
      return true
    case (.tagged(let leftTag, let leftValue), .tagged(let rightTag, let rightValue)):
      return equivalent(leftTag, rightTag) && equivalent(leftValue, rightValue)
    default:
      return false
    }
  }

}
