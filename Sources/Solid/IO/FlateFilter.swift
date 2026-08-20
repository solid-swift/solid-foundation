//
//  FlateFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import CZlib
import Foundation
import Synchronization

/// Options shared by PostScript Flate encoding and decoding.
public struct FlateOptions: Equatable, Sendable {

  /// Compression effort from 0 through 9, or -1 for the zlib default.
  public var effort: Int

  /// Predictor applied before compression and after decompression.
  public var predictor: PredictorOptions

  /// Creates Flate options.
  public init(effort: Int = -1, predictor: PredictorOptions = try! PredictorOptions()) throws {
    guard (-1...9).contains(effort) else {
      throw StreamCodecError.invalidOption("effort")
    }
    self.effort = effort
    self.predictor = predictor
  }

}

/// An incremental zlib/Deflate encoder.
public final class FlateEncoder: IncrementalFilter {

  private struct State: Sendable {
    var predictor: IncrementalPredictorEncoder
    var encoder: ZlibStreamEncoder?
    var finished = false
  }

  private let options: FlateOptions
  private let state: Mutex<State>

  /// Creates a Flate encoder.
  public init(options: FlateOptions = try! FlateOptions()) {
    self.options = options
    state = Mutex(State(predictor: IncrementalPredictorEncoder(options: options.predictor)))
  }

  /// Buffers input for prediction and final compression.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      if state.encoder == nil { state.encoder = try ZlibStreamEncoder(compressionLevel: options.effort) }
      let predicted = try state.predictor.process(input)
      let output = try state.encoder!.process(predicted)
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
      let predicted = try state.predictor.finish()
      var output = try state.encoder!.process(predicted)
      output.append(try state.encoder!.finish() ?? Data())
      return output
    }
  }

}

/// An incremental zlib/Deflate decoder that preserves trailing source bytes.
public final class FlateDecoder: IncrementalFilter {

  private struct State: Sendable {
    var predictor: IncrementalPredictorDecoder
    var decoder: ZlibStreamDecoder?
    var finished = false
  }

  private let options: FlateOptions
  private let state: Mutex<State>

  /// Creates a Flate decoder.
  public init(options: FlateOptions = try! FlateOptions()) {
    self.options = options
    state = Mutex(State(predictor: IncrementalPredictorDecoder(options: options.predictor)))
  }

  /// Decodes when the accumulated input contains a complete zlib stream.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }

      if state.decoder == nil { state.decoder = try ZlibStreamDecoder() }
      let decoded = try state.decoder!.process(input)
      var output = try state.predictor.process(decoded.output)
      if decoded.finished {
        output.append(try state.predictor.finish())
        state.finished = true
      }
      return IncrementalFilterResult(
        output: output,
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
      return try state.predictor.finish()
    }
  }

}

private enum ZlibCodec {

  static func encode(_ input: Data, effort: Int) throws -> Data {
    var stream = z_stream()
    let initialization = deflateInit2_(
      &stream,
      Int32(effort),
      Z_DEFLATED,
      MAX_WBITS,
      8,
      Z_DEFAULT_STRATEGY,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initialization == Z_OK else { throw StreamCodecError.unsupportedOperation }
    defer { deflateEnd(&stream) }

    return try input.withUnsafeBytes { inputBuffer in
      stream.next_in = UnsafeMutablePointer(
        mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
      )
      stream.avail_in = uInt(inputBuffer.count)
      var output = Data()
      var status = Z_OK

      repeat {
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        let produced = buffer.withUnsafeMutableBytes { outputBuffer in
          stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(outputBuffer.count)
          status = deflate(&stream, Z_FINISH)
          return outputBuffer.count - Int(stream.avail_out)
        }
        output.append(contentsOf: buffer.prefix(produced))
      } while status == Z_OK

      guard status == Z_STREAM_END else { throw StreamCodecError.invalidData }
      return output
    }
  }

  static func decode(
    _ input: Data,
    final: Bool
  ) throws -> (output: Data, consumedBytes: Int)? {
    var stream = z_stream()
    let initialization = inflateInit2_(
      &stream,
      MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initialization == Z_OK else { throw StreamCodecError.unsupportedOperation }
    defer { inflateEnd(&stream) }

    return try input.withUnsafeBytes { inputBuffer in
      stream.next_in = UnsafeMutablePointer(
        mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
      )
      stream.avail_in = uInt(inputBuffer.count)
      var output = Data()

      while true {
        let priorInput = stream.avail_in
        var status = Z_OK
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        let produced = buffer.withUnsafeMutableBytes { outputBuffer in
          stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(outputBuffer.count)
          status = inflate(&stream, final ? Z_FINISH : Z_NO_FLUSH)
          return outputBuffer.count - Int(stream.avail_out)
        }
        output.append(contentsOf: buffer.prefix(produced))

        if status == Z_STREAM_END {
          return (output, Int(stream.total_in))
        }
        if status == Z_DATA_ERROR || status == Z_NEED_DICT {
          throw StreamCodecError.invalidData
        }
        if status == Z_MEM_ERROR || status == Z_STREAM_ERROR {
          throw StreamCodecError.unsupportedOperation
        }
        if final && (status == Z_BUF_ERROR || stream.avail_in == 0) {
          throw StreamCodecError.truncatedData
        }
        if produced == 0 && stream.avail_in == priorInput {
          return nil
        }
        if stream.avail_in == 0 && produced == 0 {
          return nil
        }
      }
    }
  }

}
