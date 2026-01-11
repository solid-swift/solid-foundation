//
//  Schema-Validation-Context.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/2/25.
//

import SolidData
import SolidURI
import Algorithms
import Foundation


extension Schema.Validator {

  public struct Context {

    public typealias Annotation = Schema.Annotation

    public struct Scope: @unchecked Sendable {

      public let metaSchema: MetaSchema
      public let schema: Schema.SubSchema
      public let baseId: URI
      public let parentAbsoluteKeywordLocation: Pointer
      public let parentKeywordLocation: Pointer
      public let parentInstanceLocation: Pointer
      public var relativeKeywordTokens: [KeywordLocationToken] = []
      public var relativeInstanceTokens: [LocationToken] = []
      public var siblingAnnotations: [Schema.Keyword: Annotation] = [:]
      public var adjacentAnnotations: [Schema.Keyword: Set<Annotation>] = [:]

      public init(
        metaSchema: MetaSchema,
        schema: Schema.SubSchema,
        baseId: URI,
        parentAbsoluteKeywordLocation: Pointer,
        parentKeywordLocation: Pointer,
        parentInstanceLocation: Pointer
      ) {
        self.metaSchema = metaSchema
        self.schema = schema
        self.baseId = baseId
        self.parentAbsoluteKeywordLocation = parentAbsoluteKeywordLocation
        self.parentKeywordLocation = parentKeywordLocation
        self.parentInstanceLocation = parentInstanceLocation
      }

      public var id: URI? {
        guard let schema = schema as? Schema else {
          return nil
        }
        return schema.id
      }

      public var isResourceRoot: Bool {
        return id != nil
      }

      public var relativeKeywordLocation: Pointer {
        Pointer(tokens: relativeKeywordTokens.map(\.pointerToken))
      }

      public var keywordLocation: Pointer {
        parentKeywordLocation / relativeKeywordLocation
      }

      public var absoluteKeywordLocation: Pointer {
        parentAbsoluteKeywordLocation / relativeKeywordLocation
      }

      public var absoluteKeywordLocationURI: URI? {
        if absoluteKeywordLocation == keywordLocation {
          return nil
        }
        let id = id ?? baseId
        return id.appending(fragmentPointer: absoluteKeywordLocation)
      }

      public var relativeInstanceLocation: Pointer {
        Pointer(tokens: relativeInstanceTokens.map(\.pointerToken))
      }

      public var instanceLocation: Pointer {
        parentInstanceLocation / relativeInstanceLocation
      }

      public mutating func pushKeywordLocation(_ token: KeywordLocationToken) {
        relativeKeywordTokens.append(token)
      }

      public mutating func popKeywordLocation() {
        relativeKeywordTokens.removeLast()
      }

      public mutating func pushInstanceLocation(_ token: LocationToken) {
        relativeInstanceTokens.append(token)
      }

      public mutating func popInstanceLocation() {
        relativeInstanceTokens.removeLast()
      }

      public mutating func addAnnotation(_ value: Value, for keyword: Schema.Keyword) -> Annotation {
        let annotation = Annotation(
          keyword: keyword,
          value: value,
          instanceLocation: instanceLocation,
          keywordLocation: keywordLocation,
          absoluteKeywordLocation: absoluteKeywordLocationURI
        )
        siblingAnnotations[keyword] = annotation
        return annotation
      }

      public mutating func mergeInstanceAnnotations(from scope: Scope) {
        guard scope.instanceLocation == instanceLocation else {
          return
        }
        for (keyword, annotation) in scope.siblingAnnotations {
          var adjacents = adjacentAnnotations[keyword, default: []]
          adjacents.insert(annotation)
          adjacentAnnotations[keyword] = adjacents
        }
        for (keyword, annotations) in scope.adjacentAnnotations {
          var adjacents = adjacentAnnotations[keyword, default: []]
          adjacents.formUnion(annotations)
          adjacentAnnotations[keyword] = adjacents
        }
      }
    }

    public let outputFormat: OutputFormat
    public let options: Schema.Options
    public let rootInstance: Value
    public fileprivate(set) var scopes: [Scope] = []
    public fileprivate(set) var instanceLocation: Pointer = .root
    public fileprivate(set) var resultBuilder: AnyResultBuilder
    public fileprivate(set) var annotations: [Annotation]
    private var resourceSchemaCache: [URI: Schema] = [:]

    private init(
      instance: Value,
      outputFormat: OutputFormat,
      options: Schema.Options
    ) {
      self.outputFormat = outputFormat
      self.options = options
      self.rootInstance = instance
      self.resultBuilder = outputFormat.resultBuilder()
      self.annotations = []
    }

