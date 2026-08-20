/// A uniquely owned streaming baseline JPEG encoder.
public struct JPEGEncoder: ~Copyable {

  private enum State {
    case collecting
    case abandoned
    case finished
  }

  private let options: JPEGEncodingOptions
  private var samples: [UInt8] = []
  private var state = State.collecting

  /// Creates an encoder with validated options.
  public init(options: JPEGEncodingOptions) {
    self.options = options
    samples.reserveCapacity(options.sampleCount)
  }

  /// Consumes an interleaved raw-component sample span.
  public mutating func process(_ input: borrowing Span<UInt8>) throws -> JPEGEncodingResult {
    guard case .collecting = state else { throw stateError }
    guard input.count <= options.sampleCount - samples.count else {
      throw JPEGError.invalidData
    }
    for index in 0..<input.count { samples.append(input[index]) }
    return JPEGEncodingResult(
      bytes: [],
      consumedSamples: input.count,
      progress: .needsInput
    )
  }

  /// Finishes encoding and consumes the session.
  public consuming func finish() throws -> [UInt8] {
    guard case .collecting = state else { throw stateError }
    guard samples.count == options.sampleCount else { throw JPEGError.truncatedData }
    return try NativeJPEGCodec.encode(samples: samples, options: options)
  }

  /// Abandons buffered state without producing output.
  public mutating func abandon() {
    samples.removeAll(keepingCapacity: false)
    state = .abandoned
  }

  private var stateError: JPEGError {
    switch state {
    case .collecting: .invalidData
    case .abandoned: .abandoned
    case .finished: .finished
    }
  }

}
