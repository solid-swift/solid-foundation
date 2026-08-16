//
//  PredictorFilter.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

import Foundation

/// Options for TIFF and PNG prediction applied around compression codecs.
public struct PredictorOptions: Equatable, Sendable {

  /// Predictor algorithm: 1, 2, or 10 through 15.
  public var predictor: Int

  /// Samples per pixel.
  public var colors: Int

  /// Bits in each sample.
  public var bitsPerComponent: Int

  /// Samples of each color in a row.
  public var columns: Int

  /// Creates predictor options.
  public init(
    predictor: Int = 1,
    colors: Int = 1,
    bitsPerComponent: Int = 8,
    columns: Int = 1
  ) throws {
    guard predictor == 1 || predictor == 2 || (10...15).contains(predictor) else {
      throw StreamCodecError.invalidOption("predictor")
    }
    guard colors >= 1 else { throw StreamCodecError.invalidOption("colors") }
    guard [1, 2, 4, 8].contains(bitsPerComponent) else {
      throw StreamCodecError.invalidOption("bitsPerComponent")
    }
    guard columns >= 1 else { throw StreamCodecError.invalidOption("columns") }
    self.predictor = predictor
    self.colors = colors
    self.bitsPerComponent = bitsPerComponent
    self.columns = columns
  }

  var rowBytes: Int {
    (columns * colors * bitsPerComponent + 7) / 8
  }

}

/// Applies and reverses TIFF and PNG compression predictors.
public enum PredictorCodec {

  /// Applies the configured predictor to complete rows.
  public static func encode(_ data: Data, options: PredictorOptions) throws -> Data {
    guard options.predictor != 1 else { return data }
    guard data.count.isMultiple(of: options.rowBytes) else {
      throw StreamCodecError.truncatedData
    }
    if options.predictor == 2 {
      return try encodeTIFF(data, options: options)
    }
    return encodePNG(data, options: options)
  }

  /// Reverses the configured predictor from complete rows.
  public static func decode(_ data: Data, options: PredictorOptions) throws -> Data {
    guard options.predictor != 1 else { return data }
    if options.predictor == 2 {
      guard data.count.isMultiple(of: options.rowBytes) else {
        throw StreamCodecError.truncatedData
      }
      return try decodeTIFF(data, options: options)
    }
    let encodedRowBytes = options.rowBytes + 1
    guard data.count.isMultiple(of: encodedRowBytes) else {
      throw StreamCodecError.truncatedData
    }
    return try decodePNG(data, options: options)
  }

  private static func encodeTIFF(_ data: Data, options: PredictorOptions) throws -> Data {
    var output = Data()
    for rowStart in stride(from: 0, to: data.count, by: options.rowBytes) {
      let row = Data(data[rowStart..<(rowStart + options.rowBytes)])
      var samples = unpack(row, width: options.bitsPerComponent)
      for index in stride(from: samples.count - 1, through: options.colors, by: -1) {
        let modulus = 1 << options.bitsPerComponent
        samples[index] = (samples[index] - samples[index - options.colors] + modulus) % modulus
      }
      output.append(pack(samples, width: options.bitsPerComponent))
    }
    return output
  }

  private static func decodeTIFF(_ data: Data, options: PredictorOptions) throws -> Data {
    var output = Data()
    for rowStart in stride(from: 0, to: data.count, by: options.rowBytes) {
      let row = Data(data[rowStart..<(rowStart + options.rowBytes)])
      var samples = unpack(row, width: options.bitsPerComponent)
      for index in options.colors..<samples.count {
        let modulus = 1 << options.bitsPerComponent
        samples[index] = (samples[index] + samples[index - options.colors]) % modulus
      }
      output.append(pack(samples, width: options.bitsPerComponent))
    }
    return output
  }

  private static func encodePNG(_ data: Data, options: PredictorOptions) -> Data {
    let bytesPerPixel = max(1, (options.colors * options.bitsPerComponent + 7) / 8)
    var previous = [UInt8](repeating: 0, count: options.rowBytes)
    var output = Data()

    for rowStart in stride(from: 0, to: data.count, by: options.rowBytes) {
      let row = Array(data[rowStart..<(rowStart + options.rowBytes)])
      let requested = options.predictor == 15 ? Array(0...4) : [options.predictor - 10]
      let candidates = requested.map { filter in
        (filter, filterPNG(row, previous: previous, bytesPerPixel: bytesPerPixel, filter: filter))
      }
      let selected = candidates.min { lhs, rhs in
        score(lhs.1) < score(rhs.1)
      }!
      output.append(UInt8(selected.0))
      output.append(contentsOf: selected.1)
      previous = row
    }
    return output
  }

