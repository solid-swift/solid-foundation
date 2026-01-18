//
//  CompressionFilter.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import Foundation
import SwiftCompression

/// Compressing or decompressing ``Sink``.
///
/// Compresses or decompresses the data according to
/// the operation the filter was initialized with.
///
public class CompressionFilter: Filter {

  private static let bufferSize = BufferedSink.segmentSize

  private var filter: OutputFilter?
  private var input: Data
  private var output: Data?

  /// Initializes the filter with the given `operation` and `algorithm`.
  ///
  /// - Parameters:
  ///   - operation: Operation to perform on the passed in data.
  ///   - algorithm: Compression algorithm to use.
  /// - Throws: ``FilterError`` if filter stream initialization fails.
  public init(operation: FilterOperation, algorithm: Algorithm) throws {
    input = Data(capacity: Self.bufferSize)
    filter = try OutputFilter(operation, using: algorithm) { [self] data in
      guard let data else { return }

      if output == nil {
        output = data
      } else {
        output?.append(data)
      }
    }
  }

  /// Apply the compression operation to the provided data.
  ///
  /// - Parameter data: Data to be compressed or decompressed.
  /// - Returns: Next amount of ready data that has been processed.
  /// - Throws: ``IOError`` if stream is closed.
  public func process(data: Data) throws -> Data {
    guard let filter else { throw IOError.streamClosed }

    input.append(data)

    while input.count >= Self.bufferSize {

      let range = 0..<Self.bufferSize

      try filter.write(input.subdata(in: range))

      input.removeSubrange(range)
    }

    defer { output = nil }

    return output ?? Data()
  }

  /// Finalize the compression operation.
  ///
  /// - Returns: Final data after the compression operation
  ///   has been finalized.
  ///
  public func finish() throws -> Data? {
    guard let filter else { return nil }

    try filter.write(input)

    try filter.finalize()

    defer { self.filter = nil }

    return output
  }

}

public extension Source {

  /// Applies a compression/decompression filter to this stream.
  ///
  /// - Parameters:
  ///   - algorithm: Algorithm to compress with.
  ///   - operation: Compression or decompression operation to perform.
  /// - Returns: Compression source stream reading from this stream.
  /// - Throws: ``IOError``if compression/decompression stream initialization fails.
  /// - SeeAlso: ``CompressionFilter``
  ///
  func applying(compression algorithm: Algorithm, operation: FilterOperation) throws -> Source {
    filtering(using: try CompressionFilter(operation: operation, algorithm: algorithm))
  }

  /// Applies a compression filter to this stream.
  ///
  /// - Parameters algorithm: Algorithm to compress with.
  /// - Returns: Compressed source stream reading from this stream.
  /// - Throws: ``IOError``if compression stream initialization fails.
  /// - SeeAlso: ``CompressionFilter``
  ///
  func compressing(algorithm: Algorithm) throws -> Source {
    try applying(compression: algorithm, operation: .compress)
  }

  /// Applies a decompression filter to this stream.
  ///
  /// - Parameters algorithm: Algorithm to decompress with.
  /// - Returns: Decompressed source stream reading from this stream.
  /// - Throws: ``IOError``if decompression stream initialization fails.
  /// - SeeAlso: ``CompressionFilter``
  ///
  func decompressing(algorithm: Algorithm) throws -> Source {
    try applying(compression: algorithm, operation: .decompress)
  }

}

public extension Sink {

  /// Applies a compression/decompression filter to this stream.
  ///
  /// - Parameters:
  ///   - algorithm: Algorithm to compress with.
  ///   - operation: Compression or decrompression operation to perform.
  /// - Returns: Compression sink stream writing to this stream.
  /// - Throws: ``IOError``if compression/decompression stream initialization fails.
  /// - SeeAlso: ``CompressionFilter``
  ///
  func applying(compression algorithm: Algorithm, operation: FilterOperation) throws -> Sink {
    filtering(using: try CompressionFilter(operation: operation, algorithm: algorithm))
  }

  /// Applies a compression filter to this stream.
  ///
  /// - Parameters algorithm: Algorithm to compress with.
  /// - Returns: Compressed sink stream writing to this stream.
  /// - Throws: ``IOError``if compression stream initialization fails.
  /// - SeeAlso: ``CompressionFilter``
  ///
  func compressing(algorithm: Algorithm) throws -> Sink {
    try applying(compression: algorithm, operation: .compress)
  }

  /// Applies a decompression filter to this stream.
  ///
  /// - Parameters algorithm: Algorithm to decompress with.
  /// - Returns: Decompressed sink stream writing to this stream.
  /// - Throws: ``IOError``if compression stream initialization fails.
  /// - SeeAlso: ``CompressionFilter``
  ///
  func decompressing(algorithm: Algorithm) throws -> Sink {
    try applying(compression: algorithm, operation: .decompress)
  }

}
