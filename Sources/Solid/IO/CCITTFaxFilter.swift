//
//  CCITTFaxFilter.swift
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

/// Options for CCITT Group 3 and Group 4 facsimile coding.
public struct CCITTFaxOptions: Equatable, Sendable {

  /// Permits uncompressed spans within encoded lines.
  public var uncompressed: Bool

  /// Coding mode: negative for Group 4, zero for Group 3 one-dimensional, positive for mixed Group 3.
  public var k: Int

  /// Requires an end-of-line code before each scan line.
  public var endOfLine: Bool

  /// Pads each encoded scan line to a byte boundary.
  public var encodedByteAlign: Bool

  /// Number of pixels in each scan line.
  public var columns: Int

  /// Number of scan lines, or zero when decoding through an end-of-block marker.
  public var rows: Int

  /// Emits or recognizes the format end-of-block marker.
  public var endOfBlock: Bool

  /// Treats one bits as black pixels.
  public var blackIs1: Bool

  /// Maximum number of damaged rows tolerated while decoding.
  public var damagedRowsBeforeError: Int

  /// Creates CCITT facsimile options.
  public init(
    uncompressed: Bool = false,
    k: Int = 0,
    endOfLine: Bool = false,
    encodedByteAlign: Bool = false,
    columns: Int = 1728,
    rows: Int = 0,
    endOfBlock: Bool = true,
    blackIs1: Bool = false,
    damagedRowsBeforeError: Int = 0
  ) throws {
    guard (1...1_000_000).contains(columns) else {
      throw StreamCodecError.invalidOption("columns")
    }
    guard (0...1_000_000).contains(rows) else { throw StreamCodecError.invalidOption("rows") }
    guard damagedRowsBeforeError >= 0 else {
      throw StreamCodecError.invalidOption("damagedRowsBeforeError")
    }
    self.uncompressed = uncompressed
    self.k = k
    self.endOfLine = endOfLine
    self.encodedByteAlign = encodedByteAlign
    self.columns = columns
    self.rows = rows
    self.endOfBlock = endOfBlock
    self.blackIs1 = blackIs1
    self.damagedRowsBeforeError = damagedRowsBeforeError
  }

}

/// An incremental CCITT Group 3/4 encoder.
public final class CCITTFaxEncoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let options: CCITTFaxOptions
  private let state = Mutex(State())

  /// Creates a CCITT facsimile encoder.
  public init(options: CCITTFaxOptions) {
    self.options = options
  }

  /// Buffers one-bit scan lines for final encoding.
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

  /// Encodes all buffered scan lines.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      defer { state.input.removeAll() }
      return try CCITTFaxCodec.encode(state.input, options: options)
    }
  }

}

/// An incremental CCITT Group 3/4 decoder.
public final class CCITTFaxDecoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let options: CCITTFaxOptions
  private let state = Mutex(State())

  /// Creates a CCITT facsimile decoder.
  public init(options: CCITTFaxOptions = try! CCITTFaxOptions()) {
    self.options = options
  }

  /// Buffers encoded scan lines until the physical source is finished.
  public func process(input: Data) throws -> IncrementalFilterResult {
    try state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      let previousCount = state.input.count
      var combined = state.input
      combined.append(input)
      if options.endOfBlock,
         options.rows > 0,
         let end = CCITTEndOfData.endOffset(in: combined, k: options.k)
      {
        let decoded = try CCITTFaxCodec.decode(Data(combined.prefix(end)), options: options)
        state.finished = true
        state.input.removeAll()
        return IncrementalFilterResult(
          output: decoded.data,
          consumedInput: max(0, decoded.consumedBytes - previousCount),
          progress: .finished
        )
      }
      state.input = combined
      return IncrementalFilterResult(
        output: Data(),
        consumedInput: input.count,
        progress: .needsInput
      )
    }
  }

  /// Decodes the complete facsimile stream.
  public func finish() throws -> Data? {
    try state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      defer { state.input.removeAll() }
      return try CCITTFaxCodec.decode(state.input, options: options).data
    }
  }

}

private enum CCITTEndOfData {

  static func endOffset(in data: Data, k: Int) -> Int? {
    let requiredCodes = k < 0 ? 2 : 6
    var zeroRun = 0
    var consecutiveCodes = 0

    for bitOffset in 0..<(data.count * 8) {
      let byte = data[data.index(data.startIndex, offsetBy: bitOffset / 8)]
      let bit = (byte >> (7 - bitOffset % 8)) & 1
      if bit == 0 {
        zeroRun += 1
        continue
      }

      if zeroRun >= 11 {
        consecutiveCodes += 1
        if consecutiveCodes == requiredCodes {
          return (bitOffset + 8) / 8
        }
      } else {
        consecutiveCodes = 0
      }
      zeroRun = 0
    }
    return nil
  }

}

