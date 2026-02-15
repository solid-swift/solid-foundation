//
//  JSONStreamEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
/// Synchronous JSON stream encoder that consumes ``ValueEvent`` values.
struct JSONStreamEncoder: FormatStreamEncoder {

  public typealias TagShape = JSONValueWriter.Options.TagShape
  typealias Options = JSONStreamWriter.Options
  typealias Error = JSONStreamWriter.Error

  private enum RootState {
    case expectingValue
    case complete
  }

  private enum ContainerState {
    case array(hasElements: Bool)
    case object(hasPairs: Bool, expectingKey: Bool)
  }

  private enum Wrapper {
    case array(tag: Value)
    case object(tagKey: String, valueKey: String, tag: Value)
    case wrapped(tag: Value)
  }

  private struct WrapperContext {
    let wrappers: [Wrapper]
  }

  private let options: Options

  private var buffer = Data()
  private var pendingOffset = 0
  private var rootState: RootState = .expectingValue
  private var containers: [ContainerState] = []
  private var wrapperStack: [WrapperContext] = []
  private var pendingTags: [Value] = []
  private var finished = false
  private var pendingEvent = false

  init(options: Options = .default) {
    self.options = options
  }

  public var format: Format { JSON.format }

  mutating func writeEvent(_ event: ValueEvent) throws {
    guard !finished else {
      throw Error.alreadyFinished
    }

    switch event {
    case .style:
      break

    case .tag(let tag):
      pendingTags.append(tag)

    case .anchor:
      throw Error.invalidEventSequence("Anchors are not supported")

    case .alias:
      throw Error.invalidEventSequence("Aliases are not supported")

    case .key(let key):
      try prepareForValue(isKey: true)
      let wrappers = try openWrappers()
      try writeValue(key)
      try closeWrappers(wrappers)
      appendByte(JSONStructure.pairSeparator)
      try setObjectExpectingValue()

    case .scalar(let value):
      try prepareForValue(isKey: false)
      let wrappers = try openWrappers()
      try writeValue(value)
      try closeWrappers(wrappers)
      try finishValue()

    case .beginArray(_):
      try prepareForValue(isKey: false)
      let wrappers = try openWrappers()
      appendByte(JSONStructure.beginArray)
      containers.append(.array(hasElements: false))
      wrapperStack.append(.init(wrappers: wrappers))

    case .endArray:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .array = containers.popLast() else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      appendByte(JSONStructure.endArray)
      guard let wrappers = wrapperStack.popLast() else {
        throw Error.invalidEventSequence("Missing wrapper context")
      }
      try closeWrappers(wrappers.wrappers)
      try finishValue()

    case .beginObject(_):
      try prepareForValue(isKey: false)
      let wrappers = try openWrappers()
      appendByte(JSONStructure.beginObject)
      containers.append(.object(hasPairs: false, expectingKey: true))
      wrapperStack.append(.init(wrappers: wrappers))

    case .endObject:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .object(let hasPairs, let expectingKey) = containers.popLast() else {
        throw Error.invalidEventSequence("Unexpected endObject")
      }
      guard expectingKey else {
        throw Error.invalidEventSequence("Missing value for key")
      }
      _ = hasPairs
      appendByte(JSONStructure.endObject)
      guard let wrappers = wrapperStack.popLast() else {
        throw Error.invalidEventSequence("Missing wrapper context")
      }
      try closeWrappers(wrappers.wrappers)
      try finishValue()
    }
  }

  private mutating func setObjectExpectingValue() throws {
    guard case .object(let hasPairs, let expectingKey) = containers.popLast() else {
      throw Error.invalidEventSequence("Key outside object")
    }
    guard expectingKey else {
      throw Error.invalidEventSequence("Unexpected key")
    }
    containers.append(.object(hasPairs: hasPairs, expectingKey: false))
  }

  private mutating func finishValue() throws {
    if containers.isEmpty {
      rootState = .complete
      return
    }
    guard let container = containers.popLast() else {
      return
    }
    switch container {
    case .array(let hasElements):
      containers.append(.array(hasElements: hasElements))
    case .object(_, let expectingKey):
      guard !expectingKey else {
        throw Error.invalidEventSequence("Unexpected value")
      }
      containers.append(.object(hasPairs: true, expectingKey: true))
    }
  }

  private mutating func prepareForValue(isKey: Bool) throws {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      return
    }

