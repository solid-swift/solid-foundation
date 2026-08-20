private struct JPEGStreamingDecodedPlane {
  let frameIndex: Int
  let component: JPEGComponent
  let stride: Int
  var samples: ContiguousArray<UInt8>
}

struct JPEGStreamingScanDecoder {

  private let metadata: JPEGMetadata
  private let options: JPEGDecodingOptions
  private let scan: JPEGScan
  private let restartInterval: Int
  private let maximumHorizontal: Int
  private let maximumVertical: Int
  private let mcuColumns: Int
  private let mcuRows: Int
  private let scanColumns: Int
  private let totalMCUs: Int
  private let codingTables: [UInt8: JPEGBlockCodingTables]
  private var reader = JPEGIncrementalEntropyReader()
  private var planes: [JPEGStreamingDecodedPlane]
  private var predictors: [Int]
  private var coefficients = [Int](repeating: 0, count: 64)
  private var blockSamples = [UInt8](repeating: 0, count: 64)
  private var mcuIndex = 0
  private var restartIndex: UInt8 = 0
  private var bandIndex = 0

  init(
    metadata: JPEGMetadata,
    options: JPEGDecodingOptions,
    scan: JPEGScan,
    restartInterval: Int,
    quantizationTables: [UInt8: JPEGQuantizationTable],
    huffmanTables: [JPEGHuffmanKey: JPEGHuffmanTable]
  ) throws {
    self.metadata = metadata
    self.options = options
    self.scan = scan
    self.restartInterval = restartInterval
    maximumHorizontal = metadata.components.map(\.sampling.horizontal).max() ?? 1
    maximumVertical = metadata.components.map(\.sampling.vertical).max() ?? 1
    mcuColumns = JPEGCodecUtilities.ceilDivide(metadata.width, by: maximumHorizontal * 8)
    mcuRows = JPEGCodecUtilities.ceilDivide(metadata.height, by: maximumVertical * 8)
    if scan.components.count == 1 {
      let frameIndex = try Self.componentIndex(scan.components[0].identifier, in: metadata.components)
      let component = metadata.components[frameIndex]
      scanColumns = JPEGCodecUtilities.ceilDivide(
        metadata.width * component.sampling.horizontal,
        by: maximumHorizontal * 8
      )
      let scanRows = JPEGCodecUtilities.ceilDivide(
        metadata.height * component.sampling.vertical,
        by: maximumVertical * 8
      )
      totalMCUs = scanColumns * scanRows
    } else {
      scanColumns = mcuColumns
      totalMCUs = mcuColumns * mcuRows
    }
    guard totalMCUs <= options.limits.maximumMCUs else { throw JPEGError.limitExceeded }
    codingTables = try Dictionary(
      uniqueKeysWithValues: scan.components.map { scanComponent in
        let frameIndex = try Self.componentIndex(scanComponent.identifier, in: metadata.components)
        let frameComponent = metadata.components[frameIndex]
        guard let quantization = quantizationTables[frameComponent.quantizationTable],
              let dcTable = huffmanTables[
                JPEGHuffmanKey(tableClass: .dc, identifier: scanComponent.dcTable)
              ],
              let acTable = huffmanTables[
                JPEGHuffmanKey(tableClass: .ac, identifier: scanComponent.acTable)
              ]
        else {
          throw JPEGError.invalidData
        }
        return (
          scanComponent.identifier,
          try JPEGBlockCodingTables(
            quantization: JPEGCodecUtilities.naturalQuantization(quantization),
            dc: JPEGHuffmanCodec(table: dcTable),
            ac: JPEGHuffmanCodec(table: acTable)
          )
        )
      }
    )
    predictors = [Int](repeating: 0, count: metadata.components.count)
    var allocatedBytes = 0
    planes = []
    for scanComponent in scan.components {
      let frameIndex = try Self.componentIndex(scanComponent.identifier, in: metadata.components)
      let component = metadata.components[frameIndex]
      let stride = mcuColumns * component.sampling.horizontal * 8
      let rows = component.sampling.vertical * 8
      let (sampleCount, overflow) = stride.multipliedReportingOverflow(by: rows)
      guard !overflow, sampleCount <= options.limits.maximumScratchBytes - allocatedBytes else {
        throw JPEGError.limitExceeded
      }
      allocatedBytes += sampleCount
      planes.append(JPEGStreamingDecodedPlane(
        frameIndex: frameIndex,
        component: component,
        stride: stride,
        samples: ContiguousArray(repeating: 0, count: sampleCount)
      ))
    }
  }

