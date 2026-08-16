//
//  IncrementalFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation

/// The state of an incremental filtering operation after processing input.
public enum IncrementalFilterProgress: Equatable, Sendable {

  /// The filter can accept more input.
  case needsInput

  /// The filter reached its end-of-data marker.
  case finished

}

/// The result of one incremental filtering operation.
public struct IncrementalFilterResult: Sendable {

  /// Output produced while consuming the input.
  public let output: Data

  /// Number of bytes consumed from the supplied input.
  public let consumedInput: Int

  /// The filter's state after processing the input.
  public let progress: IncrementalFilterProgress

  /// Creates an incremental filtering result.
  ///
  /// - Parameters:
  ///   - output: Output produced while consuming the input.
  ///   - consumedInput: Number of bytes consumed from the supplied input.
  ///   - progress: The filter's state after processing the input.
  public init(output: Data, consumedInput: Int, progress: IncrementalFilterProgress) {
    self.output = output
    self.consumedInput = consumedInput
    self.progress = progress
  }

}

/// A synchronous filter that reports input consumption and end-of-data.
///
/// Incremental filters are suitable for framed formats in which bytes after an
/// end marker belong to a surrounding stream. Implementations must not consume
/// those trailing bytes.
public protocol IncrementalFilter: Filter, Sendable {

  /// Processes as much of `input` as the filter can consume.
  ///
  /// `consumedInput` must identify the exact prefix incorporated into the
  /// filter state. A decoder that reaches end-of-data must report `.finished`
  /// without inspecting a byte following the end marker, leaving every
  /// unconsumed byte available to the surrounding stream.
  ///
  /// - Parameter input: The next input bytes.
  /// - Returns: Produced output, input consumption, and end-of-data state.
  func process(input: Data) throws -> IncrementalFilterResult

  /// Emits currently available output without ending the stream.
  ///
  /// - Returns: Output made available by the flush operation.
  func flush() throws -> Data

  /// Finishes the filtering process and emits its final output.
  ///
  /// - Returns: Remaining output, or `nil` after a prior finish.
  func finish() throws -> Data?

}

public extension IncrementalFilter {

  /// Processes one buffer through the incremental interface.
  ///
  /// This adapter preserves the existing ``Filter`` API. Bytes following a
  /// filter end marker are intentionally not processed.
  ///
  /// - Parameter data: Data to filter.
  /// - Returns: Data produced from the supplied input.
  func process(data: Data) throws -> Data {
    var remaining = data
    var output = Data()

    while !remaining.isEmpty {
      let result = try process(input: remaining)
      precondition(result.consumedInput >= 0 && result.consumedInput <= remaining.count)
      output.append(result.output)

      if result.progress == .finished || result.consumedInput == 0 {
        break
      }

      remaining.removeFirst(result.consumedInput)
    }

    return output
  }

  /// Returns no output for filters that do not buffer flushable data.
  func flush() throws -> Data {
    Data()
  }

}
