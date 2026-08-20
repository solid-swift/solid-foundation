//
//  JPEGMetadata.swift
//  SolidIO
//
//  Created by Codex on 8/16/26.
//

import Foundation

struct JPEGMetadata: Equatable, Sendable {

  struct Component: Equatable, Sendable {
    let identifier: UInt8
    let horizontalSample: Int
    let verticalSample: Int
    let quantizationTable: Int
  }

  let width: Int
  let height: Int
  let precision: Int
  let components: [Component]
  let adobeColorTransform: Int?
  let hasJFIFMarker: Bool
  let scanCount: Int
  let endOffset: Int?

  var decodedByteCount: Int? {
    let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: components.count)
    return pixelOverflow || byteOverflow ? nil : bytes
  }

}

enum JPEGMetadataParser {

  private struct State {
    var frame: JPEGFrame?
    var adobeColorTransform: Int?
    var hasJFIFMarker = false
    var scanCount = 0
    var scannedComponents = Set<UInt8>()
    var quantizationTables = Set<Int>()
    var dcHuffmanTables = Set<Int>()
    var acHuffmanTables = Set<Int>()
  }

  private struct JPEGFrame {
    let width: Int
    var height: Int
    let precision: Int
    let components: [JPEGMetadata.Component]
  }

  static func parse(
    _ data: Data,
    externalQuantizationTables: Set<Int> = [],
    externalDCTables: Set<Int> = [],
    externalACTables: Set<Int> = []
  ) throws -> JPEGMetadata? {
    guard data.count >= 2 else { return nil }
    guard data[0] == 0xFF, data[1] == 0xD8 else { throw StreamCodecError.invalidData }

    var index = 2
    var inScan = false
    var state = State(
      quantizationTables: externalQuantizationTables,
      dcHuffmanTables: externalDCTables,
      acHuffmanTables: externalACTables
    )

    while index < data.count {
      guard let marker = try nextMarker(in: data, index: &index, inScan: &inScan) else {
        return metadata(from: state, endOffset: nil)
      }

      switch marker {
      case 0xD9:
        guard let metadata = metadata(from: state, endOffset: index),
              metadata.height > 0,
              state.scanCount > 0,
              state.scannedComponents == Set(metadata.components.map(\.identifier))
        else {
          throw StreamCodecError.invalidData
        }
        return metadata

      case 0xD8, 0xD0...0xD7:
        throw StreamCodecError.invalidData

      case 0x01:
        continue

      default:
        guard index + 2 <= data.count else { return metadata(from: state, endOffset: nil) }
        let length = integer16(data, at: index)
        guard length >= 2 else { throw StreamCodecError.invalidData }
        guard index + length <= data.count else { return metadata(from: state, endOffset: nil) }
        let payload = (index + 2)..<(index + length)
        try consume(marker: marker, payload: payload, data: data, state: &state)
        index += length
        inScan = marker == 0xDA
      }
    }

    return metadata(from: state, endOffset: nil)
  }

  private static func nextMarker(
    in data: Data,
    index: inout Int,
    inScan: inout Bool
  ) throws -> UInt8? {
    if inScan {
      while index < data.count {
        guard data[index] == 0xFF else {
          index += 1
          continue
        }
        while index < data.count, data[index] == 0xFF { index += 1 }
        guard index < data.count else { return nil }
        let marker = data[index]
        index += 1
        if marker == 0x00 || (0xD0...0xD7).contains(marker) { continue }
        inScan = false
        return marker
      }
      return nil
    }

    guard data[index] == 0xFF else { throw StreamCodecError.invalidData }
    while index < data.count, data[index] == 0xFF { index += 1 }
    guard index < data.count else { return nil }
    let marker = data[index]
    index += 1
    return marker
  }

  private static func consume(
    marker: UInt8,
    payload: Range<Int>,
    data: Data,
    state: inout State
  ) throws {
    switch marker {
    case 0xC0:
      guard state.frame == nil else { throw StreamCodecError.invalidData }
      state.frame = try parseFrame(marker: marker, payload: payload, data: data)

    case 0xC1...0xC3, 0xC5...0xC7, 0xC9...0xCB, 0xCD...0xCF:
      throw StreamCodecError.unsupportedOperation

    case 0xC4:
      try parseHuffmanTables(payload: payload, data: data, state: &state)

    case 0xCC:
      throw StreamCodecError.unsupportedOperation

    case 0xDB:
      try parseQuantizationTables(payload: payload, data: data, state: &state)

    case 0xDA:
      try parseScan(payload: payload, data: data, state: &state)

    case 0xDC:
      guard payload.count == 2,
            var frame = state.frame,
            frame.height == 0,
            state.scanCount > 0
      else {
        throw StreamCodecError.invalidData
      }
      let height = integer16(data, at: payload.lowerBound)
      guard height > 0 else { throw StreamCodecError.invalidData }
      frame.height = height
      state.frame = frame

    case 0xE0:
      state.hasJFIFMarker = state.hasJFIFMarker
        || (payload.count >= 5
          && data[payload.lowerBound..<(payload.lowerBound + 5)] == Data("JFIF\0".utf8))

    case 0xEE:
      if payload.count >= 12,
         data[payload.lowerBound..<(payload.lowerBound + 5)] == Data("Adobe".utf8)
      {
        let transform = Int(data[payload.lowerBound + 11])
        guard (0...2).contains(transform) else { throw StreamCodecError.invalidData }
        if let current = state.adobeColorTransform, current != transform {
          throw StreamCodecError.invalidData
        }
        state.adobeColorTransform = transform
      }

    default:
      break
    }
  }

