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

  struct DeterministicCase: Sendable {
    let id: String
    let value: Value
    let options: CBORStreamWriter.Options
    let expectedDeterministic: Bool
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
      value: .tagged(tag: .number(1), value: .string("tagged"))
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

  static let deterministicCases: [DeterministicCase] = [
    .init(
      id: "buffered-sorts-keys",
      value: .object([.string("b"): .number(1), .string("a"): .number(2)]),
      options: .init(deterministicMode: .buffered()),
      expectedDeterministic: true
    ),
    .init(
      id: "assume-sorted-keeps-order",
      value: .object([.string("b"): .number(1), .string("a"): .number(2)]),
      options: .init(deterministicMode: .assumeSortedKeys),
      expectedDeterministic: false
    ),
    .init(
      id: "assume-sorted-preserves-sorted",
      value: .object([.string("a"): .number(2), .string("b"): .number(1)]),
      options: .init(deterministicMode: .assumeSortedKeys),
      expectedDeterministic: true
    ),
    .init(
      id: "buffered-maxpairs-fallback",
      value: .object([.string("b"): .number(1), .string("a"): .number(2)]),
      options: .init(deterministicMode: .buffered(maxPairs: 1, maxBytes: 1024)),
      expectedDeterministic: false
    ),
    .init(
      id: "buffered-maxbytes-fallback",
      value: .object([.string("b"): .number(1), .string("a"): .number(2)]),
      options: .init(deterministicMode: .buffered(maxPairs: 10, maxBytes: 1)),
      expectedDeterministic: false
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

  @Test("Emit stream", arguments: cases)
  func emitStream(_ testCase: TestCase) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink)
    let events = ValueEventEncoder().encode(testCase.value)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    let value = try CBORValueReader(data: sink.data).read()
    #expect(value == testCase.value, "\(testCase.id): streamed emit mismatch")
  }

  @Test("Emit deterministic stream", arguments: deterministicCases)
  func emitDeterministicStream(_ testCase: DeterministicCase) async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(sink: sink, options: testCase.options)
    let events = ValueEventEncoder().encode(testCase.value)
    for event in events {
      try await writer.write(event)
    }
    try await writer.finish()

    let deterministicBytes = try CBORValueWriter.write(testCase.value, options: .init(deterministic: true))
    let nondeterministicBytes = try CBORValueWriter.write(testCase.value, options: .init(deterministic: false))
    let expected = testCase.expectedDeterministic ? deterministicBytes : nondeterministicBytes

    #expect(sink.data == expected, "\(testCase.id): deterministic stream bytes mismatch")
  }

  @Test("Emit strict deterministic rejects indefinite map")
  func emitStrictDeterministicRejectsIndefiniteMap() async {
    let sink = DataSink()
    let writer = CBORStreamWriter(
      sink: sink,
      options: .init(deterministicMode: .strict(maxPairs: 10, maxBytes: 1024))
    )
    let events: [ValueEvent] = [
      .beginObject(count: nil),
      .key(.string("a")),
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

  @Test("Emit strict deterministic rejects max bytes")
  func emitStrictDeterministicRejectsMaxBytes() async throws {
    let sink = DataSink()
    let writer = CBORStreamWriter(
      sink: sink,
      options: .init(deterministicMode: .strict(maxPairs: 10, maxBytes: 1))
    )
    let value = Value.object([.string("b"): .number(1), .string("a"): .number(2)])
    let events = ValueEventEncoder().encode(value)

    await #expect(throws: Swift.Error.self) {
      for event in events {
        try await writer.write(event)
      }
      try await writer.finish()
    }
  }
}

private func parseStreamed(cbor: Data, chunkSizes: [Int]) async throws -> Value {
  let source = ChunkedSource(data: cbor, chunkSizes: chunkSizes)
  let reader = CBORStreamReader()
  let driver = FormatStreamReaderDriver(reader: reader, source: source, bufferSize: 64)
  var decoder = ValueEventDecoder()

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
