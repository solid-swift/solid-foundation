//
//  YAMLTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidCore
import SolidData
import SolidIO
import SolidYAML
import Testing


@Suite("YAML Tests")
struct YAMLTests {

  struct TestCase: Sendable, CustomStringConvertible, Identifiable {
    let id: String
    let yaml: String
    let value: Value

    var description: String { id }
  }

  struct ErrorCase: Sendable, CustomStringConvertible, Identifiable {
    enum Kind: Sendable {
      case invalidSyntax
      case invalidIndentation
    }

    let id: String
    let yaml: String
    let line: Int
    let column: Int
    let kind: Kind

    var description: String { id }
  }

  static let cases: [TestCase] = [
    .init(
      id: "scalar-string",
      yaml: "hello\n",
      value: "hello"
    ),
    .init(
      id: "sequence",
      yaml: "- 1\n- 2\n- 3\n",
      value: [1, 2, 3]
    ),
    .init(
      id: "mapping",
      yaml: "name: Alice\nactive: true\ncount: 3\n",
      value: [
        "name": "Alice",
        "active": true,
        "count": 3,
      ]
    ),
    .init(
      id: "nested",
      yaml: "person:\n  name: \"Bob\"\n  tags: [a, b]\n",
      value: [
        "person": [
          "name": "Bob",
          "tags": ["a", "b"],
        ]
      ]
    ),
    .init(
      id: "explicit-doc",
      yaml: "---\nfoo: null\nbar: ~\n...\n",
      value: [
        "foo": .null,
        "bar": .null,
      ]
    ),
  ]

  static let errorCases: [ErrorCase] = [
    .init(
      id: "unterminated-double-quote",
      yaml: "\"foo",
      line: 1,
      column: 5,
      kind: .invalidSyntax
    ),
    .init(
      id: "invalid-tag",
      yaml: "!<tag",
      line: 1,
      column: 6,
      kind: .invalidSyntax
    ),
    .init(
      id: "tab-indentation",
      yaml: "\tkey: value\n",
      line: 1,
      column: 2,
      kind: .invalidIndentation
    ),
  ]

  @Test("Parse value", .serialized, arguments: cases)
  func parseValue(_ testCase: TestCase) throws {
    let value = try YAMLValueReader(string: testCase.yaml).read()
    #expect(value == testCase.value, "\(testCase.id): parsed value mismatch")
  }

  @Test("Emit value", arguments: cases)
  func emitValue(_ testCase: TestCase) throws {
    let writer = YAMLValueWriter(options: .default)
    try writer.write(testCase.value)
    let output = writer.data()
    let value = try YAMLValueReader(data: output).read()
    #expect(value == testCase.value, "\(testCase.id): emitted value mismatch")
  }

  @Test("Parse stream", arguments: cases)
  func parseStream(_ testCase: TestCase) async throws {
    let source = Data(testCase.yaml.utf8).source()
    let reader = YAMLStreamReader(source: source)
    var decoder = ValueEventDecoder()

    while let event = try await reader.next() {
      try decoder.append(event)
    }

    let value = try decoder.finish()
    #expect(value == testCase.value, "\(testCase.id): streamed parse mismatch")
  }

  @Test("Emit stream", arguments: cases)
  func emitStream(_ testCase: TestCase) async throws {
    let sink = DataSink()
    let writer = YAMLStreamWriter(sink: sink)
    var events: [ValueEvent] = []
    emitEvents(from: testCase.value, into: &events)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    let value = try YAMLValueReader(data: sink.data).read()
    #expect(value == testCase.value, "\(testCase.id): streamed emit mismatch")
  }

  @Test("Error locations", arguments: errorCases)
  func errorLocations(_ testCase: ErrorCase) throws {
    let error =
      #expect(throws: Error.self) {
        _ = try YAMLValueReader(string: testCase.yaml).read()
      }
    let yamlError = try #require(error as? any YAML.Error)
    switch (yamlError, testCase.kind) {
    case (YAML.ParseError.invalidSyntax(_, let location), .invalidSyntax):
      #expect(location?.line == testCase.line, "\(testCase.id): line mismatch")
      #expect(location?.column == testCase.column, "\(testCase.id): column mismatch")
    case (YAML.ParseError.invalidIndentation(let location), .invalidIndentation):
      #expect(location?.line == testCase.line, "\(testCase.id): line mismatch")
      #expect(location?.column == testCase.column, "\(testCase.id): column mismatch")
    default:
      Issue.record("\(testCase.id): unexpected error kind")
    }
  }

}

private func emitEvents(from value: Value, into events: inout [ValueEvent]) {
  switch value {
  case .tagged(let tag, let value):
    events.append(.tag(tag))
    emitEvents(from: value, into: &events)
  case .array(let array):
    events.append(.beginArray)
    for item in array {
      emitEvents(from: item, into: &events)
    }
    events.append(.endArray)
  case .object(let object):
    events.append(.beginObject)
    for (key, val) in object {
      events.append(.key(key))
      emitEvents(from: val, into: &events)
    }
    events.append(.endObject)
  default:
    events.append(.scalar(value))
  }
}
