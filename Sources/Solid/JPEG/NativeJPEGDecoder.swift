private struct JPEGDecodedPlane {
  let component: JPEGComponent
  let blockColumns: Int
  let blockRows: Int
  let stride: Int
  var samples: [UInt8]
}

enum NativeJPEGDecoder {

  static func decode(bytes: [UInt8], options: JPEGDecodingOptions) throws -> JPEGDecodingResult {
    let image = try JPEGParser.parse(bytes: bytes, options: options)
    let components = image.metadata.components
    let maximumHorizontal = components.map(\.sampling.horizontal).max() ?? 1
    let maximumVertical = components.map(\.sampling.vertical).max() ?? 1
    let mcuColumns = JPEGCodecUtilities.ceilDivide(
      image.metadata.width,
      by: maximumHorizontal * 8
    )
    let mcuRows = JPEGCodecUtilities.ceilDivide(
      image.metadata.height,
      by: maximumVertical * 8
    )
    let mcuCount = mcuColumns * mcuRows
    guard mcuCount <= options.limits.maximumMCUs else { throw JPEGError.limitExceeded }

    var allocatedBytes = 0
    var planes: [JPEGDecodedPlane] = try components.map { component in
      let blockColumns = JPEGCodecUtilities.ceilDivide(
        image.metadata.width * component.sampling.horizontal,
        by: maximumHorizontal * 8
      )
      let blockRows = JPEGCodecUtilities.ceilDivide(
        image.metadata.height * component.sampling.vertical,
        by: maximumVertical * 8
      )
      let paddedBlockColumns = mcuColumns * component.sampling.horizontal
      let paddedBlockRows = mcuRows * component.sampling.vertical
      let (sampleCount, overflow) = (paddedBlockColumns * 8).multipliedReportingOverflow(
        by: paddedBlockRows * 8
      )
      guard !overflow, sampleCount <= options.limits.maximumScratchBytes - allocatedBytes else {
        throw JPEGError.limitExceeded
      }
      allocatedBytes += sampleCount
      return JPEGDecodedPlane(
        component: component,
        blockColumns: blockColumns,
        blockRows: blockRows,
        stride: paddedBlockColumns * 8,
        samples: [UInt8](repeating: 0, count: sampleCount)
      )
    }

    var decodedComponents = Set<UInt8>()
    for parsedScan in image.scans {
      try decode(
        parsedScan,
        image: image,
        mcuColumns: mcuColumns,
        mcuRows: mcuRows,
        planes: &planes
      )
      decodedComponents.formUnion(parsedScan.scan.components.map(\.identifier))
    }
    guard decodedComponents == Set(components.map(\.identifier)) else {
      throw JPEGError.invalidData
    }

    let output = try interleave(
      planes: planes,
      metadata: image.metadata,
      options: options,
      maximumHorizontal: maximumHorizontal,
      maximumVertical: maximumVertical
    )
    return JPEGDecodingResult(
      metadata: image.metadata,
      rows: [
        JPEGDecodedRows(
          firstRow: 0,
          rowCount: image.metadata.height,
          componentCount: components.count,
          samples: output,
          componentIdentifiers: components.map(\.identifier)
        )
      ],
      consumedBytes: image.consumedBytes,
      progress: .finished
    )
  }

