/// Options controlling deterministic baseline JPEG encoding.
public struct JPEGEncodingOptions: Equatable, Sendable {

  /// Image width in samples.
  public let width: Int

  /// Image height in samples.
  public let height: Int

  /// Frame components in interleaved input order.
  public let components: [JPEGComponent]

  /// Quantization tables available to the image.
  public let quantizationTables: [JPEGQuantizationTable]

  /// Huffman tables available to the image.
  public let huffmanTables: [JPEGHuffmanTable]

  /// Ordered scans, or an empty array to create one interleaved scan.
  public let scans: [JPEGScan]

  /// Number of MCUs between restart markers, or zero for none.
  public let restartInterval: Int

  /// Optional component color transform.
  public let colorTransform: JPEGColorTransform

  /// Resource limits for the encoding operation.
  public let limits: JPEGLimits

  /// Creates validated baseline JPEG encoding options.
  public init(
    width: Int,
    height: Int,
    components: [JPEGComponent],
    quantizationTables: [JPEGQuantizationTable] = [],
    huffmanTables: [JPEGHuffmanTable] = [],
    scans: [JPEGScan] = [],
    restartInterval: Int = 0,
    colorTransform: JPEGColorTransform = .none,
    limits: JPEGLimits = .default
  ) throws {
    guard width > 0,
          height > 0,
          width <= min(65_535, limits.maximumWidth),
          height <= min(65_535, limits.maximumHeight),
          (1...min(4, limits.maximumComponents)).contains(components.count),
          Set(components.map(\.identifier)).count == components.count,
          components.reduce(0, { $0 + $1.sampling.horizontal * $1.sampling.vertical }) <= 10,
          quantizationTables.count <= 4,
          Set(quantizationTables.map(\.identifier)).count == quantizationTables.count,
          huffmanTables.count <= 8,
          scans.count <= limits.maximumScans,
          (0...65_535).contains(restartInterval)
    else {
      throw JPEGError.invalidConfiguration("encodingOptions")
    }
    let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (samples, sampleOverflow) = pixels.multipliedReportingOverflow(by: components.count)
    guard !pixelOverflow, !sampleOverflow, samples <= limits.maximumInputBytes else {
      throw JPEGError.limitExceeded
    }
    self.width = width
    self.height = height
    self.components = components
    self.quantizationTables = quantizationTables
    self.huffmanTables = huffmanTables
    self.scans = scans
    self.restartInterval = restartInterval
    self.colorTransform = colorTransform
    self.limits = limits
  }

  /// Number of interleaved input samples required by the encoder.
  public var sampleCount: Int { width * height * components.count }

}

/// Options controlling baseline JPEG decoding.
public struct JPEGDecodingOptions: Equatable, Sendable {

  /// Expected width, or zero to accept the frame width.
  public let expectedWidth: Int

  /// Expected height, or zero to accept the frame height.
  public let expectedHeight: Int

  /// Expected component count, or zero to accept the frame count.
  public let expectedComponents: Int

  /// Caller-supplied quantization tables for abbreviated data.
  public let quantizationTables: [JPEGQuantizationTable]

  /// Caller-supplied Huffman tables for abbreviated data.
  public let huffmanTables: [JPEGHuffmanTable]

  /// Expected frame components, or an empty array to accept the frame declaration.
  public let components: [JPEGComponent]

  /// Optional transform overriding the implementation default.
  public let colorTransform: JPEGColorTransform?

  /// Resource limits for the decoding operation.
  public let limits: JPEGLimits

  /// Creates baseline JPEG decoding options.
  public init(
    expectedWidth: Int = 0,
    expectedHeight: Int = 0,
    expectedComponents: Int = 0,
    components: [JPEGComponent] = [],
    quantizationTables: [JPEGQuantizationTable] = [],
    huffmanTables: [JPEGHuffmanTable] = [],
    colorTransform: JPEGColorTransform? = nil,
    limits: JPEGLimits = .default
  ) throws {
    guard expectedWidth >= 0,
          expectedHeight >= 0,
          (0...min(4, limits.maximumComponents)).contains(expectedComponents),
          components.isEmpty || components.count == expectedComponents || expectedComponents == 0,
          Set(components.map(\.identifier)).count == components.count,
          quantizationTables.count <= 4,
          huffmanTables.count <= 8
    else {
      throw JPEGError.invalidConfiguration("decodingOptions")
    }
    self.expectedWidth = expectedWidth
    self.expectedHeight = expectedHeight
    self.expectedComponents = expectedComponents
    self.components = components
    self.quantizationTables = quantizationTables
    self.huffmanTables = huffmanTables
    self.colorTransform = colorTransform
    self.limits = limits
  }

}
