import CZlib
import Foundation

final class ZlibStreamDecoder: @unchecked Sendable {
  struct Result {
    let output: Data
    let consumedInput: Int
    let finished: Bool
  }

  private var stream = z_stream()
  private var isFinished = false
  private var isEnded = false

  init() throws {
    let status = inflateInit2_(
      &stream,
      MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard status == Z_OK else { throw StreamCodecError.unsupportedOperation }
  }

  deinit {
    if !isEnded { inflateEnd(&stream) }
  }

  func process(_ input: Data) throws -> Result {
    guard !isFinished else { return Result(output: Data(), consumedInput: 0, finished: true) }
    return try input.withUnsafeBytes { inputBuffer in
      let bytes = inputBuffer.bindMemory(to: Bytef.self)
      stream.next_in = UnsafeMutablePointer(mutating: bytes.baseAddress)
      stream.avail_in = uInt(bytes.count)
      var output = Data()
      var status = Z_OK
      repeat {
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        let produced = buffer.withUnsafeMutableBytes { outputBuffer in
          stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(outputBuffer.count)
          status = inflate(&stream, Z_NO_FLUSH)
          return outputBuffer.count - Int(stream.avail_out)
        }
        output.append(contentsOf: buffer.prefix(produced))
        if status == Z_STREAM_END {
          isFinished = true
          inflateEnd(&stream)
          isEnded = true
          break
        }
        if status == Z_DATA_ERROR || status == Z_NEED_DICT { throw StreamCodecError.invalidData }
        if status == Z_MEM_ERROR || status == Z_STREAM_ERROR {
          throw StreamCodecError.unsupportedOperation
        }
        if status == Z_BUF_ERROR || (stream.avail_in == 0 && produced == 0) { break }
      } while stream.avail_in > 0 || stream.avail_out == 0
      return Result(
        output: output,
        consumedInput: input.count - Int(stream.avail_in),
        finished: isFinished
      )
    }
  }

  func finish() throws {
    guard isFinished else { throw StreamCodecError.truncatedData }
  }
}
