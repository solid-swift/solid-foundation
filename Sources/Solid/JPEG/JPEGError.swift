/// An error produced while validating or processing JPEG data.
public enum JPEGError: Error, Equatable, Sendable {

  /// The encoded data is structurally invalid.
  case invalidData

  /// The encoded data ended before a complete image was available.
  case truncatedData

  /// A caller-provided option is invalid.
  case invalidConfiguration(String)

  /// Processing would exceed a configured resource limit.
  case limitExceeded

  /// The image uses a JPEG feature outside the baseline codec.
  case unsupportedFeature(String)

  /// The session was explicitly abandoned.
  case abandoned

  /// The session was already finalized.
  case finished

}
