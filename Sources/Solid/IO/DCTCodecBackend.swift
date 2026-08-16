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

enum DCTCodecBackends {

  static let platform: any DCTCodecBackend = ImageIODCTCodecBackend()

}
