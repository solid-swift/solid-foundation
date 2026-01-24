//
//  Schema-StreamValidator.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import SolidData


extension Schema {

  /// Streaming schema validator that consumes ``ValueEvent`` instances.
  ///
  /// - Note: This currently buffers a full value before validating.
  public struct StreamValidator {

    public enum Error: Swift.Error {
      case invalidEventSequence(String)
      case incompleteValue
      case alreadyFinished
    }

    private let schema: Schema
    private let outputFormat: Schema.Validator.OutputFormat
    private let options: Schema.Options
    private var builder = ValueEventBuilder()
    private var finished = false

    public init(
      schema: Schema,
      outputFormat: Schema.Validator.OutputFormat = .basic,
      options: Schema.Options = .default
    ) {
      self.schema = schema
      self.outputFormat = outputFormat
      self.options = options
    }

    public mutating func consume(_ event: ValueEvent) throws {
      guard !finished else {
        throw Error.alreadyFinished
      }
      try builder.append(event)
    }

    public mutating func finish() throws -> (result: Validator.Result, annotations: [Schema.Annotation]) {
      guard !finished else {
        throw Error.alreadyFinished
      }
      finished = true
      let instance = try builder.finish()
      return try Validator.validate(
        instance: instance,
        using: schema,
        outputFormat: outputFormat,
        options: options
      )
    }
  }

}

private struct ValueEventBuilder {

  private enum Container {
    case array([Value], tags: [Value])
    case object(Value.Object, expectingKey: Bool, currentKey: Value?, tags: [Value])
  }

  private var stack: [Container] = []
  private var pendingTags: [Value] = []
  private var root: Value?

  mutating func append(_ event: ValueEvent) throws {
    switch event {
    case .tag(let tag):
      pendingTags.append(tag)

    case .scalar(let value):
      try appendValue(value)

    case .beginArray:
      let tags = pendingTags
      pendingTags.removeAll()
      stack.append(.array([], tags: tags))

    case .endArray:
      guard case .array(let values, let tags) = stack.popLast() else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Unexpected endArray")
      }
      try appendValue(applyTags(Value.array(values), tags: tags))

    case .beginObject:
      let tags = pendingTags
      pendingTags.removeAll()
      stack.append(.object(Value.Object(), expectingKey: true, currentKey: nil, tags: tags))

    case .endObject:
      guard case .object(let object, let expectingKey, _, let tags) = stack.popLast() else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Unexpected endObject")
      }
      guard expectingKey else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Missing value for key")
      }
      try appendValue(applyTags(Value.object(object), tags: tags))

    case .key(let key):
      guard case .object(let object, let expectingKey, let currentKey, let tags) = stack.popLast() else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Unexpected key")
      }
      guard expectingKey, currentKey == nil else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Unexpected key position")
      }
      let taggedKey = applyTags(key, tags: pendingTags)
      pendingTags.removeAll()
      stack.append(.object(object, expectingKey: false, currentKey: taggedKey, tags: tags))
    }
  }

  mutating func finish() throws -> Value {
    guard stack.isEmpty, pendingTags.isEmpty, let root else {
      throw Schema.StreamValidator.Error.incompleteValue
    }
    return root
  }

  private func applyTags(_ value: Value, tags: [Value]) -> Value {
    var tagged = value
    for tag in tags.reversed() {
      tagged = .tagged(tag: tag, value: tagged)
    }
    return tagged
  }

  private mutating func appendValue(_ value: Value) throws {
    let taggedValue = applyTags(value, tags: pendingTags)
    pendingTags.removeAll()

    guard let container = stack.popLast() else {
      guard root == nil else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Multiple root values")
      }
      root = taggedValue
      return
    }

    switch container {
    case .array(var values, let tags):
      values.append(taggedValue)
      stack.append(.array(values, tags: tags))

    case .object(var object, let expectingKey, let currentKey, let tags):
      guard !expectingKey, let key = currentKey else {
        throw Schema.StreamValidator.Error.invalidEventSequence("Missing key for value")
      }
      object[key] = taggedValue
      stack.append(.object(object, expectingKey: true, currentKey: nil, tags: tags))
    }
  }

}
