//
//  NWConnectionSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/31/25.
//

import Foundation
import Network
import SolidCore


public final class NWConnectionSource: NWConnectionStream, Source, @unchecked Sendable {

  @AtomicCounter public var bytesRead: Int

  private func process<DataType: DataProtocol>(_ response: NWConnection.ReceiveResponse<DataType>) throws -> DataType? {
    let (data, context, isComplete) = response
    if isComplete {
      streamCompleted()
    }
    if let data {
      _bytesRead.add(data.count)
    }
    return data
  }

  public func read(next: Int) async throws -> Data? {
    guard let connection else { throw IOError.streamClosed }
    guard !isCompleted else { throw IOError.endOfStream }

    let response = try await connection.receive(minimumIncompleteLength: next, maximumLength: next)
    return try process(response)
  }

  public func read(max: Int) async throws -> Data? {
    guard let connection else { throw IOError.streamClosed }
    guard !isCompleted else { throw IOError.endOfStream }

    let response = try await connection.receive(minimumIncompleteLength: 0, maximumLength: max)
    return try process(response)
  }

  public func read(exactly count: Int) async throws -> Data {
    guard let connection else { throw IOError.streamClosed }
    guard !isCompleted else { throw IOError.endOfStream }

    let response = try await connection.receive(minimumIncompleteLength: count, maximumLength: count)
    guard let data = try process(response), data.count == count else {
      throw IOError.endOfStream
    }

    return data
  }

}
