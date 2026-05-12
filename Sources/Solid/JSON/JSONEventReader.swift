//
//  JSONEventReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

import Foundation
import SolidData

/// A push parser for JSON that produces ``ParseEvent`` values with zero-copy ``ScalarRef`` references.
///
/// Merges tokenization and structural validation into a single pass. Strings and numbers
/// are captured as raw byte slices into the input buffer — escape processing and number
/// parsing are deferred to ``JSONScalarResolver`` at materialization time.
public struct JSONEventReader: ~Copyable, FormatEventReader, Sendable {

  // MARK: - Token scanning state

  private enum TokenState: Sendable {
    case idle
    case string(StringScanState)
    case number(NumberScanState)
    case keyword(KeywordState)
  }

  private struct StringScanState: Sendable {
    /// Buffer offset where string content starts (after the opening `"`).
    var mark: ParseBuffer.Position
    /// Whether the previous byte was an unprocessed `\`.
    var escaping: Bool = false
    /// Whether any JSON escape sequence was observed while scanning this string.
    var containsEscapes: Bool = false
  }

  private enum NumberPhase: Sendable {
    case start
    case minus
    case intZero
    case intDigits
    case fracStart
    case fracDigits
    case expStart
    case expSign
    case expDigits
  }

  private struct NumberScanState: Sendable {
    /// Buffer offset where the number starts.
    var mark: ParseBuffer.Position
    var phase: NumberPhase = .start
    var isInteger: Bool = true

    var isAccepting: Bool {
      switch phase {
      case .intZero, .intDigits, .fracDigits, .expDigits:
        return true
      default:
        return false
      }
    }
  }

  private struct KeywordState: Sendable {
    var expected: ContiguousArray<UInt8>
    var index: Int = 0
    var scalarRef: ScalarRef
  }

  // MARK: - Container tracking

  private enum ArrayState: Sendable {
    case expectValueOrEnd
    case expectValue
    case expectCommaOrEnd
  }

  private enum ObjectState: Sendable {
    case expectKeyOrEnd
    case expectKey
    case expectColon
    case expectValue
    case expectCommaOrEnd
  }

  private enum ContainerFrame: Sendable {
    case array(ArrayState)
    case object(ObjectState)
  }

  private enum RootState: Sendable {
    case expectingValue
    case complete
  }

  // MARK: - State

  private var buffer = ParseBuffer()
  private var finalReceived = false
  private var tokenState: TokenState = .idle
  private var containers: ContiguousArray<ContainerFrame> = []
  private var rootState: RootState = .expectingValue
  private var rootCompletionYielded = false
  private var _isFinished = false
  private let _resolver = JSONScalarResolver()

  // MARK: - FormatEventReader

  public init() {}

  public var format: Format { JSON.format }
  public var scalarResolver: any ScalarResolver { _resolver }
  public var isFinished: Bool { _isFinished }

  public mutating func feedInput(_ data: consuming Data, isFinal: Bool) {
    if !data.isEmpty {
      buffer.append(data)
    }
    if isFinal {
      finalReceived = true
    }
  }

