//
//  MediaRanges.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

import SolidNet


/// An ordered collection of HTTP `Accept` media ranges.
public struct MediaRanges {

  private let ranges: [MediaRange]

  /// Creates an ordered collection of media ranges.
  public init(_ ranges: [MediaRange]) {
    self.ranges = ranges.enumerated().map { order, range in
      range.with(order: order)
    }
  }

  /// Parses an HTTP `Accept` header field value.
  public static func parse(_ fieldValue: String) throws -> MediaRanges {
    try MediaRangesParser(fieldValue).parse()
  }

  /// Serializes the ranges as an HTTP `Accept` field value.
  public var serialized: String {
    ranges.map(\.serialized).joined(separator: ",")
  }

  /// Returns the best available media type according to this range collection.
  public func bestMatch(in available: some Sequence<MediaType>) -> MediaType? {
    var best: Match?
    for (availableOrder, mediaType) in available.enumerated() {
      guard let range = preferredRange(for: mediaType), range.quality > 0 else {
        continue
      }

      let match = Match(
        mediaType: mediaType,
        quality: range.quality,
        specificity: specificity(of: range.mediaType),
        rangeOrder: range.order,
        availableOrder: availableOrder
      )
      if best.map({ match.isBetter(than: $0) }) ?? true {
        best = match
      }
    }
    return best?.mediaType
  }

  private func preferredRange(for mediaType: MediaType) -> MediaRange? {
    var preferred: MediaRange?
    for range in ranges where range.mediaType.matches(mediaType) {
      guard let current = preferred else {
        preferred = range
        continue
      }

      let rangeSpecificity = specificity(of: range.mediaType)
      let currentSpecificity = specificity(of: current.mediaType)
      if rangeSpecificity > currentSpecificity ||
        (rangeSpecificity == currentSpecificity && range.order < current.order) {
        preferred = range
      }
    }
    return preferred
  }

  private func specificity(of mediaType: MediaType) -> Int {
    var score = 0
    if mediaType.type != .any {
      score += 100
    }
    if mediaType.subtype != "*" {
      score += 50
    }
    if mediaType.suffix != nil {
      score += 10
    }
    score += mediaType.parameters.count
    return score
  }

  private struct Match {
    let mediaType: MediaType
    let quality: Double
    let specificity: Int
    let rangeOrder: Int
    let availableOrder: Int

    func isBetter(than other: Match) -> Bool {
      if quality != other.quality {
        return quality > other.quality
      }
      if specificity != other.specificity {
        return specificity > other.specificity
      }
      if rangeOrder != other.rangeOrder {
        return rangeOrder < other.rangeOrder
      }
      return availableOrder < other.availableOrder
    }
  }
}

extension MediaRanges: Equatable {}

extension MediaRanges: Sendable {}

extension MediaRanges: Collection {

  /// The collection index type.
  public typealias Index = Array<MediaRange>.Index

  /// The position of the first media range.
  public var startIndex: Index { ranges.startIndex }

  /// The position one past the last media range.
  public var endIndex: Index { ranges.endIndex }

  /// Accesses the media range at the provided position.
  public subscript(position: Index) -> MediaRange {
    ranges[position]
  }

  /// Returns the position immediately after the provided position.
  public func index(after index: Index) -> Index {
    ranges.index(after: index)
  }
}
