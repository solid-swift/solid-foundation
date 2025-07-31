//
//  Filter.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import Foundation


/// Data processing filter.
///
public protocol Filter {

  /// Start/continue the filtering process by transforming a
  /// single data buffer and returning the resultant data buffer.
  ///
  /// - Parameters data: Data to be filtered/transformed.
  /// - Returns The next block of data produced by the filter,
  /// which may not be the complete transformed data. If not, the
  /// final data will be returned in ``finish()``.
  ///
  func process(data: Data) async throws -> Data

  /// Finishes the filtering process and returns any
  /// final data produced.
  ///
  /// - Returns The remaining produced data, if any.
  ///
  func finish() async throws -> Data?

}

extension Filter {

  // Wraps filter process failures in IOError
  internal func process(data: Data) async throws(IOError) -> Data {
    do {
      return try await process(data: data)
    } catch {
      throw .filterFailed(error)
    }
  }

}
