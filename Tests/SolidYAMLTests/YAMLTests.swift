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

  @Test("Value reader rejects additional document")
  func valueReaderRejectsAdditionalDocument() throws {
    var yamlReader = YAMLValueReader(
      string: """
      ---
      foo: 1
      ---
      bar: 2
      """
    )

    #expect(throws: Error.self) {
      _ = try yamlReader.read()
    }
  }

  @Test("Compact sequence mapping value can be nested block mapping")
  func compactSequenceMappingValueCanBeNestedBlockMapping() throws {
    let yaml = """
    refusals:
    - locator:
        claimId: "rcl--5j6lp6"
        relationId: null
        endpointKind: "PARTICIPANT"
        participantIndex: 1
      mentionSurface: "MICROSCOPIC AEROSOL BUBBLES OF LIQUID OXYGEN"
      candidateEntities: []
      source: "NON_CHARACTER_REFERENT"
    """

    var yamlReader = YAMLValueReader(string: yaml)
    let value = try yamlReader.read()

    #expect(value == [
      "refusals": [
        [
          "locator": [
            "claimId": "rcl--5j6lp6",
            "relationId": .null,
            "endpointKind": "PARTICIPANT",
            "participantIndex": 1,
          ],
          "mentionSurface": "MICROSCOPIC AEROSOL BUBBLES OF LIQUID OXYGEN",
          "candidateEntities": .array([]),
          "source": "NON_CHARACTER_REFERENT",
        ]
      ]
    ])
  }

  @Test("Emit value", arguments: cases)
  func emitValue(_ testCase: TestCase) throws {
    let writer = YAMLValueWriter(options: .default)
    let output = try writer.write(testCase.value)
    var outputReader = try YAMLValueReader(data: output)
    let value = try outputReader.read()
    #expect(value == testCase.value, "\(testCase.id): emitted value mismatch")
  }

  @Test("Emit mapping value ending with colon")
  func emitMappingValueEndingWithColon() throws {
    let value: Value = [
      "beat": [
        "text": "They follow, snapping at his heel:",
        "locator": [
          "kind": "script-tree-node",
          "nodeId": "acn-1sr7h5v",
        ],
      ]
    ]

    let output = try YAMLValueWriter.write(value)
    var outputReader = try YAMLValueReader(data: output)
    let emittedValue = try outputReader.read()

    #expect(emittedValue == value)
  }

  @Test("Parse stream", arguments: cases)
  func parseStream(_ testCase: TestCase) async throws {
    let source = Data(testCase.yaml.utf8).source()
    let reader = YAMLStreamReader()
    let driver = FormatStreamReaderDriver(reader: reader, source: source)
    var decoder = ParseEventDecoder(resolver: YAMLScalarResolver())

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
    var events: [EmitEvent] = []
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

  @Test("Parse document event batch stream", arguments: documentCases)
  func parseDocumentEventBatchStream(_ testCase: DocumentCase) async throws {
    let source = Data(testCase.yaml.utf8).source()
    let driver = FormatDocumentStreamReaderDriver(
      reader: YAMLDocumentEventReader(),
      source: source,
      bufferSize: 4
    )
    var decoder = ParseDocumentEventDecoder(resolver: YAMLScalarResolver())
    var documents: [YAMLValueDocument] = []

    while true {
      let status = try await driver.readBatch { events in
        for event in events {
          if let document = try decoder.append(event) {
            documents.append(YAMLValueDocument(
              value: document.value,
              explicitStart: document.explicitStart,
              explicitEnd: document.explicitEnd
            ))
          }
        }
      }
      if status == .endOfStream {
        break
      }
    }
    try decoder.finish()

    #expect(documents == testCase.documents, "\(testCase.id): batched document events mismatch")
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

  @Test("Document stream writer preserves typed-looking strings")
  func documentStreamWriterPreservesTypedLookingStrings() async throws {
    let documents = [
      YAMLValueDocument(value: [
        "empty": "",
        "null": "null",
        "bool": "true",
        "number": "1",
      ])
    ]

    let sink = DataSink()
    let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)
    for document in documents {
      try await writer.write(document)
    }
    try await writer.finish()

    let reader = try YAMLDocumentReader(data: sink.data)
    let writtenDocuments = try reader.readAll()
    #expect(writtenDocuments == documents)
  }

  @Test("Document stream writer rejects overlapping writes", .timeLimit(.minutes(1)))
  func documentStreamWriterRejectsOverlappingWrites() async throws {
    let sink = BlockingYAMLDocumentSink()
    let writer = YAMLDocumentStreamWriter(sink: sink, options: .default)

    async let firstWrite: Void = writer.write(.init(value: ["first": 1]))
    await sink.waitUntilWriteStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      try await writer.write(.init(value: ["second": 2]))
    }

    await sink.releaseWrites()
    try await firstWrite
    try await writer.finish()
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

private func emitEvents(from value: Value, into events: inout [EmitEvent]) {
  switch value {
  case .tagged(let tags, let value):
    for tag in tags {
      events.append(.tag(tag))
    }
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
      events.append(.scalar(key))
      emitEvents(from: val, into: &events)
    }
    events.append(.endObject)
  default:
    events.append(.scalar(value))
  }
}

private actor BlockingYAMLDocumentSink: Sink {

  private var storage = Data()
  private var writeStarted = false
  private var writeReleased = false
  private var writeStartedContinuations: [CheckedContinuation<Void, Never>] = []
  private var writeReleaseContinuations: [CheckedContinuation<Void, Never>] = []

  var bytesWritten: Int {
    get async throws { storage.count }
  }

  func write(data: Data) async throws {
    writeStarted = true
    resumeWriteStartedContinuations()

    if !writeReleased {
      await withCheckedContinuation { continuation in
        writeReleaseContinuations.append(continuation)
      }
    }

    storage.append(data)
  }

  func waitUntilWriteStarted() async {
    guard !writeStarted else { return }

    await withCheckedContinuation { continuation in
      writeStartedContinuations.append(continuation)
    }
  }

  func releaseWrites() {
    writeReleased = true
    let continuations = writeReleaseContinuations
    writeReleaseContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func close() async throws {}

  private func resumeWriteStartedContinuations() {
    let continuations = writeStartedContinuations
    writeStartedContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }
}
