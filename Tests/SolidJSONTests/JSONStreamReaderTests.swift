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
  var builder = ValueEventBuilder()

  while let event = try await reader.next() {
    try builder.append(event)
  }

  return try builder.finish()
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

    let requested = chunkSizes.isEmpty
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

private struct ValueEventBuilder {

  enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteValue
  }

  private enum Container {
    case array([Value], tags: [Value])
    case object(Value.Object, expectingKey: Bool, currentKey: Value?, tags: [Value])
  }

  private var stack: [Container] = []
  private var pendingTags: [Value] = []
  private var root: Value?

  mutating func append(_ event: ValueEvent) throws {
    switch event {
    case .tag(let tag):
      pendingTags.append(tag)

    case .scalar(let value):
      try appendValue(value)

    case .beginArray:
      let tags = pendingTags
      pendingTags.removeAll()
      stack.append(.array([], tags: tags))

    case .endArray:
      guard case .array(let values, let tags) = stack.popLast() else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      try appendValue(applyTags(.array(values), tags: tags))

    case .beginObject:
      let tags = pendingTags
      pendingTags.removeAll()
      stack.append(.object(Value.Object(), expectingKey: true, currentKey: nil, tags: tags))

    case .endObject:
      guard case .object(let object, let expectingKey, _, let tags) = stack.popLast() else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      try appendValue(applyTags(.object(object), tags: tags))

    case .key(let key):
      guard case .object(let object, let expectingKey, let currentKey, let tags) = stack.popLast() else {
        throw Error.invalidEventSequence("Unexpected key")
      }
      guard expectingKey, currentKey == nil else {
        throw Error.invalidEventSequence("Unexpected key position")
      }
      let taggedKey = applyTags(key, tags: pendingTags)
      pendingTags.removeAll()
      stack.append(.object(object, expectingKey: false, currentKey: taggedKey, tags: tags))
    }
  }

  mutating func finish() throws -> Value {
    guard stack.isEmpty, pendingTags.isEmpty, let root else {
      throw Error.incompleteValue
    }
    return root
  }

  private func applyTags(_ value: Value, tags: [Value]) -> Value {
    var tagged = value
    for tag in tags.reversed() {
      tagged = .tagged(tag: tag, value: tagged)
    }
    return tagged
  }

  private mutating func appendValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll()

    guard let container = stack.popLast() else {
      guard root == nil else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      root = taggedValue
      return
    }

    switch container {
    case .array(var values, let tags):
      values.append(taggedValue)
      stack.append(.array(values, tags: tags))

    case .object(var object, let expectingKey, let currentKey, let tags):
      guard !expectingKey, let key = currentKey else {
        throw Error.invalidEventSequence("Missing key for value")
      }
      object[key] = taggedValue
      stack.append(.object(object, expectingKey: true, currentKey: nil, tags: tags))
    }
  }
}
