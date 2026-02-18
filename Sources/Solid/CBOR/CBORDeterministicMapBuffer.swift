//
//  CBORDeterministicMapBuffer.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/18/26.
//

import Foundation
import SolidData

/// Buffers map key-value pairs during encoding so they can be
/// sorted by encoded key bytes for deterministic CBOR output.

struct ValueEventSequenceBuilder {
  var events: [ValueEvent] = []
  private var depth = 0
  private(set) var isComplete = false

  mutating func append(_ event: ValueEvent) throws {
    events.append(event)
    switch event {
    case .beginArray, .beginObject:
      depth += 1
    case .endArray, .endObject:
      depth -= 1
      if depth < 0 {
        throw CBOREncoder.Error.invalidEventSequence("Unexpected container end")
      }
      if depth == 0 {
        isComplete = true
      }
    case .scalar:
      if depth == 0 {
        isComplete = true
      }
    case .key:
      if depth == 0 {
        throw CBOREncoder.Error.invalidEventSequence("Key outside object")
      }
    default:
      break
    }
  }
}

struct BufferedPair {
  let key: Value
  let keyBytes: Data
  let valueEvents: [ValueEvent]
  let order: Int
}

struct MapBufferCompletion {
  let expectedPairs: Int
  let pairs: [BufferedPair]
  let mode: CBOREncoder.DeterministicMode
}

struct MapBuffer {
  let expectedPairs: Int
  let mode: CBOREncoder.DeterministicMode
  var pairs: [BufferedPair] = []
  var pendingKey: Value?
  var currentValue: ValueEventSequenceBuilder?

  mutating func handle(_ event: ValueEvent) throws -> MapBufferCompletion? {
    if var builder = currentValue {
      try builder.append(event)
      currentValue = builder
      if builder.isComplete {
        try finalizePair()
      }
      return nil
    }

    switch event {
    case .key(let key):
      guard pendingKey == nil else {
        throw CBOREncoder.Error.invalidEventSequence("Missing value for key")
      }
      pendingKey = key
      return nil
    case .endObject:
      guard pendingKey == nil else {
        throw CBOREncoder.Error.invalidEventSequence("Missing value for key")
      }
      guard pairs.count == expectedPairs else {
        throw CBOREncoder.Error.invalidEventSequence("Missing map entries")
      }
      return MapBufferCompletion(expectedPairs: expectedPairs, pairs: pairs, mode: mode)
    default:
      guard pendingKey != nil else {
        throw CBOREncoder.Error.invalidEventSequence("Value without key")
      }
      var builder = ValueEventSequenceBuilder()
      try builder.append(event)
      currentValue = builder
      if builder.isComplete {
        try finalizePair()
      }
      return nil
    }
  }

  private mutating func finalizePair() throws {
    guard let key = pendingKey, let builder = currentValue else { return }
    let keyBytes = try CBOREncoder.encodeValue(key, deterministic: true)
    let pair = BufferedPair(key: key, keyBytes: keyBytes, valueEvents: builder.events, order: pairs.count)
    pairs.append(pair)
    pendingKey = nil
    currentValue = nil
    if pairs.count > expectedPairs {
      throw CBOREncoder.Error.invalidEventSequence("Too many map entries")
    }
  }
}