    public static func root(
      instance: Value,
      schema: Schema,
      outputFormat: OutputFormat,
      options: Schema.Options
    ) -> Self {
      var context = Self(
        instance: instance,
        outputFormat: outputFormat,
        options: options
      )
      context.scopes.append(
        Scope(
          metaSchema: schema.metaSchema,
          schema: schema,
          baseId: schema.id,
          parentAbsoluteKeywordLocation: .root,
          parentKeywordLocation: .root,
          parentInstanceLocation: .root
        )
      )
      context.resultBuilder.push()
      return context
    }

    public var currentScope: Scope {
      get {
        guard let scope = scopes.last else {
          fatalError("No current scope")
        }
        return scope
      }
      set {
        guard !scopes.isEmpty else {
          fatalError("No current scope")
        }
        scopes[scopes.count - 1] = newValue
      }
    }

    public var scopeIds: some Sequence<URI> {
      scopes.lazy.map(\.schema.id).uniqued()
    }

    @discardableResult
    fileprivate mutating func pushScope(_ schema: Schema.SubSchema, baseId: URI? = nil) -> Scope {
      let isResourceRoot = schema is Schema || baseId != nil
      let currentScope = currentScope
      let scope = Scope(
        metaSchema: (schema as? Schema)?.metaSchema ?? currentScope.metaSchema,
        schema: schema,
        baseId: baseId ?? (isResourceRoot ? schema.id : currentScope.baseId),
        parentAbsoluteKeywordLocation: isResourceRoot ? .root : currentScope.keywordLocation,
        parentKeywordLocation: currentScope.keywordLocation,
        parentInstanceLocation: currentScope.instanceLocation
      )
      scopes.append(scope)
      return scope
    }

    @discardableResult
    fileprivate mutating func popScope(validation: Schema.Validation) -> Scope {
      guard let scope = scopes.popLast() else {
        fatalError("No current scope")
      }
      if validation.isValid {
        currentScope.mergeInstanceAnnotations(from: scope)
      }
      return scope
    }

    fileprivate mutating func pushKeywordLocation(_ token: KeywordLocationToken) {
      currentScope.pushKeywordLocation(token)
      resultBuilder.push()
    }

    fileprivate mutating func popKeywordLocation(validation: Schema.Validation) {
      resultBuilder.pop(validation: validation, in: currentScope)
      currentScope.popKeywordLocation()
    }

    fileprivate mutating func pushInstanceLocation(_ token: LocationToken) {
      currentScope.pushInstanceLocation(token)
    }

    fileprivate mutating func popInstanceLocation() {
      currentScope.popInstanceLocation()
    }

    public var schema: Schema.SubSchema {
      currentScope.schema
    }

    public var baseId: URI {
      currentScope.baseId
    }

    public var id: URI? {
      currentScope.id
    }

    public var isCollecting: Bool {
      return options.collectAnnotations != .none || outputFormat == .detailed || outputFormat == .verbose
    }

    public mutating func collect(_ annotation: Annotation) {
      switch options.collectAnnotations {
      case .none:
        break
      case .all:
        annotations.append(annotation)
      case .matching(let filter):
        switch filter {
        case .keywords(let keywords):
          if keywords.contains(annotation.keyword) {
            annotations.append(annotation)
          }
        }
      }
    }

    public mutating func siblingAnnotation<K>(
      for keywordBehaviorType: K.Type
    ) -> Annotation? where K: Schema.KeywordBehavior & Schema.KeywordBehaviorBuilder {
      return currentScope.siblingAnnotations[K.keyword]
    }

    public func adjacentAnnotations(for keyword: Schema.Keyword) -> [Annotation] {
      let scope = currentScope
      let siblings = scope.siblingAnnotations[keyword].map { [$0] } ?? []
      let adjacents = scope.adjacentAnnotations[keyword].map(Array.init) ?? []
      return siblings + adjacents
    }

    public struct InstanceSpecificer {
      public var instance: Value
      public var location: LocationToken?

      public var locationPointer: Pointer { Pointer(tokens: location.map { [$0.pointerToken] } ?? []) }

      private init(instance: Value, location: LocationToken?) {
        self.instance = instance
        self.location = location
      }

      public func push(to context: inout Context) {
        if let location {
          context.pushInstanceLocation(location)
        }
      }

      public func pop(from context: inout Context, validation: Schema.Validation) {
        if location != nil {
          context.popInstanceLocation()
        }
      }

      public static func using(_ instance: Value, at location: LocationToken) -> Self {
        return InstanceSpecificer(instance: instance, location: location)
      }

      public static func inPlace(_ instance: Value) -> Self {
        return InstanceSpecificer(instance: instance, location: nil)
      }
    }

    @discardableResult
    public mutating func validate(
      instance instanceSpec: InstanceSpecificer,
      using keywordBehavior: some Schema.KeywordBehavior
    ) -> Schema.Validation {

      let keyword = keywordBehavior.keyword

      instanceSpec.push(to: &self)
      pushKeywordLocation(keyword)
      tracePre()

      let validation = keywordBehavior.apply(instance: instanceSpec.instance, context: &self)

      if case .annotation(let value) = validation {
        let annotation = currentScope.addAnnotation(value, for: keyword)
        collect(annotation)
      }

      tracePost(validation: validation)
      popKeywordLocation(validation: validation)
      instanceSpec.pop(from: &self, validation: validation)

      return validation
    }

