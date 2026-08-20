/// Resource limits enforced by JPEG encoders and decoders.
public struct JPEGLimits: Equatable, Sendable {

  /// Maximum permitted image width.
  public var maximumWidth: Int

  /// Maximum permitted image height.
  public var maximumHeight: Int

  /// Maximum permitted number of components.
  public var maximumComponents: Int

  /// Maximum permitted number of scans.
  public var maximumScans: Int

  /// Maximum permitted number of minimum coded units.
  public var maximumMCUs: Int

  /// Maximum encoded input size.
  public var maximumInputBytes: Int

  /// Maximum encoded or decoded output size.
  public var maximumOutputBytes: Int

  /// Maximum temporary working storage.
  public var maximumScratchBytes: Int

  /// Creates a JPEG resource budget.
  public init(
    maximumWidth: Int = 65_535,
    maximumHeight: Int = 65_535,
    maximumComponents: Int = 4,
    maximumScans: Int = 64,
    maximumMCUs: Int = 67_108_864,
    maximumInputBytes: Int = 512 * 1_024 * 1_024,
    maximumOutputBytes: Int = 512 * 1_024 * 1_024,
    maximumScratchBytes: Int = 64 * 1_024 * 1_024
  ) throws {
    guard maximumWidth > 0,
          maximumHeight > 0,
          maximumComponents > 0,
          maximumScans > 0,
          maximumMCUs > 0,
          maximumInputBytes >= 0,
          maximumOutputBytes >= 0,
          maximumScratchBytes >= 0
    else {
      throw JPEGError.invalidConfiguration("limits")
    }
    self.maximumWidth = maximumWidth
    self.maximumHeight = maximumHeight
    self.maximumComponents = maximumComponents
    self.maximumScans = maximumScans
    self.maximumMCUs = maximumMCUs
    self.maximumInputBytes = maximumInputBytes
    self.maximumOutputBytes = maximumOutputBytes
    self.maximumScratchBytes = maximumScratchBytes
  }

  /// The default bounded resource budget.
  public static var `default`: Self { try! Self() }

}
