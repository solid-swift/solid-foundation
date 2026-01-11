//
//  SchemaCodableMacro.swift
//  SolidFoundation
//
//  Created by Warp on 12/24/25.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftCompilerPlugin

@main
struct SolidCodingPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    SchemaCodableMacro.self
  ]
}

// MARK: Field model
private struct Field {
  let name: String
  let schemaName: String
  let type: TypeSyntax
  let isOptional: Bool
  let wrappedType: TypeSyntax
  let schemaType: String
  let format: String?
  let contentEncoding: String?
  let isRequiredOverride: Bool?
  let itemsSchema: String?
  let additionalPropertiesSchema: String?
}

// MARK: Macro
public struct SchemaCodableMacro: MemberMacro {

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declGroup: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {

    guard let structDecl = declGroup.as(StructDeclSyntax.self) else {
      throw DiagnosticsError(diagnostics: [
        Diagnostic(node: Syntax(node), message: SimpleError("SchemaCodable only applies to structs"))
      ])
    }

    let fields = structDecl.memberBlock.members.compactMap { member -> Field? in
      guard
        let varDecl = member.decl.as(VariableDeclSyntax.self),
        varDecl.bindings.count == 1,
        let binding = varDecl.bindings.first,
        binding.accessorBlock == nil,               // skip computed
        binding.pattern.is(IdentifierPatternSyntax.self)
      else { return nil }
      let originalName = binding.pattern.as(IdentifierPatternSyntax.self)!.identifier.text
      guard let type = binding.typeAnnotation?.type else { return nil }
      let (isOpt, wrapped) = unwrapOptional(type)
      let attrs = parseAttributes(varDecl.attributes)
      let mapping = mapSchema(for: wrapped, attrs: attrs)
      return Field(
        name: originalName,
        schemaName: attrs.nameOverride ?? originalName,
        type: type.trimmed,
        isOptional: isOpt,
        wrappedType: wrapped.trimmed,
        schemaType: mapping.type,
        format: mapping.format,
        contentEncoding: mapping.contentEncoding,
        isRequiredOverride: attrs.isRequired,
        itemsSchema: mapping.items,
        additionalPropertiesSchema: mapping.additionalProperties
      )
    }

    let typeSchemaStruct = makeTypeSchemaStruct(for: structDecl.name.text, fields: fields)
    let encodeMethod = makeEncodeMethod(fields: fields)
    let decodeInit = makeDecodeInit(for: structDecl.name.text, fields: fields)

    return [typeSchemaStruct, encodeMethod, decodeInit]
  }

  // MARK: Builders

  private static func makeTypeSchemaStruct(for typeName: String, fields: [Field]) -> DeclSyntax {
    let pointerDecls = fields.map { field in
      "public static let \(field.name) = Pointer(\"\(field.name)\")"
    }.joined(separator: "\n")

    let schemaProps = fields.map { field -> String in
      let typeValue = field.isOptional && field.isRequiredOverride != true
        ? "[\"null\", \"\(field.schemaType)\"]"
        : "\"\(field.schemaType)\""
      var dict = "\"type\": \(typeValue)"
      if let format = field.format {
        dict += ", \"format\": \"\(format)\""
      }
      if let enc = field.contentEncoding {
        dict += ", \"contentEncoding\": \"\(enc)\""
      }
      if let items = field.itemsSchema {
        dict += ", \"items\": \(items)"
      }
      if let addl = field.additionalPropertiesSchema {
        dict += ", \"additionalProperties\": \(addl)"
      }
      return "\"\(field.schemaName)\": [\(dict)]"
    }.joined(separator: ",\n")

    return DeclSyntax(stringLiteral:
      """
      public struct TypeSchema: AssociatedSchema {
        public typealias AssociatedType = \(typeName)

        \(pointerDecls)

        public static let schema: Schema = Schema.Builder.build(constant: [
          "type": "object",
          "properties": [
            \(schemaProps)
          ],
          "required": [\(fields.filter { ($0.isRequiredOverride ?? !$0.isOptional) }.map { "\"\($0.schemaName)\"" }.joined(separator: ", "))]
        ])
      }
      """
    )
  }

  private static func makeEncodeMethod(fields: [Field]) -> DeclSyntax {
    let bodyLines = fields.map { field in
      if field.isOptional {
        return """
        if let value = \(field.name) {
          try encoder.encode(value, at: TypeSchema.\(field.schemaName))
        }
        """
      } else {
        return "try encoder.encode(\(field.name), at: TypeSchema.\(field.schemaName))"
      }
    }.joined(separator: "\n    ")

    return DeclSyntax(stringLiteral:
      """
      public func encode(to encoder: inout some SchemaEncoder) throws {
        \(bodyLines)
      }
      """
    )
  }

