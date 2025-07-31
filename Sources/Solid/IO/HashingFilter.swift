//
//  HashingResult.swift
//  SolidIO
//
//  Created by Kevin Wooten on 7/5/25.
//

import Crypto
import Foundation


/// Provides access to the result of a hashing filter, after
/// the stream that is using has been closed.
///
public protocol HashingResult {

  /// Computed digest result.
  ///
  /// - Note: The value is not valid until the
  /// stream that is using the related filter is
  /// closed.
  ///
  var digest: Data { get }

}

/// Filter that computes a hash of the processed data.
///
public class HashingFilter: Filter, HashingResult {

  /// Hash Algorithm.
  ///
  public enum Algorithm {

    /// Secure Hashing Algorithm 2 (SHA-2) hashing with a 512-bit digest.
    case sha512

    /// Secure Hashing Algorithm 2 (SHA-2) hashing with a 384-bit digest.
    case sha384

    /// Secure Hashing Algorithm 2 (SHA-2) hashing with a 256-bit digest.
    case sha256

    /// Secure Hashing Algorithm 1 (SHA-1) hashing with a 160-bit digest.
    ///
    /// - Warning: SHA-1 is considered insecure and should not be used
    /// for cryptographic operations.
    ///
    case sha1

    /// MD5 Hashing Algorithm.
    ///
    /// - Warning: MD5 is considered insecure and should not be used
    /// for cryptographic operations.
    ///
    case md5
  }

  private struct HashingDigester<HF: HashFunction>: Digester {

    var hashFunction: HF

    mutating func update(data: some DataProtocol) { hashFunction.update(data: data) }
    func finalize() -> Data { Data(hashFunction.finalize()) }

  }

  private var hasher: Digester

  /// Calculated hash digest.
  ///
  /// - Note: Available after calling the ``finish()``, which
  /// is called when ``FilterSink/close()`` or ``FilterSource/close()``.
  ///
  public private(set) var digest = Data()

  /// Initialize the instance to use the algorithm provided by
  /// `algorithm`.
  ///
  /// - Parameter algorithm: Hashing algorithm used to compute ``digest``.
  ///
  public init(algorithm: Algorithm) {
    switch algorithm {
    case .md5:
      hasher = HashingDigester(hashFunction: Insecure.MD5())
    case .sha1:
      hasher = HashingDigester(hashFunction: Insecure.SHA1())
    case .sha256:
      hasher = HashingDigester(hashFunction: SHA256())
    case .sha384:
      hasher = HashingDigester(hashFunction: SHA384())
    case .sha512:
      hasher = HashingDigester(hashFunction: SHA512())
    }
  }

  internal init<HF: HashFunction>(_ hashFunction: HF) {
    hasher = HashingDigester(hashFunction: hashFunction)
  }

  /// Updates the hash calculation and returns the
  /// data provided in `data`.
  ///
  /// - Parameter data: Data to upate the hash calculation with.
  /// - Returns: Available hashed data after applying the filter's hash algorithm.
  ///
  public func process(data: Data) -> Data {

    hasher.update(data: data)

    return data
  }

  /// Finishes the hash calculation and saves the
  /// result in the ``digest`` property.
  ///
  public func finish() async throws -> Data? {

    digest = hasher.finalize()

    return nil
  }

}

public extension Source {

  /// Applies a hashing filter to this stream.
  ///
  /// - Parameters algorithm: Hashing algorithm to calculate.
  /// - Returns: Hashing source stream reading from this stream and an
  ///   result object that provides access to the calculated digest.
  /// - SeeAlso: ``HashingFilter``
  ///
  func hashing(algorithm: HashingFilter.Algorithm) -> (Source, HashingResult) {
    let filter = HashingFilter(algorithm: algorithm)
    return (filtering(using: filter), filter)
  }

}

public extension Sink {

  /// Applies a hashing filter to this stream.
  ///
  /// - Parameters algorithm: Hashing algorithm to calculate.
  /// - Returns: Hashing sink stream writing to this stream and an
  ///   result object that provides access to the calculated digest.
  /// - SeeAlso: ``HashingFilter``
  ///
  func hashing(algorithm: HashingFilter.Algorithm) -> (Sink, HashingResult) {
    let filter = HashingFilter(algorithm: algorithm)
    return (filtering(using: filter), filter)
  }

}