    let current = containers.removeLast()
    switch current {
    case .array(let hasElements):
      if hasElements {
        appendByte(JSONStructure.elementSeparator)
      }
      containers.append(.array(hasElements: true))

    case .object(let hasPairs, let expectingKey):
      if isKey {
        guard expectingKey else {
          throw Error.invalidEventSequence("Unexpected key")
        }
        if hasPairs {
          appendByte(JSONStructure.elementSeparator)
        }
        containers.append(.object(hasPairs: hasPairs, expectingKey: true))
      } else {
        guard !expectingKey else {
          throw Error.invalidEventSequence("Unexpected value")
        }
        containers.append(.object(hasPairs: hasPairs, expectingKey: false))
      }
    }
  }

  private mutating func openWrappers() throws -> [Wrapper] {
    let tags = pendingTags
    pendingTags.removeAll()

    guard !tags.isEmpty else {
      return []
    }

    var wrappers: [Wrapper] = []
    for tag in tags {
      switch options.tagShape {
      case .unwrapped:
        continue
      case .array:
        appendByte(JSONStructure.beginArray)
        try writeValue(tag)
        appendByte(JSONStructure.elementSeparator)
        wrappers.append(.array(tag: tag))
      case .object(let tagKey, let valueKey):
        appendByte(JSONStructure.beginObject)
        try writeValue(.string(tagKey))
        appendByte(JSONStructure.pairSeparator)
        try writeValue(tag)
        appendByte(JSONStructure.elementSeparator)
        try writeValue(.string(valueKey))
        appendByte(JSONStructure.pairSeparator)
        wrappers.append(.object(tagKey: tagKey, valueKey: valueKey, tag: tag))
      case .wrapped:
        appendByte(JSONStructure.beginObject)
        try writeValue(tag)
        appendByte(JSONStructure.pairSeparator)
        wrappers.append(.wrapped(tag: tag))
      }
    }
    return wrappers
  }

  private mutating func closeWrappers(_ wrappers: [Wrapper]) throws {
    for wrapper in wrappers.reversed() {
      switch wrapper {
      case .array:
        appendByte(JSONStructure.endArray)
      case .object, .wrapped:
        appendByte(JSONStructure.endObject)
      }
    }
  }

  private mutating func writeValue(_ value: Value) throws {
    switch value {
    case .null:
      writeNull()
    case .bool(let bool):
      writeBool(bool)
    case .number(let number):
      writeNumber(number)
    case .bytes(let data):
      writeString(data.base64EncodedString())
    case .string(let string):
      writeString(string)
    case .array(let array):
      appendByte(JSONStructure.beginArray)
      for (idx, item) in array.enumerated() {
        if idx > 0 {
          appendByte(JSONStructure.elementSeparator)
        }
        try writeValue(item)
      }
      appendByte(JSONStructure.endArray)
    case .object(let object):
      appendByte(JSONStructure.beginObject)
      var index = 0
      for (key, val) in object {
        if index > 0 {
          appendByte(JSONStructure.elementSeparator)
        }
        try writeValue(key)
        appendByte(JSONStructure.pairSeparator)
        try writeValue(val)
        index += 1
      }
      appendByte(JSONStructure.endObject)
    case .tagged(let tag, let value):
      switch options.tagShape {
      case .unwrapped:
        try writeValue(value)
      case .array:
        try writeValue(.array([tag, value]))
      case .object(let tagKey, let valueKey):
        var object = Value.Object()
        object[.string(tagKey)] = tag
        object[.string(valueKey)] = value
        try writeValue(.object(object))
      case .wrapped:
        var object = Value.Object()
        object[tag] = value
        try writeValue(.object(object))
      }
    }
  }

  private mutating func writeString(_ value: String) {
    appendByte(JSONStructure.quotationMark)
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"":
        appendString("\\\"")
      case "\\" where options.escapeSlashes:
        appendString("\\\\")
      case "/" where options.escapeSlashes:
        appendString("\\/")
      case "\u{8}":
        appendString("\\b")
      case "\u{c}":
        appendString("\\f")
      case "\n":
        appendString("\\n")
      case "\r":
        appendString("\\r")
      case "\t":
        appendString("\\t")
      case "\u{0}"..."\u{f}":
        appendString("\\u000\(String(scalar.value, radix: 16))")
      case "\u{10}"..."\u{1f}":
        appendString("\\u00\(String(scalar.value, radix: 16))")
      default:
        appendString(String(scalar))
      }
    }
    appendByte(JSONStructure.quotationMark)
  }

  private mutating func writeNumber(_ value: Value.Number) {
    appendString(value.description)
  }

  private mutating func writeBool(_ value: Bool) {
    appendString(value ? "true" : "false")
  }

  private mutating func writeNull() {
    appendString("null")
  }

  private mutating func appendString(_ string: String) {
    appendBytes(string.utf8)
  }

  private mutating func appendBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
    buffer.append(contentsOf: bytes)
  }

  private mutating func appendByte(_ byte: UInt8) {
    buffer.append(byte)
  }

  // MARK: - FormatStreamEncoder

  mutating func encode(_ event: ValueEvent, output: inout OutputSpan<UInt8>) throws -> FormatStreamEncodeStatus {
    if pendingEvent {
      let pendingStatus = drainPending(into: &output)
      if pendingStatus == .needMoreOutputSpace {
        return pendingStatus
      }
      pendingEvent = false
      return .producedOutput
    }

    let pendingStatus = drainPending(into: &output)
    if pendingStatus == .needMoreOutputSpace {
      return pendingStatus
    }

    try writeEvent(event)
    let status = drainPending(into: &output)
    if status == .needMoreOutputSpace {
      pendingEvent = true
    }
    return status
  }

  mutating func finish(output: inout OutputSpan<UInt8>) throws -> FormatStreamEncodeStatus {
    let pendingStatus = drainPending(into: &output)
    if pendingStatus == .needMoreOutputSpace {
      return pendingStatus
    }

    if finished {
      let finalStatus = drainPending(into: &output)
      return finalStatus == .needMoreOutputSpace ? finalStatus : .endOfStream
    }
    guard containers.isEmpty, wrapperStack.isEmpty, pendingTags.isEmpty, rootState == .complete else {
      throw Error.incompleteJSON
    }
    finished = true
    let finalStatus = drainPending(into: &output)
    return finalStatus == .needMoreOutputSpace ? finalStatus : .endOfStream
  }

  private mutating func drainPending(into output: inout OutputSpan<UInt8>) -> FormatStreamEncodeStatus {
    guard pendingOffset < buffer.count else {
      buffer.removeAll(keepingCapacity: true)
      pendingOffset = 0
      return .producedOutput
    }

    guard !output.isFull else { return .needMoreOutputSpace }

    while pendingOffset < buffer.count && !output.isFull {
      output.append(buffer[pendingOffset])
      pendingOffset += 1
    }

    if pendingOffset >= buffer.count {
      buffer.removeAll(keepingCapacity: true)
      pendingOffset = 0
      return .producedOutput
    }

    return .needMoreOutputSpace
  }
}
