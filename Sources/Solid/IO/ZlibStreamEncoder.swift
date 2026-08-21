import CZlib
import Foundation
import Synchronization

/// An incremental encoder for an RFC 1950 zlib stream.
public final class ZlibStreamEncoder: Sendable {
  private struct State: @unchecked Sendable {
    var stream: z_stream
    var finished: Bool
    var ended: Bool
  }

  private static let outputBufferSize = 32 * 1024

  private let state: Mutex<State>

  /// Creates an encoder with a compression level from zero through nine, or `-1` for zlib's default.
  public init(compressionLevel: Int = -1) throws {
    guard (-1...9).contains(compressionLevel) else {
      throw StreamCodecError.invalidOption("compressionLevel")
    }
    state = Mutex(State(stream: z_stream(), finished: false, ended: false))
    let status = state.withLock { state in
      deflateInit2_(
        &state.stream,
        Int32(compressionLevel),
        Z_DEFLATED,
        MAX_WBITS,
        8,
        Z_DEFAULT_STRATEGY,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
      )
    }
    guard status == Z_OK else { throw StreamCodecError.unsupportedOperation }
  }

  deinit {
    state.withLock { state in
      guard !state.ended else { return }
      deflateEnd(&state.stream)
      state.ended = true
    }
  }

  /// Incorporates bytes into the stream and returns compressed bytes currently available.
  public func process(_ input: Data) throws -> Data {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      guard !input.isEmpty else { return Data() }
      return try Self.deflate(input, flush: Z_NO_FLUSH, state: &state)
    }
  }

  /// Makes buffered compressed bytes available without ending the stream.
  public func flush() throws -> Data {
    try state.withLock { state in
      guard !state.finished else { return Data() }
      return try Self.deflate(Data(), flush: Z_SYNC_FLUSH, state: &state)
    }
  }

  /// Ends the stream and returns its final compressed bytes, or `nil` after a prior finish.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      let output = try Self.deflate(Data(), flush: Z_FINISH, state: &state)
      deflateEnd(&state.stream)
      state.ended = true
      return output
    }
  }

  private static func deflate(
    _ input: Data,
    flush: Int32,
    state: inout State
  ) throws -> Data {
    try input.withUnsafeBytes { inputBuffer in
      let bytes = inputBuffer.bindMemory(to: Bytef.self)
      var offset = 0
      var output = Data()
      var status = Z_OK

      repeat {
        if state.stream.avail_in == 0, offset < bytes.count {
          let count = min(bytes.count - offset, Int(uInt.max))
          state.stream.next_in = UnsafeMutablePointer(mutating: bytes.baseAddress?.advanced(by: offset))
          state.stream.avail_in = uInt(count)
          offset += count
        }

        var buffer = [UInt8](repeating: 0, count: outputBufferSize)
        let produced = buffer.withUnsafeMutableBytes { outputBuffer in
          state.stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
          state.stream.avail_out = uInt(outputBuffer.count)
          status = CZlib.deflate(&state.stream, flush)
          return outputBuffer.count - Int(state.stream.avail_out)
        }
        output.append(contentsOf: buffer.prefix(produced))

        guard status == Z_OK || status == Z_STREAM_END || (flush == Z_SYNC_FLUSH && status == Z_BUF_ERROR)
        else { throw StreamCodecError.invalidData }

        if flush == Z_FINISH, status == Z_STREAM_END { break }
        if flush == Z_SYNC_FLUSH, state.stream.avail_out != 0 { break }
      } while state.stream.avail_in != 0 || offset < bytes.count || flush != Z_NO_FLUSH

      guard flush != Z_FINISH || status == Z_STREAM_END else {
        throw StreamCodecError.invalidData
      }
      return output
    }
  }
}
