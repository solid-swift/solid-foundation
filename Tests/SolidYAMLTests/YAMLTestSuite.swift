//
//  YAMLTestSuite.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidData
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

  private static let filteredCases: [Case] = {
    let env = ProcessInfo.processInfo.environment
    var filtered = cases
    if let raw = env["YAML_TEST_CASES"], !raw.isEmpty {
      let ids = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
      filtered = filtered.filter { ids.contains($0.id) }
    }
    if let prefix = env["YAML_TEST_CASE_PREFIX"], !prefix.isEmpty {
      filtered = filtered.filter { $0.id.hasPrefix(prefix) }
    }
    if let rawLimit = env["YAML_TEST_CASE_LIMIT"], let limit = Int(rawLimit), limit >= 0 {
      filtered = Array(filtered.prefix(limit))
    }
    return filtered
  }()

  private static let defaultMaxResidentBytes: UInt64 = 16 * 1024 * 1024 * 1024
  private static let maxResidentBytes: UInt64? = parseMemoryLimit(from: "YAML_TEST_CASE_MEM_LIMIT")

  @Test("Suite availability")
  func suiteAvailability() {
    #expect(!Self.filteredCases.isEmpty, "No YAML test suite cases discovered")
  }

  // Enable specific expected-fail cases when the parser reports errors reliably.
  private static let failingCases: [Case] = filteredCases.filter { $0.shouldFail }
  private static let passingCases: [Case] = filteredCases.filter {
    !$0.shouldFail &&
      FileManager.default.fileExists(atPath: $0.directory.appendingPathComponent("in.json").path)
  }
  private static let eventCases: [Case] = filteredCases.filter {
    !$0.shouldFail &&
      FileManager.default.fileExists(atPath: $0.directory.appendingPathComponent("test.event").path)
  }

  @Test("Parse against json expectation", arguments: passingCases)
  func parse(_ testCase: Case) throws {
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
      #expect(Self.equivalent(actual, expected),
              "\(testCase.id): value mismatch (actual: \(actual), expected: \(expected))")
      if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
        try #require(bytes <= limit,
                     "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in parse \(testCase.id): \(String(format: "%.2f", gb)) GB")
      }
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
        try #require(bytes <= limit,
                     "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in reject \(testCase.id): \(String(format: "%.2f", gb)) GB")
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
        throw YAML.Error.invalidUTF8
      }

      var parser = try YAMLParser(text: yamlText)
      let documents = try parser.parseDocumentStream()
      let actual = Self.renderEventLines(from: documents)

      #expect(actual == expected, "\(testCase.id): event stream mismatch")
      if let limit = Self.maxResidentBytes, let bytes = Self.currentMaxResidentBytes() {
        let gb = Double(bytes) / 1024.0 / 1024.0 / 1024.0
        let limitGb = Double(limit) / 1024.0 / 1024.0 / 1024.0
        try #require(bytes <= limit,
                     "Memory usage exceeded \(String(format: "%.2f", limitGb)) GB in events \(testCase.id): \(String(format: "%.2f", gb)) GB")
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

  private static func loadEventLines(from url: URL) throws -> [String] {
    let raw = try String(contentsOf: url, encoding: .utf8)
    return splitEventLines(raw)
  }

  private static func splitEventLines(_ text: String) -> [String] {
    let normalized = text
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
      for (lValue, rValue) in zip(left, right) {
        if !equivalent(lValue, rValue) {
          return false
        }
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
