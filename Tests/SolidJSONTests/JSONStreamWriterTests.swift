//
//  JSONStreamWriterTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
import SolidIO
import SolidJSON
import Testing


@Suite("JSON Stream Writer Tests")
struct JSONStreamWriterTests {

  @Test("Write nested value")
  func writeNestedValue() async throws {
    let value: Value = [
      "name": "Alice",
      "scores": [95, 87, 92],
      "active": true,
      "meta": [
        "nickname": "Al",
        "flags": [false, .null],
      ],
    ]

    let output = try await writeStreamed(value: value)
    let expected = try JSONValueWriter.write(value)
    #expect(output == expected)
  }

  @Test("Write tagged value with array shape")
  func writeTaggedValueArrayShape() async throws {
    let value: Value = .tagged(tags: ["tag"], value: ["value": 1])
    let options = JSONStreamWriter.Options(tagShape: .array)

    let output = try await writeStreamed(value: value, options: options)
    let expected = try JSONValueWriter.write(value, options: .init(tagShape: .array))
    #expect(output == expected)
  }

  @Test("JSON format metadata reports text and no native bytes")
  func formatMetadataReportsTextAndNoNativeBytes() {
    #expect(JSON.format.kind == .text)
    #expect(JSON.format.supports(type: .string))
    #expect(!JSON.format.supports(type: .bytes))
  }

  @Test("JSON value writer rejects non-string object keys")
  func valueWriterRejectsNonStringObjectKeys() throws {
    let value: Value = .object([.number(1): .string("bad")])

    let error = #expect(throws: JSONStreamWriter.Error.self) {
      _ = try JSONValueWriter.write(value)
    }
    guard case .invalidObjectKey = try #require(error) else {
      Issue.record("Expected invalidObjectKey")
      return
    }
  }

  @Test("JSON value writer rejects non-string wrapped tag keys")
  func valueWriterRejectsNonStringWrappedTagKeys() throws {
    let value: Value = .tagged(tags: [.number(1)], value: .string("bad"))

    let error = #expect(throws: JSONStreamWriter.Error.self) {
      _ = try JSONValueWriter.write(value, options: .init(tagShape: .wrapped))
    }
    guard case .invalidTagType = try #require(error) else {
      Issue.record("Expected invalidTagType")
      return
    }
  }

  @Test("JSON value writer rejects non-finite numbers")
  func valueWriterRejectsNonFiniteNumbers() throws {
    let values: [Value] = [
      .number(.binary(.float32(Float32.nan))),
      .number(.binary(.float64(Double.infinity))),
      .number(.binary(.float64(-Double.infinity))),
    ]

    for value in values {
      let error = #expect(throws: JSONStreamWriter.Error.self) {
        _ = try JSONValueWriter.write(value)
      }
      guard case .invalidNumber = try #require(error) else {
        Issue.record("Expected invalidNumber for \(value)")
        return
      }
    }
  }
}

private func writeStreamed(value: Value, options: JSONStreamWriter.Options = .default) async throws -> Data {
  let sink = DataSink()
  let writer = JSONStreamWriter(sink: sink, bufferSize: 8, options: options)
  var events: [EmitEvent] = []
  emitEvents(from: value, into: &events)
  for event in events {
    try await writer.write(event)
  }
  try await writer.finish()
  return sink.data
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
