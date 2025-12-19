//
//  UUID-NodeIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/22/25.
//


public extension UUID {

  protocol NodeIDSource {

    func generate() -> UUID.NodeID

  }

}
