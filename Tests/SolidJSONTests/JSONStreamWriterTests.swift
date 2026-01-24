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
    let expected = JSONValueWriter.write(value)
    #expect(output == expected)
  }

  @Test("Write tagged value with array shape")
  func writeTaggedValueArrayShape() async throws {
    let value: Value = .tagged(tag: "tag", value: ["value": 1])
    let options = JSONStreamWriter.Options(tagShape: .array)

    let output = try await writeStreamed(value: value, options: options)
    let expected = JSONValueWriter.write(value, options: .init(tagShape: .array))
    #expect(output == expected)
  }
}

private func writeStreamed(value: Value, options: JSONStreamWriter.Options = .default) async throws -> Data {
  let sink = DataSink()
  let writer = JSONStreamWriter(sink: sink, bufferSize: 8, options: options)
  var events: [ValueEvent] = []
  emitEvents(from: value, into: &events)
  for event in events {
    try await writer.write(event)
  }
  try await writer.finish()
  return sink.data
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
