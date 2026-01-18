//
//  SwiftCompression.swift
//  SwiftCompression
//
//  A cross-platform compression shim that passes through Apple's Compression
//  framework on Apple platforms and provides SWCompression-backed implementations
//  on Linux and other platforms.
//

#if canImport(Compression)
  // On Apple platforms, re-export the Compression framework
  @_exported import Compression
#else
  // On non-Apple platforms, provide our own implementation backed by SWCompression
  import Foundation
  import SWCompression

  // MARK: - Algorithm

  /// Compression algorithm to use for compression/decompression operations.
  public enum Algorithm: CaseIterable, Sendable {

    /// The LZ4 compression algorithm for fast compression.
    case lz4

    /// The LZ4 compression algorithm, without frame headers.
    case lz4Raw

    /// The LZMA compression algorithm, which is recommended for high-compression ratio.
    ///
    /// - Note: On non-Apple platforms, LZMA only supports decompression.
    ///   Compression operations will throw an error.
    case lzma

    /// The zlib compression algorithm, which is recommended for cross-platform compression.
    case zlib

    /// The LZFSE compression algorithm, which is recommended for use on Apple platforms.
    ///
    /// - Note: LZFSE is not available on non-Apple platforms.
    @available(*, unavailable, message: "LZFSE is only available on Apple platforms")
    case lzfse

    /// The Brotli compression algorithm, which is recommended for text compression.
    ///
    /// - Note: Brotli compression is not available on non-Apple platforms via SWCompression.
    @available(*, unavailable, message: "Brotli is only available on Apple platforms")
    case brotli

    /// The LZBITMAP compression algorithm, which is designed to exploit the
    /// vector instruction set of current CPUs.
    ///
    /// - Note: LZBITMAP is only available on Apple platforms.
    @available(*, unavailable, message: "LZBITMAP is only available on Apple platforms")
    case lzbitmap

    public static var allCases: [Algorithm] {
      [.lz4, .lz4Raw, .lzma, .zlib]
    }
  }

  // MARK: - FilterOperation

  /// The operation to perform during compression filtering.
  public enum FilterOperation: Sendable {
    /// Compress the data.
    case compress
    /// Decompress the data.
    case decompress
  }

  // MARK: - FilterError

  /// Errors that can occur during compression/decompression operations.
  public enum FilterError: Error {
    /// The filter could not be initialized.
    case filterInitializationFailed
    /// The compression/decompression operation failed.
    case operationFailed
    /// The data is invalid or corrupted.
    case invalidData
    /// The algorithm does not support the requested operation on this platform.
    case unsupportedOperation(algorithm: Algorithm, operation: FilterOperation)
  }

  // MARK: - OutputFilter

  /// A filter that processes data through compression or decompression.
  ///
  /// This implementation uses SWCompression on non-Apple platforms to provide
  /// compression functionality compatible with Apple's Compression framework.
  public class OutputFilter {

    private let operation: FilterOperation
    private let algorithm: Algorithm
    private let writeHandler: (Data?) -> Void
    private var buffer: Data

    /// Creates an output filter for compression or decompression.
    ///
    /// - Parameters:
    ///   - operation: The operation to perform (compress or decompress).
    ///   - algorithm: The compression algorithm to use.
    ///   - writeHandler: A closure called with processed data chunks.
    /// - Throws: `FilterError.filterInitializationFailed` if the filter cannot be created,
    ///           or `FilterError.unsupportedOperation` if the algorithm doesn't support
    ///           the requested operation on this platform.
    public init(
      _ operation: FilterOperation,
      using algorithm: Algorithm,
      writingTo writeHandler: @escaping (Data?) -> Void
    ) throws {
      // Check for unsupported operations
      if algorithm == .lzma && operation == .compress {
        throw FilterError.unsupportedOperation(algorithm: algorithm, operation: operation)
      }

      self.operation = operation
      self.algorithm = algorithm
      self.writeHandler = writeHandler
      self.buffer = Data()
    }

    /// Writes data to the filter for processing.
    ///
    /// - Parameter data: The data to process. Pass `nil` to signal end of input.
    /// - Throws: `FilterError.operationFailed` if the operation fails.
    public func write(_ data: Data?) throws {
      guard let data else {
        // End of input signal - process any remaining buffered data
        return
      }
      buffer.append(data)
    }

    /// Finalizes the filter and flushes any remaining data.
    ///
    /// - Throws: `FilterError.operationFailed` if finalization fails.
    public func finalize() throws {
      guard !buffer.isEmpty else {
        writeHandler(nil)
        return
      }

      let processedData: Data
      do {
        switch operation {
        case .compress:
          processedData = try compress(data: buffer, algorithm: algorithm)
        case .decompress:
          processedData = try decompress(data: buffer, algorithm: algorithm)
        }
      } catch let error as FilterError {
        throw error
      } catch {
        throw FilterError.operationFailed
      }

      writeHandler(processedData)
      writeHandler(nil)
      buffer = Data()
    }

    // MARK: - Private Compression Methods

    private func compress(data: Data, algorithm: Algorithm) throws -> Data {
      switch algorithm {
      case .lz4, .lz4Raw:
        return LZ4.compress(data: data)
      case .lzma:
        // LZMA compression is not supported by SWCompression
        throw FilterError.unsupportedOperation(algorithm: algorithm, operation: .compress)
      case .zlib:
        return ZlibArchive.archive(data: data)
      case .lzfse, .brotli, .lzbitmap:
        // These should never be reached due to @available markers
        throw FilterError.operationFailed
      }
    }

    private func decompress(data: Data, algorithm: Algorithm) throws -> Data {
      switch algorithm {
      case .lz4, .lz4Raw:
        return try LZ4.decompress(data: data)
      case .lzma:
        return try LZMA.decompress(data: data)
      case .zlib:
        return try ZlibArchive.unarchive(archive: data)
      case .lzfse, .brotli, .lzbitmap:
        // These should never be reached due to @available markers
        throw FilterError.operationFailed
      }
    }
  }

#endif