  public mutating func readEvent() throws -> ParseEvent? {
    guard !_isFinished else { return nil }

    // Resume in-progress tokenization
    switch tokenState {
    case .string(var state):
      if let event = try continueString(&state) {
        tokenState = .idle
        return event
      }
      tokenState = .string(state)
      return nil

    case .number(var state):
      if let event = try continueNumber(&state) {
        tokenState = .idle
        return event
      }
      tokenState = .number(state)
      return nil

    case .keyword(var state):
      if let event = try continueKeyword(&state) {
        tokenState = .idle
        return event
      }
      tokenState = .keyword(state)
      return nil

    case .idle:
      break
    }

    // Main dispatch loop — loops on non-event-producing tokens (`,` and `:`)
    while true {
      skipWhitespace()

      guard !buffer.isEmpty else {
        if finalReceived {
          if case .expectingValue = rootState {
            throw JSON.Error.unexpectedEndOfStream
          }
          _isFinished = true
        }
        return nil
      }

      if case .complete = rootState {
        guard rootCompletionYielded else {
          rootCompletionYielded = true
          return nil
        }
        skipWhitespace()
        guard !buffer.isEmpty else {
          if finalReceived {
            _isFinished = true
          }
          return nil
        }
        throw JSON.Error.invalidStructure("Extra data after root value")
      }

      guard let byte = buffer.peekByte() else {
        return nil
      }

      switch byte {
      case JSONStructure.beginArray:
        _ = try readByte()
        try validateValuePosition()
        containers.append(.array(.expectValueOrEnd))
        return .beginArray(count: nil)

      case JSONStructure.endArray:
        _ = try readByte()
        guard case .array(let state) = containers.last else {
          throw JSON.Error.invalidStructure("Unexpected ]")
        }
        guard state == .expectValueOrEnd || state == .expectCommaOrEnd else {
          throw JSON.Error.invalidStructure("Unexpected ] in array")
        }
        containers.removeLast()
        didFinishValue()
        return .endArray

      case JSONStructure.beginObject:
        _ = try readByte()
        try validateValuePosition()
        containers.append(.object(.expectKeyOrEnd))
        return .beginObject(count: nil)

      case JSONStructure.endObject:
        _ = try readByte()
        guard case .object(let state) = containers.last else {
          throw JSON.Error.invalidStructure("Unexpected }")
        }
        guard state == .expectKeyOrEnd || state == .expectCommaOrEnd else {
          throw JSON.Error.invalidStructure("Unexpected } in object")
        }
        containers.removeLast()
        didFinishValue()
        return .endObject

      case JSONStructure.pairSeparator:
        _ = try readByte()
        guard case .object(.expectColon) = containers.last else {
          throw JSON.Error.invalidStructure("Unexpected :")
        }
        containers[containers.count - 1] = .object(.expectValue)
        continue // no event produced, loop for value

      case JSONStructure.elementSeparator:
        _ = try readByte()
        guard let container = containers.last else {
          throw JSON.Error.invalidStructure("Unexpected ,")
        }
        switch container {
        case .array(let state):
          guard state == .expectCommaOrEnd else {
            throw JSON.Error.invalidStructure("Unexpected , in array")
          }
          containers[containers.count - 1] = .array(.expectValue)
        case .object(let state):
          guard state == .expectCommaOrEnd else {
            throw JSON.Error.invalidStructure("Unexpected , in object")
          }
          containers[containers.count - 1] = .object(.expectKey)
        }
        continue // no event produced, loop for next key/value

      case JSONStructure.quotationMark:
        _ = try readByte() // consume opening "
        var state = StringScanState(mark: buffer.mark())
        if let event = try continueString(&state) {
          return event
        }
        tokenState = .string(state)
        return nil

      case JSONStructure.nullStart:
        var state = KeywordState(
          expected: [0x6E, 0x75, 0x6C, 0x6C],
          scalarRef: .null
        )
        if let event = try continueKeyword(&state) {
          return event
        }
        tokenState = .keyword(state)
        return nil

      case JSONStructure.trueStart:
        var state = KeywordState(
          expected: [0x74, 0x72, 0x75, 0x65],
          scalarRef: .bool(true)
        )
        if let event = try continueKeyword(&state) {
          return event
        }
        tokenState = .keyword(state)
        return nil

      case JSONStructure.falseStart:
        var state = KeywordState(
          expected: [0x66, 0x61, 0x6C, 0x73, 0x65],
          scalarRef: .bool(false)
        )
        if let event = try continueKeyword(&state) {
          return event
        }
        tokenState = .keyword(state)
        return nil

      default:
        if isNumberStart(byte) {
          var state = NumberScanState(mark: buffer.mark())
          if let event = try continueNumber(&state) {
            return event
          }
          tokenState = .number(state)
          return nil
        }
        throw JSON.Error.invalidToken
      }
    }
  }

  // MARK: - String scanning (zero-copy)

