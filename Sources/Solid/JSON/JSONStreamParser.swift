//
//  JSONStreamParser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData


/// Incremental JSON parser that emits ``ValueEvent`` instances.
public struct JSONPushParser {

  public enum Error: Swift.Error {
    case unexpectedEndOfStream
    case invalidToken
    case invalidString
    case invalidNumber
    case invalidBoolean
    case invalidEscapeSequence
    case invalidUTF8String
    case invalidStructure(String)
  }

  private enum RootState {
    case expectingValue
    case complete
  }

  private enum ArrayState {
    case expectValueOrEnd
    case expectValue
    case expectCommaOrEnd
  }

  private enum ObjectState {
    case expectKeyOrEnd
    case expectKey
    case expectColon
    case expectValue
    case expectCommaOrEnd
  }

  private enum ContainerState {
    case array(ArrayState)
    case object(ObjectState)
  }

  private var tokenizer = JSONStreamingTokenizer()
  private var containers: [ContainerState] = []
  private var rootState: RootState = .expectingValue
  private var finished = false

  public init() {}

  public var isFinished: Bool { finished }

  public mutating func feed(_ data: Data, isFinal: Bool = false) {
    tokenizer.append(data, isFinal: isFinal)
  }

  public mutating func nextEvent() throws -> ValueEvent? {
    guard !finished else { return nil }

    while true {
      guard let token = try tokenizer.nextToken() else {
        return try handleNoToken()
      }

      if rootState == .complete {
        throw Error.invalidStructure("Extra data after root value")
      }

      if let event = try handleToken(token) {
        return event
      }
    }
  }

  private mutating func handleNoToken() throws -> ValueEvent? {
    if tokenizer.isFinalized {
      if !tokenizer.isIdle || !tokenizer.isBufferEmpty {
        throw Error.unexpectedEndOfStream
      }
      if rootState == .expectingValue {
        throw Error.unexpectedEndOfStream
      }
      finished = true
    }
    return nil
  }

  private mutating func handleToken(_ token: JSONToken) throws -> ValueEvent? {
    switch token {
    case .scalar(let scalar):
      if let event = try handleScalar(scalar) {
        return event
      }
      return nil

    case .beginArray:
      try startValue()
      containers.append(.array(.expectValueOrEnd))
      return .beginArray(count: nil)

    case .endArray:
      guard case .array(let state) = containers.popLast() else {
        throw Error.invalidStructure("Unexpected endArray")
      }
      guard state == .expectValueOrEnd || state == .expectCommaOrEnd else {
        throw Error.invalidStructure("Unexpected endArray state")
      }
      finishValue()
      return .endArray

    case .beginObject:
      try startValue()
      containers.append(.object(.expectKeyOrEnd))
      return .beginObject(count: nil)

    case .endObject:
      guard case .object(let state) = containers.popLast() else {
        throw Error.invalidStructure("Unexpected endObject")
      }
      guard state == .expectKeyOrEnd || state == .expectCommaOrEnd else {
        throw Error.invalidStructure("Unexpected endObject state")
      }
      finishValue()
      return .endObject

    case .pairSeparator:
      guard case .object(let state) = containers.popLast() else {
        throw Error.invalidStructure("Unexpected pair separator")
      }
      guard state == .expectColon else {
        throw Error.invalidStructure("Unexpected pair separator state")
      }
      containers.append(.object(.expectValue))
      return nil

    case .elementSeparator:
      guard let container = containers.popLast() else {
        throw Error.invalidStructure("Unexpected element separator")
      }
      switch container {
      case .array(let state):
        guard state == .expectCommaOrEnd else {
          throw Error.invalidStructure("Unexpected element separator in array")
        }
        containers.append(.array(.expectValue))
      case .object(let state):
        guard state == .expectCommaOrEnd else {
          throw Error.invalidStructure("Unexpected element separator in object")
        }
        containers.append(.object(.expectKey))
      }
      return nil
    }
  }

  private mutating func handleScalar(_ scalar: JSONToken.Scalar) throws -> ValueEvent? {
    if case .object(let state) = containers.last {
      if state == .expectKeyOrEnd || state == .expectKey {
        guard case .string(let string) = scalar else {
          throw Error.invalidStructure("Expected string key")
        }
        _ = containers.popLast()
        containers.append(.object(.expectColon))
        return .key(.string(string))
      }
    }

    try startValue()
    let value = try convertScalar(scalar)
    finishValue()
    return .scalar(value)
  }

  private func convertScalar(_ scalar: JSONToken.Scalar) throws -> Value {
    switch scalar {
    case .null:
      return .null
    case .bool(let value):
      return .bool(value)
    case .string(let value):
      return .string(value)
    case .number(let number):
      return number.toValue()
    }
  }

  private mutating func startValue() throws {
    if let container = containers.last {
      switch container {
      case .array(let state):
        guard state == .expectValue || state == .expectValueOrEnd else {
          throw Error.invalidStructure("Unexpected value in array")
        }
      case .object(let state):
        guard state == .expectValue else {
          throw Error.invalidStructure("Unexpected value in object")
        }
      }
    } else {
      guard rootState == .expectingValue else {
        throw Error.invalidStructure("Multiple root values")
      }
    }
  }

  private mutating func finishValue() {
    guard let container = containers.popLast() else {
      rootState = .complete
      return
    }
    switch container {
    case .array:
      containers.append(.array(.expectCommaOrEnd))
    case .object:
      containers.append(.object(.expectCommaOrEnd))
    }
  }
}
