//
//  UUID-V4Source.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 10/18/25.
//

import Foundation


public extension UUID {

  /// Source for UUID v4 following RFC-9562/4122.
  ///
  final class V4Source: UniqueIDSource, Sendable {

    public static let `default` = V4Source()

    public typealias ID = UUID

    private nonisolated(unsafe) var randomGenerator: any RandomNumberGenerator
    private let q = DispatchQueue(label: "UUID.V4Source")

    public init(randomGenerator: RandomNumberGenerator = SystemRandomNumberGenerator()) {
      self.randomGenerator = randomGenerator
    }

    public func generate() -> UUID { q.sync(execute: unsafeGenerate) }

    private func unsafeGenerate() -> UUID {
      return UUID { out in
        V4Format.pack(randomGenerator: &randomGenerator, out: &out)
      }
    }
  }

  static func v4() -> UUID { V4Source.default.generate() }
}
