/// Progress of a streaming JPEG session.
public enum JPEGSessionProgress: Equatable, Sendable {

  /// The session can accept more input.
  case needsInput

  /// The complete image has been processed.
  case finished

}

/// Encoded bytes produced while consuming source samples.
public struct JPEGEncodingResult: Equatable, Sendable {

  /// Encoded JPEG bytes produced by the operation.
  public let bytes: [UInt8]

  /// Number of source samples consumed.
  public let consumedSamples: Int

  /// Session progress after the operation.
  public let progress: JPEGSessionProgress

  /// Creates an encoding result.
  public init(bytes: [UInt8], consumedSamples: Int, progress: JPEGSessionProgress) {
    self.bytes = bytes
    self.consumedSamples = consumedSamples
    self.progress = progress
  }

}

/// A band of interleaved raw component rows decoded from a JPEG image.
public struct JPEGDecodedRows: Equatable, Sendable {

  /// Index of the first decoded row.
  public let firstRow: Int

  /// Number of rows in this band.
  public let rowCount: Int

  /// Number of interleaved components per pixel.
  public let componentCount: Int

  /// Interleaved raw component samples.
  public let samples: [UInt8]

  /// Creates a decoded row band.
  public init(firstRow: Int, rowCount: Int, componentCount: Int, samples: [UInt8]) {
    self.firstRow = firstRow
    self.rowCount = rowCount
    self.componentCount = componentCount
    self.samples = samples
  }

}

/// Rows and metadata produced while consuming encoded JPEG bytes.
public struct JPEGDecodingResult: Equatable, Sendable {

  /// Metadata once the frame header has been decoded.
  public let metadata: JPEGMetadata?

  /// Decoded row bands produced by the operation.
  public let rows: [JPEGDecodedRows]

  /// Number of encoded bytes consumed.
  public let consumedBytes: Int

  /// Session progress after the operation.
  public let progress: JPEGSessionProgress

  /// Creates a decoding result.
  public init(
    metadata: JPEGMetadata?,
    rows: [JPEGDecodedRows],
    consumedBytes: Int,
    progress: JPEGSessionProgress
  ) {
    self.metadata = metadata
    self.rows = rows
    self.consumedBytes = consumedBytes
    self.progress = progress
  }

}
