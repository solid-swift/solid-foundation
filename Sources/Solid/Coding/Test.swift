//
//  Test.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/30/25.
//


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
    try encoder.encode(name, at: CodingKeys.name)
    try encoder.encode(birthDate, at: CodingKeys.birthDate, nestedIn: Self.schema)
    try encoder.encode(avatar, at: CodingKeys.avatar)
  }

  public init(from decoder: inout some SchemaDecoder) throws {
    name = try decoder.decode(String.self, at: CodingKeys.name)
    birthDate = try decoder.decode(ZonedDateTime.self, at: CodingKeys.birthDate, nestedIn: Self.schema)
    avatar = try decoder.decode(Data.self, at: CodingKeys.avatar)
  }

  public enum CodingKeys {
    public static let name: Pointer = "name"
    public static let birthDate: Pointer = "birthDate"
    public static let avatar: Pointer = "avatar"
  }

  public static let schema = Schema.Builder.build(constant: [
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
