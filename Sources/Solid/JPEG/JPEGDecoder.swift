/// A uniquely owned streaming baseline JPEG decoder.
public struct JPEGDecoder: ~Copyable {

  private enum State {
    case collecting
    case abandoned
    case finished
  }

  private let options: JPEGDecodingOptions
  private var bytes: [UInt8] = []
  private var state = State.collecting

  /// Creates a decoder with validated options.
  public init(options: JPEGDecodingOptions = try! JPEGDecodingOptions()) {
    self.options = options
  }

  /// Consumes encoded JPEG bytes and emits any complete row bands.
  public mutating func process(_ input: borrowing Span<UInt8>) throws -> JPEGDecodingResult {
    guard case .collecting = state else { throw stateError }
    guard input.count <= options.limits.maximumInputBytes - bytes.count else {
      throw JPEGError.limitExceeded
    }
    for index in 0..<input.count { bytes.append(input[index]) }
    return JPEGDecodingResult(
      metadata: nil,
      rows: [],
      consumedBytes: input.count,
      progress: .needsInput
    )
  }

  /// Finishes decoding and consumes the session.
  public consuming func finish() throws -> JPEGDecodingResult {
    guard case .collecting = state else { throw stateError }
    return try NativeJPEGCodec.decode(bytes: bytes, options: options)
  }

  /// Abandons buffered state without producing output.
  public mutating func abandon() {
    bytes.removeAll(keepingCapacity: false)
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
