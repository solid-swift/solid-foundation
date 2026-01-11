//
//  NWConnectionGroups.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/31/25.
//

#if canImport(Network)
import Network
import ObjectiveC

public extension NWConnectionGroup {

  static func create(
    with groupDescriptor: any NWGroupDescriptor,
    using parameters: NWParameters,
    connectionBufferSize: Int = 1000
  ) -> (
    NWConnectionGroup,
    AsyncStream<NWConnectionGroup.State>,
    AsyncThrowingStream<NWConnection, Error>
  ) {

    let group = NWConnectionGroup(with: groupDescriptor, using: parameters)

    let (stateChangeStream, stateChangeContinuation) =
      AsyncStream.makeStream(
        of: NWConnectionGroup.State.self,
        bufferingPolicy: .bufferingNewest(connectionBufferSize)
      )

    let (newConnectionsStream, newConnectionsContinuation) =
      AsyncThrowingStream.makeStream(
        of: NWConnection.self,
        throwing: Error.self,
        bufferingPolicy: .bufferingNewest(connectionBufferSize)
      )

    group.newConnectionHandler = { newConnection in
      newConnectionsContinuation.yield(newConnection)
    }

    group.stateUpdateHandler = { state in
      stateChangeContinuation.yield(state)
      switch state {
      case .cancelled:
        newConnectionsContinuation.finish()
      case .failed(let error):
        newConnectionsContinuation.finish(throwing: error)
      default:
        break
      }
    }

    return (group, stateChangeStream, newConnectionsStream)
  }

  final class SolidState {

    let newConnectionsStream: AsyncThrowingStream<NWConnection, Error>

    init(newConnectionsStream: AsyncThrowingStream<NWConnection, Error>) {
      self.newConnectionsStream = newConnectionsStream
    }


    static let key = Int.random(in: 0..<Int.max)
  }

  private func associate(state: SolidState) {
    withUnsafePointer(to: SolidState.key) { keyPointer in
      objc_setAssociatedObject(self, keyPointer, state, .OBJC_ASSOCIATION_RETAIN)
    }
  }

  private var state: SolidState {
    let associated =
      withUnsafePointer(to: SolidState.key) { keyPointer in
        objc_getAssociatedObject(self, keyPointer)
      }
    guard let associated, let state = associated as? SolidState else {
      fatalError("No SolidState for NWConnectionGroup")
    }
    return state
  }

  func sink(to endpoint: NWEndpoint? = nil) throws(NWError) -> NWConnectionSink {

    guard let connection = self.extract(connectionTo: endpoint) else {
      throw NWError.posix(.ECONNREFUSED)
    }

    return NWConnectionSink(connection: connection, group: self)
  }

  func newConnections() -> some AsyncSequence<NWConnection, Error> {
    return state.newConnectionsStream
  }

}

#endif

