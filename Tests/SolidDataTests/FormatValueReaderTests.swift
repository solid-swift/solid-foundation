//
//  FormatValueReaderTests.swift
//  SolidFoundation
//
//  Created by Codex on 5/14/26.
//

import Foundation
import SolidData
import Testing


@Suite("Format Value Reader Tests")
struct FormatValueReaderTests {

  @Test("Default strict trailing data error is semantic")
  func defaultStrictTrailingDataErrorIsSemantic() throws {
    var reader = FormatValueReader(
      reader: TwoRootValueReader(),
      data: Data([0x01]),
      format: TestFormat.instance,
      unexpectedEndError: { TestError.unexpectedEnd },
      requiresEndOfStream: true
    )

    do {
      _ = try reader.read()
      Issue.record("Expected trailing data error")
    } catch {
      #expect(error as? FormatValueReaderError == .trailingData)
    }
  }
}


private enum TestFormat: Format, Sendable {
  case instance

  var kind: FormatKind { .binary }

  func supports(type: ValueType) -> Bool { true }
}


private enum TestError: Error, Sendable, Equatable {
  case unexpectedEnd
}


private struct TwoRootValueReader: FormatStreamReader {

  private var emitted = false

  var format: Format { TestFormat.instance }

  mutating func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ParseEvent>
  ) throws -> FormatStreamReadStatus {
    if !emitted, !input.isEmpty {
      output.append(.scalar(.materialized(.number(1))))
      output.append(.scalar(.materialized(.number(2))))
      emitted = true
      return .producedOutput
    }
    return isFinal ? .endOfStream : .needMoreInput
  }
}
