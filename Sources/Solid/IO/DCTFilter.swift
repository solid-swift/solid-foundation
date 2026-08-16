//
//  DCTFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization

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
    let (pixels, pixelOverflow) = columns.multipliedReportingOverflow(by: rows)
    let (_, sampleOverflow) = pixels.multipliedReportingOverflow(by: colors)
    guard !pixelOverflow, !sampleOverflow else { throw StreamCodecError.invalidOption("dimensions") }
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

  var sampleCount: Int {
    columns * rows * colors
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

  /// Maximum decoded bytes the codec may materialize.
  public var maximumDecodedBytes: Int

  /// Creates baseline JPEG/DCT decoding options.
  public init(
    columns: Int = 0,
    rows: Int = 0,
    colors: Int = 0,
    colorTransform: Int? = nil,
    horizontalSamples: [Int] = [],
    verticalSamples: [Int] = [],
    quantizationTables: [Data] = [],
    huffmanTables: [DCTHuffmanTable] = [],
    maximumDecodedBytes: Int = .max
  ) throws {
    guard columns >= 0 else { throw StreamCodecError.invalidOption("columns") }
    guard rows >= 0 else { throw StreamCodecError.invalidOption("rows") }
    guard (0...4).contains(colors) else { throw StreamCodecError.invalidOption("colors") }
    guard colorTransform == nil || colorTransform == 0 || colorTransform == 1 else {
      throw StreamCodecError.invalidOption("colorTransform")
    }
    guard maximumDecodedBytes >= 0 else {
      throw StreamCodecError.invalidOption("maximumDecodedBytes")
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
    self.maximumDecodedBytes = maximumDecodedBytes
  }

}

/// An incremental baseline JPEG/DCT encoder.
public final class DCTEncoder: IncrementalFilter {

  private enum State: Sendable {
    case collecting(Data)
    case processing
    case finished
  }

  private let options: DCTEncodeOptions
  private let backend: any DCTCodecBackend
  private let state = Mutex<State>(.collecting(Data()))

  /// Creates a DCT encoder.
  public init(options: DCTEncodeOptions) {
    self.options = options
    backend = DCTCodecBackends.platform
  }

  init(options: DCTEncodeOptions, backend: any DCTCodecBackend) {
    self.options = options
    self.backend = backend
  }

  /// Buffers image samples for final JPEG encoding.
  public func process(input: Data) throws -> IncrementalFilterResult {
    let payload: Data? = try state.withLock { state in
      guard case .collecting(var buffered) = state else { throw StreamCodecError.invalidData }
      let expected = options.sampleCount
      guard buffered.count + input.count <= expected else {
        throw StreamCodecError.invalidData
      }
      buffered.append(input)
      guard buffered.count == expected else {
        state = .collecting(buffered)
        return nil
      }
      state = .processing
      return buffered
    }
    guard let payload else {
      return IncrementalFilterResult(
        output: Data(),
        consumedInput: input.count,
        progress: .needsInput
      )
    }

    do {
      let output = try backend.encode(payload, options: options)
      state.withLock { $0 = .finished }
      return IncrementalFilterResult(
        output: output,
        consumedInput: input.count,
        progress: .finished
      )
    } catch {
      state.withLock { $0 = .finished }
      throw error
    }
  }

  /// Encodes the buffered image as a baseline JPEG stream.
  public func finish() throws -> Data? {
    let payload: Data? = try state.withLock { state in
      switch state {
      case .collecting(let buffered):
        guard buffered.count == options.sampleCount else {
          state = .finished
          throw StreamCodecError.truncatedData
        }
        state = .processing
        return buffered
      case .processing:
        throw StreamCodecError.invalidData
      case .finished:
        return nil
      }
    }
    guard let payload else { return nil }
    do {
      let output = try backend.encode(payload, options: options)
      state.withLock { $0 = .finished }
      return output
    } catch {
      state.withLock { $0 = .finished }
      throw error
    }
  }

}

/// An incremental baseline JPEG/DCT decoder.
public final class DCTDecoder: IncrementalFilter {

  private enum State: Sendable {
    case collecting(Data)
    case processing
    case finished
  }

  private let options: DCTDecodeOptions
  private let backend: any DCTCodecBackend
  private let state = Mutex<State>(.collecting(Data()))

  /// Creates a DCT decoder.
  public init(options: DCTDecodeOptions = try! DCTDecodeOptions()) {
    self.options = options
    backend = DCTCodecBackends.platform
  }

  init(options: DCTDecodeOptions, backend: any DCTCodecBackend) {
    self.options = options
    self.backend = backend
  }

  /// Decodes once a complete JPEG end-of-image marker is available.
  public func process(input: Data) throws -> IncrementalFilterResult {
    let work: (jpeg: Data, metadata: JPEGMetadata, components: Int, consumed: Int)? = try state
      .withLock { state in
        switch state {
        case .finished:
          return nil
        case .processing:
          throw StreamCodecError.invalidData
        case .collecting(let buffered):
          let previousCount = buffered.count
          var combined = buffered
          combined.append(input)
          guard let metadata = try JPEGMetadataParser.parse(combined) else {
            state = .collecting(combined)
            return nil
          }
          let outputComponents = try validate(metadata: metadata)
          guard let end = metadata.endOffset else {
            state = .collecting(combined)
            return nil
          }
          state = .processing
          return (
            Data(combined.prefix(end)),
            metadata,
            outputComponents,
            max(0, end - previousCount)
          )
        }
      }
    guard let work else {
      let isFinished = state.withLock {
        if case .finished = $0 { return true }
        return false
      }
      if isFinished {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      return IncrementalFilterResult(
        output: Data(),
        consumedInput: input.count,
        progress: .needsInput
      )
    }

    do {
      let output = try backend.decode(
        work.jpeg,
        metadata: work.metadata,
        outputComponents: work.components
      )
      let expected = work.metadata.width * work.metadata.height * work.components
      guard output.count == expected else { throw StreamCodecError.invalidData }
      state.withLock { $0 = .finished }
      return IncrementalFilterResult(
        output: output,
        consumedInput: work.consumed,
        progress: .finished
      )
    } catch {
      state.withLock { $0 = .finished }
      throw error
    }
  }

  /// Rejects a physical source end before JPEG end-of-image.
  public func finish() throws -> Data? {
    try state.withLock { state in
      switch state {
      case .collecting:
        state = .finished
        throw StreamCodecError.truncatedData
      case .processing:
        throw StreamCodecError.invalidData
      case .finished:
        return nil
      }
    }
  }

  private func validate(metadata: JPEGMetadata) throws -> Int {
    guard options.horizontalSamples.isEmpty,
          options.verticalSamples.isEmpty,
          options.quantizationTables.isEmpty,
          options.huffmanTables.isEmpty
    else {
      throw StreamCodecError.unsupportedOperation
    }
    guard metadata.components.count != 2 else { throw StreamCodecError.unsupportedOperation }
    guard options.columns == 0 || options.columns == metadata.width,
          options.rows == 0 || options.rows == metadata.height,
          options.colors == 0 || options.colors == metadata.components.count
    else {
      throw StreamCodecError.invalidData
    }

    let components = options.colors == 0 ? metadata.components.count : options.colors
    let effectiveTransform = metadata.adobeColorTransform
      ?? options.colorTransform
      ?? (components == 3 ? 1 : 0)
    switch components {
    case 1:
      break
    case 3:
      if metadata.adobeColorTransform == nil {
        guard effectiveTransform == 1 else { throw StreamCodecError.unsupportedOperation }
      } else {
        guard effectiveTransform == 0 || effectiveTransform == 1 else {
          throw StreamCodecError.unsupportedOperation
        }
      }
    case 4:
      guard metadata.adobeColorTransform != nil,
            effectiveTransform == 0 || effectiveTransform == 2
      else {
        throw StreamCodecError.unsupportedOperation
      }
    default:
      throw StreamCodecError.unsupportedOperation
    }

    let (pixels, pixelOverflow) = metadata.width.multipliedReportingOverflow(by: metadata.height)
    let (decodedBytes, byteOverflow) = pixels.multipliedReportingOverflow(by: components)
    guard !pixelOverflow, !byteOverflow else { throw StreamCodecError.invalidData }
    guard decodedBytes <= options.maximumDecodedBytes else {
      throw StreamCodecError.limitExceeded
    }
    return components
  }

}
