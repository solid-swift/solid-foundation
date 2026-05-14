//
//  FormatStreamDriverError.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

import Foundation

/// Errors thrown by asynchronous format stream drivers.
public enum FormatStreamDriverError: Error, Sendable, Equatable, LocalizedError {

  /// A driver operation is already in progress.
  case operationInProgress

  public var errorDescription: String? {
    switch self {
    case .operationInProgress:
      return "Format stream driver operation is already in progress"
    }
  }
}
