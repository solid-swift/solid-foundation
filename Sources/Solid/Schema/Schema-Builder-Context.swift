//
//  Schema-Builder-Context.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/5/25.
//

import SolidData
import SolidURI
import Foundation
import OrderedCollections


extension Schema.Builder {

  public struct Context {

    public typealias Error = Schema.Error
    public typealias Options = Schema.Options

    public struct Scope {

      public let instance: Value
      public let instanceLocation: Pointer
      public let baseId: URI

      public var relativeInstanceLocation: Pointer = .root
      public var idRef: URI?
      public var anchor: String?
      public var dynamicAnchor: String?
      public var metaSchema: MetaSchema

      public var keywordBehaviors: Schema.ObjectSubSchema.KeywordBehaviors = [:]
      public var resources: [Schema] = []
      public var subSchemas: [Schema.SubSchema] = []
      public var dynamicRefs: Set<URI> = []

      public var isResourceRoot: Bool {
        idRef != nil
      }
    }

    public let options: Options

    private var scopes: [Scope] = []

    public init(
      instance: Value,
      baseId: URI,
      options: Options
    ) {
      self.options = options
      self.scopes = [
        Scope(
          instance: instance,
          instanceLocation: .root,
          baseId: baseId,
          metaSchema: options.defaultSchema
        )
      ]
    }

    private init(
      options: Options,
      scopes: [Scope]
    ) {
      self.options = options
      self.scopes = scopes
    }

    public func with(options: Options? = nil) -> Self {
      Self(options: options ?? self.options, scopes: scopes)
    }

    private var currentScope: Scope {
      get {
        guard scopes.count > 0 else {
          fatalError("Scope stack is empty")
        }
        return scopes[scopes.count - 1]
      }
      set {
        guard scopes.count > 0 else {
          fatalError("Scope stack is empty")
        }
        scopes[scopes.count - 1] = newValue
      }
    }

    private mutating func pushScope() {
      scopes.append(
        Scope(
          instance: self.instance,
          instanceLocation: self.instanceLocation,
          baseId: self.baseId,
          metaSchema: self.metaSchema
        )
      )
    }

    private mutating func popScope() {
      guard let scope = scopes.popLast() else {
        fatalError("Scope stack is empty")
      }
      if !scope.isResourceRoot {
        currentScope.resources.append(contentsOf: scope.resources)
        currentScope.dynamicRefs.formUnion(scope.dynamicRefs)
      }
    }

    public var isRootScope: Bool {
      scopes.count == 1
    }

    private mutating func pushLocation(_ relativeLocation: [KeywordLocationToken]) -> Pointer {
      let prevLocation = currentScope.relativeInstanceLocation
      currentScope.relativeInstanceLocation /= relativeLocation
      return prevLocation
    }

    private mutating func popLocation(_ prevLocation: Pointer) {
      currentScope.relativeInstanceLocation = prevLocation
    }

    public var scopeInstance: Value {
      currentScope.instance
    }

    public var instance: Value {
      let scope = currentScope
      return scope.instance[scope.relativeInstanceLocation]
        .neverNil("No instance at \(scope.relativeInstanceLocation)")
    }

    public var schemaInstanceLocation: Pointer {
      let scope = currentScope
      return if scope.isResourceRoot {
        scope.instanceLocation
      } else {
        scope.instanceLocation / scope.relativeInstanceLocation
      }
    }

    public var instanceLocation: Pointer {
      let scope = currentScope
      return if scope.isResourceRoot {
        scope.relativeInstanceLocation
      } else {
        scope.instanceLocation / scope.relativeInstanceLocation
      }
    }

    public var isResourceRoot: Bool {
      currentScope.idRef != nil
    }

    public var baseId: URI {
      let scope = currentScope
      return scope.idRef?.resolved(against: scope.baseId) ?? scope.baseId
    }

    public var idRef: URI? {
      get { currentScope.idRef }
      set { currentScope.idRef = newValue }
    }

    public var anchor: String? {
      get { currentScope.anchor }
      set { currentScope.anchor = newValue }
    }

    public var dynamicAnchor: String? {
      get { currentScope.dynamicAnchor }
      set { currentScope.dynamicAnchor = newValue }
    }

    public var locationId: URI {
      baseId.updating(fragmentPointer: instanceLocation)
    }

    public var anchorId: URI? {
      anchor.map { baseId.updating(.fragment($0)) }
    }

    public var dynamicAnchorId: URI? {
      dynamicAnchor.map { baseId.updating(.fragment($0)) }
    }

    public var canonicalId: URI {
      let id = anchorId ?? locationId
      return if id.fragment == "" {
        id.removing(.fragment)
      } else {
        id
      }
    }

    public var metaSchema: MetaSchema {
      get { currentScope.metaSchema }
      set { currentScope.metaSchema = newValue }
    }

    public var resources: [Schema] {
      currentScope.resources
    }

    public var subSchemas: [Schema.SubSchema] {
      currentScope.subSchemas
    }