  private static func decode(
    _ parsedScan: JPEGParsedScan,
    image: JPEGParsedImage,
    mcuColumns: Int,
    mcuRows: Int,
    planes: inout [JPEGDecodedPlane]
  ) throws {
    var reader = JPEGEntropyBitReader(bytes: parsedScan.entropyBytes)
    var predictors = [Int](repeating: 0, count: planes.count)
    var coefficients = [Int](repeating: 0, count: 64)
    var blockSamples = [UInt8](repeating: 0, count: 64)
    var mcuIndex = 0
    var restartIndex: UInt8 = 0
    let codingTables = try Dictionary(
      uniqueKeysWithValues: parsedScan.scan.components.map { scanComponent in
        let frameIndex = try componentIndex(scanComponent.identifier, in: image.metadata.components)
        return (
          scanComponent.identifier,
          try blockCodingTables(
            scanComponent: scanComponent,
            frameComponent: image.metadata.components[frameIndex],
            image: image
          )
        )
      }
    )

    let totalMCUs: Int
    if parsedScan.scan.components.count == 1 {
      let scanComponent = parsedScan.scan.components[0]
      let frameIndex = try componentIndex(scanComponent.identifier, in: image.metadata.components)
      totalMCUs = planes[frameIndex].blockColumns * planes[frameIndex].blockRows
      for blockY in 0..<planes[frameIndex].blockRows {
        for blockX in 0..<planes[frameIndex].blockColumns {
          try decodeBlock(
            reader: &reader,
            frameIndex: frameIndex,
            codingTables: codingTables[scanComponent.identifier]!,
            predictors: &predictors,
            coefficients: &coefficients,
            blockSamples: &blockSamples
          )
          writeBlock(blockSamples, blockX: blockX, blockY: blockY, plane: &planes[frameIndex])
          mcuIndex += 1
          try consumeRestartIfNeeded(
            mcuIndex: mcuIndex,
            totalMCUs: totalMCUs,
            interval: parsedScan.restartInterval,
            restartIndex: &restartIndex,
            predictors: &predictors,
            reader: &reader
          )
        }
      }
    } else {
      totalMCUs = mcuColumns * mcuRows
      for mcuY in 0..<mcuRows {
        for mcuX in 0..<mcuColumns {
          for scanComponent in parsedScan.scan.components {
            let frameIndex = try componentIndex(scanComponent.identifier, in: image.metadata.components)
            let component = image.metadata.components[frameIndex]
            for vertical in 0..<component.sampling.vertical {
              for horizontal in 0..<component.sampling.horizontal {
                try decodeBlock(
                  reader: &reader,
                  frameIndex: frameIndex,
                  codingTables: codingTables[scanComponent.identifier]!,
                  predictors: &predictors,
                  coefficients: &coefficients,
                  blockSamples: &blockSamples
                )
                writeBlock(
                  blockSamples,
                  blockX: mcuX * component.sampling.horizontal + horizontal,
                  blockY: mcuY * component.sampling.vertical + vertical,
                  plane: &planes[frameIndex]
                )
              }
            }
          }
          mcuIndex += 1
          try consumeRestartIfNeeded(
            mcuIndex: mcuIndex,
            totalMCUs: totalMCUs,
            interval: parsedScan.restartInterval,
            restartIndex: &restartIndex,
            predictors: &predictors,
            reader: &reader
          )
        }
      }
    }
  }

  private static func decodeBlock(
    reader: inout JPEGEntropyBitReader,
    frameIndex: Int,
    codingTables: JPEGBlockCodingTables,
    predictors: inout [Int],
    coefficients: inout [Int],
    blockSamples: inout [UInt8]
  ) throws {
    for index in 0..<64 { coefficients[index] = 0 }
    let dcCategory = Int(try codingTables.dc.decode(from: &reader))
    guard dcCategory <= 11 else { throw JPEGError.invalidData }
    let dcBits = try reader.readBits(count: dcCategory)
    let difference = JPEGCodecUtilities.decodedMagnitude(dcBits, category: dcCategory)
    predictors[frameIndex] += difference
    coefficients[0] = predictors[frameIndex] * codingTables.quantization[0]

    var zigzagIndex = 1
    while zigzagIndex < 64 {
      let symbol = Int(try codingTables.ac.decode(from: &reader))
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
      let value = JPEGCodecUtilities.decodedMagnitude(bits, category: category)
      let naturalIndex = JPEGConstants.zigzag[zigzagIndex]
      coefficients[naturalIndex] = value * codingTables.quantization[naturalIndex]
      zigzagIndex += 1
    }
    JPEGDCT.inverse(coefficients: coefficients, samples: &blockSamples)
  }

