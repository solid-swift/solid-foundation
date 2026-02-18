//
//  CBORValueReaderTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation
@testable import SolidCBOR
import SolidData
import Testing


@Suite("CBOR Value Reader Tests")
struct CBORValueReaderTests {

  struct DecodeCase: Sendable {
    let id: String
    let bytes: [UInt8]
    let expected: Value
    let options: CBORValueReader.Options
  }

  struct DecodeErrorCase: Sendable {
    let id: String
    let bytes: [UInt8]
    let options: CBORValueReader.Options
  }

  @Test("Decode numbers", arguments: numberCases)
  func decodeNumbers(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode byte strings", arguments: byteStringCases)
  func decodeByteStrings(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode UTF-8 strings", arguments: utf8StringCases)
  func decodeUtf8Strings(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode arrays", arguments: arrayCases)
  func decodeArrays(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode maps", arguments: mapCases)
  func decodeMaps(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode tags", arguments: taggedCases)
  func decodeTagged(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode simple values", arguments: simpleCases)
  func decodeSimpleValues(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode floats", arguments: floatCases)
  func decodeFloats(_ testCase: DecodeCase) throws {
    let value = try decode(testCase.bytes, options: testCase.options)
    #expect(value == testCase.expected, "\(testCase.id): decoded value mismatch")
  }

  @Test("Decode errors", arguments: errorCases)
  func decodeErrors(_ testCase: DecodeErrorCase) {
    #expect(throws: Error.self) {
      _ = try decode(testCase.bytes, options: testCase.options)
    }
  }

  @Test("Decode map from issue 29")
  func decodeMapFromIssue29() throws {
    let loremIpsumData = Data([
      0x4C, 0x6F, 0x72, 0x65, 0x6D, 0x20, 0x69, 0x70, 0x73, 0x75, 0x6D, 0x20, 0x64, 0x6F,
      0x6C, 0x6F, 0x72, 0x20, 0x73, 0x69, 0x74, 0x20, 0x61, 0x6D, 0x65, 0x74, 0x2C, 0x20,
      0x63, 0x6F, 0x6E, 0x73, 0x65, 0x63, 0x74, 0x65, 0x74, 0x75, 0x72, 0x20, 0x61, 0x64,
      0x69, 0x70, 0x69, 0x73, 0x63, 0x69, 0x6E, 0x67, 0x20, 0x65, 0x6C, 0x69, 0x74, 0x2E,
      0x20, 0x51, 0x75, 0x69, 0x73, 0x71, 0x75, 0x65, 0x20, 0x65, 0x78, 0x20, 0x61, 0x6E,
      0x74, 0x65, 0x2C, 0x20, 0x73, 0x65, 0x6D, 0x70, 0x65, 0x72, 0x20, 0x75, 0x74, 0x20,
      0x66, 0x61, 0x75, 0x63, 0x69, 0x62, 0x75, 0x73, 0x20, 0x70, 0x68, 0x61, 0x72, 0x65,
      0x74, 0x72, 0x61, 0x2C, 0x20, 0x61, 0x63, 0x63, 0x75, 0x6D, 0x73, 0x61, 0x6E, 0x20,
      0x65, 0x74, 0x20, 0x61, 0x75, 0x67, 0x75, 0x65, 0x2E, 0x20, 0x56, 0x65, 0x73, 0x74,
      0x69, 0x62, 0x75, 0x6C, 0x75, 0x6D, 0x20, 0x76, 0x75, 0x6C, 0x70, 0x75, 0x74, 0x61,
      0x74, 0x65, 0x20, 0x65, 0x6C, 0x69, 0x74, 0x20, 0x6C, 0x69, 0x67, 0x75, 0x6C, 0x61,
      0x2C, 0x20, 0x65, 0x75, 0x20, 0x74, 0x69, 0x6E, 0x63, 0x69, 0x64, 0x75, 0x6E, 0x74,
      0x20, 0x6F, 0x72, 0x63, 0x69, 0x20, 0x6C, 0x61, 0x63, 0x69, 0x6E, 0x69, 0x61, 0x20,
      0x71, 0x75, 0x69, 0x73, 0x2E, 0x20, 0x50, 0x72, 0x6F, 0x69, 0x6E, 0x20, 0x73, 0x63,
      0x65, 0x6C, 0x65, 0x72, 0x69, 0x73, 0x71, 0x75, 0x65, 0x20, 0x64, 0x75, 0x69, 0x20,
      0x61, 0x74, 0x20, 0x6D, 0x61, 0x67, 0x6E, 0x61, 0x20, 0x70, 0x6C, 0x61, 0x63, 0x65,
      0x72, 0x61, 0x74, 0x2C, 0x20, 0x69, 0x64, 0x20, 0x62, 0x6C, 0x61, 0x6E, 0x64, 0x69,
      0x74, 0x20, 0x66, 0x65, 0x6C, 0x69, 0x73, 0x20, 0x76, 0x65, 0x68, 0x69, 0x63, 0x75,
      0x6C, 0x61, 0x2E, 0x20, 0x4D, 0x61, 0x65, 0x63, 0x65, 0x6E, 0x61, 0x73, 0x20, 0x61,
      0x63, 0x20, 0x6E, 0x69, 0x73, 0x6C, 0x20, 0x61, 0x20, 0x6F, 0x64, 0x69, 0x6F, 0x20,
      0x76, 0x61, 0x72, 0x69, 0x75, 0x73, 0x20, 0x63, 0x6F, 0x6E, 0x64, 0x69, 0x6D, 0x65,
      0x6E, 0x74, 0x75, 0x6D, 0x20, 0x6C,
    ])
    let data =
      Data([0xBF, 0x63, 0x6F, 0x66, 0x66, 0x00, 0x64, 0x64, 0x61, 0x74, 0x61, 0x59, 0x01, 0x2C]
        + loremIpsumData
        + [0x62, 0x72, 0x63, 0x00, 0x63, 0x6C, 0x65, 0x6E, 0x19, 0x01, 0x2C, 0xFF])

    let expectedMap = object([
      ("off", 0),
      ("data", .bytes(loremIpsumData)),
      ("rc", 0),
      ("len", 300),
    ])

    let value = try decode(Array(data), options: .init())
    #expect(value == expectedMap)
  }
}

private let numberCases: [CBORValueReaderTests.DecodeCase] = {
  var cases: [CBORValueReaderTests.DecodeCase] = []
  for i in 0..<24 {
    cases.append(.init(id: "uint\(i)", bytes: [UInt8(i)], expected: .number(i), options: .init()))
  }
  cases.append(.init(id: "uint8-255", bytes: [0x18, 0xFF], expected: .number(255), options: .init()))
  cases.append(.init(id: "uint16-1000", bytes: [0x19, 0x03, 0xE8], expected: .number(1000), options: .init()))
  cases.append(.init(id: "uint16-max", bytes: [0x19, 0xFF, 0xFF], expected: .number(65535), options: .init()))
  cases.append(
    .init(
      id: "uint32-1000000",
      bytes: [0x1A, 0x00, 0x0F, 0x42, 0x40],
      expected: .number(1_000_000),
      options: .init()
    )
  )
  cases.append(
    .init(
      id: "uint32-max",
      bytes: [0x1A, 0xFF, 0xFF, 0xFF, 0xFF],
      expected: .number(UInt64(4_294_967_295)),
      options: .init()
    )
  )
  cases.append(
    .init(
      id: "uint64-1000000000000",
      bytes: [0x1B, 0x00, 0x00, 0x00, 0xE8, 0xD4, 0xA5, 0x10, 0x00],
      expected: .number(1_000_000_000_000 as Int64),
      options: .init()
    )
  )
  cases.append(
    .init(
      id: "uint64-max",
      bytes: [0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
      expected: .number(UInt64.max),
      options: .init()
    )
  )

  cases.append(.init(id: "neg-1", bytes: [0x20], expected: .number(-1), options: .init()))
  cases.append(.init(id: "neg-2", bytes: [0x21], expected: .number(-2), options: .init()))
  cases.append(.init(id: "neg-24", bytes: [0x37], expected: .number(-24), options: .init()))
  cases.append(.init(id: "neg-256", bytes: [0x38, 0xFF], expected: .number(-256), options: .init()))
  cases.append(
    .init(
      id: "neg-1000",
      bytes: [0x39, 0x03, 0xE7],
      expected: .number(-1_000),
      options: .init()
    )
  )
  cases.append(
    .init(
      id: "neg-1000000",
      bytes: [0x3A, 0x00, 0x0F, 0x42, 0x3F],
      expected: .number(-1_000_000),
      options: .init()
    )
  )
  cases.append(
    .init(
      id: "neg-1000000000000",
      bytes: [0x3B, 0x00, 0x00, 0x00, 0xE8, 0xD4, 0xA5, 0x0F, 0xFF],
      expected: .number(-1_000_000_000_000 as Int64),
      options: .init()
    )
  )
  return cases
}()

private let byteStringCases: [CBORValueReaderTests.DecodeCase] = [
  .init(id: "bytes-empty", bytes: [0x40], expected: .bytes(Data()), options: .init()),
  .init(id: "bytes-1", bytes: [0x41, 0xF0], expected: .bytes(Data([0xF0])), options: .init()),
  .init(
    id: "bytes-23",
    bytes: [
      0x57,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xAA,
    ],
    expected: .bytes(Data([
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xAA,
    ])),
    options: .init()
  ),
  .init(id: "bytes-len8-empty", bytes: [0x58, 0], expected: .bytes(Data()), options: .init()),
  .init(id: "bytes-len8-1", bytes: [0x58, 1, 0xF0], expected: .bytes(Data([0xF0])), options: .init()),
  .init(
    id: "bytes-len16-3",
    bytes: [0x59, 0x00, 3, 0xC0, 0xFF, 0xEE],
    expected: .bytes(Data([0xC0, 0xFF, 0xEE])),
    options: .init()
  ),
  .init(
    id: "bytes-len32-3",
    bytes: [0x5A, 0x00, 0x00, 0x00, 3, 0xC0, 0xFF, 0xEE],
    expected: .bytes(Data([0xC0, 0xFF, 0xEE])),
    options: .init()
  ),
  .init(
    id: "bytes-len64-3",
    bytes: [0x5B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 3, 0xC0, 0xFF, 0xEE],
    expected: .bytes(Data([0xC0, 0xFF, 0xEE])),
    options: .init()
  ),
  .init(
    id: "bytes-indefinite",
    bytes: [0x5F, 0x58, 3, 0xC0, 0xFF, 0xEE, 0x43, 0xC0, 0xFF, 0xEE, 0xFF],
    expected: .bytes(Data([0xC0, 0xFF, 0xEE, 0xC0, 0xFF, 0xEE])),
    options: .init()
  ),
]

private let utf8StringCases: [CBORValueReaderTests.DecodeCase] = [
  .init(id: "string-empty", bytes: [0x60], expected: .string(""), options: .init()),
  .init(id: "string-1", bytes: [0x61, 0x42], expected: .string("B"), options: .init()),
  .init(id: "string-len8-empty", bytes: [0x78, 0], expected: .string(""), options: .init()),
  .init(id: "string-len8-1", bytes: [0x78, 1, 0x42], expected: .string("B"), options: .init()),
  .init(
    id: "string-len16-3",
    bytes: [0x79, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .string("ABC"),
    options: .init()
  ),
  .init(
    id: "string-len32-3",
    bytes: [0x7A, 0x00, 0x00, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .string("ABC"),
    options: .init()
  ),
  .init(
    id: "string-len64-3",
    bytes: [0x7B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .string("ABC"),
    options: .init()
  ),
  .init(
    id: "string-indefinite",
    bytes: [0x7F, 0x78, 3, 0x41, 0x42, 0x43, 0x63, 0x41, 0x42, 0x43, 0xFF],
    expected: .string("ABCABC"),
    options: .init()
  ),
]

private let arrayCases: [CBORValueReaderTests.DecodeCase] = [
  .init(id: "array-empty", bytes: [0x80], expected: .array([]), options: .init()),
  .init(
    id: "array-mixed",
    bytes: [0x82, 0x18, 1, 0x79, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .array([1, "ABC"]),
    options: .init()
  ),
  .init(id: "array-len8-empty", bytes: [0x98, 0], expected: .array([]), options: .init()),
  .init(
    id: "array-len8-3",
    bytes: [0x98, 3, 0x18, 2, 0x18, 2, 0x79, 0x00, 3, 0x41, 0x42, 0x43, 0xFF],
    expected: .array([2, 2, "ABC"]),
    options: .init()
  ),
  .init(
    id: "array-indefinite",
    bytes: [
      0x9F,
      0x18,
      255,
      0x9B,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      2,
      0x18,
      1,
      0x79,
      0x00,
      3,
      0x41,
      0x42,
      0x43,
      0x79,
      0x00,
      3,
      0x41,
      0x42,
      0x43,
      0xFF,
    ],
    expected: .array([255, .array([1, "ABC"]), "ABC"]),
    options: .init()
  ),
  .init(
    id: "array-nested-indefinite",
    bytes: [0x9F, 0x81, 0x01, 0x82, 0x02, 0x03, 0x9F, 0x04, 0x05, 0xFF, 0xFF],
    expected: .array([.array([1]), .array([2, 3]), .array([4, 5])]),
    options: .init()
  ),
]

private let mapCases: [CBORValueReaderTests.DecodeCase] = [
  .init(id: "map-empty", bytes: [0xA0], expected: .object(.init()), options: .init()),
  .init(
    id: "map-single",
    bytes: [0xA1, 0x63, 0x6B, 0x65, 0x79, 0x37],
    expected: object([("key", -24)]),
    options: .init()
  ),
  .init(
    id: "map-len8",
    bytes: [0xB8, 1, 0x63, 0x6B, 0x65, 0x79, 0x81, 0x37],
    expected: object([("key", .array([-24]))]),
    options: .init()
  ),
  .init(
    id: "map-indefinite",
    bytes: [0xBF, 0x63, 0x6B, 0x65, 0x79, 0xA1, 0x63, 0x6B, 0x65, 0x79, 0x37, 0xFF],
    expected: object([("key", object([("key", -24)]))]),
    options: .init()
  ),
]

private let taggedCases: [CBORValueReaderTests.DecodeCase] = [
  .init(
    id: "tag-0",
    bytes: [0xC0, 0x79, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .tagged(tags: [.number(0)], value: .string("ABC")),
    options: .init()
  ),
  .init(
    id: "tag-255",
    bytes: [0xD8, 255, 0x79, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .tagged(tags: [.number(255)], value: .string("ABC")),
    options: .init()
  ),
  .init(
    id: "tag-uint64-max",
    bytes: [0xDB, 255, 255, 255, 255, 255, 255, 255, 255, 0x79, 0x00, 3, 0x41, 0x42, 0x43],
    expected: .tagged(tags: [.number(UInt64.max)], value: .string("ABC")),
    options: .init()
  ),
]

private let simpleCases: [CBORValueReaderTests.DecodeCase] = [
  .init(id: "simple-0", bytes: [0xE0], expected: .number(0), options: .init()),
  .init(id: "simple-19", bytes: [0xF3], expected: .number(19), options: .init()),
  .init(id: "simple-19-extended", bytes: [0xF8, 19], expected: .number(19), options: .init()),
  .init(id: "false", bytes: [0xF4], expected: .bool(false), options: .init()),
  .init(id: "true", bytes: [0xF5], expected: .bool(true), options: .init()),
  .init(id: "null", bytes: [0xF6], expected: .null, options: .init()),
  .init(id: "undefined-as-null", bytes: [0xF7], expected: .null, options: .init(undefined: .convertToNull)),
]

private let floatCases: [CBORValueReaderTests.DecodeCase] = [
  .init(
    id: "half--4",
    bytes: [0xF9, 0xC4, 0x00],
    expected: .number(Float16(-4.0)),
    options: .init()
  ),
  .init(
    id: "half--inf",
    bytes: [0xF9, 0xFC, 0x00],
    expected: .number(-Float16.infinity),
    options: .init()
  ),
  .init(
    id: "float-100000",
    bytes: [0xFA, 0x47, 0xC3, 0x50, 0x00],
    expected: .number(Float32(100_000.0)),
    options: .init()
  ),
  .init(
    id: "float-inf",
    bytes: [0xFA, 0x7F, 0x80, 0x00, 0x00],
    expected: .number(Float32.infinity),
    options: .init()
  ),
  .init(
    id: "double--4.1",
    bytes: [0xFB, 0xC0, 0x10, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66],
    expected: .number(Double(-4.1)),
    options: .init()
  ),
]

private let errorCases: [CBORValueReaderTests.DecodeErrorCase] = [
  .init(id: "missing-uint16", bytes: [0x19, 0xFF], options: .init()),
  .init(id: "missing-uint32", bytes: [0x1A], options: .init()),
  .init(id: "missing-uint64", bytes: [0x1B, 0x00, 0x00], options: .init()),
  .init(id: "undefined-default", bytes: [0xF7], options: .init()),
  .init(
    id: "invalid-negative-bignum-tag",
    bytes: [0xDB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 3, 0xA0],
    options: .init()
  ),
]

private func decode(_ bytes: [UInt8], options: CBORValueReader.Options) throws -> Value {
  var reader = CBORValueReader(data: Data(bytes), options: options)
  return try reader.read()
}

private func object(_ pairs: [(String, Value)]) -> Value {
  let elements = pairs.map { (Value.string($0.0), $0.1) }
  return .object(Value.Object(uniqueKeysWithValues: elements))
}
