//
//  UUID-Version.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public extension UUID {

  enum Version: UInt8, Sendable {
    case null = 0
    case v1 = 1
    case v3 = 3
    case v4 = 4
    case v5 = 5
    case v6 = 6
    case v7 = 7
    case v8 = 8
    case unknown = 0xf
  }

}

public extension UUID.Version {

  var nibble: UInt8 {
    rawValue << 4
  }

}
