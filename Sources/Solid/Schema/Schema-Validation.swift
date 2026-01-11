//
//  Schema-Validation.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/24/25.
//

import SolidData


extension Schema {

  public enum Validation {
    case valid
    case annotation(Value)
    case invalid(String?)

    public static var invalid: Validation { .invalid(nil) }

    public var isValid: Bool {
      switch self {
      case .valid, .annotation:
        return true
      default:
        return false
      }
    }

    public var annotation: Value? {
      guard case .annotation(let value) = self else {
        return nil
      }
      return value
    }

    public var invalidReason: String? {
      guard case .invalid(let reason) = self else {
        return nil
      }
      return reason
    }
  }

}

extension Schema.Validation: Sendable {}

extension Schema.Validation: Equatable {}

extension Schema.Validation: Hashable {}
