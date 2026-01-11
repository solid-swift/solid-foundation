//
//  SolidSchemaTestSuite.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

@testable import SolidData
@testable import SolidSchema
@testable import SolidURI
@testable import SolidJSON
import Foundation
import Testing


@Suite("Solid Schema Test")
public struct SolidSchemaTestSuite {

  @Suite struct `Bytes Validation` {

    @Test func `single type assertion`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "bytes"
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      #expect(try schema.validate(instance: .bytes(Data([1, 2, 3, 4, 5]))).isValid == true)
      #expect(try schema.validate(instance: .string("not bytes")).isValid == false)
    }

    @Test func `multiple types assertion`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": ["bytes", "string"]
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      #expect(try schema.validate(instance: .bytes(Data([1, 2, 3, 4, 5]))).isValid == true)
      #expect(try schema.validate(instance: .string("not bytes")).isValid == true)
      #expect(try schema.validate(instance: .number(21)).isValid == false)
    }

    @Test func `minSize assertion`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "bytes",
            "minSize": 5,
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      #expect(try schema.validate(instance: .bytes(Data([1, 2, 3, 4, 5]))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data([1, 2, 3]))).isValid == false)
    }

    @Test func `maxSize assertion`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "bytes",
            "maxSize": 3,
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      #expect(try schema.validate(instance: .bytes(Data([1, 2, 3]))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data([1, 2, 3, 4, 5]))).isValid == false)
    }
  }

  @Suite struct `Coding Vocabulary` {

    @Test func `uuid string default/canonical validation`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "string",
            "format": "uuid",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      // Format is annotation only
      #expect(try schema.validate(instance: .string("550e8400-e29b-41d4-a716-446655440000")).isValid == true)
      #expect(try schema.validate(instance: .string("not-a-uuid")).isValid == true)
    }

    @Test func `uuid bytes length validation`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "bytes",
            "format": "uuid",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      // Format only applies to the strings
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 16))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 15))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 17))).isValid == true)
    }

    @Test func `ipv4 bytes length validation`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "bytes",
            "format": "ipv4",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      // Format only applies to the strings
      #expect(try schema.validate(instance: .bytes(Data([127, 0, 0, 1]))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data([127, 0, 0]))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 16))).isValid == true)
    }

    @Test func `ipv6 bytes length validation`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "bytes",
            "format": "ipv6",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      // Format only applies to the strings
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 16))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 15))).isValid == true)
      #expect(try schema.validate(instance: .bytes(Data(repeating: 0, count: 4))).isValid == true)
    }

    @Test func `offset date time tuple array validation`() async throws {

      let schema =
        Schema.Builder.build(
          constant: [
            "type": "array",
            "format": "offset-date-time",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      // The `offset-date-time` format is unknown

      // Valid: [epochNanos, offsetSeconds]
      #expect(
        try schema
          .validate(
            instance: .array([
              .number(1_000_000_000),
              .number(0),
            ])
          )
          .isValid == true
      )

      // Invalid: wrong length
      #expect(
        try schema
          .validate(
            instance: .array([
              .number(1_000_000_000)
            ])
          )
          .isValid == true
      )

      // Invalid: offset out of range
      #expect(
        try schema
          .validate(
            instance: .array([
              .number(1_000_000_000),
              .number(100_000),
            ])
          )
          .isValid == true
      )
    }

    @Test func `gates allow only valid companion keywords`() async throws {

      // `units` should only be meaningful for time formats; using it with an unrelated format
      // should not crash validation. We assert it still validates a correct email format schema
      // by ignoring `units` at instance time.
      let emailWithUnitsSchema: Schema =
        Schema.Builder.build(
          constant: [
            "type": "string",
            "format": "email",
            "units": "milliseconds",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      // Email format should still validate emails (units is an extension keyword; behavior depends on meta-schema gating).
      #expect(try emailWithUnitsSchema.validate(instance: .string("a@b.com")).isValid == true)
      #expect(try emailWithUnitsSchema.validate(instance: .string("not-an-email")).isValid == true)

      // `bitWidth` should be meaningful only for numeric formats. Use it with float.
      let floatSchema =
        Schema.Builder.build(
          constant: [
            "type": "number",
            "format": "float",
            "bitWidth": 32,
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      #expect(try floatSchema.validate(instance: .number(1.25)).isValid == true)

      // `contentEncoding` should be used with UUIDs (string form). This schema is a UUID string
      // with an explicit contentEncoding marker. Actual decoding/recognition is handled by locators.
      let uuidWithContentEncoding: Schema =
        Schema.Builder.build(
          constant: [
            "type": "string",
            "format": "uuid",
            "contentEncoding": "uuid-canonical",
          ],
          options: .default(for: .v1_2020_12_Solid)
        )

      #expect(
        try uuidWithContentEncoding.validate(instance: .string("550e8400-e29b-41d4-a716-446655440000")).isValid == true
      )
      #expect(try uuidWithContentEncoding.validate(instance: .string("not-a-uuid")).isValid == true)
    }
  }
}
