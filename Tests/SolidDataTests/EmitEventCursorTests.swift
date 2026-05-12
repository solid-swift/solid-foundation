//
//  EmitEventCursorTests.swift
//  SolidFoundation
//
//  Created by Codex on 5/11/26.
//

import SolidData
import Testing


@Suite("EmitEventCursor")
struct EmitEventCursorTests {

  @Test("value cursor matches EmitEventEncoder order")
  func valueCursorMatchesRecursiveEncoder() throws {
    let value: Value = .object([
      .string("a"): .array([.number(1), .bool(true)]),
      .string("b"): .tagged(tags: [.string("tag")], value: .null),
    ])

    let expected = EmitEventEncoder().encode(value)

    var cursor = ValueEmitEventCursor(value)
    var actual: [EmitEvent] = []
    while let event = try cursor.next() {
      actual.append(event)
    }

    #expect(actual == expected)
  }

  @Test("cursor can omit container sizes")
  func cursorCanOmitContainerSizes() throws {
    let value: Value = .array([.string("x")])
    var cursor = ValueEmitEventCursor(value, includeContainerSizes: false)

    #expect(try cursor.next() == .beginArray(count: nil))
    #expect(try cursor.next() == .scalar(.string("x")))
    #expect(try cursor.next() == .endArray)
    #expect(try cursor.next() == nil)
  }

  @Test("value cursor emits deeply nested values without prebuilding all events")
  func valueCursorEmitsNestedValues() throws {
    var value: Value = .null
    for _ in 0..<512 {
      value = .array([value])
    }

    var cursor = ValueEmitEventCursor(value)
    var eventCount = 0
    while try cursor.next() != nil {
      eventCount += 1
    }

    #expect(eventCount == 1025)
  }
}
