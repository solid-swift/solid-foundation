//
//  JSONStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
import SolidIO


/// Async JSON stream writer that consumes ``ValueEvent`` values.
public final class JSONStreamWriter: FormatStreamWriter {

  public typealias TagShape = JSONValueWriter.Options.TagShape

  public struct Options: Sendable {

    public static let `default` = Self()

    public var tagShape: TagShape
    public var escapeSlashes: Bool

    public init(tagShape: TagShape = .unwrapped, escapeSlashes: Bool = false) {
      self.tagShape = tagShape
      self.escapeSlashes = escapeSlashes
    }
  }

  public enum Error: Swift.Error {
    case invalidEventSequence(String)
    case incompleteJSON
    case alreadyFinished
  }

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

  private let sink: any Sink
  private let bufferSize: Int
  private let options: Options

  private var buffer = Data()
  private var rootState: RootState = .expectingValue
  private var containers: [ContainerState] = []
  private var wrapperStack: [WrapperContext] = []
  private var pendingTags: [Value] = []
  private var finished = false

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public var format: Format { JSON.format }

  public func write(_ event: ValueEvent) async throws {
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
      try await prepareForValue(isKey: true)
      let wrappers = try await openWrappers()
      try await writeValue(key)
      try await closeWrappers(wrappers)
      try await appendByte(JSONStructure.pairSeparator)
      try setObjectExpectingValue()

    case .scalar(let value):
      try await prepareForValue(isKey: false)
      let wrappers = try await openWrappers()
      try await writeValue(value)
      try await closeWrappers(wrappers)
      try finishValue()

    case .beginArray:
      try await prepareForValue(isKey: false)
      let wrappers = try await openWrappers()
      try await appendByte(JSONStructure.beginArray)
      containers.append(.array(hasElements: false))
      wrapperStack.append(.init(wrappers: wrappers))

    case .endArray:
      guard pendingTags.isEmpty else {
        throw Error.invalidEventSequence("Tag without value")
      }
      guard case .array = containers.popLast() else {
        throw Error.invalidEventSequence("Unexpected endArray")
      }
      try await appendByte(JSONStructure.endArray)
      guard let wrappers = wrapperStack.popLast() else {
        throw Error.invalidEventSequence("Missing wrapper context")
      }
      try await closeWrappers(wrappers.wrappers)
      try finishValue()

    case .beginObject:
      try await prepareForValue(isKey: false)
      let wrappers = try await openWrappers()
      try await appendByte(JSONStructure.beginObject)
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
      try await appendByte(JSONStructure.endObject)
      guard let wrappers = wrapperStack.popLast() else {
        throw Error.invalidEventSequence("Missing wrapper context")
      }
      try await closeWrappers(wrappers.wrappers)
      try finishValue()
    }
  }

  public func finish() async throws {
    guard !finished else {
      throw Error.alreadyFinished
    }
    guard containers.isEmpty, wrapperStack.isEmpty, pendingTags.isEmpty, rootState == .complete else {
      throw Error.incompleteJSON
    }
    try await flush()
    finished = true
  }

  public func close() async throws {
    try await finish()
    try await sink.close()
  }

  public func flush() async throws {
    guard !buffer.isEmpty else { return }
    try await sink.write(data: buffer)
    buffer.removeAll(keepingCapacity: true)
  }

  private func setObjectExpectingValue() throws {
    guard case .object(let hasPairs, let expectingKey) = containers.popLast() else {
      throw Error.invalidEventSequence("Key outside object")
    }
    guard expectingKey else {
      throw Error.invalidEventSequence("Unexpected key")
    }
    containers.append(.object(hasPairs: hasPairs, expectingKey: false))
  }

  private func finishValue() throws {
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

  private func prepareForValue(isKey: Bool) async throws {
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
        try await appendByte(JSONStructure.elementSeparator)
      }
      containers.append(.array(hasElements: true))

    case .object(let hasPairs, let expectingKey):
      if isKey {
        guard expectingKey else {
          throw Error.invalidEventSequence("Unexpected key")
        }
        if hasPairs {
          try await appendByte(JSONStructure.elementSeparator)
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

  private func openWrappers() async throws -> [Wrapper] {
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
        try await appendByte(JSONStructure.beginArray)
        try await writeValue(tag)
        try await appendByte(JSONStructure.elementSeparator)
        wrappers.append(.array(tag: tag))
      case .object(let tagKey, let valueKey):
        try await appendByte(JSONStructure.beginObject)
        try await writeValue(.string(tagKey))
        try await appendByte(JSONStructure.pairSeparator)
        try await writeValue(tag)
        try await appendByte(JSONStructure.elementSeparator)
        try await writeValue(.string(valueKey))
        try await appendByte(JSONStructure.pairSeparator)
        wrappers.append(.object(tagKey: tagKey, valueKey: valueKey, tag: tag))
      case .wrapped:
        try await appendByte(JSONStructure.beginObject)
        try await writeValue(tag)
        try await appendByte(JSONStructure.pairSeparator)
        wrappers.append(.wrapped(tag: tag))
      }
    }
    return wrappers
  }

  private func closeWrappers(_ wrappers: [Wrapper]) async throws {
    for wrapper in wrappers.reversed() {
      switch wrapper {
      case .array:
        try await appendByte(JSONStructure.endArray)
      case .object, .wrapped:
        try await appendByte(JSONStructure.endObject)
      }
    }
  }

  private func writeValue(_ value: Value) async throws {
    switch value {
    case .null:
      try await writeNull()
    case .bool(let bool):
      try await writeBool(bool)
    case .number(let number):
      try await writeNumber(number)
    case .bytes(let data):
      try await writeString(data.base64EncodedString())
    case .string(let string):
      try await writeString(string)
    case .array(let array):
      try await appendByte(JSONStructure.beginArray)
      for (idx, item) in array.enumerated() {
        if idx > 0 {
          try await appendByte(JSONStructure.elementSeparator)
        }
        try await writeValue(item)
      }
      try await appendByte(JSONStructure.endArray)
    case .object(let object):
      try await appendByte(JSONStructure.beginObject)
      var index = 0
      for (key, val) in object {
        if index > 0 {
          try await appendByte(JSONStructure.elementSeparator)
        }
        try await writeValue(key)
        try await appendByte(JSONStructure.pairSeparator)
        try await writeValue(val)
        index += 1
      }
      try await appendByte(JSONStructure.endObject)
    case .tagged(let tag, let value):
      switch options.tagShape {
      case .unwrapped:
        try await writeValue(value)
      case .array:
        try await writeValue(.array([tag, value]))
      case .object(let tagKey, let valueKey):
        var object = Value.Object()
        object[.string(tagKey)] = tag
        object[.string(valueKey)] = value
        try await writeValue(.object(object))
      case .wrapped:
        var object = Value.Object()
        object[tag] = value
        try await writeValue(.object(object))
      }
    }
  }

  private func writeString(_ value: String) async throws {
    try await appendByte(JSONStructure.quotationMark)
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"":
        try await appendString("\\\"")
      case "\\" where options.escapeSlashes:
        try await appendString("\\\\")
      case "/" where options.escapeSlashes:
        try await appendString("\\/")
      case "\u{8}":
        try await appendString("\\b")
      case "\u{c}":
        try await appendString("\\f")
      case "\n":
        try await appendString("\\n")
      case "\r":
        try await appendString("\\r")
      case "\t":
        try await appendString("\\t")
      case "\u{0}"..."\u{f}":
        try await appendString("\\u000\(String(scalar.value, radix: 16))")
      case "\u{10}"..."\u{1f}":
        try await appendString("\\u00\(String(scalar.value, radix: 16))")
      default:
        try await appendString(String(scalar))
      }
    }
    try await appendByte(JSONStructure.quotationMark)
  }

  private func writeNumber(_ value: Value.Number) async throws {
    try await appendString(value.description)
  }

  private func writeBool(_ value: Bool) async throws {
    try await appendString(value ? "true" : "false")
  }

  private func writeNull() async throws {
    try await appendString("null")
  }

  private func appendString(_ string: String) async throws {
    try await appendBytes(string.utf8)
  }

  private func appendBytes<S: Sequence>(_ bytes: S) async throws where S.Element == UInt8 {
    buffer.append(contentsOf: bytes)
    if buffer.count >= bufferSize {
      try await flush()
    }
  }

  private func appendByte(_ byte: UInt8) async throws {
    buffer.append(byte)
    if buffer.count >= bufferSize {
      try await flush()
    }
  }
}
