//
//  NWConnectionStream.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import SolidCore
import Network

public class NWConnectionStream: Stream, Flushable, @unchecked Sendable {

  public let group: NWConnectionGroup?
  @AtomicOptionalReference public var connection: NWConnection?
  @AtomicFlag package var isCompleted: Bool

  public init(connection: NWConnection, group: NWConnectionGroup? = nil) {
    self.group = group
    self._connection = AtomicOptionalReference(value: connection)
  }

  package func streamCompleted() {
    _isCompleted.signal()
  }

  public func flush() async throws {
    guard let connection else {
      return
    }
    try await connection.send(nil as DispatchData?, contentContext: .defaultMessage, isComplete: false)
  }

  public func close() async throws {
    guard let connection = _connection.nilify() else { return }

    try await connection.send(nil as DispatchData?, contentContext: .finalMessage, isComplete: true)

    if let group {
      if group.reinsert(connection: connection) {
        return
      }
    }

    connection.cancel()
  }

}
