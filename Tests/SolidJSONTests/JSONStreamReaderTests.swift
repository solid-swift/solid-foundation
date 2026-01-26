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
    let expected = try JSONValueReader(string: json).read()
    #expect(streamed == expected)
  }

  @Test("Chunk-split numbers with exponent")
  func chunkSplitNumbers() async throws {
    let json = #"{"value":-12.34e-5,"other":0}"#
    let streamed = try await parseStreamed(json: json, chunkSizes: [1])
    let expected = try JSONValueReader(string: json).read()
    #expect(streamed == expected)
  }

  @Test("Nested containers across chunk boundaries")
  func nestedContainers() async throws {
    let json = #"{"a":[1,{"b":[true,false,null]},[]],"c":{}}"#
    let streamed = try await parseStreamed(json: json, chunkSizes: [1])
    let expected = try JSONValueReader(string: json).read()
    #expect(streamed == expected)
  }
}

private func parseStreamed(json: String, chunkSizes: [Int]) async throws -> Value {
  let source = ChunkedSource(data: Data(json.utf8), chunkSizes: chunkSizes)
  let reader = JSONStreamReader(source: source, bufferSize: 64)
  var decoder = ValueEventDecoder()

  while let event = try await reader.next() {
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
