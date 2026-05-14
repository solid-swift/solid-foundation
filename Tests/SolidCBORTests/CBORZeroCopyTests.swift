//
//  CBORZeroCopyTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/23/26.
//

import Foundation
import SolidCBOR
import SolidData
import Testing


@Suite("CBOR Zero-Copy Tests")
struct CBORZeroCopyTests {

  // MARK: - Kind inspection without materialization

  @Test("positive inline integer has .integer kind and 1-byte rawData")
  func positiveInlineIntegerKind() throws {
    // CBOR: 0x0A = positive integer 10 (inline)
    let events = try parseEvents([0x0A])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
    #expect(scalars[0].rawData == Data([0x0A]))
  }

  @Test("positive 1-byte integer has .integer kind")
  func positive1ByteIntegerKind() throws {
    // CBOR: 0x18 0x2A = positive integer 42 (1-byte follows)
    let events = try parseEvents([0x18, 0x2A])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
    #expect(scalars[0].rawData == Data([0x18, 0x2A]))
  }

  @Test("positive 2-byte integer has .integer kind")
  func positive2ByteIntegerKind() throws {
    // CBOR: 0x19 0x03 0xE8 = positive integer 1000
    let events = try parseEvents([0x19, 0x03, 0xE8])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
    #expect(scalars[0].rawData == Data([0x19, 0x03, 0xE8]))
  }

  @Test("negative integer has .integer kind")
  func negativeIntegerKind() throws {
    // CBOR: 0x38 0x63 = negative integer -100 (0x20 base + 0x18 = 1-byte follows, magnitude 99)
    let events = try parseEvents([0x38, 0x63])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
    #expect(scalars[0].rawData == Data([0x38, 0x63]))
  }

