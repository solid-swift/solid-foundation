//
//  UUID-RandomNodeIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation


public extension UUID {

  /// Generates a random 48-bit node identifier with the multicast bit set,
  /// per RFC 4122/9562 guidance for UUID v1 when a MAC address is not available.
  ///
  final class RandomNodeIDSource: NodeIDSource {

    private var randomGenerator: any RandomNumberGenerator
    private let q = DispatchQueue(label: "RandomNodeIDSource")

    public init(randomGenerator: some RandomNumberGenerator) {
      self.randomGenerator = randomGenerator
    }

    public func generate() -> NodeID { q.sync(execute: unsafeGenerate) }

    private func unsafeGenerate() -> NodeID {
      NodeID { out in
        for _ in 0..<out.capacity {
          out.append(randomGenerator.next())
        }
        // Set multicast bit (least significant bit of the first octet)
        out[0] |= 0x01
      }
    }
  }
}
