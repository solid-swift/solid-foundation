//
//  JSONStreamingTokenizer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation

/// Byte-level streaming tokenizer for JSON input.
///
/// Incrementally consumes raw bytes and produces ``JSONToken`` values,
/// handling multi-chunk string, number, and keyword parsing with
/// surrogate pair reassembly for escaped Unicode.
struct JSONStreamingTokenizer {

  private enum State {
    case idle
    case string(StringState)
    case number(NumberState)
    case keyword(KeywordState)
  }

  private struct StringState {
    var output: [UInt8] = []
    var escaping = false
    var unicodeRemaining = 0
    var unicodeValue: UInt16 = 0
    var pendingHighSurrogate: UInt16?
    var requireUnicodeEscape = false
  }

  private enum NumberPhase {
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

  private struct NumberState {
    var text: [UInt8] = []
    var phase: NumberPhase = .start
    var isInteger = true
    var isNegative = false

    var isAccepting: Bool {
      switch phase {
      case .intZero, .intDigits, .fracDigits, .expDigits:
        return true
      default:
        return false
      }
    }
  }

  private struct KeywordState {
    var bytes: [UInt8]
    var index: Int = 0
    var kind: Kind

    enum Kind {
      case null
      case bool(Bool)
    }
  }

  private var buffer = Data()
  private var offset = 0
  private var isFinal = false
  private var state: State = .idle

  var isFinalized: Bool { isFinal }
  var isIdle: Bool {
    if case .idle = state { return true }
    return false
  }
  var isBufferEmpty: Bool { offset >= buffer.count }

  mutating func append(_ data: Data, isFinal: Bool) {
    if !data.isEmpty {
      buffer.append(data)
    }
    if isFinal {
      self.isFinal = true
    }
  }

  mutating func nextToken() throws -> JSONToken? {
    switch state {
    case .string:
      return try continueString()
    case .number:
      return try continueNumber()
    case .keyword:
      return try continueKeyword()
    case .idle:
      break
    }

    consumeWhitespace()
    guard let byte = peekByte() else {
      return nil
    }

    switch byte {
    case JSONStructure.beginArray:
      advance()
      return .beginArray
    case JSONStructure.endArray:
      advance()
      return .endArray
    case JSONStructure.beginObject:
      advance()
      return .beginObject
    case JSONStructure.endObject:
      advance()
      return .endObject
    case JSONStructure.elementSeparator:
      advance()
      return .elementSeparator
    case JSONStructure.pairSeparator:
      advance()
      return .pairSeparator
    case JSONStructure.quotationMark:
      advance()
      state = .string(StringState())
      return try continueString()
    case JSONStructure.nullStart:
      return try startKeyword(bytes: [0x6E, 0x75, 0x6C, 0x6C], kind: .null)
    case JSONStructure.falseStart:
      return try startKeyword(bytes: [0x66, 0x61, 0x6C, 0x73, 0x65], kind: .bool(false))
    case JSONStructure.trueStart:
      return try startKeyword(bytes: [0x74, 0x72, 0x75, 0x65], kind: .bool(true))
    default:
      if isNumberStart(byte) {
        state = .number(NumberState())
        return try continueNumber()
      }
      throw JSONPushParser.Error.invalidToken
    }
  }

  private mutating func startKeyword(bytes: [UInt8], kind: KeywordState.Kind) throws -> JSONToken? {
    state = .keyword(KeywordState(bytes: bytes, kind: kind))
    return try continueKeyword()
  }

  private mutating func continueKeyword() throws -> JSONToken? {
    guard case .keyword(var keyword) = state else { return nil }

    while let byte = peekByte() {
      let expected = keyword.bytes[keyword.index]
      guard byte == expected else {
        throw JSONPushParser.Error.invalidToken
      }
      advance()
      keyword.index += 1
      if keyword.index == keyword.bytes.count {
        state = .idle
        switch keyword.kind {
        case .null:
          return .scalar(.null)
        case .bool(let value):
          return .scalar(.bool(value))
        }
      }
    }

    state = .keyword(keyword)
    if isFinal {
      throw JSONPushParser.Error.unexpectedEndOfStream
    }
    return nil
  }

