//
//  NWConnectionSink.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/31/25.
//

import SolidCore
import Foundation
import Network


public final class NWConnectionSink: NWConnectionStream, Sink, @unchecked Sendable {

  @AtomicCounter public var bytesWritten: Int

  public func write(data: Data) async throws {
    guard let connection else { return }

    try await connection.send(data, contentContext: .defaultMessage, isComplete: false)

    _bytesWritten.add(data.count)
  }

}
