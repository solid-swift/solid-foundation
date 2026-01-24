//
//  JSONTokenReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/24/24.
//

import Foundation

struct JSONTokenReader {

  public enum Error: Swift.Error {

    public enum InvalidData {
      case invalidToken
      case invalidString
      case invalidNumber
      case invalidBoolean
      case invalidEscapeSequence
      case unexpectedValue(expected: [JSONToken.Scalar.Kind], found: JSONToken.Scalar.Kind)
      case unexpectedToken(expected: [JSONToken.Kind], found: JSONToken.Kind)
      case unescapedControlCharacterInString(ascii: UInt8, in: String, index: Int)
    }

    case invalidData(InvalidData, location: Location)
    case unexpectedEndOfStream
    case fragmentDisallowed(location: Location)
    case noValue(location: Location)
  }

  public struct Location {
    public var line: Int
    public var column: Int

    public func advanced(by distance: Int) -> Location {
      Location(line: line, column: column + distance)
    }
  }

  private static let whitespaceASCII: [UInt8] = [
    0x09,    // Horizontal tab
    0x0A,    // Line feed or New line
    0x0D,    // Carriage return
    0x20,    // Space
  ]

  typealias Index = Int
  typealias IndexDistance = Int

  class UTF8Source {
    let buffer: Data
    var offset: Int
    var location: Location

    init(buffer: Data) {
      self.buffer = buffer
      self.offset = 0
      self.location = Location(line: 1, column: 1)
    }

    func peek(count: Int) -> UInt8? {
      guard offset + count < buffer.endIndex else {
        return nil
      }
      return buffer[offset + count]
    }

    func peekASCII() throws -> UInt8? {
      try checkNext()
      guard buffer[offset] < 0x80 else {
        return nil
      }
      return buffer[offset]
    }

    func skip(count: Int) throws {
      for idx in 0..<count {
        try checkNext()
        offset += 1
        if offset >= buffer.endIndex {
          guard idx == count - 1 else {
            throw Error.unexpectedEndOfStream
          }
          return
        }
        let ascii = buffer[offset]
        if ascii == 0x0A || ascii == 0x0D {
          location.line += 1
          location.column = 1
        } else {
          location.column += 1
        }
      }
    }

    func takeASCII() throws -> UInt8? {
      guard let ascii = try peekASCII() else {
        return nil
      }
      offset += 1
      return ascii
    }

    func checkNext() throws {
      guard hasNext() else {
        throw Error.unexpectedEndOfStream
      }
    }

    func hasNext() -> Bool {
      return offset + 1 <= buffer.endIndex
    }
  }

  let source: UTF8Source
  var location: Location

  public init(data: Data) {
    self.init(source: UTF8Source(buffer: data))
  }

  public init(string: String) {
    self.init(source: UTF8Source(buffer: string.data(using: .utf8, allowLossyConversion: true) ?? Data()))
  }

  private init(source: UTF8Source) {
    self.source = source
    self.location = Location(line: 1, column: 1)
  }

  func consumeWhitespace() {
    while let char = try? source.peekASCII(), Self.whitespaceASCII.contains(char) {
      try? source.skip(count: 1)
    }
  }

  func consumeStructure(_ ascii: UInt8) throws -> Bool {
    consumeWhitespace()
    if try !consumeASCII(ascii) {
      return false
    }
    consumeWhitespace()
    return true
  }

  func consumeASCII(_ ascii: UInt8) throws -> Bool {
    let taken = try source.peekASCII()
    guard taken == ascii else {
      return false
    }
    try source.skip(count: 1)
    return true
  }

  func consumeASCIISequence(_ sequence: String) throws -> Bool {
    for scalar in sequence.unicodeScalars where try !consumeASCII(UInt8(scalar.value)) {
      return false
    }
    return true
  }

  func takeMatching(_ match: @escaping (UInt8) -> Bool) -> ([Character]) throws -> ([Character])? {
    return { input in
      guard let taken = try self.source.takeASCII(), match(taken) else {
        return nil
      }
      return (input + [Character(UnicodeScalar(taken))])
    }
  }

  // MARK: - String Parsing

