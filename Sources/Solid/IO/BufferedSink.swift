//
//  BufferedSink.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/4/25.
//

import Foundation
import SolidCore
import Synchronization

/// ``Sink`` that buffers data before writing to ``sink``.
///
public class BufferedSink: Sink, Flushable, @unchecked Sendable {

  /// Size of segments written to ``BufferedSink/sink``.
  public static let segmentSize = BufferedSource.segmentSize

  /// ``Sink`` that data is written to.
  public let sink: Sink

  /// Size of buffers that will be written to ``sink``.
  public let segmentSize: Int

  /// Number of bytes written to this stream.
  @AtomicCounter public var bytesWritten: Int
  @AtomicFlag private var closed: Bool
  private let bufferedData = Mutex(Data())

  /// Initializes instance to write data to `sink` with a minimum
  /// buffer size of `segmentSize`.
  ///
  /// - Parameters:
  ///   - sink: ``Sink`` data will be written to.
  ///   - segmentSize: Miniumum size of data buffers written to ``sink``.
  ///
  public init(sink: Sink, segmentSize: Int = BufferedSink.segmentSize) {
    self.sink = sink
    self.segmentSize = segmentSize
  }

  public func write(data: Data) async throws {
    guard !closed else {
      throw IOError.streamClosed
    }

    _bytesWritten.add(data.count)

    let available =
      self.bufferedData.withLock { bufferedData in
        bufferedData.append(data)
        return bufferedData.count
      }
    if available > segmentSize {
      try await flush(size: available)
    }
  }

  public func flush() async throws {
    guard !closed else {
      throw IOError.streamClosed
    }

    try await flush(size: segmentSize)
  }

  private func flush(size: Int) async throws {

    func availableData(processedCount: Int?) throws -> Data? {
      bufferedData.withLock { bufferedData in

        if let processedCount {
          bufferedData = bufferedData.dropFirst(processedCount)
        }

        return if bufferedData.count > size {
          bufferedData.prefix(segmentSize)
        } else {
          nil
        }
      }
    }

    var lastProcessedCount: Int?

    while let data = try availableData(processedCount: lastProcessedCount) {

      try Task.checkCancellation()

      try await sink.write(data: data)

      lastProcessedCount = data.count
    }
  }

  public func close() async throws {
    let wasClosed = _closed.signal()
    guard !wasClosed else { return }

    try await flush(size: 0)

    try await sink.close()
  }

}
