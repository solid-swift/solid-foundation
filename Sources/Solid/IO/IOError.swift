//
//  IOError.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/4/25.
//

import Foundation


/// I/O related errors.
///
public enum IOError: Error, LocalizedError {

  /// End-of-stream was encountered during a read.
  case endOfStream

  /// The stream is closed.
  case streamClosed

  /// Filter operation failed.
  /// - Parameter Error: The filter error that cause the I/O error.
  case filterFailed(Error)

  public var errorDescription: String? {
    switch self {
    case .endOfStream: return "End of Stream"
    case .streamClosed: return "Stream Closed"
    case .filterFailed(let error): return "Filter Failed: \(error.localizedDescription)"
    }
  }

}
