//
//  UniqueIDStringEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//


public protocol UniqueIDStringEncoding {

  associatedtype ID: UniqueID

  func encode(_ id: ID) -> String
  func decode(_ string: String) throws -> ID

}
