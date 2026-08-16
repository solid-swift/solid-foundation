//
//  DCTFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
#endif

/// A JPEG Huffman table supplied to DCT encoding.
public struct DCTHuffmanTable: Equatable, Sendable {

  /// Counts of codes having bit lengths 1 through 16.
  public var codeCounts: Data

  /// Symbols ordered by code length.
  public var symbols: Data

  /// Creates a JPEG Huffman table.
  public init(codeCounts: Data, symbols: Data) throws {
    guard codeCounts.count == 16,
          codeCounts.reduce(0, { $0 + Int($1) }) == symbols.count
    else {
      throw StreamCodecError.invalidOption("huffmanTable")
    }
    self.codeCounts = codeCounts
    self.symbols = symbols
  }

}

/// Options for baseline JPEG/DCT encoding.
public struct DCTEncodeOptions: Equatable, Sendable {

  /// Number of image columns.
  public var columns: Int

  /// Number of image rows.
  public var rows: Int

  /// Number of input color components.
  public var colors: Int

  /// Horizontal sampling factors for each component.
  public var horizontalSamples: [Int]

  /// Vertical sampling factors for each component.
  public var verticalSamples: [Int]

  /// Quantization tables, each containing 64 bytes in zigzag order.
  public var quantizationTables: [Data]

  /// Scale applied to supplied or implementation-default quantization tables.
  public var quantizationFactor: Double

  /// Alternating DC and AC Huffman tables.
  public var huffmanTables: [DCTHuffmanTable]

  /// Color conversion selector accepted by the PostScript DCT filter.
  public var colorTransform: Int

  /// Creates baseline JPEG/DCT encoding options.
  public init(
    columns: Int,
    rows: Int,
    colors: Int,
    horizontalSamples: [Int] = [],
    verticalSamples: [Int] = [],
    quantizationTables: [Data] = [],
    quantizationFactor: Double = 1,
    huffmanTables: [DCTHuffmanTable] = [],
    colorTransform: Int = 1
  ) throws {
    guard columns > 0 else { throw StreamCodecError.invalidOption("columns") }
    guard rows > 0 else { throw StreamCodecError.invalidOption("rows") }
    guard (1...4).contains(colors) else { throw StreamCodecError.invalidOption("colors") }
    let horizontalSamples = horizontalSamples.isEmpty
      ? Array(repeating: 1, count: colors)
      : horizontalSamples
    let verticalSamples = verticalSamples.isEmpty
      ? Array(repeating: 1, count: colors)
      : verticalSamples
    guard horizontalSamples.count == colors,
          verticalSamples.count == colors,
          horizontalSamples.allSatisfy({ (1...4).contains($0) }),
          verticalSamples.allSatisfy({ (1...4).contains($0) }),
          zip(horizontalSamples, verticalSamples).reduce(0, { $0 + $1.0 * $1.1 }) <= 10
    else {
      throw StreamCodecError.invalidOption("samples")
    }
    guard quantizationTables.count <= 4,
          quantizationTables.allSatisfy({ $0.count == 64 })
    else {
      throw StreamCodecError.invalidOption("quantizationTables")
    }
    guard (0...1_000_000).contains(quantizationFactor) else {
      throw StreamCodecError.invalidOption("quantizationFactor")
    }
    guard huffmanTables.count <= 8 else {
      throw StreamCodecError.invalidOption("huffmanTables")
    }
    guard colorTransform == 0 || colorTransform == 1 else {
      throw StreamCodecError.invalidOption("colorTransform")
    }
    self.columns = columns
    self.rows = rows
    self.colors = colors
    self.horizontalSamples = horizontalSamples
    self.verticalSamples = verticalSamples
    self.quantizationTables = quantizationTables
    self.quantizationFactor = quantizationFactor
    self.huffmanTables = huffmanTables
    self.colorTransform = colorTransform
  }

}

/// Options for baseline JPEG/DCT decoding.
public struct DCTDecodeOptions: Equatable, Sendable {

  /// Expected number of columns, or zero to use the JPEG header.
  public var columns: Int

  /// Expected number of rows, or zero to use the JPEG header.
  public var rows: Int

  /// Requested output components, or zero to use the encoded color model.
  public var colors: Int

