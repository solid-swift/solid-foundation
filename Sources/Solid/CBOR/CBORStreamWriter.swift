//
//  CBORStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation
import SolidData
import SolidIO

/// Async CBOR stream writer that consumes ``ValueEvent`` values.
public final class CBORStreamWriter: FormatStreamWriter {

  public enum DeterministicMode: Sendable, Equatable {
    case none
    case assumeSortedKeys
    case buffered(maxPairs: Int = 4096, maxBytes: Int = 8 * 1024 * 1024)
    case strict(maxPairs: Int = 4096, maxBytes: Int = 8 * 1024 * 1024)
  }

  public struct Options: Sendable {

    public static let `default` = Self()

    public var deterministicMode: DeterministicMode

    public init(deterministicMode: DeterministicMode = .none) {
      self.deterministicMode = deterministicMode
    }
  }

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteCBOR
    case alreadyFinished
    case invalidTagValue

    fileprivate static func from(_ error: CBOREncoder.Error) -> Self {
      switch error {
      case .invalidEventSequence(let message):
        return .invalidEventSequence(message)
      case .incompleteCBOR:
        return .incompleteCBOR
      case .alreadyFinished:
        return .alreadyFinished
      case .invalidTagValue:
        return .invalidTagValue
      }
    }
  }

  private var driver: FormatStreamWriterDriver<CBORStreamEncoder>
  private var finished = false

  public init(sink: any Sink, options: Options = .default, bufferSize: Int = BufferedSink.segmentSize) {
    self.driver = FormatStreamWriterDriver(
      encoder: CBORStreamEncoder(
        writer: CBOREncoder(
          options: .init(deterministic: false, deterministicMode: .init(options.deterministicMode))
        )
      ),
      sink: sink,
      bufferSize: bufferSize
    )
  }

  public var format: Format { CBOR.format }

  public func write(_ event: ValueEvent) async throws {
    guard !finished else { throw Error.alreadyFinished }
    do {
      try await driver.write(event)
    } catch let error as CBOREncoder.Error {
      throw Error.from(error)
    }
  }

  public func finish() async throws {
    guard !finished else { throw Error.alreadyFinished }
    do {
      try await driver.finish()
    } catch let error as CBOREncoder.Error {
      throw Error.from(error)
    }
    finished = true
  }

  public func close() async throws {
    try await finish()
    try await driver.close()
  }
}
