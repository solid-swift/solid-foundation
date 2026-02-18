//
//  FilesStreams.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/1/25.
//

import SolidCore
import Foundation
import Synchronization


/// ``Source`` that sequentially reads data from a file.
///
/// - Note: ``FileSource`` uses high performance `DispatchIO`.
///
public class FileSource: FileStream, Source, @unchecked Sendable {

  // swift-format-ignore: NoLeadingUnderscores
  private let _bytesRead = Atomic<Int>(0)

  public var bytesRead: Int { _bytesRead.load(ordering: .acquiring) }

  /// Initialize the source from a file `URL`.
  ///
  /// - Parameter url: `URL` of the file to operate on.
  /// - Throws: `POSIXError` error if the file cannot be opened for reading.
  ///
  public convenience init(url: URL) throws {
    try self.init(fileHandle: FileHandle(forReadingFrom: url))
  }

  /// Initialize the source from a file path.
  ///
  /// - Parameter path: path of the file to operate on.
  /// - Throws: `POSIXError` error if the file cannot be opened for reading.
  ///
  public convenience init(path: String) throws {
    guard let fileHandle = FileHandle(forReadingAtPath: path) else {
      throw POSIXError(.ENOENT)
    }
    self.init(fileHandle: fileHandle)
  }

  public func read(max: Int) async throws -> Data? {

    repeat {
      do {
        let dispatchIO = try self.dispatchIO

        let data: Data? = try await withTaskCancellationHandler {

          try await withCheckedThrowingContinuation { continuation in

            var collectedData = Data()

            dispatchIO.read(offset: 0, length: max, queue: .taskPriorityQueue) { done, data, error in

              if error == ECANCELED {

                return continuation.resume(throwing: CancellationError())
              }

              if let data, !data.isEmpty {

                collectedData.append(Data(data))
              }

              if error != 0 {

                return continuation.resume(throwing: POSIXError(POSIXError.Code(rawValue: error) ?? .EIO))
              } else if done {

                return continuation.resume(returning: collectedData.isEmpty ? nil : collectedData)
              }

            }
          }

        } onCancel: {
          cancel()
        }

        if let data {
          _bytesRead.add(data.count, ordering: .acquiringAndReleasing)
        }

        return data

      } catch is CancellationError {
        // retry
      }
    } while !Task.isCancelled

    throw CancellationError()
  }

}


/// ``Sink`` that sequentially writes data to a file.
///
/// - Note: ``FileSink`` uses high performance `DispatchIO`.
///
public final class FileSink: FileStream, Sink, @unchecked Sendable {

  // swift-format-ignore: NoLeadingUnderscores
  private let _bytesWritten = Atomic<Int>(0)

  public var bytesWritten: Int { _bytesWritten.load(ordering: .acquiring) }

  /// Initialize the sink from a file `URL`.
  ///
  /// - Parameter url: `URL` of the file to operate on.
  /// - Throws: `POSIXError` error if the file cannot be opened for writing.
  ///
  public convenience init(url: URL) throws {
    try self.init(fileHandle: FileHandle(forWritingTo: url))
  }

  /// Initialize the sink from a file path.
  ///
  /// - Parameter path: path of the file to operate on.
  /// - Throws: `POSIXError` error if the file cannot be opened for writing.
  ///
  public convenience init(path: String) throws {
    guard let fileHandle = FileHandle(forWritingAtPath: path) else {
      throw POSIXError(.ENOENT)
    }
    self.init(fileHandle: fileHandle)
  }

