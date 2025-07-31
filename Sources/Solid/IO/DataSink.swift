//
//  DataSink.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

import SolidCore
import Foundation
import Synchronization


/// ``Sink`` that writes directly to a `Data` buffer.
///
public final class DataSink: Sink, @unchecked Sendable {

  struct State {
    var data: Data
    var bytesWritten: Int
    var closed: Bool
  }

  private let state: Mutex<State>

  /// Data buffer sink is writing to.
  public var data: Data { state.withLock(\.data) }
  public var bytesWritten: Int { state.withLock(\.bytesWritten) }

  @AtomicFlag var closed: Bool

  /// Initialize the stream with a specified target `data` buffer.
  ///
  /// - Parameter data: Data buffer to write to. Defaults to
  /// the empty buffer.
  ///
  public init(data: Data = Data()) {
    self.state = Mutex(State(data: data, bytesWritten: 0, closed: false))
  }

  public func write(data: Data) throws {
    try self.state.withLock { state in
      guard !state.closed else { throw IOError.streamClosed }

      state.data.append(data)

      state.bytesWritten += data.count
    }
  }

  public func close() {
    state.withLock { $0.closed = true }
  }

}

/// ``Source`` that reads directly from a `Data` buffer.
///
public final class DataSource: Source, @unchecked Sendable {

  struct State {
    var data: Data
    var bytesRead: Int
    var closed: Bool
  }

  private let state: Mutex<State>

  /// Data buffer source is reading from.
  public var data: Data { state.withLock(\.data) }
  @AtomicCounter public var bytesRead: Int

  /// Initialize the stream with a specified source `data` buffer.
  ///
  /// - Parameter data: Data buffer to read from.
  ///
  public init(data: Data) {
    self.state = Mutex(State(data: data, bytesRead: 0, closed: false))
  }

  public func read(max maxLength: Int) throws -> Data? {
    return try state.withLock { state in
      guard !state.closed else { throw IOError.streamClosed }

      guard !state.data.isEmpty else {
        return nil
      }

      let result = state.data.prefix(maxLength)

      state.data.removeSubrange(0..<result.count)

      state.bytesRead += result.count

      return result
    }
  }

  public func close() {
    state.withLock { $0.closed = true }
  }

}

public extension Data {

  static func sink() -> DataSink { DataSink() }

  func source() -> DataSource { DataSource(data: self) }

}