private enum CCITTImageIO {

  static func encode(_ data: Data, options: CCITTFaxOptions) throws -> Data {
    #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
      guard options.endOfBlock else { throw StreamCodecError.unsupportedOperation }
      let rowBytes = (options.columns + 7) / 8
      guard data.count.isMultiple(of: rowBytes) else { throw StreamCodecError.truncatedData }
      let rows = data.count / rowBytes
      guard rows > 0 else { throw StreamCodecError.truncatedData }
      var pixels = data
      if options.blackIs1 {
        for index in pixels.indices { pixels[index] ^= 0xFF }
      }
      guard let provider = CGDataProvider(data: pixels as CFData),
            let image = CGImage(
              width: options.columns,
              height: rows,
              bitsPerComponent: 1,
              bitsPerPixel: 1,
              bytesPerRow: rowBytes,
              space: CGColorSpaceCreateDeviceGray(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
            )
      else {
        throw StreamCodecError.invalidData
      }
      let tiff = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(
        tiff,
        UTType.tiff.identifier as CFString,
        1,
        nil
      ) else {
        throw StreamCodecError.unsupportedOperation
      }
      let compression = options.k < 0 ? 4 : 3
      let properties: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [
          kCGImagePropertyTIFFCompression: compression
        ]
      ]
      CGImageDestinationAddImage(destination, image, properties as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { throw StreamCodecError.invalidData }
      var encoded = try TIFFFaxContainer.extractStrips(from: tiff as Data)
      if CCITTEndOfData.endOffset(in: encoded, k: options.k) == nil {
        if options.k < 0 {
          encoded.append(contentsOf: [0x00, 0x10, 0x01])
        } else {
          encoded.append(contentsOf: [0x00, 0x10, 0x01, 0x00, 0x10, 0x01, 0x00, 0x10, 0x01])
        }
      }
      return encoded
    #else
      throw StreamCodecError.unsupportedOperation
    #endif
  }

  static func decode(_ data: Data, options: CCITTFaxOptions) throws -> Data {
    #if canImport(CoreGraphics) && canImport(ImageIO)
      guard options.rows > 0 else { throw StreamCodecError.unsupportedOperation }
      guard options.damagedRowsBeforeError == 0 else {
        throw StreamCodecError.unsupportedOperation
      }
      let tiff = TIFFFaxContainer.wrap(data, options: options)
      guard let source = CGImageSourceCreateWithData(tiff as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw StreamCodecError.invalidData
      }
      let rowBytes = (options.columns + 7) / 8
      var grayscale = [UInt8](repeating: 0, count: options.columns * options.rows)
      let context = grayscale.withUnsafeMutableBytes { buffer in
        CGContext(
          data: buffer.baseAddress,
          width: options.columns,
          height: options.rows,
          bitsPerComponent: 8,
          bytesPerRow: options.columns,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      }
      guard let context else { throw StreamCodecError.unsupportedOperation }
      context.draw(image, in: CGRect(x: 0, y: 0, width: options.columns, height: options.rows))
      var output = [UInt8](repeating: 0, count: rowBytes * options.rows)
      for row in 0..<options.rows {
        for column in 0..<options.columns {
          let isBlack = grayscale[row * options.columns + column] < 128
          let setBit = options.blackIs1 ? isBlack : !isBlack
          if setBit {
            output[row * rowBytes + column / 8] |= 1 << (7 - column % 8)
          }
        }
      }
      return Data(output)
    #else
      throw StreamCodecError.unsupportedOperation
    #endif
  }

}

private enum TIFFFaxContainer {

  static func extractStrips(from tiff: Data) throws -> Data {
    guard tiff.count >= 8 else { throw StreamCodecError.invalidData }
    let littleEndian = tiff[0] == 0x49 && tiff[1] == 0x49
    guard littleEndian || (tiff[0] == 0x4D && tiff[1] == 0x4D) else {
      throw StreamCodecError.invalidData
    }
    let ifdOffset = Int(read32(tiff, at: 4, littleEndian: littleEndian))
    guard ifdOffset + 2 <= tiff.count else { throw StreamCodecError.invalidData }
    let count = Int(read16(tiff, at: ifdOffset, littleEndian: littleEndian))
    var offsets: [Int] = []
    var byteCounts: [Int] = []

    for entry in 0..<count {
      let offset = ifdOffset + 2 + entry * 12
      guard offset + 12 <= tiff.count else { throw StreamCodecError.invalidData }
      let tag = read16(tiff, at: offset, littleEndian: littleEndian)
      let type = read16(tiff, at: offset + 2, littleEndian: littleEndian)
      let valueCount = Int(read32(tiff, at: offset + 4, littleEndian: littleEndian))
      if tag == 273 {
        offsets = try values(tiff, entry: offset, type: type, count: valueCount, littleEndian: littleEndian)
      } else if tag == 279 {
        byteCounts = try values(tiff, entry: offset, type: type, count: valueCount, littleEndian: littleEndian)
      }
    }
    guard offsets.count == byteCounts.count, !offsets.isEmpty else {
      throw StreamCodecError.invalidData
    }
    var output = Data()
    for (offset, count) in zip(offsets, byteCounts) {
      guard offset >= 0, count >= 0, offset + count <= tiff.count else {
        throw StreamCodecError.invalidData
      }
      output.append(tiff[offset..<(offset + count)])
    }
    return output
  }

  static func wrap(_ fax: Data, options: CCITTFaxOptions) -> Data {
    let alignedFaxCount = fax.count + fax.count % 2
    let ifdOffset = 8 + alignedFaxCount
    let entries: [(UInt16, UInt16, UInt32, UInt32)] = [
      (256, 4, 1, UInt32(options.columns)),
      (257, 4, 1, UInt32(options.rows)),
      (258, 3, 1, 1),
      (259, 3, 1, UInt32(options.k < 0 ? 4 : 3)),
      (262, 3, 1, 1),
      (266, 3, 1, 1),
      (273, 4, 1, 8),
      (277, 3, 1, 1),
      (278, 4, 1, UInt32(options.rows)),
      (279, 4, 1, UInt32(fax.count)),
      (options.k < 0 ? 293 : 292, 4, 1, groupOptions(options)),
    ]
    var output = Data([0x49, 0x49, 0x2A, 0x00])
    append32(UInt32(ifdOffset), to: &output)
    output.append(fax)
    if fax.count % 2 != 0 { output.append(0) }
    append16(UInt16(entries.count), to: &output)
    for entry in entries {
      append16(entry.0, to: &output)
      append16(entry.1, to: &output)
      append32(entry.2, to: &output)
      if entry.1 == 3 {
        append16(UInt16(entry.3), to: &output)
        append16(0, to: &output)
      } else {
        append32(entry.3, to: &output)
      }
    }
    append32(0, to: &output)
    return output
  }

  private static func groupOptions(_ options: CCITTFaxOptions) -> UInt32 {
    var value: UInt32 = 0
    if options.k > 0 { value |= 1 }
    if options.uncompressed { value |= 2 }
    if options.encodedByteAlign { value |= 4 }
    return value
  }

  private static func values(
    _ data: Data,
    entry: Int,
    type: UInt16,
    count: Int,
    littleEndian: Bool
  ) throws -> [Int] {
    let width = type == 3 ? 2 : 4
    guard type == 3 || type == 4 else { throw StreamCodecError.invalidData }
    let valueOffset = count * width <= 4
      ? entry + 8
      : Int(read32(data, at: entry + 8, littleEndian: littleEndian))
    guard valueOffset + count * width <= data.count else { throw StreamCodecError.invalidData }
    return (0..<count).map { index in
      if type == 3 {
        return Int(read16(data, at: valueOffset + index * 2, littleEndian: littleEndian))
      }
      return Int(read32(data, at: valueOffset + index * 4, littleEndian: littleEndian))
    }
  }

  private static func read16(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt16 {
    let first = UInt16(data[offset])
    let second = UInt16(data[offset + 1])
    return littleEndian ? first | second << 8 : first << 8 | second
  }

  private static func read32(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt32 {
    let lower = UInt32(read16(data, at: offset, littleEndian: littleEndian))
    let upper = UInt32(read16(data, at: offset + 2, littleEndian: littleEndian))
    return littleEndian ? lower | upper << 16 : lower << 16 | upper
  }

  private static func append16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8(value >> 8))
  }

  private static func append32(_ value: UInt32, to data: inout Data) {
    append16(UInt16(value & 0xFFFF), to: &data)
    append16(UInt16(value >> 16), to: &data)
  }

}
