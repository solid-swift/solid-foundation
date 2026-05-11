//
//  ScalarRefTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/22/26.
//

import Foundation
@testable import SolidData
import Testing


@Suite("ScalarRef Tests")
struct ScalarRefTests {

  // MARK: - Zero-cost convenience properties

  @Test("isNull returns true for null")
  func isNullForNull() {
    let ref = ScalarRef.null
    #expect(ref.isNull)
  }

  @Test("isNull returns false for non-null")
  func isNullForNonNull() {
    let ref = ScalarRef.bool(true)
    #expect(!ref.isNull)
  }

  @Test("boolValue returns value for bool")
  func boolValueForBool() {
    #expect(ScalarRef.bool(true).boolValue == true)
    #expect(ScalarRef.bool(false).boolValue == false)
  }

  @Test("boolValue returns nil for non-bool")
  func boolValueForNonBool() {
    #expect(ScalarRef.null.boolValue == nil)
    #expect(ScalarRef.materialized(.string("hello")).boolValue == nil)
  }

  // MARK: - Kind without materialization

  @Test("kind is available without materialization for buffered scalars")
  func kindWithoutMaterialization() {
    let data = Data("42".utf8)
    let region = ParseBuffer.Region(data: data)
    let ref = ScalarRef(kind: .integer, region: region)
    // Access kind without calling materialize — validates zero-cost inspection
    #expect(ref.kind == .integer)
    #expect(!ref.isNull)
    #expect(ref.boolValue == nil)
  }

  @Test("kind inferred correctly from materialized values")
  func kindInferredFromMaterialized() {
    #expect(ScalarRef.materialized(.null).kind == .null)
    #expect(ScalarRef.materialized(.bool(true)).kind == .bool(true))
    #expect(ScalarRef.materialized(.bool(false)).kind == .bool(false))
    #expect(ScalarRef.materialized(.string("hello")).kind == .string)
    #expect(ScalarRef.materialized(.number(42)).kind == .number)
    #expect(ScalarRef.materialized(.bytes(Data([0xFF]))).kind == .bytes)
  }

  // MARK: - Raw data access

  @Test("rawData returns bytes for buffered scalar")
  func rawDataForBuffered() {
    let data = Data("hello".utf8)
    let region = ParseBuffer.Region(data: data)
    let ref = ScalarRef(kind: .string, region: region)
    #expect(ref.rawData == data)
  }

  @Test("rawData returns nil for pre-materialized scalar")
  func rawDataForMaterialized() {
    let ref = ScalarRef.materialized(.string("hello"))
    #expect(ref.rawData == nil)
  }

  @Test("ParseBuffer region records retained segment metadata")
  func parseBufferRegionMetadata() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abcdef".utf8))

