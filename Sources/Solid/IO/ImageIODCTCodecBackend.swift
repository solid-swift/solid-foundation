//
//  ImageIODCTCodecBackend.swift
//  SolidIO
//
//  Created by Codex on 8/16/26.
//

import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
#endif

struct ImageIODCTCodecBackend: DCTCodecBackend {

  func encode(_ data: Data, options: DCTEncodeOptions) throws -> Data {
    #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
      guard options.colors != 2,
            options.quantizationTables.isEmpty,
            options.huffmanTables.isEmpty,
            options.quantizationFactor == 1
      else {
        throw StreamCodecError.unsupportedOperation
      }
      if options.colors == 3 {
        guard options.colorTransform == 1 else { throw StreamCodecError.unsupportedOperation }
      } else if options.colors == 4 {
        guard options.colorTransform == 0 else { throw StreamCodecError.unsupportedOperation }
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
      CGImageDestinationAddImage(
        destination,
        image,
        [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary
      )
      guard CGImageDestinationFinalize(destination) else { throw StreamCodecError.invalidData }

      let transform = options.colors == 1 ? nil : options.colorTransform
      let encoded = try addingAdobeMarkerIfNeeded(to: output as Data, transform: transform)
      let metadata = try JPEGMetadataParser.parse(encoded)
      guard let metadata,
            metadata.endOffset == encoded.count,
            metadata.width == options.columns,
            metadata.height == options.rows,
            metadata.components.count == options.colors,
            zip(metadata.components, options.horizontalSamples).allSatisfy({
              $0.horizontalSample == $1
            }),
            zip(metadata.components, options.verticalSamples).allSatisfy({
              $0.verticalSample == $1
            }),
            transform == nil || metadata.adobeColorTransform == transform
      else {
        throw StreamCodecError.unsupportedOperation
      }
      return encoded
    #else
      throw StreamCodecError.unsupportedOperation
    #endif
  }

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int
  ) throws -> Data {
    #if canImport(CoreGraphics) && canImport(ImageIO)
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width == metadata.width,
            image.height == metadata.height
      else {
        throw StreamCodecError.invalidData
      }

      let colorSpace: CGColorSpace
      switch outputComponents {
      case 1: colorSpace = CGColorSpaceCreateDeviceGray()
      case 3: colorSpace = CGColorSpaceCreateDeviceRGB()
      case 4: colorSpace = CGColorSpaceCreateDeviceCMYK()
      default: throw StreamCodecError.unsupportedOperation
      }

      let contextComponents = outputComponents == 3 ? 4 : outputComponents
      let (pixels, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
      let (byteCount, byteOverflow) = pixels.multipliedReportingOverflow(by: contextComponents)
      guard !pixelOverflow, !byteOverflow else { throw StreamCodecError.invalidData }
      var rendered = [UInt8](repeating: 0, count: byteCount)
      let bitmapInfo = outputComponents == 3
        ? CGImageAlphaInfo.noneSkipLast.rawValue
        : CGImageAlphaInfo.none.rawValue
      let created = rendered.withUnsafeMutableBytes { buffer in
        CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * contextComponents,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      }
      guard let context = created else { throw StreamCodecError.unsupportedOperation }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      if outputComponents == 3 {
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

  private func addingAdobeMarkerIfNeeded(to data: Data, transform: Int?) throws -> Data {
    guard let transform else { return data }
    guard data.starts(with: [0xFF, 0xD8]) else { throw StreamCodecError.invalidData }
    if let metadata = try JPEGMetadataParser.parse(data),
       let encodedTransform = metadata.adobeColorTransform
    {
      guard encodedTransform == transform else { throw StreamCodecError.unsupportedOperation }
      return data
    }

    let marker = Data([
      0xFF, 0xEE, 0x00, 0x0E,
      0x41, 0x64, 0x6F, 0x62, 0x65,
      0x00, 0x64,
      0x00, 0x00,
      0x00, 0x00,
      UInt8(transform),
    ])
    var result = Data(capacity: data.count + marker.count)
    result.append(data.prefix(2))
    result.append(marker)
    result.append(data.dropFirst(2))
    return result
  }

}