  /// Optional color conversion selector.
  public var colorTransform: Int?

  /// Horizontal sampling factors supplied for an abbreviated stream.
  public var horizontalSamples: [Int]

  /// Vertical sampling factors supplied for an abbreviated stream.
  public var verticalSamples: [Int]

  /// Quantization tables supplied for an abbreviated stream.
  public var quantizationTables: [Data]

  /// Huffman tables supplied for an abbreviated stream.
  public var huffmanTables: [DCTHuffmanTable]

  /// Creates baseline JPEG/DCT decoding options.
  public init(
    columns: Int = 0,
    rows: Int = 0,
    colors: Int = 0,
    colorTransform: Int? = nil,
    horizontalSamples: [Int] = [],
    verticalSamples: [Int] = [],
    quantizationTables: [Data] = [],
    huffmanTables: [DCTHuffmanTable] = []
  ) throws {
    guard columns >= 0 else { throw StreamCodecError.invalidOption("columns") }
    guard rows >= 0 else { throw StreamCodecError.invalidOption("rows") }
    guard (0...4).contains(colors) else { throw StreamCodecError.invalidOption("colors") }
    guard colorTransform == nil || colorTransform == 0 || colorTransform == 1 else {
      throw StreamCodecError.invalidOption("colorTransform")
    }
    guard horizontalSamples.allSatisfy({ (1...4).contains($0) }),
          verticalSamples.allSatisfy({ (1...4).contains($0) }),
          horizontalSamples.isEmpty || colors == 0 || horizontalSamples.count == colors,
          verticalSamples.isEmpty || colors == 0 || verticalSamples.count == colors,
          quantizationTables.count <= 4,
          quantizationTables.allSatisfy({ $0.count == 64 }),
          huffmanTables.count <= 8
    else {
      throw StreamCodecError.invalidOption("tables")
    }
    self.columns = columns
    self.rows = rows
    self.colors = colors
    self.colorTransform = colorTransform
    self.horizontalSamples = horizontalSamples
    self.verticalSamples = verticalSamples
    self.quantizationTables = quantizationTables
    self.huffmanTables = huffmanTables
  }

}

/// An incremental baseline JPEG/DCT encoder.
public final class DCTEncoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let options: DCTEncodeOptions
  private let state = Mutex(State())

  /// Creates a DCT encoder.
  public init(options: DCTEncodeOptions) {
    self.options = options
  }

  /// Buffers image samples for final JPEG encoding.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else { throw StreamCodecError.invalidData }
      state.input.append(input)
      return IncrementalFilterResult(
        output: Data(),
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Encodes the buffered image as a baseline JPEG stream.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      defer { state.input.removeAll() }
      return try DCTImageIO.encode(state.input, options: options)
    }
  }

}

/// An incremental baseline JPEG/DCT decoder.
public final class DCTDecoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let options: DCTDecodeOptions
  private let state = Mutex(State())

  /// Creates a DCT decoder.
  public init(options: DCTDecodeOptions = try! DCTDecodeOptions()) {
    self.options = options
  }

  /// Decodes once a complete JPEG end-of-image marker is available.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      let previousCount = state.input.count
      var combined = state.input
      combined.append(input)
      guard let end = try JPEGFraming.endOffset(in: combined) else {
        state.input = combined
        return IncrementalFilterResult(
          output: Data(),
          consumedInput: input.count,
          progress: .needsInput
        )
      }
      let jpeg = Data(combined.prefix(end))
      let output = try DCTImageIO.decode(jpeg, options: options)
      state.finished = true
      state.input.removeAll()
      return IncrementalFilterResult(
        output: output,
        consumedInput: max(0, end - previousCount),
        progress: .finished
      )
    }
  }

  /// Rejects a physical source end before JPEG end-of-image.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      throw StreamCodecError.truncatedData
    }
  }

}

private enum JPEGFraming {

