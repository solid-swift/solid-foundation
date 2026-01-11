//
//  Tempo.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/31/25.
//

import SolidData
import SolidSchema
import SolidTempo


extension Instant: ExplicitSchemaCodable {

  public func encode(to encoder: inout some SchemaEncoder, using schema: Schema) throws {

    let type = encoder.resolveType(for: schema, defaults: (.string, .array))
    switch type {

    case .string:
      try encoder.encode(description, at: .root)

    case .array:
      try encoder.encode(.tagged(tag: "ns", value: .number(durationSinceEpoch.nanoseconds)), at: .root)

    default:
      throw SchemaCodingError.unsupportedEncoding(type: type.valueType, for: Instant.self)
    }
  }

  public init(from decoder: inout some SchemaDecoder, using schema: Schema) throws {
    fatalError()
  }

}

extension ZoneOffset: ExplicitSchemaCodable {

  public func encode(to encoder: inout some SchemaEncoder, using schema: Schema) throws {

    let type = encoder.resolveType(for: schema, defaults: (.string, .number))
    switch type {

    case .string:
      try encoder.encode(self.description(style: .complete), at: .root)

    case .number:
      try encoder.encode(.number(totalSeconds), at: .root)

    case _:
      throw SchemaCodingError.unsupportedEncoding(type: type.valueType, for: ZoneOffset.self)
    }
  }

  public init(from decoder: inout some SchemaDecoder, using schema: Schema) throws {
    fatalError()
  }

}

extension Zone: ExplicitSchemaCodable {

  public func encode(to encoder: inout some SchemaEncoder, using schema: Schema) throws {

    let type = encoder.resolveType(for: schema, defaults: (.string, .number))
    switch type {

    case .string:
      try encoder.encode(self.identifier, at: .root)

    case _:
      throw SchemaCodingError.unsupportedEncoding(type: type.valueType, for: ZoneOffset.self)
    }
  }

  public init(from decoder: inout some SchemaDecoder, using schema: Schema) throws {
    fatalError()
  }

}

extension ZonedDateTime: ExplicitSchemaCodable {

  public enum CodingKeys {
    public static let localDateTime: Pointer = 0
    public static let zoneId: Pointer = 1
  }

  public static let schema =
    Schema.Builder.build(
      constant: [
        "type": ["string", "array"],
        "prefixItems": [
          ["type": "number"],
          ["type": "string"],
        ],
        "format": "zoned-date-time",
      ],
      options: .default(for: .v1_2020_12_Solid)
    )

  public func encode(to encoder: inout some SchemaEncoder, using schema: Schema) throws {

    let type = schema.behavior(Schema.Generic.Types.self)?.types.first ?? .string
    switch type {

    case .string:
      try encoder.encode(self.description, at: .root)

    case .array:
      try encoder.encode(self.dateTime.instant(at: self.offset), at: CodingKeys.localDateTime, nestedIn: schema)
      try encoder.encode(self.zone, at: CodingKeys.zoneId, nestedIn: schema)

    default:
      throw SchemaCodingError.unsupportedEncoding(type: type.valueType, for: Self.self)
    }
  }

  public init(from decoder: inout some SchemaDecoder, using schema: Schema) throws {

    let type = schema.behavior(Schema.Generic.Types.self)?.types.first ?? .string
    switch type {

    case .string:
      let string = try decoder.decode(String.self, at: .root)
      guard let value = ZonedDateTime.parse(string: string, in: .default) else {
        throw SchemaCodingError.invalidValue(for: schema, at: CodingKeys.localDateTime, actual: .string(string))
      }
      self = value

    case .array:
      let instant = try decoder.decode(Instant.self, at: CodingKeys.localDateTime, nestedIn: schema)
      let zone = try Zone(identifier: decoder.decode(String.self, at: CodingKeys.zoneId))
      self = try ZonedDateTime.of(instant: instant, zone: zone)

    default:
      throw SchemaCodingError.unsupportedEncoding(type: type.valueType, for: Self.self)
    }
  }
}
