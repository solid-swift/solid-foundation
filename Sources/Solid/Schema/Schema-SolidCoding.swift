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

      public enum Size: Equatable, Hashable, Sendable, CustomStringConvertible {

        public enum Finite: Int, CaseIterable, Equatable, Hashable, Sendable {
          case `8bit` = 8
          case `16bit` = 16
          case `32bit` = 32
          case `64bit` = 64
          case `128bit` = 128
        }

        case finite(Finite)
        case infinite

        public init?(value: Value) {

          switch value {

          case .number(let num):
            guard
              let int = num.int(as: Int.self),
              let finiteSize = Finite(rawValue: int)
            else {
              return nil
            }
            self = .finite(finiteSize)

          case .string(let str):
            guard str == "big" else { return nil }
            self = .infinite

          default:
            return nil
          }
        }

        public var finite: Int? {
          guard case .finite(let size) = self else { return nil }
          return size.rawValue
        }

        public var isFinite: Bool {
          guard case .finite = self else { return false }
          return true
        }

        public var value: Value {
          switch self {
          case .finite(let size): .number(size.rawValue)
          case .infinite: .string("big")
          }
        }

        public var description: String { value.description }

        public static let allCases: [Size] = [
          .finite(.`8bit`),
          .finite(.`16bit`),
          .finite(.`32bit`),
          .finite(.`64bit`),
          .finite(.`128bit`),
          .infinite
        ]
      }

      public static let keyword: Keyword = .bitWidth

      public let size: Size

      public static func build(from schemaInstance: Value, context: inout Builder.Context) throws -> Self? {

        guard let size = Size(value: schemaInstance) else {
          try context.invalidValue("Invalid bit width, must be one of \(Size.allCases)")
        }

        return Self(size: size)
      }

      public func annotate(context: inout Schema.Validator.Context) -> Value? {
        return size.value
      }
    }

  }

}
