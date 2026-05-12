//
//  EmitEventCursor.swift
//  SolidFoundation
//
//  Created by Codex on 5/11/26.
//

/// Pull-based source of ``EmitEvent`` values.
public protocol EmitEventCursor {

  mutating func next() throws -> EmitEvent?
}


/// Event cursor backed by an existing event array.
public struct BufferedEmitEventCursor: EmitEventCursor {

  private var events: ArraySlice<EmitEvent>

  public init(_ events: [EmitEvent]) {
    self.events = events[...]
  }

  public mutating func next() throws -> EmitEvent? {
    guard !events.isEmpty else { return nil }
    return events.removeFirst()
  }
}


/// Event cursor that traverses a ``Value`` without prebuilding the full event stream.
public struct ValueEmitEventCursor: EmitEventCursor {

  private enum Frame {
    case value(Value)
    case tags(tags: [Value], index: Int, value: Value)
    case array(IndexingIterator<Value.Array>)
    case object(iterator: Value.Object.Iterator, pendingValue: Value?)
    case endArray
    case endObject
  }

  private let includeContainerSizes: Bool
  private var stack: [Frame]

  public init(_ value: Value, includeContainerSizes: Bool = true) {
    self.includeContainerSizes = includeContainerSizes
    self.stack = [.value(value)]
  }

  public mutating func next() throws -> EmitEvent? {
    while let frame = stack.popLast() {
      switch frame {
      case .value(let value):
        if let event = push(value) {
          return event
        }

      case .tags(let tags, let index, let value):
        guard index < tags.count else {
          stack.append(.value(value))
          continue
        }
        stack.append(.tags(tags: tags, index: index + 1, value: value))
        return .tag(tags[index])

      case .array(var iterator):
        guard let value = iterator.next() else {
          continue
        }
        stack.append(.array(iterator))
        stack.append(.value(value))

      case .object(var iterator, let pendingValue):
        if let pendingValue {
          stack.append(.object(iterator: iterator, pendingValue: nil))
          stack.append(.value(pendingValue))
          continue
        }
        guard let entry = iterator.next() else {
          continue
        }
        stack.append(.object(iterator: iterator, pendingValue: entry.value))
        return .scalar(entry.key)

      case .endArray:
        return .endArray

      case .endObject:
        return .endObject
      }
    }

    return nil
  }

  private mutating func push(_ value: Value) -> EmitEvent? {
    switch value {
    case .tagged(let tags, let inner):
      guard !tags.isEmpty else {
        stack.append(.value(inner))
        return nil
      }
      stack.append(.tags(tags: tags, index: 1, value: inner))
      return .tag(tags[0])

    case .array(let array):
      stack.append(.endArray)
      stack.append(.array(array.makeIterator()))
      return .beginArray(count: includeContainerSizes ? array.count : nil)

    case .object(let object):
      stack.append(.endObject)
      stack.append(.object(iterator: object.makeIterator(), pendingValue: nil))
      return .beginObject(count: includeContainerSizes ? object.count : nil)

    default:
      return .scalar(value)
    }
  }
}
