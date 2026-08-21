//
//  FlateFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

/// Options shared by Flate encoding and decoding.
public struct FlateOptions: Equatable, Sendable {

  /// Compression effort from 0 through 9, or -1 for the zlib default.
  public var effort: Int

  /// Creates Flate options.
  public init(effort: Int = -1) throws {
    guard (-1...9).contains(effort) else {
      throw StreamCodecError.invalidOption("effort")
    }
    self.effort = effort
  }

}

/// An incremental zlib/Deflate encoder.
public final class FlateEncoder: IncrementalFilter {

  private struct State: Sendable {
    var encoder: ZlibStreamEncoder?
    var finished = false
  }

  private let options: FlateOptions
  private let state: Mutex<State>

  /// Creates a Flate encoder.
  public init(options: FlateOptions = try! FlateOptions()) {
    self.options = options
    state = Mutex(State())
  }

  /// Buffers input for prediction and final compression.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      if state.encoder == nil { state.encoder = try ZlibStreamEncoder(compressionLevel: options.effort) }
      let output = try state.encoder!.process(input)
      return IncrementalFilterResult(
        output: output,
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Compresses all buffered input and emits the zlib end marker.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      if state.encoder == nil { state.encoder = try ZlibStreamEncoder(compressionLevel: options.effort) }
      return try state.encoder!.finish()
    }
  }

}

/// An incremental zlib/Deflate decoder that preserves trailing source bytes.
public final class FlateDecoder: IncrementalFilter {

  private struct State: Sendable {
    var decoder: ZlibStreamDecoder?
    var finished = false
  }

  private let options: FlateOptions
  private let state: Mutex<State>

  /// Creates a Flate decoder.
  public init(options: FlateOptions = try! FlateOptions()) {
    self.options = options
    state = Mutex(State())
  }

  /// Decodes when the accumulated input contains a complete zlib stream.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }

      if state.decoder == nil { state.decoder = try ZlibStreamDecoder() }
      let decoded = try state.decoder!.process(input)
      if decoded.finished {
        state.finished = true
      }
      return IncrementalFilterResult(
        output: decoded.output,
        consumedInput: decoded.consumedInput,
        progress: decoded.finished ? .finished : .needsInput
      )
    }
  }

  /// Rejects a truncated zlib stream at the physical source end.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      guard let decoder = state.decoder else { throw StreamCodecError.truncatedData }
      try decoder.finish()
      state.finished = true
      return nil
    }
  }

}
