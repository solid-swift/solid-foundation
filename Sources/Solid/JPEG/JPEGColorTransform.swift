/// A component transform applied around JPEG coding.
public enum JPEGColorTransform: Int, Equatable, Sendable {

  /// Preserve components without color conversion.
  case none = 0

  /// Convert RGB samples to and from YCbCr.
  case yCbCr = 1

}
