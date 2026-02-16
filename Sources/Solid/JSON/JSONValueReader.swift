//
//  JSONReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/25/25.
//

import SolidData
import Foundation

public struct JSONValueReader: FormatReader {

  var tokenReader: JSONTokenReader

  public init(data: Data) {
    self.tokenReader = JSONTokenReader(data: data)
  }

  public init(string: String) {
    self.tokenReader = JSONTokenReader(string: string)
  }

  public var format: Format { JSON.format }

  public mutating func read() throws -> Value {
    return try tokenReader.readValue(converter: ValueConverter.instance)
  }

  public mutating func validateValue() throws {
    try tokenReader.readValue(converter: NullConverter.instance)
  }

  enum ValueConverter: JSONTokenConverter {

    case instance

    typealias ValueType = SolidData.Value

    func convertScalar(_ value: JSONToken.Scalar) throws -> Value {
      switch value {
      case .string(let string): .string(string)
      case .number(let number): Self.convertNumber(number)
      case .bool(let bool): .bool(bool)
      case .null: .null
      }
    }

    /// Convert a JSON number token to a Value, using a fast integer path
    /// to avoid BigDecimal construction for simple integers.
    private static func convertNumber(_ number: JSONToken.Scalar.Number) -> Value {
      let text = number.value
      // Fast path: simple integers (all ASCII digits, optionally prefixed with -)
      // bypass BigDecimal entirely via TextNumber(text:) which still builds BigDecimal
      // but we can go even faster for simple ints by parsing directly to Int64/UInt64
      if number.isInteger {
        let utf8 = text.utf8
        var idx = utf8.startIndex
        let isNeg = utf8[idx] == UInt8(ascii: "-")
        if isNeg { utf8.formIndex(after: &idx) }

        // Parse as UInt64 to avoid overflow on large positive values
        var magnitude: UInt64 = 0
        var overflow = false
        while idx < utf8.endIndex {
          let digit = utf8[idx] &- UInt8(ascii: "0")
          let (m1, o1) = magnitude.multipliedReportingOverflow(by: 10)
          let (m2, o2) = m1.addingReportingOverflow(UInt64(digit))
          if o1 || o2 { overflow = true; break }
          magnitude = m2
          utf8.formIndex(after: &idx)
        }

        if !overflow {
          if isNeg {
            if magnitude <= UInt64(Int64.max) + 1 {
              let intVal = Int64(bitPattern: 0 &- magnitude)
              return .number(Value.BinaryNumber.int64(intVal))
            }
            // Falls through to TextNumber for very large negatives
          } else {
            if magnitude <= UInt64(Int64.max) {
              return .number(Value.BinaryNumber.int64(Int64(magnitude)))
            } else {
              return .number(Value.BinaryNumber.uint64(magnitude))
            }
          }
        }
      }

      // Fallback: use TextNumber which constructs BigDecimal
      guard let textNumber = Value.TextNumber(text: text) else {
        // Should not happen — the JSON parser already validated the number
        return .number(text)
      }
      return .number(textNumber)
    }

    func convertArray(_ value: [Value]) throws -> Value {
      return .array(value)
    }

    func convertObject(_ value: [(String, Value)]) throws -> Value {
      var object = Value.Object()
      for (key, val) in value {
        object[.string(key)] = val
      }
      return .object(object)
    }

    func convertNull() -> Value {
      return .null
    }
  }

  enum NullConverter: JSONTokenConverter {

    case instance

    typealias ValueType = Void

    func convertScalar(_ value: JSONToken.Scalar) throws -> Void {
      return
    }

    func convertArray(_ value: [Void]) throws -> Void {
      return
    }

    func convertObject(_ value: [(String, Void)]) throws -> Void {
      return
    }

    func convertNull() -> Void {
      return
    }
  }
}
