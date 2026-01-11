//
//  Pointer-Error.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/31/25.
//

import Foundation

extension Pointer {

  /// Errors that can occur when working with JSON Pointers.
  public enum Error: Swift.Error {
    /// The reference token is invalid.
    ///
    /// This error occurs when trying to create a reference token from an invalid string.
    case invalidReferenceToken(String, position: Int, details: String)
    /// The pointer is invalid.
    ///
    /// This error occurs when trying to create a pointer from an invalid string.
    case invalidPointer(String, position: Int, details: String)
  }

}

extension Pointer.Error: Sendable {}

extension Pointer.Error: Equatable {}

extension Pointer.Error: Hashable {}

extension Pointer.Error: LocalizedError {

  /// Human-readable description of the error.
  public var errorDescription: String? {
    switch self {
    case .invalidReferenceToken(let token, let position, let details):
      return "The reference token '\(token)' is invalid (position \(position)): \(details)"
    case .invalidPointer(let pointer, let position, let details):
      return "The pointer '\(pointer)' is invalid (position \(position)): \(details)"
    }
  }

}
