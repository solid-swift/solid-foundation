/// Horizontal and vertical sampling factors for one JPEG component.
public struct JPEGSampling: Equatable, Hashable, Sendable {

  /// Horizontal sampling factor.
  public let horizontal: Int

  /// Vertical sampling factor.
  public let vertical: Int

  /// Creates validated baseline JPEG sampling factors.
  public init(horizontal: Int = 1, vertical: Int = 1) throws {
    guard (1...4).contains(horizontal), (1...4).contains(vertical) else {
      throw JPEGError.invalidConfiguration("sampling")
    }
    self.horizontal = horizontal
    self.vertical = vertical
  }

  /// Unit sampling in both dimensions.
  public static var unit: Self { try! Self() }

}

/// A JPEG frame component.
public struct JPEGComponent: Equatable, Hashable, Sendable {

  /// Component identifier stored in the JPEG frame.
  public let identifier: UInt8

  /// Component sampling factors.
  public let sampling: JPEGSampling

  /// Quantization-table identifier.
  public let quantizationTable: UInt8

  /// Creates a JPEG frame component.
  public init(
    identifier: UInt8,
    sampling: JPEGSampling = .unit,
    quantizationTable: UInt8 = 0
  ) throws {
    guard quantizationTable < 4 else {
      throw JPEGError.invalidConfiguration("quantizationTable")
    }
    self.identifier = identifier
    self.sampling = sampling
    self.quantizationTable = quantizationTable
  }

}
