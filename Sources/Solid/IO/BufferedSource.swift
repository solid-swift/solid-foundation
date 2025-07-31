//
//  BufferedSource.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/4/25.
//

import Foundation


/// ``Source`` that buffers data read from ``source``.
///
public class BufferedSource: Source, @unchecked Sendable {

  /// Size of segments read from ``BufferedSource/source``.
  public static let segmentSize = 64 * 1024

  /// ``Source``that data is read from.
  public let source: Source

  /// Size of buffers that will be requested from ``source``.
  public let segmentSize: Int

  public private(set) var bytesRead: Int = 0
  private var closed = false

  private var data = Data()

  /// Initializes instance to read data from `source` using
  /// requested size of `segmentSize`.
  ///
  /// - Parameters:
  ///   - source: ``Source`` that data will be written to.
  ///   - segmentSize: Size of data buffers written to `sink`.
  ///
  public init(source: Source, segmentSize: Int = BufferedSource.segmentSize) {
    self.source = source
    self.segmentSize = segmentSize
  }

  /// Requires that the internal buffer has at least
  /// `requiredSize` bytes available.
  ///
  /// - Parameter requiredSize: Number of bytes required to be avilable
  /// - Returns: True if the internal buffer has the required amount of data available.
  /// - Throws: ``IOError`` if the stream is closed or a ``CancellationError``.
  public func require(count requiredSize: Int) async throws -> Bool {
    guard !closed else { throw IOError.streamClosed }

    while data.count < requiredSize {

      try Task.checkCancellation()

      guard let more = try await source.read(max: segmentSize) else {
        return false
      }

      data.append(more)
    }

    return true
  }

  public func read(max: Int) async throws -> Data? {
    guard !closed else { throw IOError.streamClosed }

    if data.isEmpty {

      guard let data = try await source.read(next: max) else {
        return nil
      }

      self.data.append(data)
    }

    let data = data.prefix(max)
    self.data = self.data.subdata(in: data.count..<self.data.count)

    bytesRead += data.count

    return data
  }

  public func read(next: Int) async throws -> Data? {
    guard !closed else { throw IOError.streamClosed }

    _ = try await require(count: next)

    return try await read(max: next)
  }

  public func close() async throws {
    guard !closed else { return }
    defer { closed = true }

    try await source.close()
  }

}

public extension Source {

  /// Applies buffering to this source via ``BufferedSource``.
  ///
  /// - Parameter segmentSize: Size of buffers that will be read from this stream.
  /// - Returns: Buffered source stream reading from this stream.
  func buffering(segmentSize: Int = BufferedSource.segmentSize) -> Source {
    if self is BufferedSource {
      return self
    }
    return BufferedSource(source: self, segmentSize: segmentSize)
  }

}

public extension Sink {

  /// Applies buffering to this sink via ``BufferedSink``.
  ///
  /// - Parameter segmentSize: Size of buffers that will be written to this stream.
  /// - Returns: Buffered sink stream writing to this stream.
  func buffering(segmentSize: Int = BufferedSink.segmentSize) -> Sink {
    if self is BufferedSink {
      return self
    }
    return BufferedSink(sink: self, segmentSize: segmentSize)
  }

}