  public func write(data: Data) async throws {

    repeat {
      do {
        let dispatchIO = try self.dispatchIO

        try await withTaskCancellationHandler {

          try await withCheckedThrowingContinuation { continuation in

            data.withUnsafeBytes { dataPtr in

              let data = DispatchData(bytes: dataPtr)

              let handler: @Sendable (Bool, DispatchData?, Int32) -> Void = { done, _, error in

                if error == ECANCELED {
                  continuation.resume(throwing: CancellationError())
                  return
                }

                guard done else {
                  return
                }

                if error != 0 {
                  let code = POSIXError.Code(rawValue: error) ?? .EIO
                  continuation.resume(throwing: POSIXError(code))
                } else {
                  continuation.resume(returning: ())
                }
              }

              dispatchIO.write(offset: 0, data: data, queue: .taskPriorityQueue, ioHandler: handler)
            }
          } as Void

        } onCancel: {
          cancel()
        }

        _bytesWritten.add(data.count, ordering: .acquiringAndReleasing)

        return

      } catch is CancellationError {
        // retry
      }
    } while !Task.isCancelled

    throw CancellationError()
  }

}


/// Common ``Stream`` that operates on a file.
///
/// - Note: ``FileStream`` uses high performance `DispatchIO`.
///
public class FileStream: Stream, @unchecked Sendable {

  private static let progressReportLimits = (
    lowWaterMark: 8 * 1024,
    highWaterMark: 64 * 1024,
    maxInterval: DispatchTimeInterval.microseconds(50)
  )

  fileprivate enum State {
    case open(DispatchIO)
    case closing([CheckedContinuation<Void, Error>])
    case closed
  }

  internal let fileHandle: FileHandle
  fileprivate let state = Mutex<State>(.closed)

  /// Initialize the stream from a file handle.
  ///
  /// - Parameter fileHandle: Handle of the file to operate on.
  ///
  public required init(fileHandle: FileHandle) {

    self.fileHandle = fileHandle
    self.state.withLock { $0 = .open(createDispatchIO()) }
  }

  fileprivate var dispatchIO: DispatchIO {
    get throws {
      try state.withLock { state in
        guard case .open(let dispatchIO) = state else {
          throw IOError.streamClosed
        }
        return dispatchIO
      }
    }
  }

  fileprivate func cancel() {
    state.withLock { state in
      guard case .open(let dispatchIO) = state else {
        return
      }
      // Cancel current dispatches
      dispatchIO.close(flags: .stop)
      state = .open(createDispatchIO())
    }
  }

  fileprivate func createDispatchIO() -> DispatchIO {

    let dispatchIO =
      DispatchIO(type: .stream, fileDescriptor: fileHandle.fileDescriptor, queue: .global(qos: .utility)) { error in
        self.state.withLock { state in
          guard case .closing(let waiting) = state else {
            return
          }

          let result: Result<Void, Error> =
            if error != 0 {
              .failure(POSIXError(.init(rawValue: error) ?? .EIO))
            } else {
              .success(())
            }

          for waiter in waiting {
            waiter.resume(with: result)
          }

          state = .closed
        }
      }

    // Ensure handlers are called frequently to allow timely cancellation
    dispatchIO.setLimit(lowWater: Self.progressReportLimits.lowWaterMark)
    dispatchIO.setLimit(highWater: Self.progressReportLimits.highWaterMark)
    dispatchIO.setInterval(interval: Self.progressReportLimits.maxInterval, flags: [])
    return dispatchIO
  }

  public func close() async throws {
    try await withCheckedThrowingContinuation { continuation in

      state.withLock { state in
        switch state {

        case .open(let dispatchIO):
          state = .closing([continuation])
          dispatchIO.close(flags: [.stop])

        case .closing(let waiting):
          state = .closing(waiting + [continuation])

        case .closed:
          continuation.resume()
        }
      }
    }
  }

}


private extension DispatchQueue {

  static var taskPriorityQueue: DispatchQueue {

    let qos: DispatchQoS.QoSClass
    switch Task.currentPriority {
    case .userInitiated, .high:
      qos = .userInitiated
    case .utility:
      qos = .utility
    case .background, .low:
      qos = .background
    default:
      qos = .default
    }

    return DispatchQueue.global(qos: qos)
  }

}