  private static func parseFrame(
    marker: UInt8,
    payload: Range<Int>,
    data: Data
  ) throws -> JPEGFrame {
    guard payload.count >= 6 else { throw StreamCodecError.invalidData }
    let precision = Int(data[payload.lowerBound])
    let height = integer16(data, at: payload.lowerBound + 1)
    let width = integer16(data, at: payload.lowerBound + 3)
    let count = Int(data[payload.lowerBound + 5])
    guard precision == 8,
          width > 0,
          (1...4).contains(count),
          payload.count == 6 + count * 3
    else {
      throw StreamCodecError.invalidData
    }

    var identifiers = Set<UInt8>()
    var components: [JPEGMetadata.Component] = []
    var sampleTotal = 0
    for componentIndex in 0..<count {
      let offset = payload.lowerBound + 6 + componentIndex * 3
      let identifier = data[offset]
      let samples = data[offset + 1]
      let horizontalSample = Int(samples >> 4)
      let verticalSample = Int(samples & 0x0F)
      let quantizationTable = Int(data[offset + 2])
      guard identifiers.insert(identifier).inserted,
            (1...4).contains(horizontalSample),
            (1...4).contains(verticalSample),
            (0...3).contains(quantizationTable)
      else {
        throw StreamCodecError.invalidData
      }
      sampleTotal += horizontalSample * verticalSample
      components.append(
        JPEGMetadata.Component(
          identifier: identifier,
          horizontalSample: horizontalSample,
          verticalSample: verticalSample,
          quantizationTable: quantizationTable
        )
      )
    }
    guard sampleTotal <= 10 else { throw StreamCodecError.invalidData }
    return JPEGFrame(
      width: width,
      height: height,
      precision: precision,
      components: components
    )
  }

  private static func parseQuantizationTables(
    payload: Range<Int>,
    data: Data,
    state: inout State
  ) throws {
    var index = payload.lowerBound
    while index < payload.upperBound {
      let descriptor = data[index]
      index += 1
      let precision = Int(descriptor >> 4)
      let identifier = Int(descriptor & 0x0F)
      guard precision == 0, (0...3).contains(identifier), index + 64 <= payload.upperBound else {
        throw StreamCodecError.invalidData
      }
      state.quantizationTables.insert(identifier)
      index += 64
    }
  }

  private static func parseHuffmanTables(
    payload: Range<Int>,
    data: Data,
    state: inout State
  ) throws {
    var index = payload.lowerBound
    while index < payload.upperBound {
      let descriptor = data[index]
      index += 1
      let tableClass = Int(descriptor >> 4)
      let identifier = Int(descriptor & 0x0F)
      guard (0...1).contains(tableClass),
            (0...3).contains(identifier),
            index + 16 <= payload.upperBound
      else {
        throw StreamCodecError.invalidData
      }
      let symbolCount = data[index..<(index + 16)].reduce(0) { $0 + Int($1) }
      index += 16
      guard symbolCount <= 256, index + symbolCount <= payload.upperBound else {
        throw StreamCodecError.invalidData
      }
      if tableClass == 0 {
        state.dcHuffmanTables.insert(identifier)
      } else {
        state.acHuffmanTables.insert(identifier)
      }
      index += symbolCount
    }
  }

  private static func parseScan(
    payload: Range<Int>,
    data: Data,
    state: inout State
  ) throws {
    guard let frame = state.frame, payload.count >= 4 else { throw StreamCodecError.invalidData }
    let componentCount = Int(data[payload.lowerBound])
    guard (1...frame.components.count).contains(componentCount),
          payload.count == 1 + componentCount * 2 + 3,
          state.scanCount < 64
    else {
      throw StreamCodecError.invalidData
    }

    var identifiers = Set<UInt8>()
    for componentIndex in 0..<componentCount {
      let offset = payload.lowerBound + 1 + componentIndex * 2
      let identifier = data[offset]
      let tables = data[offset + 1]
      let dcTable = Int(tables >> 4)
      let acTable = Int(tables & 0x0F)
      guard frame.components.contains(where: { $0.identifier == identifier }),
            identifiers.insert(identifier).inserted,
            !state.scannedComponents.contains(identifier),
            state.dcHuffmanTables.contains(dcTable),
            state.acHuffmanTables.contains(acTable)
      else {
        throw StreamCodecError.invalidData
      }
    }

    let spectralOffset = payload.upperBound - 3
    guard data[spectralOffset] == 0,
          data[spectralOffset + 1] == 63,
          data[spectralOffset + 2] == 0,
          frame.components.allSatisfy({ state.quantizationTables.contains($0.quantizationTable) })
    else {
      throw StreamCodecError.invalidData
    }
    state.scannedComponents.formUnion(identifiers)
    state.scanCount += 1
  }

  private static func metadata(from state: State, endOffset: Int?) -> JPEGMetadata? {
    guard let frame = state.frame else { return nil }
    return JPEGMetadata(
      width: frame.width,
      height: frame.height,
      precision: frame.precision,
      components: frame.components,
      adobeColorTransform: state.adobeColorTransform,
      hasJFIFMarker: state.hasJFIFMarker,
      scanCount: state.scanCount,
      endOffset: endOffset
    )
  }

  private static func integer16(_ data: Data, at index: Int) -> Int {
    Int(data[index]) << 8 | Int(data[index + 1])
  }

}
