//
//  JSONStreamEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData

/// Typealias preserving the original name for use by ``JSONStreamWriter`` and ``JSONValueWriter``.
typealias JSONStreamEncoder = BufferedStreamEncoder<JSONEventWriter>

/// Synchronous JSON event writer that serializes ``ValueEvent`` values into bytes.
struct JSONEventWriter: FormatEventWriter {

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
  private var rootState: RootState = .expectingValue
  private var containers: [ContainerState] = []
  private var wrapperStack: [WrapperContext] = []
  private var pendingTags: [Value] = []

  init(options: Options = .default) {
    self.options = options
  }

  public var format: Format { JSON.format }

  // MARK: - FormatEventWriter

  mutating func writeEvent(_ event: ValueEvent, into output: inout Data) throws {
    swap(&buffer, &output)
    defer { swap(&buffer, &output) }
    try writeEventImpl(event)
  }

  mutating func finishWriting(into output: inout Data) throws {
    guard containers.isEmpty, wrapperStack.isEmpty, pendingTags.isEmpty, rootState == .complete else {
      throw Error.incompleteJSON
    }
  }

  // MARK: - Event Implementation

  private mutating func writeEventImpl(_ event: ValueEvent) throws {
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
    guard !containers.isEmpty else {
      throw Error.invalidEventSequence("Key outside object")
    }
    let idx = containers.count - 1
    guard case .object(let hasPairs, let expectingKey) = containers[idx] else {
      throw Error.invalidEventSequence("Key outside object")
    }
    guard expectingKey else {
      throw Error.invalidEventSequence("Unexpected key")
    }
    containers[idx] = .object(hasPairs: hasPairs, expectingKey: false)
  }

  private mutating func finishValue() throws {
    if containers.isEmpty {
      rootState = .complete
      return
    }
    let idx = containers.count - 1
    switch containers[idx] {
    case .array:
      break  // no state change needed
    case .object(_, let expectingKey):
      guard !expectingKey else {
        throw Error.invalidEventSequence("Unexpected value")
      }
      containers[idx] = .object(hasPairs: true, expectingKey: true)
    }
  }

  private mutating func prepareForValue(isKey: Bool) throws {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw Error.invalidEventSequence("Multiple root values")
      }
      return
    }

    let idx = containers.count - 1
    switch containers[idx] {
    case .array(let hasElements):
      if hasElements {
        appendByte(JSONStructure.elementSeparator)
      }
      containers[idx] = .array(hasElements: true)

    case .object(let hasPairs, let expectingKey):
      if isKey {
        guard expectingKey else {
          throw Error.invalidEventSequence("Unexpected key")
        }
        if hasPairs {
          appendByte(JSONStructure.elementSeparator)
        }
        containers[idx] = .object(hasPairs: hasPairs, expectingKey: true)
      } else {
        guard !expectingKey else {
          throw Error.invalidEventSequence("Unexpected value")
        }
        containers[idx] = .object(hasPairs: hasPairs, expectingKey: false)
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
    case .tagged(let tags, let value):
      switch options.tagShape {
      case .unwrapped:
        try writeValue(value)
      case .array:
        for tag in tags {
          appendByte(JSONStructure.beginArray)
          try writeValue(tag)
          appendByte(JSONStructure.elementSeparator)
        }
        try writeValue(value)
        for _ in tags {
          appendByte(JSONStructure.endArray)
        }
      case .object(let tagKey, let valueKey):
        for tag in tags {
          appendByte(JSONStructure.beginObject)
          try writeValue(.string(tagKey))
          appendByte(JSONStructure.pairSeparator)
          try writeValue(tag)
          appendByte(JSONStructure.elementSeparator)
          try writeValue(.string(valueKey))
          appendByte(JSONStructure.pairSeparator)
        }
        try writeValue(value)
        for _ in tags {
          appendByte(JSONStructure.endObject)
        }
      case .wrapped:
        for tag in tags {
          appendByte(JSONStructure.beginObject)
          try writeValue(tag)
          appendByte(JSONStructure.pairSeparator)
        }
        try writeValue(value)
        for _ in tags {
          appendByte(JSONStructure.endObject)
        }
      }
    }
  }

  // Pre-computed UTF-8 byte sequences for \u0000 through \u001F control characters.
  // Named escapes (\b, \t, \n, \f, \r) are handled separately; these are the generic \u00XX forms.
  private static let controlCharEscapes: [[UInt8]] = {
    (0...0x1F).map { byte in
      let hi = byte >> 4        // 0 or 1
      let lo = byte & 0x0F
      let hexChars: [UInt8] = [
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,  // '0'-'7'
        0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,  // '8'-'9','a'-'f'
      ]
      // \u00XY
      return [0x5C, 0x75, 0x30, 0x30, hexChars[hi], hexChars[lo]]
    }
  }()

  private mutating func writeString(_ value: String) {
    appendByte(JSONStructure.quotationMark)
    let escapeSlashes = options.escapeSlashes
    var utf8 = value.utf8
    var safeStart = utf8.startIndex
    var i = utf8.startIndex
    while i < utf8.endIndex {
      let byte = utf8[i]
      // Multi-byte UTF-8 sequences (byte >= 0x80) are always safe — include in the run
      if byte >= 0x80 {
        i = utf8.index(after: i)
        continue
      }
      // Check for characters that need escaping
      let escape: ContiguousArray<UInt8>?
      switch byte {
      case 0x22: // "
        escape = [0x5C, 0x22]  // \"
      case 0x5C: // backslash
        escape = [0x5C, 0x5C]  // \\
      case 0x2F where escapeSlashes: // /
        escape = [0x5C, 0x2F]  // \/
      case 0x08: // \b
        escape = [0x5C, 0x62]
      case 0x0C: // \f
        escape = [0x5C, 0x66]
      case 0x0A: // \n
        escape = [0x5C, 0x6E]
      case 0x0D: // \r
        escape = [0x5C, 0x72]
      case 0x09: // \t
        escape = [0x5C, 0x74]
      case 0x00...0x1F: // other control characters
        // Flush safe run before escape
        if safeStart < i {
          buffer.append(contentsOf: utf8[safeStart..<i])
        }
        buffer.append(contentsOf: Self.controlCharEscapes[Int(byte)])
        i = utf8.index(after: i)
        safeStart = i
        continue
      default:
        // Safe ASCII byte (0x20-0x7E excluding " and \)
        i = utf8.index(after: i)
        continue
      }
      // Flush safe run, then write escape sequence
      if safeStart < i {
        buffer.append(contentsOf: utf8[safeStart..<i])
      }
      buffer.append(contentsOf: escape!)
      i = utf8.index(after: i)
      safeStart = i
    }
    // Flush remaining safe run
    if safeStart < utf8.endIndex {
      buffer.append(contentsOf: utf8[safeStart..<utf8.endIndex])
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
}
