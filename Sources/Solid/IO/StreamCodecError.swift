//
//  StreamCodecError.swift
//  SolidIO
//
//  Created by Codex on 8/15/26.
//

/// An error produced by a reusable stream codec.
public enum StreamCodecError: Error, Equatable, Sendable {

  /// The encoded stream is malformed.
  case invalidData

  /// The encoded stream ended before its required end marker or payload.
  case truncatedData

  /// A codec option is outside the supported format range.
  case invalidOption(String)

  /// The codec is not available on the current platform.
  case unsupportedOperation

}
