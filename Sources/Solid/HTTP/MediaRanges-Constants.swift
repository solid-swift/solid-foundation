//
//  MediaRanges-Constants.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/30/26.
//

import SolidNet


public extension MediaRanges {

  /// Accepts `application/json` and any media type with a `+json` structured suffix.
  static let json = MediaRanges([MediaRange(.json), MediaRange(.anyStructuredJSON)])

  /// Accepts `application/xml` and any media type with a `+xml` structured suffix.
  static let xml = MediaRanges([MediaRange(.xml), MediaRange(.anyStructuredXML)])

  /// Accepts `application/cbor` and any media type with a `+cbor` structured suffix.
  static let cbor = MediaRanges([MediaRange(.cbor), MediaRange(.anyStructuredCBOR)])

  /// Accepts `application/cbor-seq` and any media type with a `+cbor-seq` structured suffix.
  static let cborSequence = MediaRanges([MediaRange(.cborSequence), MediaRange(.anyStructuredCBORSequence)])
}