  func parseString() throws -> String {
    consumeWhitespace()

    let start = source.location

    guard try consumeASCII(JSONStructure.quotationMark) else {
      throw Error.invalidData(.invalidString, location: start)
    }

    var stringStart = source.offset
    var copy = 0
    var output: String?

    while let byte = source.peek(count: copy) {
      switch byte {
      case JSONStructure.quotationMark:
        try source.skip(count: copy + 1)
        guard var result = output else {
          // if we don't have an output string we create a new string
          return try makeString(at: stringStart..<stringStart + copy, start: start)
        }
        // if we have an output string we append
        result += try makeString(at: stringStart..<stringStart + copy, start: start)
        return result

      case 0...31:
        // All Unicode characters may be placed within the
        // quotation marks, except for the characters that must be escaped:
        // quotation mark, reverse solidus, and the control characters (U+0000
        // through U+001F).
        var string = output ?? ""
        let errorIndex = source.offset + copy
        string += try makeString(at: stringStart...errorIndex, start: start)
        throw Error.invalidData(
          .unescapedControlCharacterInString(ascii: byte, in: string, index: errorIndex),
          location: start
        )

      case UInt8(ascii: "\\"):
        try source.skip(count: copy + 1)
        output = try (output ?? "") + makeString(at: stringStart..<stringStart + copy, start: start)

        let escaped = try parseEscapeSequence(start: source.location.advanced(by: copy))
        output = (output ?? "") + escaped
        stringStart = source.offset
        copy = 0

      default:
        copy += 1
        continue
      }
    }

    throw Error.unexpectedEndOfStream
  }

  private func makeString<R: RangeExpression<Int>>(at range: R, start: Location) throws -> String {
    let raw = source.buffer[range]
    guard let str = String(bytes: raw, encoding: .utf8) else {
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }
    return str
  }

  func parseEscapeSequence(start: Location) throws -> String {

    guard let byte = try source.takeASCII() else {
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }

    let output: String
    switch byte {
    case 0x22: output = "\""
    case 0x5C: output = "\\"
    case 0x2F: output = "/"
    case 0x62: output = "\u{08}"    // \b
    case 0x66: output = "\u{0C}"    // \f
    case 0x6E: output = "\u{0A}"    // \n
    case 0x72: output = "\u{0D}"    // \r
    case 0x74: output = "\u{09}"    // \t
    case 0x75: output = try parseUnicodeSequence(start: start)    // \u
    default:
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }
    return output
  }

  func parseUnicodeSequence(start: Location) throws -> String {

    guard let codeUnit = try parseCodeUnit() else {
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }

    let isLeadSurrogate = UTF16.isLeadSurrogate(codeUnit)
    let isTrailSurrogate = UTF16.isTrailSurrogate(codeUnit)

    guard isLeadSurrogate || isTrailSurrogate else {
      // The code units that are neither lead surrogates nor trail surrogates
      // form valid unicode scalars.
      guard let scalar = UnicodeScalar(codeUnit) else {
        throw Error.invalidData(.invalidEscapeSequence, location: start)
      }
      return String(scalar)
    }

    // Surrogates must always come in pairs.
    guard isLeadSurrogate else {
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }

    if try !consumeASCIISequence("\\u") {
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }

    guard let trailCodeUnit = try parseCodeUnit(), UTF16.isTrailSurrogate(trailCodeUnit) else {
      throw Error.invalidData(.invalidEscapeSequence, location: start)
    }

    return String(UTF16.decode(UTF16.EncodedScalar([codeUnit, trailCodeUnit])))
  }

  func isHexChr(_ byte: UInt8) -> Bool {
    return (byte >= 0x30 && byte <= 0x39)
      || (byte >= 0x41 && byte <= 0x46)
      || (byte >= 0x61 && byte <= 0x66)
  }

  func parseCodeUnit() throws -> UTF16.CodeUnit? {
    let hexParser = takeMatching(isHexChr)
    guard
      let result = try hexParser([]).flatMap(hexParser).flatMap(hexParser).flatMap(hexParser),
      let value = Int(String(result), radix: 16)
    else {
      return nil
    }
    return UTF16.CodeUnit(value)
  }

  // MARK: - Number parsing

