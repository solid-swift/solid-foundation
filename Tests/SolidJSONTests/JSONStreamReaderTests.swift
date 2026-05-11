//
//  JSONStreamReaderTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
import SolidIO
import SolidJSON
import Testing


@Suite("JSON Stream Reader Tests")
struct JSONStreamReaderTests {

  @Test("Chunk-split strings with escapes and surrogates")
  func chunkSplitStrings() async throws {
    let json = #"{"message":"hello\nworld","emoji":"\uD83D\uDE00","quote":"a\"b"}"#
    let streamed = try await parseStreamed(json: json, chunkSizes: [1])
    var jsonReader1 = JSONValueReader(string: json)
    let expected = try jsonReader1.read()
    #expect(streamed == expected)
  }

  @Test("Chunk-split numbers with exponent")
  func chunkSplitNumbers() async throws {
    let json = #"{"value":-12.34e-5,"other":0}"#
    let streamed = try await parseStreamed(json: json, chunkSizes: [1])
    var jsonReader2 = JSONValueReader(string: json)
    let expected = try jsonReader2.read()
    #expect(streamed == expected)
  }

  @Test("Nested containers across chunk boundaries")
  func nestedContainers() async throws {
    let json = #"{"a":[1,{"b":[true,false,null]},[]],"c":{}}"#
    let streamed = try await parseStreamed(json: json, chunkSizes: [1])
    var jsonReader3 = JSONValueReader(string: json)
    let expected = try jsonReader3.read()
    #expect(streamed == expected)
  }