  /// Scan for the closing `"` without processing escape sequences.
  ///
  /// Tracks `\` state to skip escaped characters. The raw bytes between the opening
  /// and closing quotes (with escape sequences still present) are captured as a
  /// zero-copy ``ParseBuffer/Region`` for deferred unescaping by ``JSONScalarResolver``.
  private mutating func continueString(_ state: inout StringScanState) throws -> ParseEvent? {
    while true {
      let action = buffer.withContiguousReadableBytes { bytes -> StringScanAction in
        guard !bytes.isEmpty else {
          return .needMoreInput
        }

        if state.escaping {
          return .consumeEscaped
        }

        var index = bytes.startIndex
        while index < bytes.endIndex {
          switch bytes[index] {
          case JSONStructure.quotationMark:
            return .finish(consumed: index - bytes.startIndex)
          case JSONStructure.escape:
            return .escape(consumed: index - bytes.startIndex + 1)
          case 0x00...0x1F:
            return .invalidString
          default:
            bytes.formIndex(after: &index)
          }
        }
        return .consume(consumed: bytes.count)
      }

      switch action {
      case .consumeEscaped:
        try buffer.advanceInCurrentSegment(count: 1)
        state.escaping = false
        continue

      case .consume(let consumed):
        try buffer.advanceInCurrentSegment(count: consumed)
        continue

      case .escape(let consumed):
        try buffer.advanceInCurrentSegment(count: consumed)
        state.escaping = true
        state.containsEscapes = true
        continue

      case .finish(let consumed):
        if consumed > 0 {
          try buffer.advanceInCurrentSegment(count: consumed)
        }
        // End of string — slice from markOffset to offset (exclusive)
        let region = buffer.region(from: state.mark, to: buffer.mark())
        try buffer.advanceInCurrentSegment(count: 1) // consume closing "
        let ref = ScalarRef(
          kind: .string,
          region: region,
          metadata: .init(stringContainsEscapes: state.containsEscapes)
        )
        return try handleScalar(ref, isString: true)

      case .invalidString:
        throw JSON.Error.invalidString

      case .needMoreInput:
        if finalReceived {
          throw JSON.Error.unexpectedEndOfStream
        }
        return nil
      }
    }
  }

  // MARK: - Number scanning (zero-copy)

  /// Scan number bytes using the JSON number phase machine.
  ///
  /// The raw number text is captured as a zero-copy slice for deferred
  /// parsing by ``JSONScalarResolver``.
  private mutating func continueNumber(_ state: inout NumberScanState) throws -> ParseEvent? {
    while true {
      let action = buffer.withContiguousReadableBytes { bytes -> NumberScanAction in
        guard !bytes.isEmpty else {
          return .needMoreInput
        }

        var phase = state.phase
        var isInteger = state.isInteger
        var index = bytes.startIndex
        while index < bytes.endIndex {
          switch Self.numberAction(current: phase, byte: bytes[index]) {
          case .consume(let newPhase):
            phase = newPhase
            if isInteger {
              switch newPhase {
              case .fracStart, .fracDigits, .expStart, .expSign, .expDigits:
                isInteger = false
              default:
                break
              }
            }
            bytes.formIndex(after: &index)
          case .stop:
            return .stop(
              consumed: index - bytes.startIndex,
              phase: phase,
              isInteger: isInteger
            )
          case .invalid:
            return .invalid
          }
        }
        return .consume(
          consumed: bytes.count,
          phase: phase,
          isInteger: isInteger
        )
      }

      switch action {
      case .consume(let consumed, let phase, let isInteger):
        if consumed > 0 {
          try buffer.advanceInCurrentSegment(count: consumed)
        }
        state.phase = phase
        state.isInteger = isInteger
        continue

      case .stop(let consumed, let phase, let isInteger):
        if consumed > 0 {
          try buffer.advanceInCurrentSegment(count: consumed)
        }
        state.phase = phase
        state.isInteger = isInteger
        guard state.isAccepting else {
          throw JSON.Error.invalidNumber
        }
        return try finalizeNumber(state)

      case .invalid:
        throw JSON.Error.invalidNumber

      case .needMoreInput:
        if finalReceived {
          guard state.isAccepting else {
            throw JSON.Error.unexpectedEndOfStream
          }
          return try finalizeNumber(state)
        }
        return nil
      }
    }
  }

  private mutating func finalizeNumber(_ state: NumberScanState) throws -> ParseEvent {
    let region = buffer.region(from: state.mark, to: buffer.mark())
    let kind: ScalarRef.Kind = state.isInteger ? .integer : .float
    let ref = ScalarRef(kind: kind, region: region)
    return try handleScalar(ref, isString: false)
  }

  // MARK: - Keyword scanning

  private mutating func continueKeyword(_ state: inout KeywordState) throws -> ParseEvent? {
    while state.index < state.expected.count {
      guard let byte = buffer.peekByte() else {
        if finalReceived {
          throw JSON.Error.unexpectedEndOfStream
        }
        return nil
      }
      guard byte == state.expected[state.index] else {
        throw JSON.Error.invalidToken
      }
      _ = try readByte()
      state.index += 1
    }
    return try handleScalar(state.scalarRef, isString: false)
  }

  // MARK: - Structural validation

  /// Handle a completed scalar, performing structural validation and emitting the event.
  private mutating func handleScalar(_ ref: ScalarRef, isString: Bool) throws -> ParseEvent {
    // In object key position?
    if let last = containers.last, case .object(let state) = last {
      if state == .expectKeyOrEnd || state == .expectKey {
        guard isString else {
          throw JSON.Error.invalidStructure("Expected string key")
        }
        containers[containers.count - 1] = .object(.expectColon)
        return .scalar(ref)
      }
    }

    // It's a value
    try validateValuePosition()
    didFinishValue()
    return .scalar(ref)
  }