  private static let zero = UInt8(ascii: "0")
  private static let one = UInt8(ascii: "1")
  private static let nine = UInt8(ascii: "9")
  private static let minus = UInt8(ascii: "-")
  private static let plus = UInt8(ascii: "+")
  private static let lowerExponent = UInt8(ascii: "e")
  private static let upperExponent = UInt8(ascii: "E")
  private static let decimalSeparator = UInt8(ascii: ".")
  private static let allDigits = (zero...nine)
  private static let oneToNine = (one...nine)

  private static let numberCodePoints: [UInt8] = {
    var numberCodePoints = Array(zero...nine)
    numberCodePoints.append(contentsOf: [decimalSeparator, minus, plus, lowerExponent, upperExponent])
    return numberCodePoints
  }()


  func parseNumber() throws -> JSONToken.Scalar.Number {

    let start = source.location

    var isNegative = false
    var string = ""
    var isInteger = true
    var exponent = 0
    var ascii: UInt8 = 0    // set by nextASCII()

    /// Validate the input is a valid JSON number, also gather the following
    /// about the input: isNegative, isInteger, the exponent and if it is +/-,
    /// and finally the count of digits including excluding an '.'
    ///
    func checkJSONNumber() throws -> Bool {
      // Return true if the next character is any one of the valid JSON number characters
      func nextASCII() throws -> Bool {
        guard let char = try source.peekASCII(), Self.numberCodePoints.contains(char) else { return false }
        try source.skip(count: 1)
        ascii = char
        string.append(Character(UnicodeScalar(ascii)))
        return true
      }

      // Consume as many digits as possible and return with the next non-digit
      // or nil if end of string.
      func readDigits() throws -> UInt8? {
        while let char = try source.peekASCII() {
          if !Self.allDigits.contains(char) {
            return char
          }
          string.append(Character(UnicodeScalar(char)))
          try source.skip(count: 1)
        }
        return nil
      }

      guard try nextASCII() else { return false }

      if ascii == Self.minus {
        isNegative = true
        guard try nextASCII() else { return false }
      }

      if Self.oneToNine.contains(ascii) {
        guard let char = try readDigits() else { return true }
        ascii = char
        if [Self.decimalSeparator, Self.lowerExponent, Self.upperExponent].contains(ascii) {
          guard try nextASCII()
          else { return false }    // There should be at least one char as readDigits didn't remove the '.eE'
        }
      } else if ascii == Self.zero {
        guard try nextASCII() else { return true }
      } else {
        throw Error.invalidData(.invalidNumber, location: start)
      }

      if ascii == Self.decimalSeparator {
        isInteger = false
        guard try readDigits() != nil else { return true }
        guard try nextASCII() else { return true }
      } else if Self.allDigits.contains(ascii) {
        throw Error.invalidData(.invalidNumber, location: start)
      }

      guard ascii == Self.lowerExponent || ascii == Self.upperExponent else {
        // End of valid number characters
        return true
      }

      // Process the exponent
      isInteger = false
      guard try nextASCII() else { return false }
      if ascii == Self.minus || ascii == Self.plus {
        guard try nextASCII() else { return false }
      }
      guard Self.allDigits.contains(ascii) else { return false }
      exponent = Int(ascii - Self.zero)
      while try nextASCII() {
        guard Self.allDigits.contains(ascii) else { return false }    // Invalid exponent character
        exponent = (exponent * 10) + Int(ascii - Self.zero)
      }
      return true
    }

    guard try checkJSONNumber() else {
      throw Error.invalidData(.invalidNumber, location: start)
    }

    return .init(string, isInteger: isInteger, isNegative: isNegative)
  }

  // MARK: - Token parsing

  func readString() throws -> String {
    let start = source.location
    let scalar = try readScalar()
    guard case .string(let string) = scalar else {
      throw Error.invalidData(.unexpectedValue(expected: [.string], found: scalar.kind), location: start)
    }
    return string
  }

  func readNumber() throws -> JSONToken.Scalar.Number {
    let start = source.location
    let scalar = try readScalar()
    guard case .number(let number) = scalar else {
      throw Error.invalidData(.unexpectedValue(expected: [.string], found: scalar.kind), location: start)
    }
    return number
  }

  func readBool() throws -> Bool {
    let start = source.location
    let scalar = try readScalar()
    guard case .bool(let bool) = scalar else {
      throw Error.invalidData(.unexpectedValue(expected: [.bool], found: scalar.kind), location: start)
    }
    return bool
  }

