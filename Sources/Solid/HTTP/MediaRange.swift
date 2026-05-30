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
      result += ";\(key)=\(Self.serializeParameterValue(acceptExtensions[key]!))"
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
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
      return isToken(value) ? value : nil
    }

    var result = ""
    var isEscaped = false
    for character in value.dropFirst().dropLast() {
      if isEscaped {
        result.append(character)
        isEscaped = false
      }
      else if character == "\\" {
        isEscaped = true
      }
      else if character == "\"" {
        return nil
      }
      else {
        result.append(character)
      }
    }
    return isEscaped ? nil : result
  }

  private static func serializeParameterValue(_ value: String) -> String {
    guard !isToken(value) else {
      return value
    }

    var result = "\""
    for character in value {
      if character == "\\" || character == "\"" {
        result.append("\\")
      }
      result.append(character)
    }
    result.append("\"")
    return result
  }

  private static func isToken(_ value: String) -> Bool {
    guard !value.isEmpty else {
      return false
    }
    return value.utf8.allSatisfy(isTokenByte)
  }

  private static func isTokenByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A:
      true
    case 0x21, 0x23 ... 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E:
      true
    default:
      false
    }
  }
}

extension MediaRange: Equatable {}

extension MediaRange: Hashable {}

extension MediaRange: Sendable {}
