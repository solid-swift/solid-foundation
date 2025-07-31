//
//  FilterSource.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import SolidCore
import Foundation


/// ``Source`` that transforms data using a ``Filter`` after
/// reading from an originating ``Source``.
///
open class FilterSource: Source, @unchecked Sendable {

  /// The ``Source`` filtered data is read from.
  open private(set) var source: Source

  @AtomicCounter public var bytesRead: Int
  @AtomicFlag public var closed
  private var filter: any Filter

  public required init(source: Source, filter: any Filter) {
    self.source = source
    self.filter = filter
  }

  open func read(max: Int) async throws -> Data? {
    guard !closed else { throw IOError.streamClosed }

    guard let readData = try await source.read(next: max) else {

      guard let finalData = try await filter.finish() else {
        return nil
      }

      _bytesRead.add(finalData.count)

      return finalData
    }

    let processedData = try await filter.process(data: readData)

    _bytesRead.add(processedData.count)

    return processedData
  }

  open func close() async throws {
    _closed.signal()
  }

}

public extension Source {

  /// Applies the filter `filter` to this stream via ``FilterSource``.
  ///
  /// - Parameter filter: Filter to apply.
  /// - Returns: Filtered source stream reading from this stream.
  func filtering(using filter: Filter) -> Source {
    FilterSource(source: self, filter: filter)
  }

}
