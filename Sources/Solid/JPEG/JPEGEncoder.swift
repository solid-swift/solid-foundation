/// A uniquely owned streaming baseline JPEG encoder.
public struct JPEGEncoder: ~Copyable {

  private enum State {
    case collecting
    case abandoned
    case finished
  }

  private let options: JPEGEncodingOptions
  private var streamingState: NativeJPEGEncoder.StreamingState?
  private var state = State.collecting

  /// Creates an encoder with validated options.
  public init(options: JPEGEncodingOptions) {
    self.options = options
  }

  /// Consumes an interleaved raw-component sample span.
  public mutating func process(_ input: borrowing Span<UInt8>) throws -> JPEGEncodingResult {
    guard case .collecting = state else { throw stateError }
    if streamingState == nil { streamingState = try NativeJPEGEncoder.StreamingState(options: options) }
    let bytes = try streamingState!.process(input)
    return JPEGEncodingResult(
      bytes: bytes,
      consumedSamples: input.count,
      progress: .needsInput
    )
  }

  /// Finishes encoding and consumes the session.
  public consuming func finish() throws -> [UInt8] {
    try finalize()
  }

  package mutating func finalize() throws -> [UInt8] {
    guard case .collecting = state else { throw stateError }
    if streamingState == nil { streamingState = try NativeJPEGEncoder.StreamingState(options: options) }
    let output = try streamingState!.finish()
    state = .finished
    return output
  }

  /// Abandons buffered state without producing output.
  public mutating func abandon() {
    streamingState = nil
    state = .abandoned
  }

  var scratchHighWaterMark: Int { streamingState?.scratchHighWaterMark ?? 0 }

  private var stateError: JPEGError {
    switch state {
    case .collecting: .invalidData
    case .abandoned: .abandoned
    case .finished: .finished
    }
  }

}
