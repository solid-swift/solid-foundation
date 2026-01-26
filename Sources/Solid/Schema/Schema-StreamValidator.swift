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
    private var decoder = ValueEventDecoder()
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
      do {
        try decoder.append(event)
      } catch let error as ValueEventDecoder.Error {
        throw mapDecoderError(error)
      }
    }

    public mutating func finish() throws -> (result: Validator.Result, annotations: [Schema.Annotation]) {
      guard !finished else {
        throw Error.alreadyFinished
      }
      finished = true
      let instance: Value
      do {
        instance = try decoder.finish()
      } catch let error as ValueEventDecoder.Error {
        throw mapDecoderError(error)
      }
      return try Validator.validate(
        instance: instance,
        using: schema,
        outputFormat: outputFormat,
        options: options
      )
    }

    private func mapDecoderError(_ error: ValueEventDecoder.Error) -> Error {
      switch error {
      case .invalidEventSequence(let message):
        return .invalidEventSequence(message)
      case .incompleteValue:
        return .incompleteValue
      }
    }
  }

}
