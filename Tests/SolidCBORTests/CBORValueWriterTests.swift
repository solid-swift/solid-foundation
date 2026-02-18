//
//  CBORValueWriterTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation
@testable import SolidCBOR
import SolidData
import Testing


@Suite("CBOR Value Writer Tests")
struct CBORValueWriterTests {

  struct EncodeCase: Sendable {
    let id: String
    let value: Value
    let expected: [UInt8]
    let deterministic: Bool
  }

  @Test("Encode integers", arguments: integerCases)
  func encodeIntegers(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode byte strings", arguments: byteStringCases)
  func encodeByteStrings(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode UTF-8 strings", arguments: stringCases)
  func encodeStrings(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode arrays", arguments: arrayCases)
  func encodeArrays(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode maps", arguments: mapCases)
  func encodeMaps(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode deterministic maps", arguments: deterministicMapCases)
  func encodeDeterministicMaps(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode tagged values", arguments: taggedCases)
  func encodeTagged(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode simple values", arguments: simpleCases)
  func encodeSimple(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode floats", arguments: floatCases)
  func encodeFloats(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode deterministic floats", arguments: deterministicFloatCases)
  func encodeDeterministicFloats(_ testCase: EncodeCase) throws {
    let bytes = try encode(testCase.value, deterministic: testCase.deterministic)
    #expect(bytes == testCase.expected, "\(testCase.id): encoded bytes mismatch")
  }

  @Test("Encode indefinite containers when sizes omitted")
  func encodeIndefiniteContainersWithoutSizes() throws {
    let arrayBytes = try encode(.array([1, 2]), deterministic: false, includeContainerSizes: false)
    #expect(arrayBytes == [0x9F, 0x01, 0x02, 0xFF])

    let mapBytes = try encode(object([(1, 2)]), deterministic: false, includeContainerSizes: false)
    #expect(mapBytes == [0xBF, 0x01, 0x02, 0xFF])

    let nested = try encode(object([(.string("a"), .array([1, 2]))]), deterministic: false, includeContainerSizes: false)
    #expect(nested == [0xBF, 0x61, 0x61, 0x9F, 0x01, 0x02, 0xFF, 0xFF])
  }

  @Test("Encode indefinite arrays")
  func encodeIndefiniteArrays() throws {
    let bytes = try encode { encoder in
      try encoder.writeIndefiniteStart(for: .array)
      try encoder.writeArrayChunk([1, 2])
      try encoder.writeValue(.number(3))
      try encoder.writeIndefiniteStart(for: .array)
      try encoder.writeArrayChunk([1, 2, 3])
      try encoder.writeIndefiniteEnd()
      try encoder.writeIndefiniteEnd()
    }
    #expect(bytes == [0x9F, 0x01, 0x02, 0x03, 0x9F, 0x01, 0x02, 0x03, 0xFF, 0xFF])
  }

  @Test("Encode indefinite maps")
  func encodeIndefiniteMaps() throws {
    let bytes = try encode { encoder in
      try encoder.writeIndefiniteStart(for: .map)
      try encoder.writeValue(.string("a"))
      try encoder.writeValue(.number(1))
      try encoder.writeValue(.string("B"))
      try encoder.writeValue(.number(2))
      try encoder.writeIndefiniteEnd()
    }
    #expect(bytes == [0xBF, 0x61, 0x61, 0x01, 0x61, 0x42, 0x02, 0xFF])
  }

  @Test("Encode indefinite strings")
  func encodeIndefiniteStrings() throws {
    let bytes = try encode { encoder in
      try encoder.writeIndefiniteStart(for: .string)
      try encoder.writeValue(.string("a"))
      try encoder.writeValue(.string("B"))
      try encoder.writeIndefiniteEnd()
    }
    #expect(bytes == [0x7F, 0x61, 0x61, 0x61, 0x42, 0xFF])
  }

  @Test("Encode indefinite byte strings")
  func encodeIndefiniteByteStrings() throws {
    let bytes = try encode { encoder in
      try encoder.writeIndefiniteStart(for: .byteString)
      try encoder.writeValue(.bytes(Data([0xF0])))
      try encoder.writeValue(.bytes(Data([0xFF])))
      try encoder.writeIndefiniteEnd()
    }
    #expect(bytes == [0x5F, 0x41, 0xF0, 0x41, 0xFF, 0xFF])
  }
}

private let integerCases: [CBORValueWriterTests.EncodeCase] = {
  var cases: [CBORValueWriterTests.EncodeCase] = []
  for i in 0..<24 {
    cases.append(.init(id: "uint\(i)", value: .number(i), expected: [UInt8(i)], deterministic: false))
  }
  for i in 24...UInt8.max {
    cases.append(.init(id: "uint8-\(i)", value: .number(Int(i)), expected: [0x18, UInt8(i)], deterministic: false))
  }
  cases.append(.init(id: "neg-1", value: .number(-1), expected: [0x20], deterministic: false))
  cases.append(.init(id: "neg-10", value: .number(-10), expected: [0x29], deterministic: false))
  cases.append(.init(id: "neg-24", value: .number(-24), expected: [0x37], deterministic: false))
  cases.append(.init(id: "neg-25", value: .number(-25), expected: [0x38, 24], deterministic: false))
  cases.append(.init(id: "neg-1000", value: .number(-1_000), expected: [0x39, 0x03, 0xE7], deterministic: false))
  cases.append(
    .init(
      id: "uint-1000000",
      value: .number(1_000_000),
      expected: [0x1A, 0x00, 0x0F, 0x42, 0x40],
      deterministic: false
    )
  )
  cases.append(
    .init(
      id: "uint64-1000000000000",
      value: .number(Int64(1_000_000_000_000)),
      expected: [0x1B, 0x00, 0x00, 0x00, 0xE8, 0xD4, 0xA5, 0x10, 0x00],
      deterministic: false
    )
  )
  cases.append(
    .init(
      id: "neg-1000000",
      value: .number(-1_000_000),
      expected: [0x3A, 0x00, 0x0F, 0x42, 0x3F],
      deterministic: false
    )
  )
  cases.append(
    .init(
      id: "neg-1000000000000",
      value: .number(Int64(-1_000_000_000_000)),
      expected: [0x3B, 0x00, 0x00, 0x00, 0xE8, 0xD4, 0xA5, 0x0F, 0xFF],
      deterministic: false
    )
  )
  cases.append(.init(id: "int8-max", value: .number(Int8.max), expected: [0x18, 0x7F], deterministic: false))
  cases.append(.init(id: "int16-max", value: .number(Int16.max), expected: [0x19, 0x7F, 0xFF], deterministic: false))
  cases.append(
    .init(
      id: "int32-max",
      value: .number(Int32.max),
      expected: [0x1A, 0x7F, 0xFF, 0xFF, 0xFF],
      deterministic: false
    )
  )
  cases.append(
    .init(
      id: "int64-max",
      value: .number(Int64.max),
      expected: [0x1B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
      deterministic: false
    )
  )
  let intMaxExpected: [UInt8] =
    MemoryLayout<Int>.size == 4
    ? [0x1A, 0x7F, 0xFF, 0xFF, 0xFF]
    : [0x1B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
  cases.append(.init(id: "int-max", value: .number(Int.max), expected: intMaxExpected, deterministic: false))

  cases.append(.init(id: "uint8-max", value: .number(UInt8.max), expected: [0x18, 0xFF], deterministic: false))
  cases.append(.init(id: "uint16-max", value: .number(UInt16.max), expected: [0x19, 0xFF, 0xFF], deterministic: false))
  cases.append(
    .init(
      id: "uint32-max",
      value: .number(UInt32.max),
      expected: [0x1A, 0xFF, 0xFF, 0xFF, 0xFF],
      deterministic: false
    )
  )
  cases.append(
    .init(
      id: "uint64-max",
      value: .number(UInt64.max),
      expected: [0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
      deterministic: false
    )
  )
  let uintMaxExpected: [UInt8] =
    MemoryLayout<UInt>.size == 4
    ? [0x1A, 0xFF, 0xFF, 0xFF, 0xFF]
    : [0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
  cases.append(.init(id: "uint-max", value: .number(UInt.max), expected: uintMaxExpected, deterministic: false))

  cases.append(.init(id: "int8-min", value: .number(Int8.min), expected: [0x38, 0x7F], deterministic: false))
  cases.append(.init(id: "int16-min", value: .number(Int16.min), expected: [0x39, 0x7F, 0xFF], deterministic: false))
  cases.append(
    .init(
      id: "int32-min",
      value: .number(Int32.min),
      expected: [0x3A, 0x7F, 0xFF, 0xFF, 0xFF],
      deterministic: false
    )
  )
  cases.append(
    .init(
      id: "int64-min",
      value: .number(Int64.min),
      expected: [0x3B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
      deterministic: false
    )
  )
  let intMinExpected: [UInt8] =
    MemoryLayout<Int>.size == 4
    ? [0x3A, 0x7F, 0xFF, 0xFF, 0xFF]
    : [0x3B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
  cases.append(.init(id: "int-min", value: .number(Int.min), expected: intMinExpected, deterministic: false))

  return cases
}()

private let byteStringCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "bytes-empty", value: .bytes(Data()), expected: [0x40], deterministic: false),
  .init(id: "bytes-1", value: .bytes(Data([0xF0])), expected: [0x41, 0xF0], deterministic: false),
  .init(
    id: "bytes-4",
    value: .bytes(Data([0x01, 0x02, 0x03, 0x04])),
    expected: [0x44, 0x01, 0x02, 0x03, 0x04],
    deterministic: false
  ),
  .init(
    id: "bytes-23",
    value: .bytes(Data([
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xAA,
    ])),
    expected: [
      0x57,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xAA,
    ],
    deterministic: false
  ),
  .init(
    id: "bytes-24",
    value: .bytes(Data([
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xAA, 0xAA,
    ])),
    expected: [
      0x58, 24,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xAA, 0xAA,
    ],
    deterministic: false
  ),
]

private let stringCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "string-empty", value: .string(""), expected: [0x60], deterministic: false),
  .init(id: "string-a", value: .string("a"), expected: [0x61, 0x61], deterministic: false),
  .init(id: "string-B", value: .string("B"), expected: [0x61, 0x42], deterministic: false),
  .init(id: "string-ABC", value: .string("ABC"), expected: [0x63, 0x41, 0x42, 0x43], deterministic: false),
  .init(id: "string-IETF", value: .string("IETF"), expected: [0x64, 0x49, 0x45, 0x54, 0x46], deterministic: false),
  .init(
    id: "string-japanese",
    value: .string("今日は"),
    expected: [0x69, 0xE4, 0xBB, 0x8A, 0xE6, 0x97, 0xA5, 0xE3, 0x81, 0xAF],
    deterministic: false
  ),
  .init(
    id: "string-long",
    value: .string("♨️français;日本語！Longer text\n with break?"),
    expected: [
      0x78,
      0x34,
      0xE2,
      0x99,
      0xA8,
      0xEF,
      0xB8,
      0x8F,
      0x66,
      0x72,
      0x61,
      0x6E,
      0xC3,
      0xA7,
      0x61,
      0x69,
      0x73,
      0x3B,
      0xE6,
      0x97,
      0xA5,
      0xE6,
      0x9C,
      0xAC,
      0xE8,
      0xAA,
      0x9E,
      0xEF,
      0xBC,
      0x81,
      0x4C,
      0x6F,
      0x6E,
      0x67,
      0x65,
      0x72,
      0x20,
      0x74,
      0x65,
      0x78,
      0x74,
      0x0A,
      0x20,
      0x77,
      0x69,
      0x74,
      0x68,
      0x20,
      0x62,
      0x72,
      0x65,
      0x61,
      0x6B,
      0x3F,
    ],
    deterministic: false
  ),
  .init(id: "string-escaped", value: .string("\"\\"),
        expected: [0x62, 0x22, 0x5C], deterministic: false),
  .init(id: "string-unicode", value: .string("水"),
        expected: [0x63, 0xE6, 0xB0, 0xB4], deterministic: false),
  .init(id: "string-umlaut", value: .string("ü"),
        expected: [0x62, 0xC3, 0xBC], deterministic: false),
  .init(id: "string-newline", value: .string("abc\n123"),
        expected: [0x67, 0x61, 0x62, 0x63, 0x0A, 0x31, 0x32, 0x33], deterministic: false),
]

private let arrayCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "array-empty", value: .array([]), expected: [0x80], deterministic: false),
  .init(id: "array-123", value: .array([1, 2, 3]), expected: [0x83, 0x01, 0x02, 0x03], deterministic: false),
  .init(
    id: "array-nested",
    value: .array([.array([1]), .array([2, 3]), .array([4, 5])]),
    expected: [0x83, 0x81, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05],
    deterministic: false
  ),
  .init(
    id: "array-1-25",
    value: .array((1...25).map { Value.number($0) }),
    expected: [
      0x98,
      0x19,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0x0C,
      0x0D,
      0x0E,
      0x0F,
      0x10,
      0x11,
      0x12,
      0x13,
      0x14,
      0x15,
      0x16,
      0x17,
      0x18,
      0x18,
      0x18,
      0x19,
    ],
    deterministic: false
  ),
]

private let mapCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "map-empty", value: .object(.init()), expected: [0xA0], deterministic: false),
  .init(
    id: "map-nondeterministic-int",
    value: object([(1, 2), (3, 4)]),
    expected: [0xA2, 0x01, 0x02, 0x03, 0x04],
    deterministic: false
  ),
  .init(
    id: "map-nondeterministic-nested",
    value: object([(.string("a"), .array([1])), (.string("b"), .array([2, 3]))]),
    expected: [0xA2, 0x61, 0x61, 0x81, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03],
    deterministic: false
  ),
]

private let deterministicMapCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "det-map-empty", value: .object(.init()), expected: [0xA0], deterministic: true),
  .init(
    id: "det-map-ordering",
    value: object([
      (.number(100), 2),
      (.number(10), 1),
      (.string("z"), 4),
      (.array([100]), 6),
      (.number(-1), 3),
      (.string("aa"), 5),
      (.bool(false), 8),
      (.array([-1]), 7),
    ]),
    expected: [
      0xA8, 0x0A, 0x01, 0x18, 0x64, 0x02, 0x20, 0x03, 0x61, 0x7A, 0x04, 0x62,
      0x61, 0x61, 0x05, 0x81, 0x18, 0x64, 0x06, 0x81, 0x20, 0x07, 0xF4, 0x08,
    ],
    deterministic: true
  ),
]

private let taggedCases: [CBORValueWriterTests.EncodeCase] = [
  .init(
    id: "tag-positive-bignum",
    value: .tagged(tags: [.number(CBORStructure.Tags.positiveBignum)], value: .bytes(Data([
      0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]))),
    expected: [0xC2, 0x49, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    deterministic: false
  ),
  .init(
    id: "tag-uint64-max",
    value: .tagged(tags: [.number(UInt64.max)], value: .bytes(Data([
      0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]))),
    expected: [0xDB, 255, 255, 255, 255, 255, 255, 255, 255, 0x49, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    deterministic: false
  ),
]

private let simpleCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "bool-false", value: .bool(false), expected: [0xF4], deterministic: false),
  .init(id: "bool-true", value: .bool(true), expected: [0xF5], deterministic: false),
  .init(id: "null", value: .null, expected: [0xF6], deterministic: false),
]

private let floatCases: [CBORValueWriterTests.EncodeCase] = [
  .init(id: "float-0", value: .number(Float32(0.0)), expected: [0xFA, 0x00, 0x00, 0x00, 0x00], deterministic: false),
  .init(id: "float--0", value: .number(Float32(-0.0)), expected: [0xFA, 0x80, 0x00, 0x00, 0x00], deterministic: false),
  .init(id: "float-1", value: .number(Float32(1.0)), expected: [0xFA, 0x3F, 0x80, 0x00, 0x00], deterministic: false),
  .init(id: "float-1.5", value: .number(Float32(1.5)), expected: [0xFA, 0x3F, 0xC0, 0x00, 0x00], deterministic: false),
  .init(id: "float-65504", value: .number(Float32(65504.0)), expected: [0xFA, 0x47, 0x7F, 0xE0, 0x00], deterministic: false),
  .init(id: "float-100000", value: .number(Float32(100_000.0)), expected: [0xFA, 0x47, 0xC3, 0x50, 0x00], deterministic: false),
  .init(
    id: "float-max",
    value: .number(Float32(3.4028234663852886e+38)),
    expected: [0xFA, 0x7F, 0x7F, 0xFF, 0xFF],
    deterministic: false
  ),
  .init(
    id: "double-1.1",
    value: .number(Double(1.1)),
    expected: [0xFB, 0x3F, 0xF1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9A],
    deterministic: false
  ),
  .init(
    id: "double--4.1",
    value: .number(Double(-4.1)),
    expected: [0xFB, 0xC0, 0x10, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66],
    deterministic: false
  ),
  .init(
    id: "double-1e300",
    value: .number(Double(1.0e+300)),
    expected: [0xFB, 0x7E, 0x37, 0xE4, 0x3C, 0x88, 0x00, 0x75, 0x9C],
    deterministic: false
  ),
  .init(
    id: "double-subnormal",
    value: .number(Double(5.960464477539063e-8)),
    expected: [0xFB, 0x3E, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    deterministic: false
  ),
  .init(id: "float-inf", value: .number(Float32.infinity), expected: [0xFA, 0x7F, 0x80, 0x00, 0x00], deterministic: false),
  .init(id: "float--inf", value: .number(-Float32.infinity), expected: [0xFA, 0xFF, 0x80, 0x00, 0x00], deterministic: false),
  .init(
    id: "double-inf",
    value: .number(Double.infinity),
    expected: [0xFB, 0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    deterministic: false
  ),
  .init(
    id: "double--inf",
    value: .number(-Double.infinity),
    expected: [0xFB, 0xFF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    deterministic: false
  ),
  .init(id: "float-nan", value: .number(Float32.nan), expected: [0xFA, 0x7F, 0xC0, 0x00, 0x00], deterministic: false),
  .init(
    id: "double-nan",
    value: .number(Double.nan),
    expected: [0xFB, 0x7F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    deterministic: false
  ),
]

private let deterministicFloatCases: [CBORValueWriterTests.EncodeCase] = [
  .init(
    id: "det-double-1.23",
    value: .number(Double(1.23)),
    expected: [0xFB, 0x3F, 0xF3, 0xAE, 0x14, 0x7A, 0xE1, 0x47, 0xAE],
    deterministic: true
  ),
  .init(
    id: "det-double-131008",
    value: .number(Double(131_008.0)),
    expected: [0xFA, 0x47, 0xFF, 0xE0, 0x00],
    deterministic: true
  ),
  .init(
    id: "det-double-0.5",
    value: .number(Double(0.5)),
    expected: [0xF9, 0x38, 0x00],
    deterministic: true
  ),
  .init(id: "det-double-inf", value: .number(Double.infinity), expected: [0xF9, 0x7C, 0x00], deterministic: true),
  .init(id: "det-double--inf", value: .number(-Double.infinity), expected: [0xF9, 0xFC, 0x00], deterministic: true),
  .init(id: "det-double-nan", value: .number(Double.nan), expected: [0xF9, 0x7E, 0x00], deterministic: true),
  .init(
    id: "det-float-1.23",
    value: .number(Float32(1.23)),
    expected: [0xFA, 0x3F, 0x9D, 0x70, 0xA4],
    deterministic: true
  ),
  .init(
    id: "det-float-131008",
    value: .number(Float32(131_008.0)),
    expected: [0xFA, 0x47, 0xFF, 0xE0, 0x00],
    deterministic: true
  ),
  .init(
    id: "det-float-0.5",
    value: .number(Float32(0.5)),
    expected: [0xF9, 0x38, 0x00],
    deterministic: true
  ),
  .init(id: "det-float-inf", value: .number(Float32.infinity), expected: [0xF9, 0x7C, 0x00], deterministic: true),
  .init(id: "det-float--inf", value: .number(-Float32.infinity), expected: [0xF9, 0xFC, 0x00], deterministic: true),
  .init(id: "det-float-nan", value: .number(Float32.nan), expected: [0xF9, 0x7E, 0x00], deterministic: true),
  .init(
    id: "det-half-1.23",
    value: .number(Float16(1.23)),
    expected: [0xF9, 0x3C, 0xEC],
    deterministic: true
  ),
]

private func encode(_ value: Value, deterministic: Bool, includeContainerSizes: Bool = true) throws -> [UInt8] {
  let data = try CBORValueWriter.write(
    value,
    options: .init(deterministic: deterministic, includeContainerSizes: includeContainerSizes)
  )
  return Array(data)
}

private func encode(
  block: (inout CBOREncoder) throws -> Void
) throws -> [UInt8] {
  var encoder = CBOREncoder()
  try block(&encoder)
  return Array(encoder.buffer)
}

private func object(_ pairs: [(Value, Value)]) -> Value {
  return .object(Value.Object(uniqueKeysWithValues: pairs))
}
