//
//  UUID-Constants.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public extension UUID {

  static let `nil` = UUID(storage: Storage(repeating: 0))
  static let max = UUID(storage: Storage(repeating: 0xff))

}