  private mutating func continueNumber() throws -> JSONToken? {
    guard case .number(var number) = state else { return nil }

    while let byte = peekByte() {
      switch numberAction(current: number.phase, byte: byte) {
      case .consume(let phase):
        number.phase = phase
        number.text.append(byte)
        advance()
        if phase == .fracStart || phase == .expStart || phase == .expSign || phase == .expDigits {
          number.isInteger = false
        }
        if phase == .minus {
          number.isNegative = true
        }
        continue
      case .stop:
        guard number.isAccepting else {
          throw JSONPushParser.Error.invalidNumber
        }
        state = .idle
        return try makeNumberToken(number)
      case .invalid:
        throw JSONPushParser.Error.invalidNumber
      }
    }

    state = .number(number)
    if isFinal {
      guard number.isAccepting else {
        throw JSONPushParser.Error.unexpectedEndOfStream
      }
      state = .idle
      return try makeNumberToken(number)
    }
    return nil
  }

  private func makeNumberToken(_ number: NumberState) throws -> JSONToken {
    guard let string = String(bytes: number.text, encoding: .utf8) else {
      throw JSONPushParser.Error.invalidNumber
    }
    let scalar = JSONToken.Scalar.Number(string, isInteger: number.isInteger, isNegative: number.isNegative)
    return .scalar(.number(scalar))
  }

  private mutating func continueString() throws -> JSONToken? {
    guard case .string(var string) = state else { return nil }

    while let byte = peekByte() {
      advance()

      if string.unicodeRemaining > 0 {
        guard let value = hexValue(byte) else {
          throw JSONPushParser.Error.invalidEscapeSequence
        }
        string.unicodeValue = (string.unicodeValue << 4) | value
        string.unicodeRemaining -= 1
        if string.unicodeRemaining == 0 {
          try appendUnicodeValue(&string, codeUnit: string.unicodeValue)
          string.unicodeValue = 0
        }
        continue
      }

      if string.escaping {
        if string.requireUnicodeEscape && byte != UInt8(ascii: "u") {
          throw JSONPushParser.Error.invalidEscapeSequence
        }
        string.escaping = false
        if byte == UInt8(ascii: "u") {
          string.unicodeRemaining = 4
          string.unicodeValue = 0
          string.requireUnicodeEscape = false
          continue
        }
        try appendEscape(&string, byte: byte)
        continue
      }

      if string.requireUnicodeEscape {
        guard byte == UInt8(ascii: "\\") else {
          throw JSONPushParser.Error.invalidEscapeSequence
        }
        string.escaping = true
        continue
      }

      switch byte {
      case JSONStructure.quotationMark:
        guard string.unicodeRemaining == 0, !string.escaping, string.pendingHighSurrogate == nil else {
          throw JSONPushParser.Error.invalidEscapeSequence
        }
        let text = try finalizeString(string.output)
        state = .idle
        return .scalar(.string(text))
      case UInt8(ascii: "\\"):
        string.escaping = true
      case 0x00...0x1F:
        throw JSONPushParser.Error.invalidString
      default:
        string.output.append(byte)
      }
    }

    state = .string(string)
    if isFinal {
      throw JSONPushParser.Error.unexpectedEndOfStream
    }
    return nil
  }

  private func finalizeString(_ bytes: [UInt8]) throws -> String {
    guard let text = String(bytes: bytes, encoding: .utf8) else {
      throw JSONPushParser.Error.invalidUTF8String
    }
    return text
  }

