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

  struct DocumentCase: Sendable, CustomStringConvertible, Identifiable {
    let id: String
    let yaml: String
    let documents: [YAMLValueDocument]

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

  static let documentCases: [DocumentCase] = [
    .init(
      id: "two-explicit-docs",
      yaml: """
      ---
      foo: 1
      ...
      ---
      bar: 2
      """,
      documents: [
        .init(value: ["foo": 1], explicitStart: true, explicitEnd: true),
        .init(value: ["bar": 2], explicitStart: true, explicitEnd: false),
      ]
    ),
    .init(
      id: "implicit-then-explicit",
      yaml: """
      foo: 1
      ---
      bar: 2
      """,
      documents: [
        .init(value: ["foo": 1], explicitStart: false, explicitEnd: false),
        .init(value: ["bar": 2], explicitStart: true, explicitEnd: false),
      ]
    ),
  ]

  @Test("Parse value", .serialized, arguments: cases)
  func parseValue(_ testCase: TestCase) throws {
    var yamlReader = YAMLValueReader(string: testCase.yaml)
    let value = try yamlReader.read()
    #expect(value == testCase.value, "\(testCase.id): parsed value mismatch")
  }

  @Test("Emit value", arguments: cases)
  func emitValue(_ testCase: TestCase) throws {
    let writer = YAMLValueWriter(options: .default)
    let output = try writer.write(testCase.value)
    var outputReader = try YAMLValueReader(data: output)
    let value = try outputReader.read()
    #expect(value == testCase.value, "\(testCase.id): emitted value mismatch")
  }

  @Test("Parse stream", arguments: cases)
  func parseStream(_ testCase: TestCase) async throws {
    let source = Data(testCase.yaml.utf8).source()
    let reader = YAMLStreamReader()
    let driver = FormatStreamReaderDriver(reader: reader, source: source)
    var decoder = ValueEventDecoder()

    while let event = try await driver.next() {
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

    var sinkReader = try YAMLValueReader(data: sink.data)
    let value = try sinkReader.read()
    #expect(value == testCase.value, "\(testCase.id): streamed emit mismatch")
  }

  @Test("Parse documents", .serialized, arguments: documentCases)
  func parseDocuments(_ testCase: DocumentCase) throws {
    let reader = try YAMLDocumentReader(data: Data(testCase.yaml.utf8))
    let documents = try reader.readAll()
    #expect(documents == testCase.documents, "\(testCase.id): parsed documents mismatch")
  }

  @Test("Parse document stream", arguments: documentCases)
  func parseDocumentStream(_ testCase: DocumentCase) async throws {
    let source = Data(testCase.yaml.utf8).source()
    let reader = YAMLDocumentStreamReader(source: source)
    var documents: [YAMLValueDocument] = []
    while let document = try await reader.next() {
      documents.append(document)
    }
    #expect(documents == testCase.documents, "\(testCase.id): streamed documents mismatch")
  }

  @Test("Emit documents", arguments: documentCases)
  func emitDocuments(_ testCase: DocumentCase) throws {
    let writer = YAMLDocumentWriter(options: .default)
    try writer.writeAll(testCase.documents)
    let output = writer.data()
    let reader = try YAMLDocumentReader(data: output)
    let documents = try reader.readAll()
    #expect(documents == testCase.documents, "\(testCase.id): emitted documents mismatch")
  }

  @Test("Emit document stream", arguments: documentCases)
  func emitDocumentStream(_ testCase: DocumentCase) async throws {
    let sink = DataSink()
    let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)
    for document in testCase.documents {
      try await writer.write(document)
    }
    try await writer.finish()
    let reader = try YAMLDocumentReader(data: sink.data)
    let documents = try reader.readAll()
    #expect(documents == testCase.documents, "\(testCase.id): streamed emit mismatch")
  }

  @Test("Error locations", arguments: errorCases)
  func errorLocations(_ testCase: ErrorCase) throws {
    let error =
      #expect(throws: Error.self) {
        var errorReader = YAMLValueReader(string: testCase.yaml)
        _ = try errorReader.read()
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
    events.append(.beginArray(count: nil))
    for item in array {
      emitEvents(from: item, into: &events)
    }
    events.append(.endArray)
  case .object(let object):
    events.append(.beginObject(count: nil))
    for (key, val) in object {
      events.append(.key(key))
      emitEvents(from: val, into: &events)
    }
    events.append(.endObject)
  default:
    events.append(.scalar(value))
  }
}
