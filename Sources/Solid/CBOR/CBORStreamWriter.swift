//
//  CBORStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import Foundation
import SolidData
import SolidIO

/// Async CBOR stream writer that consumes ``EmitEvent`` values.
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

  private let adapter: FormatStreamWriterAdapter<CBORStreamEncoder>

  public init(sink: any Sink, options: Options = .default, bufferSize: Int = BufferedSink.segmentSize) {
    self.adapter = FormatStreamWriterAdapter(
      encoder: CBORStreamEncoder(
        writer: CBOREncoder(
          options: .init(deterministic: false, deterministicMode: options.deterministicMode)
        )
      ),
      sink: sink,
      bufferSize: bufferSize,
      alreadyFinishedError: { Error.alreadyFinished },
      mapError: { error in
        if let cborError = error as? CBOREncoder.Error {
          return Error.from(cborError)
        }
        return error
      }
    )
  }

  public var format: Format { adapter.format }

  public func write(_ event: EmitEvent) async throws {
    try await adapter.write(event)
  }

  public func finish() async throws {
    try await adapter.finish()
  }

  public func close() async throws {
    try await adapter.close()
  }
}
