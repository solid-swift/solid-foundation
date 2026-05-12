//
//  JSONZeroCopyTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/22/26.
//

import Foundation
import SolidData
import SolidJSON
import Testing


@Suite("JSON Zero-Copy Tests")
struct JSONZeroCopyTests {

  // MARK: - Kind inspection without materialization

  @Test("string scalar has .string kind and raw bytes accessible")
  func stringScalarKindAndRawData() throws {
    let events = try parseEvents(#"{"key":"value"}"#)
    // Events: beginObject, scalar("key"), scalar("value"), endObject
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 2)
    #expect(scalars[0].kind == .string)
    #expect(scalars[1].kind == .string)
    // Raw data should be the JSON string content (without quotes)
    #expect(scalars[0].rawData == Data("key".utf8))
    #expect(scalars[1].rawData == Data("value".utf8))
  }

  @Test("integer scalar has .integer kind")
  func integerScalarKind() throws {
    let events = try parseEvents("42")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
    #expect(scalars[0].rawData == Data("42".utf8))
  }

  @Test("float scalar has .float kind")
  func floatScalarKind() throws {
    let events = try parseEvents("3.14")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .float)
    #expect(scalars[0].rawData == Data("3.14".utf8))
  }

  @Test("negative integer has .integer kind")
  func negativeIntegerKind() throws {
    let events = try parseEvents("-99")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
  }

  @Test("exponent number has .float kind")
  func exponentNumberKind() throws {
    let events = try parseEvents("1e10")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .float)
  }

  @Test("null has .null kind via isNull")
  func nullKind() throws {
    let events = try parseEvents("null")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].isNull)
  }

  @Test("true has .bool(true) kind via boolValue")
  func trueKind() throws {
    let events = try parseEvents("true")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].boolValue == true)
  }

  @Test("false has .bool(false) kind via boolValue")
  func falseKind() throws {
    let events = try parseEvents("false")
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    #expect(scalars[0].boolValue == false)
  }

  // MARK: - String with escapes: raw data preserves escapes

  @Test("string with escapes: rawData preserves escape sequences")
  func stringWithEscapesRawData() throws {
    let events = try parseEvents(#""hello\nworld""#)
    let scalars = events.compactMap { event -> ScalarRef? in
      if case .scalar(let ref) = event { return ref }
      return nil
    }
    #expect(scalars.count == 1)
    // Raw data should have the literal backslash-n, not a newline
    let rawString = String(decoding: scalars[0].rawData!, as: UTF8.self)
    #expect(rawString == #"hello\nworld"#)
    // Materialized value should have the actual newline
    let resolver = JSONScalarResolver()
    let materialized = try scalars[0].materialize(using: resolver)
    #expect(materialized == .string("hello\nworld"))
  }

  @Test("JSON string scalars carry escape metadata")
  func jsonStringScalarsCarryEscapeMetadata() throws {
    let events = try parseEvents(#"["plain","line\n","slash\\"]"#)
    let resolver = MetadataRecordingJSONResolver()
    var decoder = ParseEventDecoder(resolver: resolver)

    for event in events {
      try decoder.append(event)
    }

    #expect(try decoder.finish() == .array([
      .string("plain"),
      .string("line\n"),
      .string("slash\\"),
    ]))
    #expect(resolver.stringEscapeHints == [false, true, true])
  }

  @Test("JSON string without escapes materializes directly")
  func jsonStringWithoutEscapesMaterializes() throws {
    let region = ParseBuffer.Region(data: Data("hello".utf8))
    let ref = ScalarRef(kind: .string, region: region)

    #expect(try ref.materialize(using: JSONScalarResolver()) == .string("hello"))
  }

  @Test("JSON escaped string still unescapes")
  func jsonEscapedStringStillUnescapes() throws {
    let region = ParseBuffer.Region(data: Data(#"hello\nworld"#.utf8))
    let ref = ScalarRef(kind: .string, region: region)

    #expect(try ref.materialize(using: JSONScalarResolver()) == .string("hello\nworld"))
  }

  @Test("JSON string with invalid UTF-8 after unescape throws")
  func jsonStringWithInvalidUTF8AfterUnescapeThrows() {
    let resolver = JSONScalarResolver()
    let data = Data([0xFF, UInt8(ascii: "\\"), UInt8(ascii: "n")])
    let region = ParseBuffer.Region(data: data)

    #expect {
      _ = try resolver.resolve(region, kind: .string)
    } throws: { error in
      if case JSON.Error.invalidUTF8String = error {
        return true
      }
      return false
    }

    #expect {
      _ = try resolver.resolve(data, kind: .string)
    } throws: { error in
      if case JSON.Error.invalidUTF8String = error {
        return true
      }
      return false
    }
  }

  @Test("JSON string without escapes validates UTF-8 directly from region")
  func jsonStringWithoutEscapesValidatesUTF8DirectlyFromRegion() {
    let resolver = JSONScalarResolver()
    let data = Data([0xFF])
    let region = ParseBuffer.Region(data: data)

    #expect {
      _ = try resolver.resolve(region, kind: .string)
    } throws: { error in
      if case JSON.Error.invalidUTF8String = error {
        return true
      }
      return false
    }

    #expect {
      _ = try resolver.resolve(data, kind: .string)
    } throws: { error in
      if case JSON.Error.invalidUTF8String = error {
        return true
      }
      return false
    }
  }

  @Test("JSON data resolver compatibility for strings and integers")
  func jsonDataResolverCompatibility() throws {
    let resolver = JSONScalarResolver()

    #expect(try resolver.resolve(Data("hello".utf8), kind: .string) == .string("hello"))
    #expect(try resolver.resolve(Data(#"hello\nworld"#.utf8), kind: .string) == .string("hello\nworld"))
    #expect(try resolver.resolve(Data("42".utf8), kind: .integer) == .number(42))
  }

  @Test("JSON non-integer region falls back without inventing digits")
  func jsonNonIntegerRegionFallsBack() throws {
    let region = ParseBuffer.Region(data: Data("12.3".utf8))
    let expected = try #require(Value.TextNumber(text: "12.3"))

    #expect(try JSONScalarResolver().resolve(region, kind: .integer) == .number(.text(expected)))
  }

  @Test("JSON malformed integer region throws invalid number")
  func jsonMalformedIntegerRegionThrowsInvalidNumber() {
    let resolver = JSONScalarResolver()
    let region = ParseBuffer.Region(data: Data("12x".utf8))
    let ref = ScalarRef(kind: .integer, region: region)

    #expect {
      _ = try resolver.resolve(region, kind: .integer)
    } throws: { error in
      if case JSON.Error.invalidNumber = error {
        return true
      }
      return false
    }

    #expect {
      _ = try ref.materialize(using: resolver)
    } throws: { error in
      if case JSON.Error.invalidNumber = error {
        return true
      }
      return false
    }
  }

  @Test("JSON integer overflow falls back to text number")
  func jsonIntegerOverflowFallsBackToTextNumber() throws {
    let text = "18446744073709551616"
    let expected = try #require(Value.TextNumber(text: text))
    let region = ParseBuffer.Region(data: Data(text.utf8))

    #expect(try JSONScalarResolver().resolve(region, kind: .integer) == .number(.text(expected)))
  }

  // MARK: - Deferred materialization: kind available before resolve

  @Test("mixed types: inspect all kinds without materializing")
  func mixedTypesKindInspection() throws {
    let json = #"[42, "hello", true, null, 3.14, false]"#
    let events = try parseEvents(json)
    let kinds = events.compactMap { event -> ScalarRef.Kind? in
      if case .scalar(let ref) = event { return ref.kind }
      return nil
    }
    #expect(kinds == [
      .integer,
      .string,
      .bool(true),
      .null,
      .float,
      .bool(false),
    ])
  }

  // MARK: - Chunk boundary tests

  @Test("string split across chunks materializes correctly")
  func stringSplitAcrossChunks() throws {
    // Feed "hel" then "lo" with the quotes
    let value = try parseChunked(chunks: [
      Data(#""hel"#.utf8),
      Data(#"lo""#.utf8),
    ])
    #expect(value == .string("hello"))
  }

  @Test("number split across chunks materializes correctly")
  func numberSplitAcrossChunks() throws {
    let value = try parseChunked(chunks: [
      Data("-12".utf8),
      Data(".34".utf8),
      Data("e-5".utf8),
    ])
    #expect(value == .number(.text(Value.TextNumber(text: "-12.34e-5")!)))
  }

  @Test("keyword split across chunks")
  func keywordSplitAcrossChunks() throws {
    let value = try parseChunked(chunks: [
      Data("nul".utf8),
      Data("l".utf8),
    ])
    #expect(value == .null)
  }

  @Test("single-byte chunks parse correctly")
  func singleByteChunks() throws {
    let json = #"{"a":1,"b":true}"#
    let chunks = json.utf8.map { Data([$0]) }
    let value = try parseChunked(chunks: chunks)
    #expect(value == .object([.string("a"): .number(1), .string("b"): .bool(true)]))
  }
}


// MARK: - Helpers

/// Parse JSON into events using `JSONEventReader` directly (single-shot, no chunking).
private func parseEvents(_ json: String) throws -> [ParseEvent] {
  var reader = JSONEventReader()
  reader.feedInput(Data(json.utf8), isFinal: true)

  var events: [ParseEvent] = []
  while let event = try reader.readEvent() {
    events.append(event)
  }
  return events
}

/// Parse JSON fed in chunks via `JSONEventReader`, then decode to `Value`.
private func parseChunked(chunks: [Data]) throws -> Value {
  var reader = JSONEventReader()
  var decoder = ParseEventDecoder(resolver: JSONScalarResolver())

  for (i, chunk) in chunks.enumerated() {
    let isFinal = (i == chunks.count - 1)
    reader.feedInput(chunk, isFinal: isFinal)

    while let event = try reader.readEvent() {
      try decoder.append(event)
    }
  }

  return try decoder.finish()
}


private final class MetadataRecordingJSONResolver: ScalarMetadataResolver, @unchecked Sendable {

  var stringEscapeHints: [Bool?] = []
  private let resolver = JSONScalarResolver()

  func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    try resolver.resolve(data, kind: kind)
  }

  func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value {
    try resolver.resolve(region, kind: kind)
  }

  func resolve(
    _ region: ParseBuffer.Region,
    kind: ScalarRef.Kind,
    metadata: ScalarRef.Metadata
  ) throws -> Value {
    if kind == .string {
      stringEscapeHints.append(metadata.stringContainsEscapes)
    }
    return try resolver.resolve(region, kind: kind, metadata: metadata)
  }
}