  private static func blockCodingTables(
    scanComponent: JPEGScanComponent,
    frameComponent: JPEGComponent,
    image: JPEGParsedImage
  ) throws -> JPEGBlockCodingTables {
    guard let quantization = image.quantizationTables[frameComponent.quantizationTable],
          let dcTable = image.huffmanTables[
            JPEGHuffmanKey(tableClass: .dc, identifier: scanComponent.dcTable)
          ],
          let acTable = image.huffmanTables[
            JPEGHuffmanKey(tableClass: .ac, identifier: scanComponent.acTable)
          ]
    else {
      throw JPEGError.invalidData
    }
    return try JPEGBlockCodingTables(
      quantization: JPEGCodecUtilities.naturalQuantization(quantization),
      dc: JPEGHuffmanCodec(table: dcTable),
      ac: JPEGHuffmanCodec(table: acTable)
    )
  }

  private static func writeBlock(
    _ block: [UInt8],
    blockX: Int,
    blockY: Int,
    plane: inout JPEGDecodedPlane
  ) {
    for y in 0..<8 {
      let destination = (blockY * 8 + y) * plane.stride + blockX * 8
      for x in 0..<8 { plane.samples[destination + x] = block[y * 8 + x] }
    }
  }

  private static func consumeRestartIfNeeded(
    mcuIndex: Int,
    totalMCUs: Int,
    interval: Int,
    restartIndex: inout UInt8,
    predictors: inout [Int],
    reader: inout JPEGEntropyBitReader
  ) throws {
    guard interval > 0, mcuIndex < totalMCUs, mcuIndex.isMultiple(of: interval) else { return }
    try reader.consumeRestart(restartIndex)
    restartIndex = (restartIndex + 1) & 7
    predictors = [Int](repeating: 0, count: predictors.count)
  }

  private static func interleave(
    planes: [JPEGDecodedPlane],
    metadata: JPEGMetadata,
    options: JPEGDecodingOptions,
    maximumHorizontal: Int,
    maximumVertical: Int
  ) throws -> [UInt8] {
    let count = metadata.components.count
    let outputCount = metadata.width * metadata.height * count
    guard outputCount <= options.limits.maximumOutputBytes else { throw JPEGError.limitExceeded }
    let effectiveTransform = metadata.adobeColorTransform
      ?? options.colorTransform?.rawValue
      ?? (count == 3 ? JPEGColorTransform.yCbCr.rawValue : JPEGColorTransform.none.rawValue)
    guard effectiveTransform == 0 || effectiveTransform == 1 || (effectiveTransform == 2 && count == 4)
    else {
      throw JPEGError.unsupportedFeature("color transform")
    }
    var output = [UInt8](repeating: 0, count: outputCount)
    var values = [Int](repeating: 0, count: count)
    for y in 0..<metadata.height {
      for x in 0..<metadata.width {
        for componentIndex in 0..<count {
          let component = metadata.components[componentIndex]
          let componentX = x * component.sampling.horizontal / maximumHorizontal
          let componentY = y * component.sampling.vertical / maximumVertical
          values[componentIndex] = Int(
            planes[componentIndex].samples[componentY * planes[componentIndex].stride + componentX]
          )
        }
        let base = (y * metadata.width + x) * count
        if (effectiveTransform == 1 || effectiveTransform == 2), count >= 3 {
          let converted = convertYCbCr(values)
          if effectiveTransform == 2 {
            output[base] = UInt8(converted.0)
            output[base + 1] = UInt8(converted.1)
            output[base + 2] = UInt8(converted.2)
          } else {
            output[base] = UInt8(converted.0)
            output[base + 1] = UInt8(converted.1)
            output[base + 2] = UInt8(converted.2)
          }
          if count == 4 {
            output[base + 3] = UInt8(effectiveTransform == 2 ? 255 - values[3] : values[3])
          }
        } else if count == 4, metadata.adobeColorTransform == 0 {
          for componentIndex in 0..<count {
            output[base + componentIndex] = UInt8(255 - values[componentIndex])
          }
        } else {
          for componentIndex in 0..<count {
            output[base + componentIndex] = UInt8(values[componentIndex])
          }
        }
      }
    }
    return output
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

  private static func componentIndex(_ identifier: UInt8, in components: [JPEGComponent]) throws -> Int {
    guard let index = components.firstIndex(where: { $0.identifier == identifier }) else {
      throw JPEGError.invalidData
    }
    return index
  }

}
