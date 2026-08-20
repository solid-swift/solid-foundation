/// A uniquely owned streaming baseline JPEG decoder.
public struct JPEGDecoder: ~Copyable {

  private enum State {
    case collecting
    case abandoned
    case finished
  }

  private let options: JPEGDecodingOptions
  private var streamingState: NativeJPEGStreamingDecoder
  private var state = State.collecting

  /// Creates a decoder with validated options.
  public init(options: JPEGDecodingOptions = try! JPEGDecodingOptions()) {
    self.options = options
    streamingState = NativeJPEGStreamingDecoder(options: options)
  }

  /// Consumes encoded JPEG bytes and emits any complete row bands.
  public mutating func process(_ input: borrowing Span<UInt8>) throws -> JPEGDecodingResult {
    guard case .collecting = state else { throw stateError }
    let result = try streamingState.process(input)
    if result.progress == .finished {
      state = .finished
    }
    return result
  }

  /// Finishes decoding and consumes the session.
  public consuming func finish() throws -> JPEGDecodingResult {
    try finalize()
  }

  package mutating func finalize() throws -> JPEGDecodingResult {
    switch state {
    case .collecting:
      let result = try streamingState.finish()
      state = .finished
      return result
    case .finished:
      return JPEGDecodingResult(
        metadata: nil,
        rows: [],
        consumedBytes: 0,
        progress: .finished
      )
    case .abandoned:
      throw JPEGError.abandoned
    }
  }

  /// Abandons buffered state without producing output.
  public mutating func abandon() {
    state = .abandoned
  }

  var scratchHighWaterMark: Int { streamingState.scratchHighWaterMark }

  private var stateError: JPEGError {
    switch state {
    case .collecting: .invalidData
    case .abandoned: .abandoned
    case .finished: .finished
    }
  }

}
