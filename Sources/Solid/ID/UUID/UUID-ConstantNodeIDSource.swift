//
//  UUID-ConstantNodeIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/24/25.
//


public extension UUID {

  struct ConstantNodeIDSource: NodeIDSource {

    public var nodeID: NodeID

    public init(nodeID: NodeID) {
      self.nodeID = nodeID
    }

    public func generate() -> UUID.NodeID {
      return nodeID
    }

  }

}
