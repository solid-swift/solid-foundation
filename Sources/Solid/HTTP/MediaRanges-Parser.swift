//
//  MediaRanges-Parser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

import Foundation
import SolidNet


struct MediaRangesParser {

  private let source: String

  init(_ source: String) {
    self.source = source
  }

  func parse() throws -> MediaRanges {
    let parts = MediaTypeTokens.splitOutsideQuotes(source, separator: ",")
    var ranges: [MediaRange] = []
    ranges.reserveCapacity(parts.count)

    for (order, rawPart) in parts.enumerated() {
      let range = try parseRange(String(rawPart), order: order)
      ranges.append(range)
    }

    return MediaRanges(ranges)
  }

  private func parseRange(_ source: String, order: Int) throws -> MediaRange {
    let segments = MediaTypeTokens.splitOutsideQuotes(source, separator: ";").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let typeSegment = segments.first, !typeSegment.isEmpty else {
      throw MediaRange.Error.invalid(source)
    }

    var mediaParameters: [String] = []
    var quality = 1.0
    var acceptExtensions: [String: String] = [:]
    var foundQuality = false

    for segment in segments.dropFirst() {
      guard !segment.isEmpty else {
        throw MediaRange.Error.invalid(source)
      }

      let pair = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard pair.count == 2 else {
        throw MediaRange.Error.invalid(source)
      }

      let name = String(pair[0]).lowercased()
      let value = String(pair[1])

      guard MediaTypeTokens.isToken(name) else {
        throw MediaRange.Error.invalid(source)
      }

      if name == "q" {
        guard !foundQuality else {
          throw MediaRange.Error.invalidQuality(value)
        }
        quality = try parseQuality(value)
        foundQuality = true
      }
      else if foundQuality {
        guard let parsedValue = MediaRange.parseParameterValue(value) else {
          throw MediaRange.Error.invalid(source)
        }
        acceptExtensions[name] = parsedValue
      }
      else {
        mediaParameters.append(segment)
      }
    }

    let mediaTypeSource =
      ([typeSegment] + mediaParameters).joined(separator: ";")
    guard let mediaType = MediaType(mediaTypeSource) else {
      throw MediaRange.Error.invalid(source)
    }

    return MediaRange(
      mediaType,
      quality: quality,
      order: order,
      acceptExtensions: acceptExtensions
    )
  }

  private func parseQuality(_ value: String) throws -> Double {
    guard Self.isQualityValue(value), let quality = Double(value) else {
      throw MediaRange.Error.invalidQuality(value)
    }
    return quality
  }

  private static func isQualityValue(_ value: String) -> Bool {
    guard let first = value.first, first == "0" || first == "1" else {
      return false
    }
    guard value.count == 1 || value.dropFirst().first == "." else {
      return false
    }

    let fraction = value.dropFirst(2)
    guard fraction.count <= 3 else {
      return false
    }

    if first == "1" {
      return fraction.allSatisfy { $0 == "0" }
    }
    return fraction.allSatisfy(Self.isDigit)
  }

  private static func isDigit(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
      return false
    }
    return (48 ... 57).contains(scalar.value)
  }

}
