//
//  UniqueIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//


public protocol UniqueIDSource {

  associatedtype ID: UniqueID

  func generate() -> ID

}
