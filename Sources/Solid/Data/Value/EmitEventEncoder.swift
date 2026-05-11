//
//  EmitEventEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Encodes ``Value`` instances into a stream of ``EmitEvent`` values.
public struct EmitEventEncoder: Sendable {

  public let includeContainerSizes: Bool

  public init(includeContainerSizes: Bool = true) {
    self.includeContainerSizes = includeContainerSizes
  }

  public func encode(_ value: Value) -> [EmitEvent] {
    var events: [EmitEvent] = []
    events.reserveCapacity(estimateEventCount(value))
    encode(value, into: &events)
    return events
  }

  private func estimateEventCount(_ value: Value) -> Int {
    switch value {
    case .array(let array):
      return 2 + array.reduce(0) { $0 + estimateEventCount($1) }
    case .object(let object):
      return 2 + object.reduce(0) { $0 + 1 + estimateEventCount($1.value) }
    case .tagged(let tags, let inner):
      return tags.count + estimateEventCount(inner)
    default:
      return 1
    }
  }

  public func encode(_ value: Value, into events: inout [EmitEvent]) {
    switch value {
    case .tagged(let tags, let inner):
      for tag in tags {
        events.append(.tag(tag))
      }
      encode(inner, into: &events)
    case .array(let array):
      events.append(.beginArray(count: includeContainerSizes ? array.count : nil))
      for item in array {
        encode(item, into: &events)
      }
      events.append(.endArray)
    case .object(let object):
      events.append(.beginObject(count: includeContainerSizes ? object.count : nil))
      for (key, val) in object {
        events.append(.scalar(key))
        encode(val, into: &events)
      }
      events.append(.endObject)
    default:
      events.append(.scalar(value))
    }
  }

  public func emit(_ value: Value, to emit: (EmitEvent) throws -> Void) rethrows {
    switch value {
    case .tagged(let tags, let inner):
      for tag in tags {
        try emit(.tag(tag))
      }
      try self.emit(inner, to: emit)

    case .array(let array):
      try emit(.beginArray(count: includeContainerSizes ? array.count : nil))
      for item in array {
        try self.emit(item, to: emit)
      }
      try emit(.endArray)

    case .object(let object):
      try emit(.beginObject(count: includeContainerSizes ? object.count : nil))
      for (key, val) in object {
        try emit(.scalar(key))
        try self.emit(val, to: emit)
      }
      try emit(.endObject)

    default:
      try emit(.scalar(value))
    }
  }

  public func emit(_ value: Value, to emit: (EmitEvent) async throws -> Void) async rethrows {
    switch value {
    case .tagged(let tags, let inner):
      for tag in tags {
        try await emit(.tag(tag))
      }
      try await self.emit(inner, to: emit)

    case .array(let array):
      try await emit(.beginArray(count: includeContainerSizes ? array.count : nil))
      for item in array {
        try await self.emit(item, to: emit)
      }
      try await emit(.endArray)

    case .object(let object):
      try await emit(.beginObject(count: includeContainerSizes ? object.count : nil))
      for (key, val) in object {
        try await emit(.scalar(key))
        try await self.emit(val, to: emit)
      }
      try await emit(.endObject)

    default:
      try await emit(.scalar(value))
    }
  }
}
