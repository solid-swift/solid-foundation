//
//  FormatStreamEncoderBufferTests.swift
//  SolidFoundation
//
//  Created by Codex on 5/11/26.
//

import Foundation
import SolidData
import Testing


@Suite("FormatStreamEncoderBuffer")
struct FormatStreamEncoderBufferTests {

  @Test("encodes events with tiny buffer and reserved capacity")
  func encodesWithTinyBufferAndReserve() throws {
    var buffer = FormatStreamEncoderBuffer(encoder: ByteRepeatingEncoder(), bufferSize: 2)

    let output = try buffer.encode(estimatedCapacity: 6) { emit in
      try emit(.scalar(.string("abc")))
      try emit(.scalar(.string("def")))
    }

    #expect(String(decoding: output, as: UTF8.self) == "abcdef")
  }
}


private struct ByteRepeatingEncoder: FormatStreamEncoder {

  var format: Format { TestFormat.instance }
  private var pending = ArraySlice<UInt8>()

  mutating func encode(
    _ event: EmitEvent,
    output: inout OutputSpan<UInt8>
  ) throws -> FormatStreamEncodeStatus {
    if pending.isEmpty {
      guard case .scalar(.string(let string)) = event else {
        return .producedOutput
      }
      pending = Array(string.utf8)[...]
    }

    while !pending.isEmpty, !output.isFull {
      output.append(pending.removeFirst())
    }
    return pending.isEmpty ? .producedOutput : .needMoreOutputSpace
  }

  mutating func finish(output: inout OutputSpan<UInt8>) throws -> FormatStreamEncodeStatus {
    .endOfStream
  }
}


private enum TestFormat: Format, Sendable {
  case instance

  var kind: FormatKind { .text }

  func supports(type: ValueType) -> Bool {
    true
  }
}
