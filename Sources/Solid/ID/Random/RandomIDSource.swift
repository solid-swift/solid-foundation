//
//  RandomIDSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/20/25.
//

import SolidCore
import Dispatch


public final class RandomIDSource<Value: FixedWidthInteger & UnsignedInteger & Sendable>: UniqueIDSource, Sendable {

  public typealias ID = RandomID<Value>

  private nonisolated(unsafe) var randomGenerator: any RandomNumberGenerator
  private let queue: DispatchQueue

  public init(
    randomGenerator: some RandomNumberGenerator = SystemRandomNumberGenerator(),
    queue: DispatchQueue = DispatchQueue(label: "RandomID.Source")
  ) {
    self.randomGenerator = randomGenerator
    self.queue = queue
  }

  public func generate() -> RandomID<Value> { queue.sync(execute: unsafeGenerate) }

  private func unsafeGenerate() -> RandomID<Value> { RandomID(randomGenerator: &randomGenerator) }

}


private let defaultRandomIDSourceQueue = DispatchQueue(label: "RandomID.Sources")


public extension RandomID where Value == UInt {

  static let uintSource = RandomIDSource<Value>(queue: defaultRandomIDSourceQueue)

}

public extension RandomID where Value == UInt8 {

  static let uint8Source = RandomIDSource<Value>(queue: defaultRandomIDSourceQueue)

}

public extension RandomID where Value == UInt16 {

  static let uint16Source = RandomIDSource<Value>(queue: defaultRandomIDSourceQueue)

}

public extension RandomID where Value == UInt32 {

  static let uint32Source = RandomIDSource<Value>(queue: defaultRandomIDSourceQueue)

}

public extension RandomID where Value == UInt64 {

  static let uint64Source = RandomIDSource<Value>(queue: defaultRandomIDSourceQueue)

}

public extension RandomID where Value == UInt128 {

  static let uint128Source = RandomIDSource<Value>(queue: defaultRandomIDSourceQueue)

}
