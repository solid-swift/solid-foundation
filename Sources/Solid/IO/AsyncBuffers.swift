//
//  AsyncBuffers.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/4/25.
//

import Foundation


/// An ``Swift/AsyncSequence`` of ``Foundation/DataProtocol`` buffers.
///
public struct AsyncBuffers: AsyncSequence {

  public struct AsyncIterator: AsyncIteratorProtocol {

    let source: Source
    let readSize: Int
    let required: Bool

    public func next() async throws -> Data? {
      guard required else {
        return try await source.read(max: readSize)
      }
      return try await source.read(next: readSize)
    }

  }

  private let source: Source
  private var readSize: Int
  private var required: Bool

  public init(source: Source, maxReadSize: Int) {
    self.source = source
    self.readSize = maxReadSize
    self.required = false
  }

  public init(source: Source, requiredReadSize: Int) {
    self.source = source
    self.readSize = requiredReadSize
    self.required = true
  }

  public func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator(source: source, readSize: readSize, required: required)
  }

}
