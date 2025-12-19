//
//  UUID-Variant.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public extension UUID {

  enum Variant: Sendable {
    case ncs
    case rfc
    case ms
    case future
  }

}
