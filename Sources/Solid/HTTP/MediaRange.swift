//
//  MediaRange.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

import Foundation
import SolidNet


/// A single HTTP `Accept` media range.
public struct MediaRange {

  /// An error that can occur while parsing or using media ranges.
  public enum Error: Swift.Error, Equatable, Sendable {
    /// The media range is malformed.
    case invalid(String)
    /// The quality value is malformed or outside `0...1`.
    case invalidQuality(String)
    /// A required `Content-Type` header is missing.
    case missingContentType
  }

  /// The media type pattern for this range.
  public let mediaType: MediaType

  /// The HTTP quality weight in the range `0...1`.
  public let quality: Double

  /// The original order of this range in its header field.
  public let order: Int

  /// Accept extension parameters that appear after the `q` separator.
  public let acceptExtensions: [String: String]

  /// Creates a media range.
  public init(
    _ mediaType: MediaType,
    quality: Double = 1.0,
    order: Int = 0,
    acceptExtensions: [String: String] = [:]
  ) {
    precondition((0.0 ... 1.0).contains(quality), "Media range quality must be in 0...1")
    self.mediaType = mediaType
    self.quality = quality
    self.order = order
    self.acceptExtensions = Dictionary(
      uniqueKeysWithValues: acceptExtensions.map { key, value in
        (key.lowercased(), value)
      }
    )
  }

  func with(order: Int) -> MediaRange {
    MediaRange(mediaType, quality: quality, order: order, acceptExtensions: acceptExtensions)
  }

  var serialized: String {
    var result = mediaType.serialized
    if quality != 1.0 || !acceptExtensions.isEmpty {
      result += ";q=\(Self.serialize(quality: quality))"
    }
    for key in acceptExtensions.keys.sorted() {
      result += ";\(key)=\(acceptExtensions[key]!)"
    }
    return result
  }

  private static func serialize(quality: Double) -> String {
    let rounded = (quality * 1000).rounded() / 1000
    var value = String(format: "%.3f", rounded)
    while value.last == "0" {
      value.removeLast()
    }
    if value.last == "." {
      value.removeLast()
    }
    return value
  }
}

extension MediaRange: Equatable {}

extension MediaRange: Hashable {}

extension MediaRange: Sendable {}