  /// Validate that a value is allowed in the current structural position.
  private mutating func validateValuePosition() throws {
    if let container = containers.last {
      switch container {
      case .array(let state):
        guard state == .expectValue || state == .expectValueOrEnd else {
          throw JSON.Error.invalidStructure("Unexpected value in array")
        }
      case .object(let state):
        guard state == .expectValue else {
          throw JSON.Error.invalidStructure("Unexpected value in object")
        }
      }
    } else {
      guard case .expectingValue = rootState else {
        throw JSON.Error.invalidStructure("Multiple root values")
      }
    }
  }

  /// Update container state after completing a value.
  private mutating func didFinishValue() {
    if containers.isEmpty {
      rootState = .complete
      rootCompletionYielded = false
      return
    }
    switch containers[containers.count - 1] {
    case .array:
      containers[containers.count - 1] = .array(.expectCommaOrEnd)
    case .object:
      containers[containers.count - 1] = .object(.expectCommaOrEnd)
    }
  }

  // MARK: - Whitespace

  /// Skip whitespace bytes. Compacts the buffer when the consumed prefix
  /// exceeds 4 KB to bound memory growth during long-running streams.
  ///
  /// Only called when `tokenState == .idle`, so no mark positions are active.
  private mutating func skipWhitespace() {
    var consumedWhitespace = false
    while true {
      let consumed = buffer.withContiguousReadableBytes { bytes in
        var index = bytes.startIndex
        while index < bytes.endIndex {
          switch bytes[index] {
          case 0x09, 0x0A, 0x0D, 0x20:
            bytes.formIndex(after: &index)
          default:
            return index - bytes.startIndex
          }
        }
        return bytes.count
      }

      guard consumed > 0 else {
        if consumedWhitespace {
          buffer.compact()
        }
        return
      }
      _ = try? buffer.advanceInCurrentSegment(count: consumed)
      consumedWhitespace = true
    }
  }

  private mutating func readByte() throws -> UInt8 {
    do {
      return try buffer.readByte()
    } catch ParseBufferError.unexpectedEnd {
      throw JSON.Error.unexpectedEndOfStream
    }
  }

  // MARK: - Number phase machine

  private func isNumberStart(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "-") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
  }

  private enum NumberAction {
    case consume(NumberPhase)
    case stop
    case invalid
  }

  private enum StringScanAction {
    case consumeEscaped
    case consume(consumed: Int)
    case escape(consumed: Int)
    case finish(consumed: Int)
    case invalidString
    case needMoreInput
  }

  private enum NumberScanAction {
    case consume(consumed: Int, phase: NumberPhase, isInteger: Bool)
    case stop(consumed: Int, phase: NumberPhase, isInteger: Bool)
    case invalid
    case needMoreInput
  }

  private static func numberAction(current: NumberPhase, byte: UInt8) -> NumberAction {
    switch current {
    case .start:
      if byte == UInt8(ascii: "-") { return .consume(.minus) }
      if byte == UInt8(ascii: "0") { return .consume(.intZero) }
      if byte >= UInt8(ascii: "1") && byte <= UInt8(ascii: "9") { return .consume(.intDigits) }
      return .invalid

    case .minus:
      if byte == UInt8(ascii: "0") { return .consume(.intZero) }
      if byte >= UInt8(ascii: "1") && byte <= UInt8(ascii: "9") { return .consume(.intDigits) }
      return .invalid

    case .intZero:
      if byte == UInt8(ascii: ".") { return .consume(.fracStart) }
      if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") { return .consume(.expStart) }
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .invalid }
      return .stop

    case .intDigits:
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .consume(.intDigits) }
      if byte == UInt8(ascii: ".") { return .consume(.fracStart) }
      if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") { return .consume(.expStart) }
      return .stop

    case .fracStart:
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .consume(.fracDigits) }
      return .invalid

    case .fracDigits:
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .consume(.fracDigits) }
      if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") { return .consume(.expStart) }
      return .stop

    case .expStart:
      if byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") { return .consume(.expSign) }
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .consume(.expDigits) }
      return .invalid

    case .expSign:
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .consume(.expDigits) }
      return .invalid

    case .expDigits:
      if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return .consume(.expDigits) }
      return .stop
    }
  }
}
