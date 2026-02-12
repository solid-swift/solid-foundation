//
//  CBORDocumentTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidCBOR
import SolidData
import SolidIO
import Testing


@Suite("CBOR Document Tests")
struct CBORDocumentTests {

  struct TestCase: Sendable {
    let id: String
    let values: [Value]
  }

  static let cases: [TestCase] = [
    .init(id: "single-scalar", values: [.number(42)]),
    .init(id: "mixed-documents", values: [
      .null,
      .bool(true),
      .string("hello"),
      .array([.number(1), .number(2)]),
      .object([.string("a"): .bool(false)]),
    ]),
  ]

  @Test("Read/write documents", arguments: cases)
  func readWriteDocuments(_ testCase: TestCase) throws {
    let writer = CBORDocumentWriter()
    try writer.writeAll(testCase.values.map { CBORValueDocument(value: $0) })
    let data = writer.data()

    let reader = CBORDocumentReader(data: data)
    let documents = try reader.readAll()
    let actual = documents.map(\.value)

    #expect(actual == testCase.values, "\(testCase.id): document values mismatch")
  }

  @Test("Stream document writer", arguments: cases)
  func streamDocumentWriter(_ testCase: TestCase) async throws {
    let sink = DataSink()
    let writer = CBORDocumentStreamWriter(sink: sink)
    for value in testCase.values {
      try await writer.write(CBORValueDocument(value: value))
    }
    try await writer.close()

    let reader = CBORDocumentReader(data: sink.data)
    let documents = try reader.readAll()
    let actual = documents.map(\.value)

    #expect(actual == testCase.values, "\(testCase.id): streamed write values mismatch")
  }

  @Test("Stream document reader", arguments: cases)
  func streamDocumentReader(_ testCase: TestCase) async throws {
    let writer = CBORDocumentWriter()
    try writer.writeAll(testCase.values.map { CBORValueDocument(value: $0) })
    let data = writer.data()

    let source = ChunkedSource(data: data, chunkSizes: [1, 2, 3, 1])
    let reader = CBORDocumentStreamReader(source: source, bufferSize: 4)
    var values: [Value] = []
    while let document = try await reader.next() {
      values.append(document.value)
    }

    #expect(values == testCase.values, "\(testCase.id): streamed read values mismatch")
  }
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
