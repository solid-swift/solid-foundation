//
//  CBORStreamTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation
import SolidCBOR
import SolidData
import SolidIO
import Testing


@Suite("CBOR Stream Tests")
struct CBORStreamTests {

  struct TestCase: Sendable {
    let id: String
    let value: Value
  }

  struct BoundaryCase: Sendable {
    let id: String
    let bytes: [UInt8]
    let expected: Value
    let chunkSizes: [Int]
  }

  static let cases: [TestCase] = [
    .init(id: "null", value: .null),
    .init(id: "bool", value: .bool(true)),
    .init(id: "int", value: .number(42)),
    .init(id: "negative-int", value: .number(-17)),
    .init(id: "string", value: .string("hello")),
    .init(id: "bytes", value: .bytes(Data([0x00, 0xFF, 0x7A]))),
    .init(
      id: "array-object",
      value: .array([
        .number(1),
        .object([.string("a"): .bool(false)]),
        .array([.string("x"), .string("y")]),
      ])
    ),
    .init(
      id: "tagged",
      value: .tagged(tags: [.number(1)], value: .string("tagged"))
    ),
  ]

  static let boundaryCases: [BoundaryCase] = [
    .init(
      id: "uint16-boundary",
      bytes: [0x19, 0x03, 0xE8],
      expected: .number(1_000),
      chunkSizes: [1, 1, 1]
    ),
    .init(
      id: "byte-string-length-boundary",
      bytes: [0x58, 0x18] + Array(repeating: 0xAB, count: 24),
      expected: .bytes(Data(repeating: 0xAB, count: 24)),
      chunkSizes: [1, 1, 5, 4, 13]
    ),
    .init(
      id: "text-string-length-boundary",
      bytes: [0x78, 0x18] + Array(repeating: 0x61, count: 24),
      expected: .string(String(repeating: "a", count: 24)),
      chunkSizes: [1, 1, 7, 8, 9]
    ),
  ]

  @Test("Parse stream", arguments: cases)
  func parseStream(_ testCase: TestCase) async throws {
    let data = try CBORValueWriter.write(testCase.value)
    let parsed = try await parseStreamed(cbor: data, chunkSizes: [1, 2, 3, 1])
    #expect(parsed == testCase.value, "\(testCase.id): streamed parse mismatch")
  }

  @Test("Parse stream across boundaries", arguments: boundaryCases)
  func parseStreamBoundaries(_ testCase: BoundaryCase) async throws {
    let data = Data(testCase.bytes)
    let parsed = try await parseStreamed(cbor: data, chunkSizes: testCase.chunkSizes)
    #expect(parsed == testCase.expected, "\(testCase.id): streamed boundary parse mismatch")
  }

  @Test("Document event reader emits one document per root item")
  func documentEventReaderEmitsOneDocumentPerRootItem() async throws {
    var data = Data()
    data.append(try CBORValueWriter.write(.number(1)))
    data.append(try CBORValueWriter.write(.array([.string("two")])))

    let source = ChunkedSource(data: data, chunkSizes: [1])
    let reader = CBORDocumentEventReader()
    let driver = FormatDocumentStreamReaderDriver(reader: reader, source: source, bufferSize: 2)
    var decoder = ParseDocumentEventDecoder(resolver: CBORScalarResolver())
    var documents: [FormatValueDocument] = []
    var startCount = 0
    var endCount = 0

    while let event = try await driver.next() {
      if case .startDocument(let metadata) = event {
        #expect(!metadata.explicit)
        startCount += 1
      }
      if case .endDocument(let metadata) = event {
        #expect(!metadata.explicit)
        endCount += 1
      }
      if let document = try decoder.append(event) {
        documents.append(document)
      }
    }
    try decoder.finish()

    #expect(documents.map(\.value) == [.number(1), .array([.string("two")])])
    #expect(startCount == 2)
    #expect(endCount == 2)
  }

  @Test("Document event batch reader emits one document per root item")
  func documentEventBatchReaderEmitsOneDocumentPerRootItem() async throws {
    var data = Data()
    data.append(try CBORValueWriter.write(.number(1)))
    data.append(try CBORValueWriter.write(.array([.string("two")])))

    let source = ChunkedSource(data: data, chunkSizes: [1])
    let reader = CBORDocumentEventReader()
    let driver = FormatDocumentStreamReaderDriver(reader: reader, source: source, bufferSize: 2)
    var decoder = ParseDocumentEventDecoder(resolver: CBORScalarResolver())
    var documents: [FormatValueDocument] = []
    var startCount = 0
    var endCount = 0

    while true {
      let status = try await driver.readBatch { events in
        for event in events {
          if case .startDocument(let metadata) = event {
            #expect(!metadata.explicit)
            startCount += 1
          }
          if case .endDocument(let metadata) = event {
            #expect(!metadata.explicit)
            endCount += 1
          }
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

    #expect(documents.map(\.value) == [.number(1), .array([.string("two")])])
    #expect(startCount == 2)
    #expect(endCount == 2)
  }

  @Test("Emit stream", arguments: cases)
  func emitStream(_ testCase: TestCase) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink)
    let events = EmitEventEncoder().encode(testCase.value)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    var cborReader = CBORValueReader(data: sink.data)
    let value = try cborReader.read()
    #expect(value == testCase.value, "\(testCase.id): streamed emit mismatch")
  }

  @Test("Stream writer writes a full value through bulk path")
  func cborStreamWriterWritesValueThroughBulkPath() async throws {
    let value: Value = .object([
      .string("a"): .array([.number(1), .string("two")]),
      .string("b"): .bool(false),
    ])

    let expected = try CBORValueWriter.write(value)
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, bufferSize: 8)

    try await writer.writeValue(value)
    try await writer.close()

    #expect(sink.data == expected)
  }

