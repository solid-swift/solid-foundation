//
//  YAMLStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Async YAML stream writer that consumes ``ValueEvent`` values.
public final class YAMLStreamWriter: FormatStreamWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int

    public init(indent: Int = 2) {
      self.indent = indent
    }
  }

  private enum RootState {
    case expectingValue
    case complete
  }

  private enum ContainerState {
    case array(indent: Int, hasElements: Bool)
    case object(indent: Int, hasEntries: Bool, expectingKey: Bool)
  }

  private let sink: any Sink
  private let bufferSize: Int
  private let options: Options

  private var buffer = Data()
  private var containers: [ContainerState] = []
  private var pendingTags: [Value] = []
  private var rootState: RootState = .expectingValue
  private var finished = false

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public var format: Format { YAML.format }

  public func write(_ event: ValueEvent) async throws {
    guard !finished else { throw YAML.Error.invalidSyntax("Writer already finished") }

    switch event {
    case .tag(let tag):
      pendingTags.append(tag)

    case .key(let key):
      let indent = try await prepareForKey()
      try await writePendingTags()
      try await appendString(serializeValue(key, indent: indent, allowBlock: false))
      try await appendString(":")

    case .scalar(let value):
      let indent = try await prepareForScalarValue()
      try await writePendingTags()
      try await appendString(serializeValue(value, indent: indent, allowBlock: true))
      try finishValue()

    case .beginArray:
      let indent = try await prepareForContainerValue()
      try await writePendingTags()
      containers.append(.array(indent: indent, hasElements: false))

    case .endArray:
      guard let container = containers.popLast() else {
        throw YAML.Error.invalidSyntax("Unexpected endArray")
      }
      guard case .array = container else {
        throw YAML.Error.invalidSyntax("Unexpected endArray")
      }
      try finishValue()

    case .beginObject:
      let indent = try await prepareForContainerValue()
      try await writePendingTags()
      containers.append(.object(indent: indent, hasEntries: false, expectingKey: true))

    case .endObject:
      guard let container = containers.popLast() else {
        throw YAML.Error.invalidSyntax("Unexpected endObject")
      }
      guard case .object(_, _, let expectingKey) = container else {
        throw YAML.Error.invalidSyntax("Unexpected endObject")
      }
      guard expectingKey else {
        throw YAML.Error.invalidSyntax("Missing value for key")
      }
      try finishValue()
    }
  }

  public func finish() async throws {
    guard !finished else { return }
    guard containers.isEmpty, pendingTags.isEmpty, rootState == .complete else {
      throw YAML.Error.invalidSyntax("Incomplete YAML document")
    }
    try await flush()
    finished = true
  }

  public func close() async throws {
    try await finish()
    try await sink.close()
  }

  public func flush() async throws {
    try await sink.write(data: buffer)
    buffer.removeAll(keepingCapacity: true)
  }

  // MARK: - Preparation

  private func indentString(count: Int) -> String {
    String(repeating: " ", count: count)
  }

  private func prepareForKey() async throws -> Int {
    guard let container = containers.popLast() else {
      throw YAML.Error.invalidSyntax("Key outside object")
    }
    guard case .object(let indent, let hasEntries, let expectingKey) = container else {
      throw YAML.Error.invalidSyntax("Key outside object")
    }
    guard expectingKey else {
      throw YAML.Error.invalidSyntax("Unexpected key")
    }
    if hasEntries {
      try await appendString("\n")
    } else if !buffer.isEmpty {
      try await appendString("\n")
    }
    try await appendString(indentString(count: indent))
    containers.append(.object(indent: indent, hasEntries: true, expectingKey: false))
    return indent
  }

  private func prepareForScalarValue() async throws -> Int {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw YAML.Error.invalidSyntax("Multiple root values")
      }
      return 0
    }
    guard let container = containers.popLast() else {
      throw YAML.Error.invalidSyntax("Invalid container state")
    }

    switch container {
    case .array(let indent, let hasElements):
      if hasElements || !buffer.isEmpty {
        try await appendString("\n")
      }
      try await appendString(indentString(count: indent))
      try await appendString("- ")
      containers.append(.array(indent: indent, hasElements: true))
      return indent + options.indent

    case .object(let indent, let hasEntries, let expectingKey):
      guard !expectingKey else {
        throw YAML.Error.invalidSyntax("Unexpected value before key")
      }
      containers.append(.object(indent: indent, hasEntries: hasEntries, expectingKey: true))
      try await appendString(" ")
      return indent + options.indent
    }
  }

  private func prepareForContainerValue() async throws -> Int {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw YAML.Error.invalidSyntax("Multiple root values")
      }
      return 0
    }
    guard let container = containers.popLast() else {
      throw YAML.Error.invalidSyntax("Invalid container state")
    }

    switch container {
    case .array(let indent, let hasElements):
      if hasElements || !buffer.isEmpty {
        try await appendString("\n")
      }
      try await appendString(indentString(count: indent))
      try await appendString("-")
      try await appendString("\n")
      try await appendString(indentString(count: indent + options.indent))
      containers.append(.array(indent: indent, hasElements: true))
      return indent + options.indent

    case .object(let indent, let hasEntries, let expectingKey):
      guard !expectingKey else {
        throw YAML.Error.invalidSyntax("Unexpected value before key")
      }
      try await appendString("\n")
      try await appendString(indentString(count: indent + options.indent))
      containers.append(.object(indent: indent, hasEntries: hasEntries, expectingKey: false))
      return indent + options.indent
    }
  }

  private func finishValue() throws {
    if containers.isEmpty {
      rootState = .complete
      return
    }
    guard let container = containers.popLast() else {
      return
    }
    switch container {
    case .array(let indent, let hasElements):
      containers.append(.array(indent: indent, hasElements: hasElements))
    case .object(let indent, let hasEntries, _):
      containers.append(.object(indent: indent, hasEntries: hasEntries, expectingKey: true))
    }
  }

  private func writePendingTags() async throws {
    guard !pendingTags.isEmpty else { return }
    let tags = pendingTags.map { formatTag($0) }.joined(separator: " ")
    try await appendString(tags)
    try await appendString(pendingTags.count > 0 ? " " : "")
    pendingTags.removeAll(keepingCapacity: true)
  }

  // MARK: - Serialization

  private func serializeValue(_ value: Value, indent: Int, allowBlock: Bool) -> String {
    switch value {
    case .null:
      return "null"
    case .bool(let bool):
      return bool ? "true" : "false"
    case .number(let number):
      return number.description
    case .bytes(let data):
      return "\"\(data.base64EncodedString())\""
    case .string(let string):
      return serializeString(string, indent: indent, allowBlock: allowBlock)
    case .array(let array):
      if array.isEmpty {
        return "[]"
      }
      let contents = array.map { serializeValue($0, indent: indent + options.indent, allowBlock: false) }
      return "[\(contents.joined(separator: ", "))]"
    case .object(let object):
      if object.isEmpty {
        return "{}"
      }
      let contents = object.map { key, val in
        let keyText = serializeValue(key, indent: indent + options.indent, allowBlock: false)
        let valText = serializeValue(val, indent: indent + options.indent, allowBlock: false)
        return "\(keyText): \(valText)"
      }
      return "{\(contents.joined(separator: ", "))}"
    case .tagged(let tag, let inner):
      let tagText = formatTag(tag)
      let innerText = serializeValue(inner, indent: indent, allowBlock: allowBlock)
      return "\(tagText) \(innerText)"
    }
  }

  private func serializeString(_ string: String, indent: Int, allowBlock: Bool) -> String {
    if allowBlock, string.contains("\n") {
      var result = "|\n"
      let padding = indentString(count: indent + options.indent)
      let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
      for line in lines {
        result.append(padding)
        result.append(contentsOf: line)
        result.append("\n")
      }
      return result
    }

    let requiresQuotes = string.isEmpty ||
      string.first?.isWhitespace == true ||
      string.contains(where: { ":{}[],#&*!|>'\"%@`".contains($0) }) ||
      string.contains("\n")

    if !requiresQuotes {
      return string
    }

    var escaped = "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"":
        escaped.append("\\\"")
      case "\\":
        escaped.append("\\\\")
      case "\n":
        escaped.append("\\n")
      case "\r":
        escaped.append("\\r")
      case "\t":
        escaped.append("\\t")
      default:
        escaped.append(String(scalar))
      }
    }
    escaped.append("\"")
    return escaped
  }

  private func formatTag(_ value: Value) -> String {
    let tag = value.stringified
    let simple = tag.allSatisfy { $0.isLetter || $0.isNumber || $0 == ":" || $0 == "-" || $0 == "_" || $0 == "/" || $0 == "." }
    if simple {
      return "!\(tag)"
    }
    return "!<\(tag)>"
  }

  // MARK: - Output helpers

  private func appendString(_ string: String) async throws {
    guard let data = string.data(using: .utf8) else {
      throw YAML.Error.invalidUTF8
    }
    buffer.append(data)
    if buffer.count >= bufferSize {
      try await flushIfNeeded()
    }
  }

  private func flushIfNeeded() async throws {
    if buffer.count >= bufferSize {
      try await sink.write(data: buffer)
      buffer.removeAll(keepingCapacity: true)
    }
  }
}