  var isFinished: Bool { mcuIndex == totalMCUs }

  var scratchHighWaterMark: Int {
    planes.reduce(0, { $0 + $1.samples.capacity })
      + reader.bufferedByteCount
      + coefficients.capacity * MemoryLayout<Int>.stride
      + blockSamples.capacity
  }

  mutating func process<S: Sequence>(_ bytes: S) throws -> [JPEGDecodedRows] where S.Element == UInt8 {
    reader.append(contentsOf: bytes)
    var rows: [JPEGDecodedRows] = []
    while mcuIndex < totalMCUs {
      let checkpoint = reader.checkpoint()
      let savedPredictors = predictorSnapshot
      let savedRestartIndex = restartIndex
      do {
        try decodeMCU()
        mcuIndex += 1
        if restartInterval > 0,
           mcuIndex < totalMCUs,
           mcuIndex.isMultiple(of: restartInterval)
        {
          try reader.consumeRestart(restartIndex)
          restartIndex = (restartIndex + 1) & 7
          for index in predictors.indices { predictors[index] = 0 }
        }
      } catch JPEGError.truncatedData {
        reader.restore(checkpoint)
        restorePredictors(savedPredictors)
        restartIndex = savedRestartIndex
        break
      }
      if mcuIndex.isMultiple(of: scanColumns) {
        let scanRow = mcuIndex / scanColumns
        let rowsPerBand = scan.components.count == 1
          ? metadata.components[planes[0].frameIndex].sampling.vertical
          : 1
        if scan.components.count > 1 || scanRow.isMultiple(of: rowsPerBand) || mcuIndex == totalMCUs {
          rows.append(try emitBand())
          bandIndex += 1
          reader.compact()
        }
      }
    }
    return rows
  }

  mutating func finishScan() -> [UInt8] {
    reader.finishScan()
  }

  private mutating func decodeMCU() throws {
    if scan.components.count == 1 {
      let blockX = mcuIndex % scanColumns
      let absoluteBlockY = mcuIndex / scanColumns
      let component = planes[0].component
      let localBlockY = absoluteBlockY - bandIndex * component.sampling.vertical
      try decodeBlock(scanComponent: scan.components[0], planeIndex: 0)
      writeBlock(blockX: blockX, blockY: localBlockY, planeIndex: 0)
      return
    }

    let mcuX = mcuIndex % mcuColumns
    for (planeIndex, scanComponent) in scan.components.enumerated() {
      let component = planes[planeIndex].component
      for vertical in 0..<component.sampling.vertical {
        for horizontal in 0..<component.sampling.horizontal {
          try decodeBlock(scanComponent: scanComponent, planeIndex: planeIndex)
          writeBlock(
            blockX: mcuX * component.sampling.horizontal + horizontal,
            blockY: vertical,
            planeIndex: planeIndex
          )
        }
      }
    }
  }

  private mutating func decodeBlock(
    scanComponent: JPEGScanComponent,
    planeIndex: Int
  ) throws {
    for index in 0..<64 { coefficients[index] = 0 }
    let tables = codingTables[scanComponent.identifier]!
    let frameIndex = planes[planeIndex].frameIndex
    let dcCategory = Int(try tables.dc.decode(from: &reader))
    guard dcCategory <= 11 else { throw JPEGError.invalidData }
    let dcBits = try reader.readBits(count: dcCategory)
    predictors[frameIndex] += JPEGCodecUtilities.decodedMagnitude(dcBits, category: dcCategory)
    coefficients[0] = predictors[frameIndex] * tables.quantization[0]
    var zigzagIndex = 1
    while zigzagIndex < 64 {
      let symbol = Int(try tables.ac.decode(from: &reader))
      if symbol == 0 { break }
      let run = symbol >> 4
      let category = symbol & 0x0F
      if category == 0 {
        guard run == 15 else { throw JPEGError.invalidData }
        zigzagIndex += 16
        guard zigzagIndex <= 64 else { throw JPEGError.invalidData }
        continue
      }
      guard category <= 10 else { throw JPEGError.invalidData }
      zigzagIndex += run
      guard zigzagIndex < 64 else { throw JPEGError.invalidData }
      let bits = try reader.readBits(count: category)
      let naturalIndex = JPEGConstants.zigzag[zigzagIndex]
      coefficients[naturalIndex] = JPEGCodecUtilities.decodedMagnitude(bits, category: category)
        * tables.quantization[naturalIndex]
      zigzagIndex += 1
    }
    JPEGDCT.inverse(coefficients: coefficients, samples: &blockSamples)
  }