    _ = try buffer.readByte()
    let start = buffer.mark()
    _ = try buffer.readBytes(count: 3)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.data == Data("bcd".utf8))
    #expect(region.bytes == Data("bcd".utf8))
    #expect(try region.string() == "bcd")
    #expect(region.segmentIndex == 0)
    #expect(region.segmentRange == 1..<4)
    #expect(region.isCopied == false)
  }

  @Test("ParseBuffer region reports retained storage size")
  func parseBufferRegionReportsRetainedStorageSize() throws {
    var buffer = ParseBuffer()
    buffer.append(Data(repeating: 0x61, count: 1024))

    let start = buffer.mark()
    try buffer.advance(count: 1)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.count == 1)
    #expect(region.retainedByteCount == 1024)
  }

  @Test("ParseBuffer detached region copies only visible bytes")
  func parseBufferDetachedRegionCopiesOnlyVisibleBytes() throws {
    var buffer = ParseBuffer()
    buffer.append(Data(repeating: 0x61, count: 1024))

    let start = buffer.mark()
    try buffer.advance(count: 1)
    let region = buffer.region(from: start, to: buffer.mark())
    let detached = region.detached()

    #expect(detached.bytes == Data([0x61]))
    #expect(detached.count == 1)
    #expect(detached.retainedByteCount == 1)
    #expect(detached.isCopied)
  }

  @Test("ParseBuffer retained subregion preserves source metadata")
  func parseBufferRetainedSubregionMetadata() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abcdef".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 6)
    let region = buffer.region(from: start, to: buffer.mark())
    let subregion = region.subregion(2..<5)

    #expect(subregion.bytes == Data("cde".utf8))
    #expect(try subregion.string() == "cde")
    #expect(subregion.segmentIndex == 0)
    #expect(subregion.segmentRange == 2..<5)
    #expect(subregion.isCopied == false)
  }

  @Test("ParseBuffer cross-segment region records copied storage")
  func parseBufferCrossSegmentRegionMetadata() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("ab".utf8))
    buffer.append(Data("cd".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 4)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.data == Data("abcd".utf8))
    #expect(region.bytes == Data("abcd".utf8))
    #expect(region.segmentIndex == nil)
    #expect(region.segmentRange == nil)
    #expect(region.isCopied)
  }

  @Test("ParseBuffer can advance without materializing bytes before region capture")
  func parseBufferAdvanceBeforeRegionCapture() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abcdef".utf8))

    try buffer.advance(count: 2)
    let start = buffer.mark()
    try buffer.advance(count: 3)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.bytes == Data("cde".utf8))
    #expect(try region.string() == "cde")
    #expect(region.segmentIndex == 0)
    #expect(region.segmentRange == 2..<5)
    #expect(region.isCopied == false)
  }

  @Test("ParseBuffer readRegion preserves retained and copied storage")
  func parseBufferReadRegionStorage() throws {
    var retainedBuffer = ParseBuffer()
    retainedBuffer.append(Data("abcdef".utf8))

    try retainedBuffer.advance(count: 1)
    let retainedRegion = try retainedBuffer.readRegion(count: 3)

    #expect(retainedRegion.bytes == Data("bcd".utf8))
    #expect(retainedRegion.segmentIndex == 0)
    #expect(retainedRegion.segmentRange == 1..<4)
    #expect(retainedRegion.isCopied == false)

    var copiedBuffer = ParseBuffer()
    copiedBuffer.append(Data("ab".utf8))
    copiedBuffer.append(Data("cd".utf8))

    let copiedRegion = try copiedBuffer.readRegion(count: 4)

    #expect(copiedRegion.bytes == Data("abcd".utf8))
    #expect(copiedRegion.segmentIndex == nil)
    #expect(copiedRegion.segmentRange == nil)
    #expect(copiedRegion.isCopied)
  }

  @Test("ParseBuffer readRegion canonicalizes exhausted segment before marking")
  func parseBufferReadRegionRetainsAfterSegmentBoundary() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("ab".utf8))
    buffer.append(Data("cdef".utf8))

    try buffer.advance(count: 2)
    let region = try buffer.readRegion(count: 3)

    #expect(region.bytes == Data("cde".utf8))
    #expect(region.segmentIndex == 1)
    #expect(region.segmentRange == 0..<3)
    #expect(region.isCopied == false)
  }

  @Test("ParseBuffer mark canonicalizes exhausted segment boundary")
  func parseBufferMarkAtBoundaryRetainsNextSegmentRegion() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("ab".utf8))
    buffer.append(Data("cdef".utf8))

    try buffer.advance(count: 2)
    let start = buffer.mark()
    try buffer.advance(count: 3)
    let region = buffer.region(from: start, to: buffer.mark())

    #expect(region.bytes == Data("cde".utf8))
    #expect(region.segmentIndex == 1)
    #expect(region.segmentRange == 0..<3)
    #expect(region.isCopied == false)
  }

  @Test("ParseBuffer advance and readRegion throw when insufficient data is available")
  func parseBufferAdvanceAndReadRegionUnexpectedEnd() {
    var advanceBuffer = ParseBuffer()
    advanceBuffer.append(Data("ab".utf8))

    #expect(throws: ParseBufferError.unexpectedEnd) {
      try advanceBuffer.advance(count: 3)
    }

    var regionBuffer = ParseBuffer()
    regionBuffer.append(Data("ab".utf8))

    #expect(throws: ParseBufferError.unexpectedEnd) {
      _ = try regionBuffer.readRegion(count: 3)
    }
  }

  @Test("ParseBuffer stale positions fail safely after compaction")
  func parseBufferStalePositionAfterCompactionFailsSafely() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abc".utf8))
    buffer.append(Data("def".utf8))

    let stale = buffer.mark()
    try buffer.advance(count: 3)
    buffer.compact()

    let retainedStart = buffer.mark()
    let staleRegion = buffer.region(from: stale, to: retainedStart)
    #expect(staleRegion.bytes.isEmpty)

    buffer.restore(stale)
    #expect(throws: ParseBufferError.unexpectedEnd) {
      _ = try buffer.readByte()
    }
  }

  @Test("ParseBuffer stale restore remains invalid after append")
  func parseBufferStaleRestoreDoesNotReadFutureAppends() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abc".utf8))
    buffer.append(Data("def".utf8))

    let stale = buffer.mark()
    let retainedStart: ParseBuffer.Position
    try buffer.advance(count: 3)
    buffer.compact()
    retainedStart = buffer.mark()

    buffer.restore(stale)
    buffer.append(Data("ghi".utf8))

    #expect(throws: ParseBufferError.unexpectedEnd) {
      _ = try buffer.readByte()
    }

    buffer.restore(retainedStart)
    #expect(try buffer.readByte() == UInt8(ascii: "d"))
  }

  @Test("ParseBuffer region exposes span-style unsafe byte access")
  func parseBufferRegionUnsafeBytes() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("hello".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 5)
    let region = buffer.region(from: start, to: buffer.mark())

    let byteSum = region.withUnsafeBytes { rawBuffer in
      rawBuffer.reduce(0) { $0 + Int($1) }
    }
    #expect(byteSum == Data("hello".utf8).reduce(0) { $0 + Int($1) })

    let bufferByteSum = buffer.withUnsafeBytes(for: region) { rawBuffer in
      rawBuffer.reduce(0) { $0 + Int($1) }
    }
    #expect(bufferByteSum == byteSum)
  }

  @Test("ParseBuffer retained region survives compaction")
  func parseBufferRetainedRegionSurvivesCompaction() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("abc".utf8))
    buffer.append(Data("def".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 3)
    let region = buffer.region(from: start, to: buffer.mark())
    buffer.compact()

    #expect(region.bytes == Data("abc".utf8))
    #expect(try region.string() == "abc")
    #expect(buffer.bytes(for: region) == Data("abc".utf8))
  }

  // MARK: - Materialization

  @Test("buffered materialization does not cache result")
  func bufferedMaterializationDoesNotCache() throws {
    var callCount = 0
    let data = Data("test".utf8)
    let region = ParseBuffer.Region(data: data)
    let ref = ScalarRef(kind: .string, region: region)

    let countingResolver = CountingResolver { callCount += 1 }

    let value1 = try ref.materialize(using: countingResolver)
    let value2 = try ref.materialize(using: countingResolver)

    #expect(value1 == value2)
    #expect(callCount == 2, "Buffered ScalarRef resolves each direct materialization call")
  }

  @Test("materialization prefers retained region resolver")
  func materializationPrefersRegionResolver() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("hello".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 5)
    let region = buffer.region(from: start, to: buffer.mark())
    let ref = ScalarRef(kind: .string, region: region)
    let resolver = RegionCountingResolver()

    let value = try ref.materialize(using: resolver)

    #expect(value == .string("hello"))
    #expect(resolver.regionCallCount == 1)
    #expect(resolver.dataCallCount == 0)
    #expect(resolver.lastRegionWasCopied == false)
  }

  @Test("materialization passes copied cross-segment region to region resolver")
  func materializationPassesCopiedRegionResolver() throws {
    var buffer = ParseBuffer()
    buffer.append(Data("he".utf8))
    buffer.append(Data("llo".utf8))

    let start = buffer.mark()
    _ = try buffer.readBytes(count: 5)
    let region = buffer.region(from: start, to: buffer.mark())
    let ref = ScalarRef(kind: .string, region: region)
    let resolver = RegionCountingResolver()

    let value = try ref.materialize(using: resolver)

    #expect(value == .string("hello"))
    #expect(resolver.regionCallCount == 1)
    #expect(resolver.dataCallCount == 0)
    #expect(resolver.lastRegionWasCopied == true)
  }

  @Test("pre-materialized values bypass resolver")
  func preMaterializedBypassesResolver() throws {
    let ref = ScalarRef.materialized(.string("hello"))
    let failResolver = FailResolver()

    let value = try ref.materialize(using: failResolver)
    #expect(value == .string("hello"))
  }

  @Test("pre-materialized convenience values bypass resolver")
  func preMaterializedConvenienceValuesBypassResolver() throws {
    let failResolver = FailResolver()

    #expect(try ScalarRef.null.materialize(using: failResolver) == .null)
    #expect(try ScalarRef.bool(true).materialize(using: failResolver) == .bool(true))
    #expect(try ScalarRef.bool(false).materialize(using: failResolver) == .bool(false))
  }
}


