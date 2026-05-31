//
//  HTTPFields+MediaTypes.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

import HTTPTypes
import SolidNet


/// HTTP field helpers for Solid media type values.
public extension HTTPFields {

  /// An error that can occur while using typed HTTP media field helpers.
  enum MediaTypeError: Swift.Error, Equatable, Sendable {
    /// A required `Content-Type` header is missing.
    case missingContentType
  }

  /// Sets the `Content-Type` header field.
  mutating func setContentType(_ mediaType: MediaType) {
    self[.contentType] = mediaType.serialized
  }

  /// Returns the parsed `Content-Type` header field, if present.
  func contentType() throws -> MediaType? {
    guard let value = self[.contentType] else {
      return nil
    }
    return try MediaType.parse(value)
  }

  /// Returns the parsed `Content-Type` header field or throws when it is missing.
  func requireContentType() throws -> MediaType {
    guard let contentType = try contentType() else {
      throw MediaTypeError.missingContentType
    }
    return contentType
  }

  /// Sets the `Accept` header field.
  mutating func setAccept(_ ranges: MediaRanges) {
    self[.accept] = ranges.serialized()
  }

  /// Returns the parsed `Accept` header media ranges.
  func acceptMediaRanges() throws -> MediaRanges {
    try MediaRanges.parse(self[.accept] ?? "*/*")
  }
}
