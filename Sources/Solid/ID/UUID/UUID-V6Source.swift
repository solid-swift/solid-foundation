//
//  UUID-V6Source.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation
import SolidTempo


public extension UUID {

  /// Source for UUID v6 following RFC-9562/4122.
  ///
  final class V6Source: UniqueIDSource, Sendable {

    public static let `default` = V6Source()

    public typealias ID = UUID

    private nonisolated(unsafe) var timestampFormat: any TimestampSource
    private nonisolated(unsafe) var randomGenerator: any RandomNumberGenerator
    private let nodeID: NodeID
    private let q = DispatchQueue(label: "UUID.V6Source")

    public init(
      instantSource: any InstantSource = .system,
      nodeIDSource: (any NodeIDSource)? = nil,
      randomGenerator: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
      self.timestampFormat = GregorianTimestampSource(instantSource: instantSource)
      self.randomGenerator = randomGenerator
      self.nodeID = (nodeIDSource ?? RandomNodeIDSource(randomGenerator: randomGenerator)).generate()
    }

    public func generate() -> UUID { q.sync(execute: unsafeGenerate) }

    private func unsafeGenerate() -> UUID {

      let (timestamp, clockSequence) = timestampFormat.current(randomGenerator: &randomGenerator)

      return UUID { out in

        V6Format.pack(timestamp: timestamp, clockSequence: clockSequence, nodeID: nodeID, out: &out)

        assert(out.count == 16)
      }
    }
  }

  static func v6() -> UUID { V6Source.default.generate() }
}
