//
//  FilterSink.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import SolidCore
import Foundation


/// ``Sink`` that transforms data using a ``Filter`` before
/// writing to an accepting ``Sink``.
///
open class FilterSink: Sink, @unchecked Sendable {

  /// The ``Sink`` transformed data is written to.
  open private(set) var sink: Sink

  @AtomicCounter public var bytesWritten
  @AtomicFlag public var closed
  private var filter: Filter

  public required init(sink: Sink, filter: Filter) {
    self.sink = sink
    self.filter = filter
  }

  open func write(data: Data) async throws {
    guard !closed else { return }

    let processedData = try await filter.process(data: data)

    _bytesWritten.add(processedData.count)

    try await sink.write(data: processedData)
  }

  /// Closes the stream after writing any final data to the
  /// destination ``sink``.
  ///
  /// - Throws: ``IOError`` if stream finalization and/or close fails.
  ///
  open func close() async throws {
    guard !closed else { return }
    defer { _closed.signal() }

    if let data = try await filter.finish() {

      _bytesWritten.add(data.count)

      try await sink.write(data: data)
    }
  }

}

public extension Sink {

  /// Applies the filter `filter` to this stream via ``FilterSink``.
  ///
  /// - Parameter filter: Filter to apply.
  /// - Returns: Filtered sink stream writing to this stream.
  ///
  func filtering(using filter: Filter) -> Sink {
    FilterSink(sink: self, filter: filter)
  }

}
