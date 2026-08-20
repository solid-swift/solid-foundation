/// Metadata discovered while decoding a JPEG image.
public struct JPEGMetadata: Equatable, Sendable {

  /// Image width in samples.
  public let width: Int

  /// Image height in samples.
  public let height: Int

  /// Frame components.
  public let components: [JPEGComponent]

  /// Restart interval in MCUs.
  public let restartInterval: Int

  /// Adobe APP14 color-transform value when present.
  public let adobeColorTransform: Int?

  /// Creates decoded JPEG metadata.
  public init(
    width: Int,
    height: Int,
    components: [JPEGComponent],
    restartInterval: Int,
    adobeColorTransform: Int?
  ) {
    self.width = width
    self.height = height
    self.components = components
    self.restartInterval = restartInterval
    self.adobeColorTransform = adobeColorTransform
  }

}

/// A nonfatal condition observed while processing JPEG data.
public enum JPEGDiagnostic: Equatable, Sendable {

  /// An application marker was ignored.
  case ignoredApplicationMarker(UInt8)

  /// A comment marker was ignored.
  case ignoredComment

  /// An abbreviated stream used a caller-supplied table.
  case usedExternalTable

}