  private mutating func writeBlock(blockX: Int, blockY: Int, planeIndex: Int) {
    for y in 0..<8 {
      let destination = (blockY * 8 + y) * planes[planeIndex].stride + blockX * 8
      for x in 0..<8 { planes[planeIndex].samples[destination + x] = blockSamples[y * 8 + x] }
    }
  }

  private func emitBand() throws -> JPEGDecodedRows {
    let firstRow = bandIndex * maximumVertical * 8
    let rowCount = min(maximumVertical * 8, metadata.height - firstRow)
    let identifiers = scan.components.map(\.identifier)
    let componentCount = identifiers.count
    let (pixelCount, overflow) = metadata.width.multipliedReportingOverflow(by: rowCount)
    let (outputCount, outputOverflow) = pixelCount.multipliedReportingOverflow(by: componentCount)
    guard !overflow, !outputOverflow, outputCount <= options.limits.maximumOutputBytes else {
      throw JPEGError.limitExceeded
    }
    var output = [UInt8](repeating: 0, count: outputCount)
    var values = [Int](repeating: 0, count: componentCount)
    let isCompleteFrame = Set(identifiers) == Set(metadata.components.map(\.identifier))
      && componentCount == metadata.components.count
    let effectiveTransform = metadata.adobeColorTransform
      ?? options.colorTransform?.rawValue
      ?? (componentCount == 3 ? JPEGColorTransform.yCbCr.rawValue : JPEGColorTransform.none.rawValue)
    for y in 0..<rowCount {
      for x in 0..<metadata.width {
        for planeIndex in planes.indices {
          let component = planes[planeIndex].component
          let componentX = x * component.sampling.horizontal / maximumHorizontal
          let componentY = y * component.sampling.vertical / maximumVertical
          values[planeIndex] = Int(
            planes[planeIndex].samples[componentY * planes[planeIndex].stride + componentX]
          )
        }
        let base = (y * metadata.width + x) * componentCount
        if isCompleteFrame, (effectiveTransform == 1 || effectiveTransform == 2), componentCount >= 3 {
          let converted = Self.convertYCbCr(values)
          output[base] = UInt8(converted.0)
          output[base + 1] = UInt8(converted.1)
          output[base + 2] = UInt8(converted.2)
          if componentCount == 4 {
            output[base + 3] = UInt8(effectiveTransform == 2 ? 255 - values[3] : values[3])
          }
        } else if isCompleteFrame, componentCount == 4, metadata.adobeColorTransform == 0 {
          for index in 0..<componentCount { output[base + index] = UInt8(255 - values[index]) }
        } else {
          for index in 0..<componentCount { output[base + index] = UInt8(values[index]) }
        }
      }
    }
    return JPEGDecodedRows(
      firstRow: firstRow,
      rowCount: rowCount,
      componentCount: componentCount,
      samples: output,
      componentIdentifiers: identifiers
    )
  }

  private var predictorSnapshot: (Int, Int, Int, Int) {
    (
      predictors.indices.contains(0) ? predictors[0] : 0,
      predictors.indices.contains(1) ? predictors[1] : 0,
      predictors.indices.contains(2) ? predictors[2] : 0,
      predictors.indices.contains(3) ? predictors[3] : 0
    )
  }

  private mutating func restorePredictors(_ snapshot: (Int, Int, Int, Int)) {
    if predictors.indices.contains(0) { predictors[0] = snapshot.0 }
    if predictors.indices.contains(1) { predictors[1] = snapshot.1 }
    if predictors.indices.contains(2) { predictors[2] = snapshot.2 }
    if predictors.indices.contains(3) { predictors[3] = snapshot.3 }
  }

  private static func componentIndex(_ identifier: UInt8, in components: [JPEGComponent]) throws -> Int {
    guard let index = components.firstIndex(where: { $0.identifier == identifier }) else {
      throw JPEGError.invalidData
    }
    return index
  }

  private static func convertYCbCr(_ values: [Int]) -> (Int, Int, Int) {
    let luminance = Double(values[0])
    let blueDifference = Double(values[1] - 128)
    let redDifference = Double(values[2] - 128)
    let red = JPEGDCT.clampByte(Int((luminance + 1.402 * redDifference).rounded()))
    let green = JPEGDCT.clampByte(
      Int((luminance - 0.344136 * blueDifference - 0.714136 * redDifference).rounded())
    )
    let blue = JPEGDCT.clampByte(Int((luminance + 1.772 * blueDifference).rounded()))
    return (Int(red), Int(green), Int(blue))
  }

}
