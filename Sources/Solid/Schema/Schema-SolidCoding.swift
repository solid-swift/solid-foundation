//
//  Schema-SolidCoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/28/25.
//

import SolidData
import SolidURI


extension Schema {

  public enum SolidCoding {

    public struct Units: AnnotationBehavior, BuildableKeywordBehavior {

      public static let keyword: Keyword = .units

      public let units: String

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard case .string(let units) = schemaInstance else {
          try context.invalidType(requiredType: .string)
        }

        return Self(units: units)
      }

      public func annotate(context: inout Schema.Validator.Context) -> Value? {
        return .string(units)
      }
    }

    public struct BitWidth: AnnotationBehavior, BuildableKeywordBehavior {

      public static let allowedSizes: Set<UInt8> = [16, 32, 64, 128]

      public static let keyword: Keyword = .bitWidth

      public let bitWidth: UInt8?

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        switch schemaInstance {

        case .number(let bitWidthNum):
          guard
            let bitWidth: UInt8 = bitWidthNum.int(),
            allowedSizes.contains(bitWidth)
          else {
            try context.invalidValue("Invalid bit width, must be one of \(Self.allowedSizes)")
          }
          return Self(bitWidth: bitWidth)

        case .string(let bitWidthStr):
          guard bitWidthStr == "inf" else {
            try context.invalidValue("Invalid bit width, must be one of \(Self.allowedSizes)")
          }
          return Self(bitWidth: nil)

        default:
          return nil
        }
      }

      public func annotate(context: inout Schema.Validator.Context) -> Value? {
        return bitWidth.map { .number($0) } ?? .null
      }
    }

  }

}
