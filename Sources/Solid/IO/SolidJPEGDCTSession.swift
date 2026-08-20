import Foundation
import SolidJPEG

final class SolidJPEGDCTEncoderSession: @unchecked Sendable {

  private var encoder: JPEGEncoder

  init(options: DCTEncodeOptions) throws {
    encoder = JPEGEncoder(
      options: try SolidJPEGDCTCodecBackend().makeEncodingOptions(options)
    )
  }

  func process(_ input: Data) throws -> Data {
    do {
      let result = try input.withUnsafeBytes { buffer in
        try encoder.process(Span(_unsafeElements: buffer.assumingMemoryBound(to: UInt8.self)))
      }
      return Data(result.bytes)
    } catch {
      throw SolidJPEGDCTCodecBackend.translate(error)
    }
  }

  func finish() throws -> Data {
    do {
      return Data(try encoder.finalize())
    } catch {
      throw SolidJPEGDCTCodecBackend.translate(error)
    }
  }

}

final class SolidJPEGDCTDecoderSession: @unchecked Sendable {

  private let metadata: JPEGMetadata
  private let options: DCTDecodeOptions
  private let componentIdentifiers: [UInt8]
  private var decoder: JPEGDecoder
  private var assembled: Data?

  init(options: DCTDecodeOptions, metadata: JPEGMetadata, outputComponents: Int) throws {
    self.metadata = metadata
    self.options = options
    componentIdentifiers = metadata.components.map(\.identifier)
    decoder = JPEGDecoder(
      options: try SolidJPEGDCTCodecBackend().makeDecodingOptions(
        options,
        metadata: metadata,
        outputComponents: outputComponents
      )
    )
  }

  func process(_ input: Data) throws -> IncrementalFilterResult {
    do {
      let result = try input.withUnsafeBytes { buffer in
        try decoder.process(Span(_unsafeElements: buffer.assumingMemoryBound(to: UInt8.self)))
      }
      let output = try consume(result.rows, finished: result.progress == .finished)
      return IncrementalFilterResult(
        output: output,
        consumedInput: result.consumedBytes,
        progress: result.progress == .finished ? .finished : .needsInput
      )
    } catch {
      throw SolidJPEGDCTCodecBackend.translate(error)
    }
  }

  func finish() throws -> Data? {
    do {
      let result = try decoder.finalize()
      return try consume(result.rows, finished: true)
    } catch {
      throw SolidJPEGDCTCodecBackend.translate(error)
    }
  }

  private func consume(_ rows: [JPEGDecodedRows], finished: Bool) throws -> Data {
    var direct = Data()
    for band in rows {
      let identifiers = band.componentIdentifiers.isEmpty
        ? componentIdentifiers
        : band.componentIdentifiers
      guard identifiers.count == band.componentCount else {
        throw StreamCodecError.invalidData
      }
      if identifiers == componentIdentifiers, assembled == nil {
        direct.append(contentsOf: band.samples)
      } else {
        if assembled == nil {
          assembled = Data(repeating: 0, count: metadata.width * metadata.height * componentIdentifiers.count)
        }
        try write(band, identifiers: identifiers)
      }
    }
    if finished, var assembled {
      self.assembled = nil
      try applyColorTransform(to: &assembled)
      return assembled
    }
    return direct
  }

  private func applyColorTransform(to samples: inout Data) throws {
    let count = componentIdentifiers.count
    let transform = metadata.adobeColorTransform ?? options.colorTransform ?? (count == 3 ? 1 : 0)
    guard transform == 0 || transform == 1 || (transform == 2 && count == 4) else {
      throw StreamCodecError.unsupportedOperation
    }
    if (transform == 1 || transform == 2), count >= 3 {
      for offset in stride(from: 0, to: samples.count, by: count) {
        let luminance = Double(samples[offset])
        let blueDifference = Double(Int(samples[offset + 1]) - 128)
        let redDifference = Double(Int(samples[offset + 2]) - 128)
        samples[offset] = UInt8(clamping: Int((luminance + 1.402 * redDifference).rounded()))
        samples[offset + 1] = UInt8(clamping: Int(
          (luminance - 0.344136 * blueDifference - 0.714136 * redDifference).rounded()
        ))
        samples[offset + 2] = UInt8(clamping: Int((luminance + 1.772 * blueDifference).rounded()))
        if count == 4 { samples[offset + 3] = 255 - samples[offset + 3] }
      }
    } else if count == 4, metadata.adobeColorTransform == 0 {
      for offset in samples.indices { samples[offset] = 255 - samples[offset] }
    }
  }

  private func write(_ band: JPEGDecodedRows, identifiers: [UInt8]) throws {
    guard var assembled else { throw StreamCodecError.invalidData }
    let frameComponentCount = componentIdentifiers.count
    let expected = metadata.width * band.rowCount * identifiers.count
    guard band.samples.count == expected,
          band.firstRow >= 0,
          band.firstRow + band.rowCount <= metadata.height
    else {
      throw StreamCodecError.invalidData
    }
    for (bandComponent, identifier) in identifiers.enumerated() {
      guard let frameComponent = componentIdentifiers.firstIndex(of: identifier) else {
        throw StreamCodecError.invalidData
      }
      for row in 0..<band.rowCount {
        for column in 0..<metadata.width {
          let source = (row * metadata.width + column) * identifiers.count + bandComponent
          let destination = ((band.firstRow + row) * metadata.width + column) * frameComponentCount
            + frameComponent
          assembled[destination] = band.samples[source]
        }
      }
    }
    self.assembled = assembled
  }

}
