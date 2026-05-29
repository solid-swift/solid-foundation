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
    let parts = splitOutsideQuotes(source, separator: ",")
    var ranges: [MediaRange] = []
    ranges.reserveCapacity(parts.count)

    for (order, rawPart) in parts.enumerated() {
      let range = try parseRange(String(rawPart), order: order)
      ranges.append(range)
    }

    return MediaRanges(ranges)
  }

  private func parseRange(_ source: String, order: Int) throws -> MediaRange {
    let segments = splitOutsideQuotes(source, separator: ";").map {
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

      let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)

      if name == "q", !foundQuality {
        quality = try parseQuality(value)
        foundQuality = true
      }
      else if foundQuality {
        acceptExtensions[name] = value
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
    guard let quality = Double(value), (0.0 ... 1.0).contains(quality) else {
      throw MediaRange.Error.invalidQuality(value)
    }
    return quality
  }

  private func splitOutsideQuotes(_ value: String, separator: Character) -> [String] {
    var parts: [String] = []
    var current = ""
    var isQuoted = false
    var isEscaped = false

    for character in value {
      if character == separator, !isQuoted {
        parts.append(current)
        current = ""
      }
      else {
        current.append(character)
        if character == "\"" && !isEscaped {
          isQuoted.toggle()
        }
        isEscaped = character == "\\" && !isEscaped
      }
    }

    parts.append(current)
    return parts
  }
}