  private static func decodePNG(_ data: Data, options: PredictorOptions) throws -> Data {
    let bytesPerPixel = max(1, (options.colors * options.bitsPerComponent + 7) / 8)
    let encodedRowBytes = options.rowBytes + 1
    var previous = [UInt8](repeating: 0, count: options.rowBytes)
    var output = Data()

    for rowStart in stride(from: 0, to: data.count, by: encodedRowBytes) {
      let filter = Int(data[rowStart])
      guard (0...4).contains(filter) else { throw StreamCodecError.invalidData }
      let encoded = Array(data[(rowStart + 1)..<(rowStart + encodedRowBytes)])
      var row = [UInt8](repeating: 0, count: options.rowBytes)
      for index in row.indices {
        let left = index >= bytesPerPixel ? row[index - bytesPerPixel] : 0
        let up = previous[index]
        let upperLeft = index >= bytesPerPixel ? previous[index - bytesPerPixel] : 0
        let prediction: UInt8
        switch filter {
        case 0: prediction = 0
        case 1: prediction = left
        case 2: prediction = up
        case 3: prediction = UInt8((Int(left) + Int(up)) / 2)
        default: prediction = paeth(left, up, upperLeft)
        }
        row[index] = encoded[index] &+ prediction
      }
      output.append(contentsOf: row)
      previous = row
    }
    return output
  }

  private static func filterPNG(
    _ row: [UInt8],
    previous: [UInt8],
    bytesPerPixel: Int,
    filter: Int
  ) -> [UInt8] {
    row.indices.map { index in
      let left = index >= bytesPerPixel ? row[index - bytesPerPixel] : 0
      let up = previous[index]
      let upperLeft = index >= bytesPerPixel ? previous[index - bytesPerPixel] : 0
      let prediction: UInt8
      switch filter {
      case 0: prediction = 0
      case 1: prediction = left
      case 2: prediction = up
      case 3: prediction = UInt8((Int(left) + Int(up)) / 2)
      default: prediction = paeth(left, up, upperLeft)
      }
      return row[index] &- prediction
    }
  }

  private static func paeth(_ left: UInt8, _ up: UInt8, _ upperLeft: UInt8) -> UInt8 {
    let prediction = Int(left) + Int(up) - Int(upperLeft)
    let leftDistance = abs(prediction - Int(left))
    let upDistance = abs(prediction - Int(up))
    let upperLeftDistance = abs(prediction - Int(upperLeft))
    if leftDistance <= upDistance && leftDistance <= upperLeftDistance { return left }
    if upDistance <= upperLeftDistance { return up }
    return upperLeft
  }

  private static func score(_ bytes: [UInt8]) -> Int {
    bytes.reduce(0) { result, byte in
      result + abs(Int(Int8(bitPattern: byte)))
    }
  }

  private static func unpack(_ data: Data, width: Int) -> [Int] {
    var samples: [Int] = []
    var bitOffset = 0
    while bitOffset + width <= data.count * 8 {
      var sample = 0
      for bit in 0..<width {
        let absolute = bitOffset + bit
        let byte = data[data.index(data.startIndex, offsetBy: absolute / 8)]
        sample = (sample << 1) | Int((byte >> (7 - absolute % 8)) & 1)
      }
      samples.append(sample)
      bitOffset += width
    }
    return samples
  }

  private static func pack(_ samples: [Int], width: Int) -> Data {
    var output = [UInt8](repeating: 0, count: (samples.count * width + 7) / 8)
    var bitOffset = 0
    for sample in samples {
      for bit in 0..<width where sample & (1 << (width - bit - 1)) != 0 {
        let absolute = bitOffset + bit
        output[absolute / 8] |= 1 << (7 - absolute % 8)
      }
      bitOffset += width
    }
    return Data(output)
  }

}
