/// One component participating in a JPEG scan.
public struct JPEGScanComponent: Equatable, Sendable {

  /// Frame-component identifier.
  public let identifier: UInt8

  /// DC Huffman-table identifier.
  public let dcTable: UInt8

  /// AC Huffman-table identifier.
  public let acTable: UInt8

  /// Creates a scan component.
  public init(identifier: UInt8, dcTable: UInt8 = 0, acTable: UInt8 = 0) throws {
    guard dcTable < 4, acTable < 4 else {
      throw JPEGError.invalidConfiguration("scanTable")
    }
    self.identifier = identifier
    self.dcTable = dcTable
    self.acTable = acTable
  }

}

/// A baseline sequential JPEG scan.
public struct JPEGScan: Equatable, Sendable {

  /// Components encoded by this scan.
  public let components: [JPEGScanComponent]

  /// Creates a baseline scan containing one through four unique components.
  public init(components: [JPEGScanComponent]) throws {
    guard (1...4).contains(components.count),
          Set(components.map(\.identifier)).count == components.count
    else {
      throw JPEGError.invalidConfiguration("scan")
    }
    self.components = components
  }

}
