//
//  LogMessage.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/28/25.
//

import Foundation


public struct LogMessage: Sendable {

  public enum Component: Sendable {
    case literal(String)
    case argument(any LogArgument)
    case lazy(@Sendable () -> any LogArgument)

    public var isLiteral: Bool {
      guard case .literal = self else { return false }
      return true
    }
  }

  public let components: [Component]

  public init(components: [Component]) {
    self.components = components
  }

  public init(message: String) {
    self.components = [.literal(message)]
  }

}


extension LogMessage: ExpressibleByStringInterpolation {

  public struct Interpolation: StringInterpolationProtocol {

    public var components: [LogMessage.Component]

    public init(literalCapacity: Int, interpolationCount: Int) {
      components = []
      components.reserveCapacity(interpolationCount * 2)
    }

    public mutating func appendArgument(_ argument: some LogArgument) {
      components.append(.argument(argument))
    }

    public mutating func appendLiteral(_ literal: String) {
      components.append(.literal(literal))
    }

    public mutating func appendInterpolation<T: LogConvertible>(
      _ value: T,
      format: StringLogArgument<String>.Format? = nil,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(StringLogArgument(string: { value.logDescription }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation(
      _ value: Bool,
      format: BoolLogArgument.Format? = nil,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(BoolLogArgument(value: { value }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<S: StringProtocol & Sendable>(
      _ value: S,
      format: StringLogArgument<S>.Format? = nil,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(StringLogArgument(string: { value }, format: format, privacy: privacy))
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<S: CustomStringConvertible & Sendable>(
      _ value: S,
      format: StringLogArgument<String>.Format = .default,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(StringLogArgument(string: { value.description }, format: format, privacy: privacy))
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<S: CustomDebugStringConvertible & Sendable>(
      _ value: S,
      format: StringLogArgument<String>.Format = .default,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(StringLogArgument(string: { value.debugDescription }, format: format, privacy: privacy))
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<S: CustomStringConvertible & CustomDebugStringConvertible & Sendable>(
      _ value: S,
      format: StringLogArgument<String>.Format = .default,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(StringLogArgument(string: { value.description }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<I: FixedWidthInteger & Sendable>(
      _ value: I,
      format: IntegerLogArgument<I>.Format = .default,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(IntegerLogArgument(int: { value }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<I: FixedWidthInteger & Sendable>(
      _ value: I,
      format: IntegerUnitLogArgument<I>.Format,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(IntegerUnitLogArgument(int: { value }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<I: FixedWidthInteger & Sendable>(
      _ value: I,
      unit: IntegerTimeLogArgument<I>.Unit,
      format: IntegerTimeLogArgument<I>.Format,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(IntegerTimeLogArgument(int: { value }, unit: unit, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation(
      _ value: Int,
      error system: IntegerErrorLogArgument.SubSystem,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(IntegerErrorLogArgument(int: { value }, system: system, privacy: privacy))
    }

    public mutating func appendInterpolation<F: FloatingPoint & Sendable>(
      _ value: F,
      format: FloatLogArgument<F>.Format? = nil,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(FloatLogArgument(float: { value }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<F: FloatingPoint & Sendable>(
      _ value: F,
      epoch: FloatDateLogArgument<F>.Epoch,
      format: FloatDateLogArgument<F>.Format,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(FloatDateLogArgument(float: { value }, epoch: epoch, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<E: Error>(
      _ value: E,
      format: ErrorLogArgument<E>.Format? = nil,
      privacy: LogPrivacy? = nil
    ) {
      appendArgument(ErrorLogArgument(error: { value }, format: format, privacy: privacy))
    }

    @_disfavoredOverload
    public mutating func appendInterpolation(
      _ value: Any & Sendable,
      format: StringLogArgument<String>.Format? = nil,
      privacy: LogPrivacy? = nil,
    ) {
      appendArgument(StringLogArgument(string: { String(describing: value) }, format: format, privacy: privacy))
    }

    public mutating func appendInterpolation<A: LogArgument>(
      _ value: A,
    ) {
      components.append(.lazy({ value }))
    }
    public mutating func appendInterpolation<A: LogArgument>(
      _ value: @autoclosure @escaping @Sendable () -> A,
    ) {
      components.append(.lazy(value))
    }
  }

  public init(stringInterpolation: Interpolation) {
    self.components = stringInterpolation.components
  }

  public init(stringLiteral value: String) {
    self.components = [.literal(value)]
  }

  func formattedString(for loggingPrivacy: LogPrivacy) -> String {

    var message = ""

    func append(_ argument: some LogArgument) {
      let value = argument.privacy.redact(argument, for: loggingPrivacy)
      message.append(value)
    }

    for component in components {
      switch component {
      case .literal(let literal):
        message.append(literal)
      case .argument(let argument):
        message.append(argument.formattedValue)
      case .lazy(let argumentProducer):
        let value = argumentProducer()
        message.append(value.formattedValue)
      }
    }

    return message
  }

}
