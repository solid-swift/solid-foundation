//
//  ValueEventEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Encodes ``Value`` instances into a stream of ``ValueEvent`` values.
public struct ValueEventEncoder: Sendable {

  public let includeContainerSizes: Bool

  public init(includeContainerSizes: Bool = true) {
    self.includeContainerSizes = includeContainerSizes
  }

  public func encode(_ value: Value) -> [ValueEvent] {
    var events: [ValueEvent] = []
    events.reserveCapacity(estimateEventCount(value))
    encode(value, into: &events)
    return events
  }

  private func estimateEventCount(_ value: Value) -> Int {
    switch value {
    case .array(let array):
      return 2 + array.count  // beginArray + items + endArray
    case .object(let object):
      return 2 + object.count * 2  // beginObject + (key + value) pairs + endObject
    case .tagged(let tags, _):
      return tags.count + 1  // tag events + inner value
    default:
      return 1
    }
  }

  public func encode(_ value: Value, into events: inout [ValueEvent]) {
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
        events.append(.key(key))
        encode(val, into: &events)
      }
      events.append(.endObject)
    default:
      events.append(.scalar(value))
    }
  }
}
