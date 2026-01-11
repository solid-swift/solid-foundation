//
//  Test.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/24/25.
//

import Foundation
import SolidData
import SolidSchema
import SolidTempo


public struct Test {
  public var name: String
  public var birthDate: ZonedDateTime
  public var avatar: Data
}


extension Test: SchemaCodable {

  public func encode(to encoder: inout some SchemaEncoder) throws {
    try encoder.encode(name, at: TypeSchema.name)
    try encoder.encode(birthDate, at: TypeSchema.birthDate)
  }

  public init(from decoder: inout some SchemaDecoder<Test>) throws {
    decoder.decode(Int.self, at: .name)
    name = try decoder.decode(String.self, at: TypeSchema.name)
    birthDate = try decoder.decode(ZonedDateTime.self, at: TypeSchema.birthDate)
    avatar = try decoder.decode(Data.self, at: TypeSchema.avatar)
  }

  public struct TypeSchema: AssociatedSchema {

    public enum Key: String, CaseIterable {
      case name, birthDate, avatar
    }

    public typealias AssociatedType = Test

    public static let schema: Schema = Schema.Builder.build(constant: [
      "titile": "Test",
      "$id": "local://MyLibrary/Test",
      "type": "object",
      "properties": [
        "name": [
          "type": "string",
          "pattern": "^[a-zA-Z]+$",
        ],
        "birthDate": [
          "type": ["string", "number"],
          "format": "date-time",
          "date-type": "birthday",
        ],
        "avatar": [
          "type": ["string", "bytes"],
          "contentEncoding": "base64",
        ],
      ],
      "required": ["name", "birthDate", "avatar"],
      "additionalProperties": false,
    ])
  }

}
