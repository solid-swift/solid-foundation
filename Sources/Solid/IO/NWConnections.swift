//
//  NWConnection.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import Foundation
import Network


public extension NWConnection {

  func send(
    _ content: (some DataProtocol)?,
    contentContext: ContentContext,
    isComplete: Bool = false,
  ) async throws {
    try await withCheckedThrowingContinuation { continuation in
      let completion: NWConnection.SendCompletion = .contentProcessed { error in
        continuation.resume(with: error.map(Result.failure) ?? .success(()))
      }
      send(content: content, contentContext: contentContext, isComplete: isComplete, completion: completion)
    }
  }

  func sendIdempotent(_ content: (some DataProtocol)?, contentContext: ContentContext, isComplete: Bool = false) {
    send(content: content, contentContext: contentContext, isComplete: isComplete, completion: .idempotent)
  }

  typealias ReceiveResponse<DataType: DataProtocol> =
    (content: DataType?, contentContext: ContentContext?, isComplete: Bool)

  private typealias ReceiveCompletion<DataType: DataProtocol> =
    @Sendable (DataType?, ContentContext?, Bool, Error?) -> Void

  func receive(minimumIncompleteLength minLen: Int, maximumLength maxLen: Int) async throws -> ReceiveResponse<Data> {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ReceiveResponse, Error>) -> Void in
      let completion: ReceiveCompletion<Data> = { content, contentContext, isComplete, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: (content, contentContext, isComplete))
        }
      }
      receive(minimumIncompleteLength: minLen, maximumLength: maxLen, completion: completion)
    }
  }

  func receiveDiscontiguous(
    minimumIncompleteLength minLen: Int,
    maximumLength maxLen: Int
  ) async throws -> ReceiveResponse<DispatchData> {
    try await withCheckedThrowingContinuation { continuation in
      let completion: ReceiveCompletion<DispatchData> = { content, contentContext, isComplete, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: (content, contentContext, isComplete))
        }
      }
      receiveDiscontiguous(minimumIncompleteLength: minLen, maximumLength: maxLen, completion: completion)
    }
  }

  func receiveMessage() async throws -> ReceiveResponse<Data> {
    try await withCheckedThrowingContinuation { continuation in
      receiveMessage { content, contentContext, isComplete, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: (content, contentContext, isComplete))
        }
      }
    }
  }

}