  @Test("Document event reader emits one synthetic document")
  func documentEventReaderEmitsSyntheticDocument() async throws {
    let json = #"{"a":[1,true]}"#
    let source = ChunkedSource(data: Data(json.utf8), chunkSizes: [2, 1, 3])
    let reader = JSONDocumentEventReader()
    let driver = FormatDocumentStreamReaderDriver(reader: reader, source: source, bufferSize: 4)
    var decoder = ParseDocumentEventDecoder(resolver: JSONScalarResolver())
    var documents: [FormatValueDocument] = []
    var boundaryEvents: [ParseDocumentEvent] = []

    while let event = try await driver.next() {
      boundaryEvents.append(event)
      if let document = try decoder.append(event) {
        documents.append(document)
      }
    }
    try decoder.finish()

    #expect(documents == [
      FormatValueDocument(
        value: .object([.string("a"): .array([.number(1), .bool(true)])]),
        explicitStart: false,
        explicitEnd: false
      ),
    ])
    #expect(boundaryEvents.filter { if case .startDocument = $0 { true } else { false } }.count == 1)
    #expect(boundaryEvents.filter { if case .endDocument = $0 { true } else { false } }.count == 1)
  }

  @Test("Document event batch reader emits one synthetic document")
  func documentEventBatchReaderEmitsSyntheticDocument() async throws {
    let json = #"{"a":[1,true]}"#
    let source = ChunkedSource(data: Data(json.utf8), chunkSizes: [2, 1, 3])
    let reader = JSONDocumentEventReader()
    let driver = FormatDocumentStreamReaderDriver(reader: reader, source: source, bufferSize: 4)
    var decoder = ParseDocumentEventDecoder(resolver: JSONScalarResolver())
    var documents: [FormatValueDocument] = []
    var boundaryEvents: [ParseDocumentEvent] = []

    while true {
      let status = try await driver.readBatch { events in
        boundaryEvents.append(contentsOf: events)
        for event in events {
          if let document = try decoder.append(event) {
            documents.append(document)
          }
        }
      }
      if status == .endOfStream {
        break
      }
    }
    try decoder.finish()

    #expect(documents == [
      FormatValueDocument(
        value: .object([.string("a"): .array([.number(1), .bool(true)])]),
        explicitStart: false,
        explicitEnd: false
      ),
    ])
    #expect(boundaryEvents.filter { if case .startDocument = $0 { true } else { false } }.count == 1)
    #expect(boundaryEvents.filter { if case .endDocument = $0 { true } else { false } }.count == 1)
  }

  @Test("JSON value reader rejects trailing root value")
  func valueReaderRejectsTrailingRootValue() throws {
    var reader = JSONValueReader(string: "1 2")

    #expect(throws: JSON.Error.self) {
      _ = try reader.read()
    }
  }

  @Test("JSON value reader rejects trailing garbage")
  func valueReaderRejectsTrailingGarbage() throws {
    var reader = JSONValueReader(string: #"{"a":1} garbage"#)

    #expect(throws: JSON.Error.self) {
      _ = try reader.read()
    }
  }

  @Test("JSON value reader allows trailing whitespace")
  func valueReaderAllowsTrailingWhitespace() throws {
    var reader = JSONValueReader(string: "{\"a\":1}   \n\t  ")

    #expect(try reader.read() == .object([.string("a"): .number(1)]))
  }

  @Test("JSON validation rejects trailing root data")
  func validationRejectsTrailingRootData() throws {
    var reader = JSONValueReader(string: "true false")

    #expect(throws: JSON.Error.self) {
      try reader.validateValue()
    }
  }

  @Test("JSON stream driver reports trailing data when drained")
  func streamDriverReportsTrailingDataWhenDrained() async throws {
    let source = ChunkedSource(data: Data("1 2".utf8), chunkSizes: [1])
    let reader = JSONStreamReader()
    let driver = FormatStreamReaderDriver(reader: reader, source: source, bufferSize: 1)

    guard case .scalar(let ref) = try await driver.next() else {
      Issue.record("Expected first scalar event")
      return
    }
    #expect(try ref.materialize(using: JSONScalarResolver()) == .number(1))

    await #expect(throws: JSON.Error.self) {
      _ = try await driver.next()
    }
  }

  @Test("JSON nested object and array key value transitions remain valid")
  func nestedObjectArrayKeyValueTransitionsRemainValid() async throws {
    let json = #"{"outer":{"array":[{"k":"v"},2],"empty":{}},"tail":true}"#
    let streamed = try await parseStreamed(json: json, chunkSizes: [1])
    var reader = JSONValueReader(string: json)
    #expect(streamed == (try reader.read()))
  }

  @Test("JSON rejects object value without colon after stack cleanup")
  func objectValueWithoutColonRejected() throws {
    var reader = JSONValueReader(string: #"{"a" 1}"#)

    #expect(throws: JSON.Error.self) {
      _ = try reader.read()
    }
  }

  @Test("JSON rejects missing object value after stack cleanup")
  func objectMissingValueRejected() throws {
    var reader = JSONValueReader(string: #"{"a":}"#)

    #expect(throws: JSON.Error.self) {
      _ = try reader.read()
    }
  }
}

private func parseStreamed(json: String, chunkSizes: [Int]) async throws -> Value {
  let source = ChunkedSource(data: Data(json.utf8), chunkSizes: chunkSizes)
  let reader = JSONStreamReader()
  let driver = FormatStreamReaderDriver(reader: reader, source: source, bufferSize: 64)
  var decoder = ParseEventDecoder(resolver: JSONScalarResolver())

  while let event = try await driver.next() {
    try decoder.append(event)
  }

  return try decoder.finish()
}

private final class ChunkedSource: Source, @unchecked Sendable {

  private var data: Data
  private let chunkSizes: [Int]
  private var chunkIndex = 0
  private var closed = false
  private var bytesReadValue = 0

  init(data: Data, chunkSizes: [Int]) {
    self.data = data
    self.chunkSizes = chunkSizes
  }

  var bytesRead: Int {
    get async throws { bytesReadValue }
  }

  func read(max: Int) async throws -> Data? {
    guard !closed else { throw IOError.streamClosed }
    guard !data.isEmpty else { return nil }

    let requested =
      chunkSizes.isEmpty
      ? max
      : chunkSizes[min(chunkIndex, chunkSizes.count - 1)]
    chunkIndex += 1

    let size = min(max, requested, data.count)
    let result = data.prefix(size)
    data.removeSubrange(0..<result.count)
    bytesReadValue += result.count
    return result
  }

  func close() async throws {
    closed = true
  }
}