@Suite("ParseEventDecoder Tests")
struct ParseEventDecoderTests {

  @Test("decode simple scalar")
  func decodeSimpleScalar() throws {
    var decoder = ParseEventDecoder()
    try decoder.append(.scalar(.materialized(.string("hello"))))
    let value = try decoder.finish()
    #expect(value == .string("hello"))
  }

  @Test("decode array")
  func decodeArray() throws {
    var decoder = ParseEventDecoder()
    try decoder.append(.beginArray(count: 2))
    try decoder.append(.scalar(.materialized(.number(1))))
    try decoder.append(.scalar(.materialized(.number(2))))
    try decoder.append(.endArray)
    let value = try decoder.finish()
    #expect(value == .array([.number(1), .number(2)]))
  }

  @Test("decode object")
  func decodeObject() throws {
    var decoder = ParseEventDecoder()
    try decoder.append(.beginObject(count: 1))
    try decoder.append(.scalar(.materialized(.string("key"))))
    try decoder.append(.scalar(.materialized(.number(42))))
    try decoder.append(.endObject)
    let value = try decoder.finish()
    #expect(value == .object([.string("key"): .number(42)]))
  }

  @Test("decode nested containers")
  func decodeNestedContainers() throws {
    var decoder = ParseEventDecoder()
    try decoder.append(.beginObject(count: 1))
    try decoder.append(.scalar(.materialized(.string("items"))))
    try decoder.append(.beginArray(count: 2))
    try decoder.append(.scalar(.materialized(.bool(true))))
    try decoder.append(.scalar(.null))
    try decoder.append(.endArray)
    try decoder.append(.endObject)
    let value = try decoder.finish()
    #expect(value == .object([.string("items"): .array([.bool(true), .null])]))
  }

