/// A JPEG quantization table in JPEG zigzag order.
public struct JPEGQuantizationTable: Equatable, Sendable {

  /// Table identifier.
  public let identifier: UInt8

  /// The 64 quantization values in zigzag order.
  public let values: [UInt16]

  /// Creates a JPEG quantization table.
  public init(identifier: UInt8, values: [UInt16]) throws {
    guard identifier < 4, values.count == 64, values.allSatisfy({ $0 > 0 }) else {
      throw JPEGError.invalidConfiguration("quantizationTable")
    }
    self.identifier = identifier
    self.values = values
  }

}

public extension JPEGQuantizationTable {

  /// The standard luminance quantization table from the JPEG specification.
  static var standardLuminance: Self {
    try! JPEGConstants.defaultQuantizationTables()[0]
  }

  /// The standard chrominance quantization table from the JPEG specification.
  static var standardChrominance: Self {
    try! JPEGConstants.defaultQuantizationTables()[1]
  }

}

/// The coefficient class encoded by a JPEG Huffman table.
public enum JPEGHuffmanTableClass: UInt8, Equatable, Sendable {

  /// Differential DC coefficients.
  case dc = 0

  /// Run-length encoded AC coefficients.
  case ac = 1

}

/// A canonical JPEG Huffman table.
public struct JPEGHuffmanTable: Equatable, Sendable {

  /// Coefficient class encoded by the table.
  public let tableClass: JPEGHuffmanTableClass

  /// Table identifier.
  public let identifier: UInt8

  /// Counts of codes having lengths one through sixteen.
  public let codeCounts: [UInt8]

  /// Symbols ordered by increasing code length.
  public let symbols: [UInt8]

  /// Creates and validates a canonical JPEG Huffman table.
  public init(
    tableClass: JPEGHuffmanTableClass,
    identifier: UInt8,
    codeCounts: [UInt8],
    symbols: [UInt8]
  ) throws {
    guard identifier < 4,
          codeCounts.count == 16,
          codeCounts.reduce(0, { $0 + Int($1) }) == symbols.count,
          symbols.count <= 256
    else {
      throw JPEGError.invalidConfiguration("huffmanTable")
    }
    var availableCodes = 1
    for count in codeCounts {
      availableCodes = availableCodes * 2 - Int(count)
      guard availableCodes >= 0 else {
        throw JPEGError.invalidConfiguration("huffmanTable")
      }
    }
    self.tableClass = tableClass
    self.identifier = identifier
    self.codeCounts = codeCounts
    self.symbols = symbols
  }

}
