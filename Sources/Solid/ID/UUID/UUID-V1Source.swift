//
//  UUID-V1Source.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation
import SolidTempo


public extension UUID {

  /// Generator for UUID v1 following RFC-9562/4122.
  ///
  final class V1Source: UniqueIDSource, Sendable {

    public static let `default` = V1Source()

    public typealias ID = UUID

    private nonisolated(unsafe) var timestampSource: any TimestampSource
    private nonisolated(unsafe) var randomGenerator: any RandomNumberGenerator
    private let nodeID: NodeID
    private let q = DispatchQueue(label: "UUID.V1Source")

    public init(
      instantSource: any InstantSource = .system,
      nodeIDSource: (any NodeIDSource)? = nil,
      randomGenerator: any RandomNumberGenerator = SystemRandomNumberGenerator(),
    ) {
      self.timestampSource = GregorianTimestampSource(instantSource: instantSource)
      self.randomGenerator = randomGenerator
      self.nodeID = (nodeIDSource ?? RandomNodeIDSource(randomGenerator: randomGenerator)).generate()
    }

    public func generate() -> UUID { q.sync(execute: unsafeGenerate) }

    private func unsafeGenerate() -> UUID {

      let (timestamp, clockSequence) = timestampSource.current(randomGenerator: &randomGenerator)

      do {
        return try UUID { out in

          V1Format.pack(timestamp: timestamp, clockSequence: clockSequence, nodeID: nodeID, out: &out)

          assert(out.count == 16)
        }
      } catch let e {
        fatalError("Failed to initialize UUID: \(e)")
      }
    }
  }

  static func v1() -> UUID { V1Source.default.generate() }
}