  @Test("incomplete value throws")
  func incompleteValueThrows() throws {
    var decoder = ParseEventDecoder()
    try decoder.append(.beginArray(count: nil))
    #expect(throws: ParseEventDecoder.Error.self) {
      try decoder.finish()
    }
  }

  @Test("object missing value throws on endObject")
  func objectMissingValueThrowsOnEndObject() throws {
    var decoder = ParseEventDecoder()
    try decoder.append(.beginObject(count: nil))
    try decoder.append(.scalar(.materialized(.string("key"))))
    #expect(throws: ParseEventDecoder.Error.self) {
      try decoder.append(.endObject)
    }
  }
}


@Suite("ParseDocumentEvent Tests")
struct ParseDocumentEventTests {

  @Test("document framer wraps one scalar root")
  func documentFramerWrapsScalarRoot() throws {
    var framer = ParseEventDocumentFramer()
    var events: [ParseDocumentEvent] = []

    try framer.append(.scalar(.materialized(.string("hello"))), into: &events)

    #expect(events.count == 3)
    if case .startDocument(let metadata) = events[0] {
      #expect(metadata == .implicit)
    } else {
      Issue.record("Expected start document")
    }
    if case .event(.scalar(let ref)) = events[1] {
      #expect(try ref.materialize(using: RegionCountingResolver()) == .string("hello"))
    } else {
      Issue.record("Expected scalar event")
    }
    if case .endDocument(let metadata) = events[2] {
      #expect(metadata == .implicit)
    } else {
      Issue.record("Expected end document")
    }
    try framer.finish()
  }