  static func endOffset(in data: Data) throws -> Int? {
    guard data.count >= 2 else { return nil }
    guard data[0] == 0xFF && data[1] == 0xD8 else { throw StreamCodecError.invalidData }
    var index = 2
    var inScan = false

    while index < data.count {
      guard data[index] == 0xFF else {
        if inScan {
          index += 1
          continue
        }
        throw StreamCodecError.invalidData
      }
      while index < data.count && data[index] == 0xFF { index += 1 }
      guard index < data.count else { return nil }
      let marker = data[index]
      index += 1
      if marker == 0x00 && inScan { continue }
      if marker == 0xD9 { return index }
      if marker == 0xD8 || (0xD0...0xD7).contains(marker) { continue }
      guard index + 2 <= data.count else { return nil }
      let length = Int(data[index]) << 8 | Int(data[index + 1])
      guard length >= 2 else { throw StreamCodecError.invalidData }
      guard index + length <= data.count else { return nil }
      inScan = marker == 0xDA
      index += length
    }
    return nil
  }

}

private enum DCTImageIO {

  static func encode(_ data: Data, options: DCTEncodeOptions) throws -> Data {
    #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
      guard options.colors != 2 else { throw StreamCodecError.unsupportedOperation }
      guard options.quantizationTables.isEmpty, options.huffmanTables.isEmpty else {
        throw StreamCodecError.unsupportedOperation
      }
      guard options.horizontalSamples.allSatisfy({ $0 == 1 }),
            options.verticalSamples.allSatisfy({ $0 == 1 })
      else {
        throw StreamCodecError.unsupportedOperation
      }
      let expected = options.columns * options.rows * options.colors
      guard data.count == expected else { throw StreamCodecError.truncatedData }
      let colorSpace: CGColorSpace
      switch options.colors {
      case 1: colorSpace = CGColorSpaceCreateDeviceGray()
      case 3: colorSpace = CGColorSpaceCreateDeviceRGB()
      default: colorSpace = CGColorSpaceCreateDeviceCMYK()
      }
      guard let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(
              width: options.columns,
              height: options.rows,
              bitsPerComponent: 8,
              bitsPerPixel: options.colors * 8,
              bytesPerRow: options.columns * options.colors,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
            )
      else {
        throw StreamCodecError.invalidData
      }
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      ) else {
        throw StreamCodecError.unsupportedOperation
      }
      let quality = min(1, max(0, 0.75 / options.quantizationFactor))
      CGImageDestinationAddImage(
        destination,
        image,
        [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
      )
      guard CGImageDestinationFinalize(destination) else { throw StreamCodecError.invalidData }
      return output as Data
    #else
      throw StreamCodecError.unsupportedOperation
    #endif
  }

  static func decode(_ data: Data, options: DCTDecodeOptions) throws -> Data {
    #if canImport(CoreGraphics) && canImport(ImageIO)
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw StreamCodecError.invalidData
      }
      guard options.columns == 0 || options.columns == image.width,
            options.rows == 0 || options.rows == image.height
      else {
        throw StreamCodecError.invalidData
      }
      let inferredColors: Int
      switch image.colorSpace?.model {
      case .monochrome: inferredColors = 1
      case .cmyk: inferredColors = 4
      default: inferredColors = 3
      }
      let colors = options.colors == 0 ? inferredColors : options.colors
      guard colors != 2 else { throw StreamCodecError.unsupportedOperation }
      let colorSpace: CGColorSpace
      switch colors {
      case 1: colorSpace = CGColorSpaceCreateDeviceGray()
      case 3: colorSpace = CGColorSpaceCreateDeviceRGB()
      default: colorSpace = CGColorSpaceCreateDeviceCMYK()
      }
      let contextColors = colors == 3 ? 4 : colors
      var rendered = [UInt8](repeating: 0, count: image.width * image.height * contextColors)
      let bitmapInfo = colors == 3
        ? CGImageAlphaInfo.noneSkipLast.rawValue
        : CGImageAlphaInfo.none.rawValue
      let created = rendered.withUnsafeMutableBytes { buffer in
        CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * contextColors,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      }
      guard let context = created else { throw StreamCodecError.unsupportedOperation }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      if colors == 3 {
        var output = Data(capacity: image.width * image.height * 3)
        for index in stride(from: 0, to: rendered.count, by: 4) {
          output.append(contentsOf: rendered[index..<(index + 3)])
        }
        return output
      }
      return Data(rendered)
    #else
      throw StreamCodecError.unsupportedOperation
    #endif
  }

}