    @discardableResult
    public mutating func validate(
      instance instanceSpec: InstanceSpecificer,
      using subSchema: some Schema.SubSchema,
      at keywordToken: LocationToken? = nil
    ) -> Schema.Validation {

      pushScope(subSchema)
      instanceSpec.push(to: &self)
      keywordToken.push(to: &self)
      tracePre()

      let validation = subSchema.validate(instance: instanceSpec.instance, context: &self)

      tracePost(validation: validation)
      keywordToken.pop(from: &self, validation: validation)
      instanceSpec.pop(from: &self, validation: validation)
      popScope(validation: validation)

      return validation
    }

    @discardableResult
    public mutating func validate(
      instance: Value,
      using subSchema: some Schema.SubSchema,
      at baseId: URI
    ) -> Schema.Validation {

      pushScope(subSchema, baseId: baseId)
      resultBuilder.push()
      tracePre()

      let validation = subSchema.validate(instance: instance, context: &self)

      tracePost(validation: validation)
      resultBuilder.pop(validation: validation, in: currentScope)
      popScope(validation: validation)

      return validation
    }

    public mutating func invalid(_ error: String, at keywordToken: LocationToken) {
      pushKeywordLocation(keywordToken)
      popKeywordLocation(validation: .invalid(error))
    }

    public mutating func result(validation: Schema.Validation) -> Schema.Validator.Result {
      resultBuilder.pop(validation: validation, in: currentScope)
    }

    private func tracePre() {
      let scope = currentScope
      trace("Validating \(scope.instanceLocation) @ \(scope.id ?? scope.baseId)#\(scope.keywordLocation)")
    }

    private func tracePost(validation: Schema.Validation) {
      let scope = currentScope
      let valid = validation.isValid ? "valid" : "invalid"
      trace("--> Result \(scope.instanceLocation) @ \(scope.id ?? scope.baseId)#\(scope.keywordLocation): \(valid)")
    }

    private func trace(_ message: String) {
      if options.trace {
        print(message)
      }
    }
  }
}

extension Schema.Validator.Context: Sendable {}

extension Schema.Validator.OutputFormat {

  func resultBuilder() -> Schema.Validator.Context.AnyResultBuilder {
    switch self {
    case .flag:
      return Schema.Validator.FlagResult.Builder()
    case .basic:
      return Schema.Validator.BasicResult.Builder()
    case .detailed, .verbose:
      return Schema.Validator.VerboseResult.Builder(detailsOnly: self == .detailed)
    }
  }
}

extension Schema.Validator.Context {

  public mutating func locateResource(schemaId: URI) throws -> Schema? {

    let schemaResourceId = schemaId.removing(.fragment)

    if let cachedResourceSchema = resourceSchemaCache[schemaResourceId] {
      return cachedResourceSchema
    }

    for scopeResourceSchema in scopes.lazy.reversed().compactMap({ $0.schema as? Schema }) {
      if let schema = scopeResourceSchema.locate(schemaId: schemaResourceId, options: options) {
        return schema
      }
    }

    guard
      let schema = try options.schemaLocator.locate(schemaId: schemaResourceId, options: options)
    else {
      return nil
    }

    // Cache resource schemas
    resourceSchemaCache[schema.id] = schema
    for resourceSchema in schema.resources {
      resourceSchemaCache[resourceSchema.id] = resourceSchema
    }

    return schema
  }

  public mutating func locate(
    schemaId: URI,
    allowing refTypes: Schema.RefTypes = .standard
  ) throws -> Schema.SubSchema? {

    guard let resourceSchema = try locateResource(schemaId: schemaId) else {
      return nil
    }

    let fragmentRefTypes = refTypes.subtracting([.canonical])

    return resourceSchema.locate(fragment: schemaId.fragment ?? "", allowing: fragmentRefTypes)
  }

}

public protocol KeywordLocationToken: Sendable {
  var pointerToken: Pointer.ReferenceToken { get }
}

public protocol LocationToken: KeywordLocationToken {}

extension String: LocationToken {
  public var pointerToken: Pointer.ReferenceToken { .name(self) }
}
extension Int: LocationToken {
  public var pointerToken: Pointer.ReferenceToken { .index(self) }
}
extension Schema.Keyword: KeywordLocationToken {
  public var pointerToken: Pointer.ReferenceToken { .name(rawValue) }
}

private extension Optional where Wrapped == any LocationToken {

  func push(to context: inout Schema.Validator.Context) {
    guard let token = self else {
      return
    }
    context.pushKeywordLocation(token)
  }

  func pop(from context: inout Schema.Validator.Context, validation: Schema.Validation) {
    guard self != nil else {
      return
    }
    context.popKeywordLocation(validation: validation)
  }
}
