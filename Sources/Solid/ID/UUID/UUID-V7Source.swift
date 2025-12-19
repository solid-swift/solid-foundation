//
//  UUID-V7Source.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation
import SolidTempo


public extension UUID {

  /// Source for UUID v7 following RFC-9562/4122.
  ///
  final class V7Source: UniqueIDSource, Sendable {

    public static let `default` = V7Source()

    public typealias ID = UUID

    private nonisolated(unsafe) var timestampSource: any TimestampSource
    private nonisolated(unsafe) var randomGenerator: any RandomNumberGenerator
    private let q = DispatchQueue(label: "UUID.V7Source")

    public init(
      instantSource: any InstantSource = .system,
      randomGenerator: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
      self.timestampSource = UnixTimestampSource(instantSource: instantSource)
      self.randomGenerator = randomGenerator
    }

    public func generate() -> UUID { q.sync(execute: unsafeGenerate) }

    private func unsafeGenerate() -> UUID {

      let (timestamp, clockSequence) = timestampSource.current(randomGenerator: &randomGenerator)

      do {
        return try UUID { out in

          V7Format.pack(
            timestamp: timestamp,
            clockSequence: clockSequence,
            randomGenerator: &randomGenerator,
            out: &out
          )

          assert(out.count == 16)
        }
      } catch let e {
        fatalError("Failed to initialize UUID: \(e)")
      }
    }
  }

  static func v7() -> UUID { V7Source.default.generate() }
}
