//
//  FormatStreamWriterAdapter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/15/26.
//

import Foundation
import SolidIO

/// A generic ``FormatStreamWriter`` that wraps a ``FormatStreamWriterDriver``,
/// providing the common `write`/`finish`/`close` lifecycle with customizable
/// error handling.
///
/// Each format module provides a typealias and convenience initializer
/// rather than duplicating the driver integration logic.
public final class FormatStreamWriterAdapter<Encoder: FormatStreamEncoder>: FormatStreamWriter {

  private var driver: FormatStreamWriterDriver<Encoder>
  private var finished = false
  private let alreadyFinishedError: @Sendable () -> any Swift.Error
  private let mapError: @Sendable (any Swift.Error) -> any Swift.Error

  public init(
    encoder: Encoder,
    sink: any Sink,
    bufferSize: Int = BufferedSink.segmentSize,
    alreadyFinishedError: @escaping @Sendable () -> any Swift.Error,
    mapError: @escaping @Sendable (any Swift.Error) -> any Swift.Error = { $0 }
  ) {
    self.driver = FormatStreamWriterDriver(
      encoder: encoder,
      sink: sink,
      bufferSize: bufferSize
    )
    self.alreadyFinishedError = alreadyFinishedError
    self.mapError = mapError
  }

  public var format: Format { driver.format }

  public func write(_ event: EmitEvent) async throws {
    guard !finished else { throw alreadyFinishedError() }
    do {
      try await driver.write(event)
    } catch {
      throw mapError(error)
    }
  }

  public func write(
    _ produceEvents: (_ emit: (EmitEvent) async throws -> Void) async throws -> Void
  ) async throws {
    guard !finished else { throw alreadyFinishedError() }
    do {
      try await driver.write(produceEvents)
    } catch {
      throw mapError(error)
    }
  }

  public func finish() async throws {
    guard !finished else { throw alreadyFinishedError() }
    do {
      try await driver.finish()
    } catch {
      throw mapError(error)
    }
    finished = true
  }

  public func close() async throws {
    if !finished {
      try await finish()
    }
    try await driver.close()
  }
}