  @Test("document framer wraps nested container root")
  func documentFramerWrapsContainerRoot() throws {
    var framer = ParseEventDocumentFramer()
    var events: [ParseDocumentEvent] = []

    try framer.append(.beginArray(count: nil), into: &events)
    try framer.append(.scalar(.materialized(.number(1))), into: &events)
    try framer.append(.beginObject(count: nil), into: &events)
    try framer.append(.scalar(.materialized(.string("a"))), into: &events)
    try framer.append(.scalar(.materialized(.bool(true))), into: &events)
    try framer.append(.endObject, into: &events)
    try framer.append(.endArray, into: &events)

    if case .some(.startDocument(let metadata)) = events.first {
      #expect(metadata == .implicit)
    } else {
      Issue.record("Expected start document")
    }
    if case .some(.endDocument(let metadata)) = events.last {
      #expect(metadata == .implicit)
    } else {
      Issue.record("Expected end document")
    }
    #expect(events.filter { if case .startDocument = $0 { true } else { false } }.count == 1)
    #expect(events.filter { if case .endDocument = $0 { true } else { false } }.count == 1)
    try framer.finish()
  }

  @Test("document decoder returns value documents")
  func documentDecoderReturnsValueDocuments() throws {
    var decoder = ParseDocumentEventDecoder(resolver: RegionCountingResolver())

    _ = try decoder.append(.startDocument(.init(explicit: true)))
    _ = try decoder.append(.event(.beginObject(count: 1)))
    _ = try decoder.append(.event(.scalar(.materialized(.string("key")))))
    _ = try decoder.append(.event(.scalar(.materialized(.number(42)))))
    _ = try decoder.append(.event(.endObject))
    let document = try decoder.append(.endDocument(.init(explicit: false)))

    #expect(document == FormatValueDocument(
      value: .object([.string("key"): .number(42)]),
      explicitStart: true,
      explicitEnd: false
    ))
    try decoder.finish()
  }

  @Test("document decoder reports incomplete document")
  func documentDecoderReportsIncompleteDocument() throws {
    var decoder = ParseDocumentEventDecoder(resolver: RegionCountingResolver())
    _ = try decoder.append(.startDocument(.implicit))
    _ = try decoder.append(.event(.beginArray(count: nil)))

    #expect(throws: ParseDocumentEventDecoder.Error.self) {
      _ = try decoder.append(.endDocument(.implicit))
    }
  }
}


// MARK: - Test helpers

/// A resolver that counts invocations.
private final class CountingResolver: ScalarResolver, @unchecked Sendable {
  let onResolve: () -> Void

  init(onResolve: @escaping () -> Void) {
    self.onResolve = onResolve
  }

  func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    onResolve()
    switch kind {
    case .string:
      return .string(String(decoding: data, as: UTF8.self))
    default:
      return .null
    }
  }
}

private final class RegionCountingResolver: RegionScalarResolver, @unchecked Sendable {
  var regionCallCount = 0
  var dataCallCount = 0
  var lastRegionWasCopied = false

  func resolve(_ region: ParseBuffer.Region, kind: ScalarRef.Kind) throws -> Value {
    regionCallCount += 1
    lastRegionWasCopied = region.isCopied
    return try resolve(region.bytes, kind: kind)
  }

  func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    if regionCallCount == 0 {
      dataCallCount += 1
    }
    switch kind {
    case .string:
      return .string(String(decoding: data, as: UTF8.self))
    default:
      return .null
    }
  }
}

/// A resolver that always fails — used to verify pre-materialized values bypass resolution.
private struct FailResolver: ScalarResolver {
  func resolve(_ data: Data, kind: ScalarRef.Kind) throws -> Value {
    preconditionFailure("FailResolver should never be called")
  }
}