  private mutating func appendUnicodeValue(_ state: inout StringState, codeUnit: UInt16) throws {
    if let high = state.pendingHighSurrogate {
      guard isLowSurrogate(codeUnit) else {
        throw JSONPushParser.Error.invalidEscapeSequence
      }
      let scalar = try decodeSurrogatePair(high: high, low: codeUnit)
      appendScalar(scalar, to: &state.output)
      state.pendingHighSurrogate = nil
      return
    }

    if isHighSurrogate(codeUnit) {
      state.pendingHighSurrogate = codeUnit
      state.requireUnicodeEscape = true
      return
    }

    guard !isLowSurrogate(codeUnit) else {
      throw JSONPushParser.Error.invalidEscapeSequence
    }

    guard let scalar = UnicodeScalar(codeUnit) else {
      throw JSONPushParser.Error.invalidEscapeSequence
    }
    appendScalar(scalar, to: &state.output)
  }

  private func appendEscape(_ state: inout StringState, byte: UInt8) throws {
    switch byte {
    case UInt8(ascii: "\""):
      state.output.append(UInt8(ascii: "\""))
    case UInt8(ascii: "\\"):
      state.output.append(UInt8(ascii: "\\"))
    case UInt8(ascii: "/"):
      state.output.append(UInt8(ascii: "/"))
    case UInt8(ascii: "b"):
      state.output.append(0x08)
    case UInt8(ascii: "f"):
      state.output.append(0x0C)
    case UInt8(ascii: "n"):
      state.output.append(0x0A)
    case UInt8(ascii: "r"):
      state.output.append(0x0D)
    case UInt8(ascii: "t"):
      state.output.append(0x09)
    default:
      throw JSONPushParser.Error.invalidEscapeSequence
    }
  }

  private func appendScalar(_ scalar: UnicodeScalar, to output: inout [UInt8]) {
    output.append(contentsOf: String(scalar).utf8)
  }

  private func decodeSurrogatePair(high: UInt16, low: UInt16) throws -> UnicodeScalar {
    let highValue = UInt32(high) - 0xD800
    let lowValue = UInt32(low) - 0xDC00
    let scalarValue = 0x10000 + ((highValue << 10) | lowValue)
    guard let scalar = UnicodeScalar(scalarValue) else {
      throw JSONPushParser.Error.invalidEscapeSequence
    }
    return scalar
  }

  private func isHighSurrogate(_ value: UInt16) -> Bool {
    value >= 0xD800 && value <= 0xDBFF
  }

  private func isLowSurrogate(_ value: UInt16) -> Bool {
    value >= 0xDC00 && value <= 0xDFFF
  }

  private func hexValue(_ byte: UInt8) -> UInt16? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      return UInt16(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"):
      return UInt16(byte - UInt8(ascii: "a") + 10)
    case UInt8(ascii: "A")...UInt8(ascii: "F"):
      return UInt16(byte - UInt8(ascii: "A") + 10)
    default:
      return nil
    }
  }

  private func isNumberStart(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "-") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
  }

  private enum NumberAction {
    case consume(NumberPhase)
    case stop
    case invalid
  }

  private func numberAction(current: NumberPhase, byte: UInt8) -> NumberAction {
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

  /// Skips whitespace bytes, compacting the buffer when the consumed prefix exceeds 4KB
  /// to bound memory growth during long-running streams.
  private mutating func consumeWhitespace() {
    var pos = offset
    let end = buffer.count
    scan: while pos < end {
      switch buffer[pos] {
      case 0x09, 0x0A, 0x0D, 0x20:
        pos += 1
      default:
        break scan
      }
    }
    offset = pos
    if offset > 4096 {
      buffer.removeSubrange(0..<offset)
      offset = 0
    }
  }

  private func peekByte() -> UInt8? {
    guard offset < buffer.count else { return nil }
    return buffer[offset]
  }

  private mutating func advance() {
    offset += 1
    if offset > 4096 {
      buffer.removeSubrange(0..<offset)
      offset = 0
    }
  }
}