  func readScalar() throws -> JSONToken.Scalar {
    let start = source.location
    let token = try readToken()
    guard case .scalar(let scalar) = token else {
      throw Error.invalidData(.unexpectedToken(expected: [.scalar], found: token.kind), location: start)
    }
    return scalar
  }

  func readToken(ifMatches expected: JSONToken) throws -> Bool {
    let start = source.offset
    do {
      let token = try readToken()
      guard token == expected else {
        source.offset = start
        return false
      }
      return true
    } catch {
      source.offset = start
      throw error
    }
  }

  @discardableResult
  func readToken(matching expected: [JSONToken.Kind]) throws -> JSONToken {
    let start = source.location

    let token = try readToken()
    guard expected.contains(token.kind) else {
      throw Error.invalidData(.unexpectedToken(expected: expected, found: token.kind), location: start)
    }
    return token
  }

  func readToken() throws -> JSONToken {
    let start = source.location

    consumeWhitespace()

    guard let char = try source.peekASCII() else {
      throw Error.invalidData(.invalidToken, location: start)
    }

    switch char {
    case JSONStructure.beginArray:
      try source.skip(count: 1)
      return .beginArray
    case JSONStructure.endArray:
      try source.skip(count: 1)
      return .endArray
    case JSONStructure.beginObject:
      try source.skip(count: 1)
      return .beginObject
    case JSONStructure.endObject:
      try source.skip(count: 1)
      return .endObject
    case JSONStructure.elementSeparator:
      try source.skip(count: 1)
      return .elementSeparator
    case JSONStructure.pairSeparator:
      try source.skip(count: 1)
      return .pairSeparator
    case JSONStructure.nullStart:
      if try !consumeASCIISequence("null") {
        throw Error.invalidData(.invalidToken, location: start)
      }
      return .scalar(.null)
    case JSONStructure.falseStart:
      if try !consumeASCIISequence("false") {
        throw Error.invalidData(.invalidToken, location: start)
      }
      return .scalar(.bool(false))
    case JSONStructure.trueStart:
      if try !consumeASCIISequence("true") {
        throw Error.invalidData(.invalidToken, location: start)
      }
      return .scalar(.bool(true))
    case JSONStructure.quotationMark:
      return .scalar(.string(try parseString()))
    default:
      if Self.allDigits.contains(char) || char == Self.minus {
        return .scalar(.number(try parseNumber()))
      }
      throw Error.invalidData(.invalidToken, location: start)
    }
  }

  func readValue<C: JSONTokenConverter>(converter: C) throws -> C.ValueType {

    switch try readToken() {
    case .beginArray: return try readArray()
    case .beginObject: return try readObject()
    case .scalar(let scalar): return try converter.convertScalar(scalar)
    case let token:
      throw Error.invalidData(
        .unexpectedToken(expected: [.beginArray, .beginObject, .scalar], found: token.kind),
        location: source.location
      )
    }

    func readArray() throws -> C.ValueType {
      var array: [C.ValueType] = []
      if try readToken(ifMatches: .endArray) {
        return try converter.convertArray(array)
      }
      while true {
        array.append(try readValue(converter: converter))

        if try readToken(matching: [.elementSeparator, .endArray]) == .endArray {
          break
        }
      }
      return try converter.convertArray(array)
    }

    func readObject() throws -> C.ValueType {
      var object: [(String, C.ValueType)] = []
      if try readToken(ifMatches: .endObject) {
        return try converter.convertObject(object)
      }
      while true {
        let keyScalar = try readScalar()
        guard case .string(let key) = keyScalar else {
          throw Error.invalidData(
            .unexpectedValue(expected: [.string], found: keyScalar.kind),
            location: source.location
          )
        }

        try readToken(matching: [.pairSeparator])

        let value = try readValue(converter: converter)
        if let index = object.firstIndex(where: { $0.0 == key }) {
          object[index] = (key, value)
        } else {
          object.append((key, value))
        }

        if try readToken(matching: [.elementSeparator, .endObject]) == .endObject {
          break
        }
      }
      return try converter.convertObject(object)
    }

  }

}