  @Test("Deterministic stream value write matches deterministic value writer")
  func deterministicStreamValueWriteMatchesValueWriter() async throws {
    let value: Value = .object([
      .string("z"): .number(1),
      .string("a"): .number(2),
      .bytes(Data([0x01])): .string("bytes"),
    ])

    let expected = try CBORValueWriter.write(value, options: .init(deterministic: true))
    let sink = DataSink()
    let writer = CBORStreamWriter(
      sink: sink,
      options: .init(deterministic: true),
      bufferSize: 8
    )

    try await writer.writeValue(value)
    try await writer.close()

    #expect(sink.data == expected)
  }

  @Test("Emit deterministic stream")
  func emitDeterministicStream() async throws {
    let value: Value = .object([
      .string("b"): .number(Float64(0.5)),
      .string("a"): .object([
        .number(100): .number(2),
        .number(10): .number(1),
      ]),
    ])

    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: .init(deterministic: true))
    let events = EmitEventEncoder().encode(value)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    let expected = try CBORValueWriter.write(value, options: .init(deterministic: true))
    #expect(sink.data == expected)
  }

  @Test("Emit deterministic stream sorts keys by core lexicographic order")
  func emitDeterministicStreamSortsKeysByCoreLexicographicOrder() async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: .init(deterministic: true))
    let events: [EmitEvent] = [
      .beginObject(count: 2),
      .scalar(.number(24)),
      .scalar(.number(2)),
      .scalar(.string("")),
      .scalar(.number(1)),
      .endObject,
    ]

    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    #expect(sink.data == Data([0xA2, 0x18, 0x18, 0x02, 0x60, 0x01]))
  }

  @Test("Emit deterministic stream with complex key events")
  func emitDeterministicStreamWithComplexKeyEvents() async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: .init(deterministic: true))
    let complexKey: Value = .array([
      .object([
        .string("inner"): .object([
          .string("b"): .number(1),
          .string("a"): .number(2),
        ]),
      ]),
    ])
    let expectedValue: Value = .object([
      complexKey: .string("complex"),
      .string("z"): .string("plain"),
    ])
    let events: [EmitEvent] = [
      .beginObject(count: 2),
      .beginArray(count: 1),
      .beginObject(count: 1),
      .scalar(.string("inner")),
      .beginObject(count: 2),
      .scalar(.string("b")),
      .scalar(.number(1)),
      .scalar(.string("a")),
      .scalar(.number(2)),
      .endObject,
      .endObject,
      .endArray,
      .scalar(.string("complex")),
      .scalar(.string("z")),
      .scalar(.string("plain")),
      .endObject,
    ]

    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    let expected = try CBORValueWriter.write(expectedValue, options: .init(deterministic: true))
    #expect(sink.data == expected)
  }

  @Test("Emit deterministic stream with complex key in buffered value")
  func emitDeterministicStreamWithComplexKeyInBufferedValue() async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: .init(deterministic: true))
    let events: [EmitEvent] = [
      .beginObject(count: 1),
      .scalar(.string("outer")),
      .beginObject(count: 1),
      .beginArray(count: 1),
      .scalar(.string("key")),
      .endArray,
      .scalar(.number(1)),
      .endObject,
      .endObject,
    ]

    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    let expectedKeyBytes = try CBORValueWriter.write(.array([.string("key")]), options: .init(deterministic: true))
    var expected = Data([0xA1, 0x65])
    expected.append(Data("outer".utf8))
    expected.append(0xA1)
    expected.append(expectedKeyBytes)
    expected.append(0x01)
    #expect(sink.data == expected)
  }

  @Test("Deterministic stream rejects indefinite map")
  func deterministicStreamRejectsIndefiniteMap() async {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: .init(deterministic: true))
    let events: [EmitEvent] = [
      .beginObject(count: nil),
      .scalar(.string("a")),
      .scalar(.number(1)),
      .endObject,
    ]

    await #expect(throws: Swift.Error.self) {
      for event in events {
        try await writer.write(event)
      }
      try await writer.finish()
    }
  }

  @Test("Deterministic stream rejects indefinite array")
  func deterministicStreamRejectsIndefiniteArray() async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: .init(deterministic: true))
    let events: [EmitEvent] = [
      .beginArray(count: nil),
      .scalar(.number(1)),
      .endArray,
    ]

    await #expect(throws: Swift.Error.self) {
      for event in events {
        try await writer.write(event)
      }
      try await writer.finish()
    }
  }

  @Test("Document stream writer rejects overlapping writes", .timeLimit(.minutes(1)))
  func documentStreamWriterRejectsOverlappingWrites() async throws {
    let sink = BlockingCBORDocumentSink()
    let writer = CBORDocumentStreamWriter(sink: sink)

    async let firstWrite: Void = writer.write(.init(value: .object([.string("first"): .number(1)])))
    await sink.waitUntilWriteStarted()

    await #expect(throws: FormatStreamDriverError.operationInProgress) {
      try await writer.write(.init(value: .object([.string("second"): .number(2)])))
    }

    await sink.releaseWrites()
    try await firstWrite
    try await writer.finish()
  }
}

private func parseStreamed(cbor: Data, chunkSizes: [Int]) async throws -> Value {
  let source = ChunkedSource(data: cbor, chunkSizes: chunkSizes)
  let reader = CBORStreamReader()
  let driver = FormatStreamReaderDriver(reader: reader, source: source, bufferSize: 64)
  var decoder = ParseEventDecoder(resolver: CBORScalarResolver())

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

private actor BlockingCBORDocumentSink: Sink {

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
