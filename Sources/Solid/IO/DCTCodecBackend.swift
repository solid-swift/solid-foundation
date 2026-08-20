//
//  DCTCodecBackend.swift
//  SolidIO
//
//  Created by Codex on 8/16/26.
//

import Foundation

protocol DCTCodecBackend: Sendable {

  func encode(_ data: Data, options: DCTEncodeOptions) throws -> Data

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int
  ) throws -> Data

}

protocol DCTOptionsCodecBackend: DCTCodecBackend {

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int,
    options: DCTDecodeOptions?
  ) throws -> Data

}

enum DCTCodecBackends {

  static let platform: any DCTCodecBackend = RoutingDCTCodecBackend()

}

private struct RoutingDCTCodecBackend: DCTOptionsCodecBackend {

  private let portable = SolidJPEGDCTCodecBackend()
  private let imageIO = ImageIODCTCodecBackend()

  func encode(_ data: Data, options: DCTEncodeOptions) throws -> Data {
    if imageIO.supportsEncoding(options) { return try imageIO.encode(data, options: options) }
    return try portable.encode(data, options: options)
  }

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int
  ) throws -> Data {
    try decode(data, metadata: metadata, outputComponents: outputComponents, options: nil)
  }

  func decode(
    _ data: Data,
    metadata: JPEGMetadata,
    outputComponents: Int,
    options: DCTDecodeOptions?
  ) throws -> Data {
    if imageIO.supportsDecoding(metadata: metadata, outputComponents: outputComponents, options: options) {
      return try imageIO.decode(data, metadata: metadata, outputComponents: outputComponents)
    }
    return try portable.decode(
      data,
      metadata: metadata,
      outputComponents: outputComponents,
      options: options
    )
  }

}
