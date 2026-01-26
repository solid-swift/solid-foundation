//
//  FormatError.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 1/26/26.
//


/// Common protocol for all format reading/writing errors.
public protocol FormatError: Swift.Error, Sendable {

  associatedtype RelatedFormat: Format

  /// The format that generated this error.
  var format: RelatedFormat { get }
}
