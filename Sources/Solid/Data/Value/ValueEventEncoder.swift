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
    encode(value, into: &events)
    return events
  }

  public func encode(_ value: Value, into events: inout [ValueEvent]) {
    switch value {
    case .tagged(let tag, let inner):
      events.append(.tag(tag))
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
