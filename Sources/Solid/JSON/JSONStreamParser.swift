//
//  JSONStreamParser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData


/// Incremental JSON parser that emits ``ValueEvent`` instances.
public struct JSONPushParser {

  public enum Error: Swift.Error {
    case unexpectedEndOfStream
    case invalidToken
    case invalidString
    case invalidNumber
    case invalidBoolean
    case invalidEscapeSequence
    case invalidUTF8String
    case invalidStructure(String)
  }

  private enum RootState {
    case expectingValue
    case complete
  }

  private enum ArrayState {
    case expectValueOrEnd
    case expectValue
    case expectCommaOrEnd
  }

  private enum ObjectState {
    case expectKeyOrEnd
    case expectKey
    case expectColon
    case expectValue
    case expectCommaOrEnd
  }

  private enum ContainerState {
    case array(ArrayState)
    case object(ObjectState)
  }

  private var tokenizer = JSONStreamingTokenizer()
  private var containers: [ContainerState] = []
  private var rootState: RootState = .expectingValue
  private var finished = false

  public init() {}

  public mutating func feed(_ data: Data, isFinal: Bool = false) {
    tokenizer.append(data, isFinal: isFinal)
  }

  public mutating func nextEvent() throws -> ValueEvent? {
    guard !finished else { return nil }

    while true {
      guard let token = try tokenizer.nextToken() else {
        return try handleNoToken()
      }

      if rootState == .complete {
        throw Error.invalidStructure("Extra data after root value")
      }

      if let event = try handleToken(token) {
        return event
      }
    }
  }

  private mutating func handleNoToken() throws -> ValueEvent? {
    if tokenizer.isFinalized {
      if !tokenizer.isIdle || !tokenizer.isBufferEmpty {
        throw Error.unexpectedEndOfStream
      }
      if rootState == .expectingValue {
        throw Error.unexpectedEndOfStream
      }
      finished = true
    }
    return nil
  }

  private mutating func handleToken(_ token: JSONToken) throws -> ValueEvent? {
    switch token {
    case .scalar(let scalar):
      if let event = try handleScalar(scalar) {
        return event
      }
      return nil

    case .beginArray:
      try startValue()
      containers.append(.array(.expectValueOrEnd))
      return .beginArray

    case .endArray:
      guard case .array(let state) = containers.popLast() else {
        throw Error.invalidStructure("Unexpected endArray")
      }
      guard state == .expectValueOrEnd || state == .expectCommaOrEnd else {
        throw Error.invalidStructure("Unexpected endArray state")
      }
      finishValue()
      return .endArray

    case .beginObject:
      try startValue()
      containers.append(.object(.expectKeyOrEnd))
      return .beginObject

    case .endObject:
      guard case .object(let state) = containers.popLast() else {
        throw Error.invalidStructure("Unexpected endObject")
      }
      guard state == .expectKeyOrEnd || state == .expectCommaOrEnd else {
        throw Error.invalidStructure("Unexpected endObject state")
      }
      finishValue()
      return .endObject

    case .pairSeparator:
      guard case .object(let state) = containers.popLast() else {
        throw Error.invalidStructure("Unexpected pair separator")
      }
      guard state == .expectColon else {
        throw Error.invalidStructure("Unexpected pair separator state")
      }
      containers.append(.object(.expectValue))
      return nil

    case .elementSeparator:
      guard let container = containers.popLast() else {
        throw Error.invalidStructure("Unexpected element separator")
      }
      switch container {
      case .array(let state):
        guard state == .expectCommaOrEnd else {
          throw Error.invalidStructure("Unexpected element separator in array")
        }
        containers.append(.array(.expectValue))
      case .object(let state):
        guard state == .expectCommaOrEnd else {
          throw Error.invalidStructure("Unexpected element separator in object")
        }
        containers.append(.object(.expectKey))
      }
      return nil
    }
  }

  private mutating func handleScalar(_ scalar: JSONToken.Scalar) throws -> ValueEvent? {
    if case .object(let state) = containers.last {
      if state == .expectKeyOrEnd || state == .expectKey {
        guard case .string(let string) = scalar else {
          throw Error.invalidStructure("Expected string key")
        }
        _ = containers.popLast()
        containers.append(.object(.expectColon))
        return .key(.string(string))
      }
    }

    try startValue()
    let value = try convertScalar(scalar)
    finishValue()
    return .scalar(value)
  }

  private func convertScalar(_ scalar: JSONToken.Scalar) throws -> Value {
    switch scalar {
    case .null:
      return .null
    case .bool(let value):
      return .bool(value)
    case .string(let value):
      return .string(value)
    case .number(let number):
      guard let num = Value.TextNumber(text: number.value) else {
        throw Error.invalidNumber
      }
      return .number(num)
    }
  }

  private mutating func startValue() throws {
    if let container = containers.last {
      switch container {
      case .array(let state):
        guard state == .expectValue || state == .expectValueOrEnd else {
          throw Error.invalidStructure("Unexpected value in array")
        }
      case .object(let state):
        guard state == .expectValue else {
          throw Error.invalidStructure("Unexpected value in object")
        }
      }
    } else {
      guard rootState == .expectingValue else {
        throw Error.invalidStructure("Multiple root values")
      }
    }
  }

  private mutating func finishValue() {
    guard let container = containers.popLast() else {
      rootState = .complete
      return
    }
    switch container {
    case .array:
      containers.append(.array(.expectCommaOrEnd))
    case .object:
      containers.append(.object(.expectCommaOrEnd))
    }
  }
}

private struct JSONStreamingTokenizer {

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

  private static let whitespaceASCII: [UInt8] = [
    0x09,    // Horizontal tab
    0x0A,    // Line feed
    0x0D,    // Carriage return
    0x20,    // Space
  ]

  private mutating func consumeWhitespace() {
    while let byte = peekByte(), Self.whitespaceASCII.contains(byte) {
      advance()
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