    public var keywordBehaviors: Schema.ObjectSubSchema.KeywordBehaviors {
      currentScope.keywordBehaviors
    }

    @discardableResult
    public mutating func keywordBehavior<K: Schema.KeywordBehaviorBuilder>(
      for behaviorType: K.Type,
      at keyword: Schema.Keyword? = nil
    ) throws -> K.Behavior? {

      let keyword = keyword ?? behaviorType.keyword
      let prevLocation = pushLocation([keyword])
      tracePre()
      defer {
        tracePost()
        popLocation(prevLocation)
      }

      if let keywordBehavior = currentScope.keywordBehaviors[keyword] as? K.Behavior {
        return keywordBehavior
      }

      let keywordBehavior = try K.build(from: instance, context: &self)
      currentScope.keywordBehaviors[keyword] = keywordBehavior
      return keywordBehavior
    }

    public mutating func subSchema(
      for schemaInstance: Value,
      at relLocation: [KeywordLocationToken],
      isUnknown: Bool = false
    ) throws -> Schema.SubSchema {

      let prevLocation = pushLocation(relLocation)
      defer { popLocation(prevLocation) }

      pushScope()

      let subSchema: Schema.SubSchema
      do {
        subSchema = try Schema.Builder.build(from: instance, context: &self, isUnknown: isUnknown)
      } catch {
        popScope()
        throw error
      }

      popScope()

      if let schema = subSchema as? Schema {
        currentScope.resources.append(schema)
      }
      currentScope.subSchemas.append(subSchema)

      return subSchema
    }

    public mutating func subSchema(
      for schemaInstance: Value,
      at relLocation: KeywordLocationToken...
    ) throws -> Schema.SubSchema {
      try subSchema(for: schemaInstance, at: relLocation)
    }

    public mutating func subSchemas(
      for schemaInstances: Value.Array,
      at relLocation: KeywordLocationToken...
    ) throws -> [Schema.SubSchema] {
      try schemaInstances.enumerated()
        .map { schemaIdx, schemaInstance in
          try subSchema(for: schemaInstance, at: relLocation + [schemaIdx])
        }
    }

    public mutating func subSchemas<K: Hashable>(
      for schemaInstances: Value.Object,
      at relLocation: KeywordLocationToken...,
      keyMapper: (Value, inout Self) throws -> K
    ) throws -> OrderedDictionary<K, Schema.SubSchema> {

      // map key with correct location
      func mapKey(_ keyInstance: Value) throws -> K {
        let prevLocation = currentScope.relativeInstanceLocation
        defer { currentScope.relativeInstanceLocation = prevLocation }
        currentScope.relativeInstanceLocation /= relLocation + [keyInstance.stringified, "@"]
        return try keyMapper(keyInstance, &self)
      }

      return try schemaInstances.reduce(into: OrderedDictionary()) { result, schemaEntry in
        let (schemaKeyInstance, schemaInstance) = schemaEntry
        let schemaKey = try mapKey(schemaKeyInstance)
        result[schemaKey] = try subSchema(for: schemaInstance, at: relLocation + [schemaKeyInstance.stringified])
      }
    }

    public func keywordUsageError(
      _ message: String,
      at relativeLocation: KeywordLocationToken...
    ) throws -> Never {
      throw Error.keywordUsageError(message, location: instanceLocation / relativeLocation)
    }

    public func invalidType(
      requiredType: Schema.InstanceType,
      at relativeLocation: KeywordLocationToken...
    ) throws -> Never {
      throw Error.invalidType("Must be a '\(requiredType)'", location: instanceLocation / relativeLocation)
    }

    public func invalidValue(_ message: String, at relativeLocation: KeywordLocationToken...) throws -> Never {
      throw Error.invalidValue(message, location: instanceLocation / relativeLocation)
    }

    public func invalidValue<S: Collection, T: CustomStringConvertible>(
      options: S,
      at relativeLocation: KeywordLocationToken...
    ) throws -> Never where S.Element == T {
      throw Error.invalidValue(
        options.joinedToList(prefix: "Must be one of"),
        location: instanceLocation / relativeLocation
      )
    }

    public func locate(vocabularyId: URI) throws -> MetaSchema.Vocabulary? {
      try options.vocabularyLocator.locate(vocabularyId: vocabularyId, options: options)
    }

    public func locate(metaSchemaId: URI) throws -> MetaSchema? {
      try options.metaSchemaLocator.locate(metaSchemaId: metaSchemaId, options: options)
    }

    public func locate(schemaId: URI) throws -> Schema.SubSchema? {
      try options.schemaLocator.locate(schemaId: schemaId.removing(.fragment), options: options)?
        .locate(fragment: schemaId.fragment ?? "", allowing: .standard.subtracting([.canonical]))
    }

    internal func tracePre() {
      guard options.trace else {
        return
      }
      print("Building \(currentScope.instanceLocation / currentScope.relativeInstanceLocation)")
    }

    internal func tracePost() {
    }
  }
}

extension Schema.Builder.Context.Scope: Sendable {}
extension Schema.Builder.Context: Sendable {}
