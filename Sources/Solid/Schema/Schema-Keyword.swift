//
//  Schema-Keyword.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/5/25.
//

import SolidData


extension Schema {

  public struct Keyword: RawRepresentable, Sendable, Equatable, Hashable {

    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    // - MARK: Current Draft (2020-12)

    // Annotations
    public static let title = Self(rawValue: "title")
    public static let description = Self(rawValue: "description")
    public static let comment$ = Self(rawValue: "$comment")
    public static let `default` = Self(rawValue: "default")
    public static let deprecated = Self(rawValue: "deprecated")
    public static let examples = Self(rawValue: "examples")
    public static let readOnly = Self(rawValue: "readOnly")
    public static let writeOnly = Self(rawValue: "writeOnly")

    // Generic
    public static let type = Self(rawValue: "type")
    public static let `enum` = Self(rawValue: "enum")
    public static let const = Self(rawValue: "const")

    // Compose
    public static let allOf = Self(rawValue: "allOf")
    public static let anyOf = Self(rawValue: "anyOf")
    public static let oneOf = Self(rawValue: "oneOf")
    public static let not = Self(rawValue: "not")
    public static let `if` = Self(rawValue: "if")
    public static let then = Self(rawValue: "then")
    public static let `else` = Self(rawValue: "else")
    public static let dependentSchemas = Self(rawValue: "dependentSchemas")

    // Number
    public static let multipleOf = Self(rawValue: "multipleOf")
    public static let minimum = Self(rawValue: "minimum")
    public static let maximum = Self(rawValue: "maximum")
    public static let exclusiveMinimum = Self(rawValue: "exclusiveMinimum")
    public static let exclusiveMaximum = Self(rawValue: "exclusiveMaximum")

    // String
    public static let minLength = Self(rawValue: "minLength")
    public static let maxLength = Self(rawValue: "maxLength")
    public static let pattern = Self(rawValue: "pattern")
    public static let contentMediaType = Self(rawValue: "contentMediaType")
    public static let contentEncoding = Self(rawValue: "contentEncoding")
    public static let contentSchema = Self(rawValue: "contentSchema")

    // Array
    public static let items = Self(rawValue: "items")
    public static let prefixItems = Self(rawValue: "prefixItems")
    public static let additionalItems = Self(rawValue: "additionalItems")
    public static let minItems = Self(rawValue: "minItems")
    public static let maxItems = Self(rawValue: "maxItems")
    public static let contains = Self(rawValue: "contains")
    public static let minContains = Self(rawValue: "minContains")
    public static let maxContains = Self(rawValue: "maxContains")
    public static let uniqueItems = Self(rawValue: "uniqueItems")
    public static let unevaluatedItems = Self(rawValue: "unevaluatedItems")

    // Object
    public static let properties = Self(rawValue: "properties")
    public static let patternProperties = Self(rawValue: "patternProperties")
    public static let additionalProperties = Self(rawValue: "additionalProperties")
    public static let required = Self(rawValue: "required")
    public static let dependentRequired = Self(rawValue: "dependentRequired")
    public static let minProperties = Self(rawValue: "minProperties")
    public static let maxProperties = Self(rawValue: "maxProperties")
    public static let propertyNames = Self(rawValue: "propertyNames")
    public static let unevaluatedProperties = Self(rawValue: "unevaluatedProperties")

    // Referencing
    public static let id$ = Self(rawValue: "$id")
    public static let ref$ = Self(rawValue: "$ref")
    public static let anchor$ = Self(rawValue: "$anchor")
    public static let dynamicRef$ = Self(rawValue: "$dynamicRef")
    public static let dynamicAnchor$ = Self(rawValue: "$dynamicAnchor")
    public static let defs$ = Self(rawValue: "$defs")

    // Meta
    public static let schema$ = Self(rawValue: "$schema")
    public static let vocabulary$ = Self(rawValue: "$vocabulary")

    // Format
    public static let format = Self(rawValue: "format")

    // - MARK: Legacy

    public static let definitions = Self(rawValue: "definitions")
    public static let dependencies = Self(rawValue: "dependencies")

    // - MARK: Solid

    // Bytes
    public static let minSize = Self(rawValue: "minSize")
    public static let maxSize = Self(rawValue: "maxSize")

    // Coding
    public static let units = Self(rawValue: "units")
    public static let bitWidth = Self(rawValue: "bitWidth")
    public static let encoding = Self(rawValue: "encoding")
  }

}

extension Schema.Keyword: CustomStringConvertible {

  public var description: String { rawValue }

}

internal func / (lhs: Pointer, rhs: Schema.Keyword) -> Pointer {
  lhs.appending(tokens: .name(rhs.rawValue))
}