  private static func makeDecodeInit(for typeName: String, fields: [Field]) -> DeclSyntax {
    let assignments = fields.map { field in
      if field.isOptional {
        let decodeCall = "try? decoder.decode(\(field.wrappedType.description).self, at: TypeSchema.\(field.schemaName))"
        return "self.\(field.name) = \(decodeCall)"
      } else {
        let decodeCall = "try decoder.decode(\(field.type.description).self, at: TypeSchema.\(field.schemaName))"
        return "self.\(field.name) = \(decodeCall)"
      }
    }.joined(separator: "\n    ")

    return DeclSyntax(stringLiteral:
      """
      public init(from decoder: inout some SchemaDecoder) throws {
        \(assignments)
      }
      """
    )
  }
}

// Simple diagnostic error
private struct SimpleError: DiagnosticMessage {
  let message: String
  var diagnosticID: MessageID { .init(domain: "SchemaCodableMacro", id: "error") }
  var severity: DiagnosticSeverity { .error }
  init(_ message: String) { self.message = message }
}

// MARK: Helpers
private func unwrapOptional(_ type: TypeSyntax) -> (Bool, TypeSyntax) {
  if let opt = type.as(OptionalTypeSyntax.self) {
    return (true, opt.wrappedType)
  }
  if let ident = type.as(IdentifierTypeSyntax.self),
     ident.name.text == "Optional",
     let first = ident.genericArgumentClause?.arguments.first {
    return (true, first.argument)
  }
  return (false, type)
}

private struct Attrs {
  var format: String?
  var contentEncoding: String?
  var nameOverride: String?
  var isRequired: Bool?
}

private func parseAttributes(_ attrs: AttributeListSyntax?) -> Attrs {
  var result = Attrs()
  guard let attrs else { return result }
  for attr in attrs.compactMap({ $0.as(AttributeSyntax.self) }) {
    switch attr.attributeName.trimmedDescription {
    case "SchemaFormat":
      if let arg = attr.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
        result.format = arg
      }
    case "SchemaEncoding":
      if let arg = attr.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
        result.contentEncoding = arg
      }
    case "SchemaName":
      if let arg = attr.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
        result.nameOverride = arg
      }
    case "SchemaRequired":
      result.isRequired = true
    case "SchemaNullable":
      result.isRequired = false
    default:
      break
    }
  }
  return result
}

private func mapSchema(for type: TypeSyntax, attrs: Attrs) -> (type: String, format: String?, contentEncoding: String?, items: String?, additionalProperties: String?) {
  if let ident = type.as(IdentifierTypeSyntax.self) {
    switch ident.name.text {
    case "String": return ("string", attrs.format, attrs.contentEncoding, nil, nil)
    case "Bool": return ("boolean", attrs.format, attrs.contentEncoding, nil, nil)
    case "Int", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return ("integer", attrs.format, attrs.contentEncoding, nil, nil)
    case "Float", "Double", "Float16", "Float32", "Float64": return ("number", attrs.format, attrs.contentEncoding, nil, nil)
    case "Data": return ("string", attrs.format, attrs.contentEncoding ?? "base64", nil, nil)
    case "LocalDate": return ("string", attrs.format ?? "date", attrs.contentEncoding, nil, nil)
    case "OffsetTime": return ("string", attrs.format ?? "time", attrs.contentEncoding, nil, nil)
    case "ZonedDateTime": return ("string", attrs.format ?? "date-time", attrs.contentEncoding, nil, nil)
    default: break
    }
  }

  // Array<T>
  if let arrayType = type.as(ArrayTypeSyntax.self) {
    let inner = mapSchema(for: arrayType.element, attrs: attrs)
    let itemsJSON = "[\"type\": \"\(inner.type)\"\(inner.format.map { ", \"format\": \"\($0)\"" } ?? "")\(inner.contentEncoding.map { ", \"contentEncoding\": \"\($0)\"" } ?? "")\(inner.items.map { ", \"items\": \($0)" } ?? "")\(inner.additionalProperties.map { ", \"additionalProperties\": \($0)" } ?? "")]"
    return ("array", attrs.format, attrs.contentEncoding, itemsJSON, nil)
  }

  // Dictionary<String, T>
  if let dict = type.as(DictionaryTypeSyntax.self),
     dict.key.is(IdentifierTypeSyntax.self),
     dict.key.trimmedDescription == "String" {
    let inner = mapSchema(for: dict.value, attrs: attrs)
    let addl = "[\"type\": \"\(inner.type)\"\(inner.format.map { ", \"format\": \"\($0)\"" } ?? "")\(inner.contentEncoding.map { ", \"contentEncoding\": \"\($0)\"" } ?? "")\(inner.items.map { ", \"items\": \($0)" } ?? "")\(inner.additionalProperties.map { ", \"additionalProperties\": \($0)" } ?? "")]"
    return ("object", attrs.format, attrs.contentEncoding, nil, addl)
  }

  if type.is(OptionalTypeSyntax.self) { return mapSchema(for: unwrapOptional(type).1, attrs: attrs) }

  return ("object", attrs.format, attrs.contentEncoding, nil, nil)
}
