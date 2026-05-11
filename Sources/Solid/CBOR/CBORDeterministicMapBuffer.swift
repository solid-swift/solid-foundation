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

struct BufferedPair {
  let keyBytes: Data
  let valueEvents: [EmitEvent]
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
  var currentKeyBytes: Data?
  var keyBuilder: BalancedEmitEventSequenceBuilder?
  var currentValue: BalancedEmitEventSequenceBuilder?

  mutating func handle(_ event: EmitEvent) throws -> MapBufferCompletion? {
    // 1. Currently collecting value events.
    if var builder = currentValue.take() {
      try append(event, to: &builder)
      currentValue = builder
      if builder.isComplete {
        try finalizePair()
      }
      return nil
    }

    // 2. Currently collecting key events (container key).
    if var kBuilder = keyBuilder.take() {
      try append(event, to: &kBuilder)
      if kBuilder.isComplete {
        currentKeyBytes = try deterministicKeyBytes(from: kBuilder.events)
      } else {
        keyBuilder = kBuilder
      }
      return nil
    }

    // 3. Implicit key/value alternation.
    if currentKeyBytes == nil {
      // Expecting a key.
      switch event {
      case .endObject:
        guard pairs.count == expectedPairs else {
          throw CBOREncoder.Error.invalidEventSequence("Missing map entries")
        }
        return MapBufferCompletion(expectedPairs: expectedPairs, pairs: pairs, mode: mode)
      case .scalar(let value):
        currentKeyBytes = try CBOREncoder.encodeValue(value, deterministic: true)
        return nil
      default:
        // Container key — accumulate events.
        var kBuilder = BalancedEmitEventSequenceBuilder()
        try append(event, to: &kBuilder)
        if kBuilder.isComplete {
          currentKeyBytes = try deterministicKeyBytes(from: kBuilder.events)
        } else {
          keyBuilder = kBuilder
        }
        return nil
      }
    } else {
      // Expecting a value.
      if case .endObject = event {
        throw CBOREncoder.Error.invalidEventSequence("Missing value for key")
      }
      var builder = BalancedEmitEventSequenceBuilder()
      try append(event, to: &builder)
      currentValue = builder
      if builder.isComplete {
        try finalizePair()
      }
      return nil
    }
  }

  private func append(
    _ event: EmitEvent,
    to builder: inout BalancedEmitEventSequenceBuilder
  ) throws {
    do {
      try builder.append(event)
    } catch {
      throw CBOREncoder.Error.invalidEventSequence("Unexpected container end")
    }
  }

  private func deterministicKeyBytes(from events: [EmitEvent]) throws -> Data {
    guard canEncodeDeterministically(from: events) else {
      let key = try materializeKey(from: events)
      return try CBOREncoder.encodeValue(key, deterministic: true)
    }
    return try CBOREncoder.encodeEmitEvents(
      events,
      options: .init(
        deterministic: true,
        deterministicMode: .buffered(maxPairs: Int.max, maxBytes: Int.max),
        deterministicBufferedValueEvents: true
      )
    )
  }

  private func canEncodeDeterministically(from events: [EmitEvent]) -> Bool {
    for event in events {
      switch event {
      case .beginArray(count: nil), .beginObject(count: nil):
        return false
      default:
        break
      }
    }
    return true
  }

  private func materializeKey(from events: [EmitEvent]) throws -> Value {
    var decoder = EmitEventDecoder()
    for event in events {
      try decoder.append(event)
    }
    return try decoder.finish()
  }

  private mutating func finalizePair() throws {
    guard let keyBytes = currentKeyBytes, let builder = currentValue else { return }
    let pair = BufferedPair(keyBytes: keyBytes, valueEvents: builder.events, order: pairs.count)
    pairs.append(pair)
    currentKeyBytes = nil
    currentValue = nil
    if pairs.count > expectedPairs {
      throw CBOREncoder.Error.invalidEventSequence("Too many map entries")
    }
  }
}

private extension Optional {
  mutating func take() -> Wrapped? {
    let value = self
    self = nil
    return value
  }
}