  @Test("negative inline integer has .integer kind")
  func negativeInlineIntegerKind() throws {
    // CBOR: 0x20 = negative integer -1 (inline, magnitude 0)
    let events = try parseEvents([0x20])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .integer)
    #expect(scalars[0].rawData == Data([0x20]))
  }

  @Test("UTF-8 string has .string kind and raw payload")
  func stringKind() throws {
    // CBOR: 0x65 0x68 0x65 0x6C 0x6C 0x6F = "hello" (5-byte text string)
    let events = try parseEvents([0x65, 0x68, 0x65, 0x6C, 0x6C, 0x6F])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .string)
    // Raw data is the UTF-8 payload only (no length header)
    #expect(scalars[0].rawData == Data("hello".utf8))
  }

  @Test("byte string has .bytes kind and raw payload")
  func byteStringKind() throws {
    // CBOR: 0x43 0xAA 0xBB 0xCC = 3-byte byte string
    let events = try parseEvents([0x43, 0xAA, 0xBB, 0xCC])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .bytes)
    #expect(scalars[0].rawData == Data([0xAA, 0xBB, 0xCC]))
  }

  @Test("half-precision float has .float kind with initByte + 2 IEEE bytes")
  func halfFloatKind() throws {
    // CBOR: 0xF9 0x3C 0x00 = half-precision float 1.0
    let events = try parseEvents([0xF9, 0x3C, 0x00])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .float)
    #expect(scalars[0].rawData == Data([0xF9, 0x3C, 0x00]))
  }

  @Test("single-precision float has .float kind with initByte + 4 IEEE bytes")
  func singleFloatKind() throws {
    // CBOR: 0xFA 0x47 0xC3 0x50 0x00 = single-precision float 100000.0
    let events = try parseEvents([0xFA, 0x47, 0xC3, 0x50, 0x00])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .float)
    #expect(scalars[0].rawData == Data([0xFA, 0x47, 0xC3, 0x50, 0x00]))
  }

  @Test("double-precision float has .float kind with initByte + 8 IEEE bytes")
  func doubleFloatKind() throws {
    // CBOR: 0xFB + 8 bytes for 1.1
    let bits = 1.1.bitPattern.bigEndian
    var bytes: [UInt8] = [0xFB]
    withUnsafeBytes(of: bits) { bytes.append(contentsOf: $0) }
    let events = try parseEvents(bytes)
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].kind == .float)
    #expect(scalars[0].rawData == Data(bytes))
  }

  @Test("null still has .null kind (pre-materialized)")
  func nullKind() throws {
    // CBOR: 0xF6 = null
    let events = try parseEvents([0xF6])
    let scalars = extractScalars(events)
    #expect(scalars.count == 1)
    #expect(scalars[0].isNull)
  }

  @Test("boolean still has .bool kind (pre-materialized)")
  func boolKind() throws {
    // CBOR: 0xF5 = true, 0xF4 = false
    let events = try parseEvents([0x82, 0xF5, 0xF4])
    let scalars = extractScalars(events)
    #expect(scalars.count == 2)
    #expect(scalars[0].boolValue == true)
    #expect(scalars[1].boolValue == false)
  }

  // MARK: - Materialization correctness

  @Test("positive integer materializes correctly")
  func positiveIntegerMaterialization() throws {
    let resolver = CBORScalarResolver()

    // Inline: 10
    let events1 = try parseEvents([0x0A])
    let value1 = try extractScalars(events1)[0].materialize(using: resolver)
    #expect(value1 == .number(10))

    // 1-byte: 42
    let events2 = try parseEvents([0x18, 0x2A])
    let value2 = try extractScalars(events2)[0].materialize(using: resolver)
    #expect(value2 == .number(42))

    // 2-byte: 1000
    let events3 = try parseEvents([0x19, 0x03, 0xE8])
    let value3 = try extractScalars(events3)[0].materialize(using: resolver)
    #expect(value3 == .number(1000))

    // 4-byte: 1000000
    let events4 = try parseEvents([0x1A, 0x00, 0x0F, 0x42, 0x40])
    let value4 = try extractScalars(events4)[0].materialize(using: resolver)
    #expect(value4 == .number(1_000_000))
  }

  @Test("negative integer materializes correctly")
  func negativeIntegerMaterialization() throws {
    let resolver = CBORScalarResolver()

    // Inline: -1 (magnitude 0)
    let events1 = try parseEvents([0x20])
    let value1 = try extractScalars(events1)[0].materialize(using: resolver)
    #expect(value1 == .number(-1))

    // 1-byte: -100 (magnitude 99 = 0x63)
    let events2 = try parseEvents([0x38, 0x63])
    let value2 = try extractScalars(events2)[0].materialize(using: resolver)
    #expect(value2 == .number(-100))
  }

  @Test("half-precision float materializes correctly")
  func halfFloatMaterialization() throws {
    let resolver = CBORScalarResolver()
    // Half-precision 1.0 = 0xF9 0x3C 0x00
    let events = try parseEvents([0xF9, 0x3C, 0x00])
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .number(Float16(1.0)))
  }

  @Test("single-precision float materializes correctly")
  func singleFloatMaterialization() throws {
    let resolver = CBORScalarResolver()
    // Single-precision 3.14
    let bits = Float32(3.14).bitPattern.bigEndian
    var bytes: [UInt8] = [0xFA]
    withUnsafeBytes(of: bits) { bytes.append(contentsOf: $0) }
    let events = try parseEvents(bytes)
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .number(Float32(3.14)))
  }

  @Test("double-precision float materializes correctly")
  func doubleFloatMaterialization() throws {
    let resolver = CBORScalarResolver()
    // Double-precision 1.1
    let bits = Float64(1.1).bitPattern.bigEndian
    var bytes: [UInt8] = [0xFB]
    withUnsafeBytes(of: bits) { bytes.append(contentsOf: $0) }
    let events = try parseEvents(bytes)
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .number(Float64(1.1)))
  }

  @Test("string materializes correctly")
  func stringMaterialization() throws {
    let resolver = CBORScalarResolver()
    // "hello" = 0x65 + UTF-8 bytes
    let events = try parseEvents([0x65, 0x68, 0x65, 0x6C, 0x6C, 0x6F])
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .string("hello"))
  }

  @Test("byte string materializes correctly")
  func byteStringMaterialization() throws {
    let resolver = CBORScalarResolver()
    // 3-byte byte string
    let events = try parseEvents([0x43, 0xAA, 0xBB, 0xCC])
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .bytes(Data([0xAA, 0xBB, 0xCC])))
  }

  @Test("empty string materializes correctly")
  func emptyStringMaterialization() throws {
    let resolver = CBORScalarResolver()
    // Empty text string: 0x60
    let events = try parseEvents([0x60])
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .string(""))
  }

  @Test("empty byte string materializes correctly")
  func emptyByteStringMaterialization() throws {
    let resolver = CBORScalarResolver()
    // Empty byte string: 0x40
    let events = try parseEvents([0x40])
    let value = try extractScalars(events)[0].materialize(using: resolver)
    #expect(value == .bytes(Data()))
  }

  // MARK: - Chunk boundary tests

  @Test("integer split across chunks materializes correctly")
  func integerSplitAcrossChunks() throws {
    // 2-byte integer 1000: [0x19, 0x03, 0xE8] split after first byte
    let value = try parseChunked(chunks: [
      Data([0x19]),
      Data([0x03, 0xE8]),
    ])
    #expect(value == .number(1000))
  }

  @Test("string split across chunks materializes correctly")
  func stringSplitAcrossChunks() throws {
    // "hello" (0x65 + 5 bytes) split in the middle
    let value = try parseChunked(chunks: [
      Data([0x65, 0x68, 0x65]),
      Data([0x6C, 0x6C, 0x6F]),
    ])
    #expect(value == .string("hello"))
  }

  @Test("single-byte chunks parse correctly")
  func singleByteChunks() throws {
    // Map {10: true} = [0xA1, 0x0A, 0xF5] — one byte at a time
    let value = try parseChunked(chunks: [
      Data([0xA1]),
      Data([0x0A]),
      Data([0xF5]),
    ])
    #expect(value == .object([.number(10): .bool(true)]))
  }

  // MARK: - Mixed types in containers

  @Test("mixed types in array: inspect all kinds")
  func mixedTypesKindInspection() throws {
    // Array of [42, "hi", true, null, 1.0(half)]
    // 0x85 = array(5)
    // 0x18 0x2A = 42
    // 0x62 0x68 0x69 = "hi"
    // 0xF5 = true
    // 0xF6 = null
    // 0xF9 0x3C 0x00 = half 1.0
    let events = try parseEvents([
      0x85,
      0x18, 0x2A,
      0x62, 0x68, 0x69,
      0xF5,
      0xF6,
      0xF9, 0x3C, 0x00,
    ])
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
    ])
  }
}


// MARK: - Helpers

/// Parse CBOR bytes into events using `CBOREventReader` directly (single-shot).
private func parseEvents(_ bytes: [UInt8]) throws -> [ParseEvent] {
  var reader = CBOREventReader()
  reader.feedInput(Data(bytes), isFinal: true)

  var events: [ParseEvent] = []
  while let event = try reader.readEvent() {
    events.append(event)
  }
  return events
}

/// Extract scalar refs from parsed events.
private func extractScalars(_ events: [ParseEvent]) -> [ScalarRef] {
  events.compactMap { event -> ScalarRef? in
    if case .scalar(let ref) = event { return ref }
    return nil
  }
}

/// Parse CBOR fed in chunks via `CBOREventReader`, then decode to `Value`.
private func parseChunked(chunks: [Data]) throws -> Value {
  var reader = CBOREventReader()
  var decoder = ParseEventDecoder(resolver: CBORScalarResolver())

  for (i, chunk) in chunks.enumerated() {
    let isFinal = (i == chunks.count - 1)
    reader.feedInput(chunk, isFinal: isFinal)

    while let event = try reader.readEvent() {
      try decoder.append(event)
    }
  }

  return try decoder.finish()
}
