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
    precondition(
      acceptExtensions.keys.allSatisfy { name in
        MediaTypeTokens.isToken(name) && name.lowercased() != "q"
      },
      "Accept extension names must be tokens and cannot be q"
    )
    var normalizedAcceptExtensionNames = Set<String>()
    precondition(
      acceptExtensions.keys.allSatisfy { name in
        normalizedAcceptExtensionNames.insert(name.lowercased()).inserted
      },
      "Accept extension names must be unique (case-insensitive)"
    )
    precondition(
      acceptExtensions.values.allSatisfy(MediaTypeTokens.canSerializeParameterValue),
      "Accept extension values must be serializable as tokens or quoted strings"
    )

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

  /// Returns the canonical serialized form for this media range.
  public var serialized: String {
    var result = mediaType.serialized
    if quality != 1.0 || !acceptExtensions.isEmpty {
      result += ";q=\(Self.serialize(quality: quality))"
    }
    for key in acceptExtensions.keys.sorted() {
      result += ";\(key)=\(MediaTypeTokens.serializeParameterValue(acceptExtensions[key]!))"
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

  static func parseParameterValue(_ value: String) -> String? {
    MediaTypeTokens.parseParameterValue(value)
  }
}

extension MediaRange: Equatable {}

extension MediaRange: Hashable {}

extension MediaRange: Sendable {}
