//
//  YAMLStreamEncoder.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidCore
import SolidData
/// Typealias preserving the original name for use by ``YAMLStreamWriter`` and ``YAMLValueWriter``.
typealias YAMLStreamEncoder = BufferedStreamEncoder<YAMLEventWriter>

/// Synchronous YAML event writer that serializes ``ValueEvent`` values into bytes.
struct YAMLEventWriter: FormatEventWriter {

  static let anchorTagPrefix = "tag:solid.foundation,2025:anchor:"
  typealias Options = YAMLStreamWriter.Options

  private enum RootState {
    case expectingValue
    case complete
  }

  private enum ContainerKind {
    case array
    case object
  }

  private struct ContainerState {
    let kind: ContainerKind
    let indent: Int
    var inlinePrefix: String
    let allowInline: Bool
    let style: ValueCollectionStyle
    let originalStyle: ValueCollectionStyle
    var pendingTags: [Value]
    var pendingAnchor: String?
    var opened: Bool
    var expectingKey: Bool
    var hasEntries: Bool
    var inlineActive: Bool
    var lastKeyWasEmpty: Bool
    var explicitValuePending: Bool
    var isSetMapping: Bool
  }

  private struct ContainerContext {
    let indent: Int
    let inlinePrefix: String
    let allowInline: Bool
  }

  private let options: Options
  private let indentString: String

  private var buffer = Data()
  private var containers: [ContainerState] = []
  private var pendingTags: [Value] = []
  private var pendingAnchor: String?
  private var pendingStyle: ValueStyle?
  private var rootState: RootState = .expectingValue
  private var atLineStart = true

  init(options: Options = .default) {
    self.options = options
    self.indentString = String(repeating: " ", count: options.indent)
  }

  public var format: Format { YAML.format }

  // MARK: - FormatEventWriter

  mutating func writeEvent(_ event: ValueEvent, into output: inout Data) throws {
    swap(&buffer, &output)
    defer { swap(&buffer, &output) }
    try writeEventImpl(event)
  }

  mutating func finishWriting(into output: inout Data) throws {
    guard
      containers.isEmpty, pendingTags.isEmpty,
      pendingAnchor == nil, pendingStyle == nil,
      rootState == .complete
    else {
      throw YAML.EmitError.invalidState("Incomplete YAML document")
    }
    if !output.isEmpty, !atLineStart {
      swap(&buffer, &output)
      defer { swap(&buffer, &output) }
      try appendString("\n")
    }
  }

  // MARK: - Event Implementation

  private mutating func writeEventImpl(_ event: ValueEvent) throws {
    switch event {
    case .style(let style):
      guard pendingStyle == nil else {
        throw YAML.EmitError.invalidEvent("Style without value")
      }
      pendingStyle = style

    case .tag(let tag):
      pendingTags.append(tag)

    case .anchor(let name):
      guard pendingAnchor == nil else {
        throw YAML.EmitError.invalidEvent("Anchor without value")
      }
      pendingAnchor = name

    case .alias(let name):
      try writeAlias(name)

    case .key(let key):
      try writeKey(key)

    case .scalar(let value):
      try writeScalar(value)

    case .beginArray(_):
      try beginContainer(kind: .array)

    case .endArray:
      try endContainer(kind: .array)

    case .beginObject(_):
      try beginContainer(kind: .object)

    case .endObject:
      try endContainer(kind: .object)
    }
  }

  // Finish/flush are handled by the encoder interface.

  // MARK: - Preparation

  private func indentString(count: Int) -> String {
    String(repeating: " ", count: count)
  }

  private mutating func writeKey(_ key: Value) throws {
    guard var container = containers.popLast() else {
      throw YAML.EmitError.invalidEvent("Key outside object")
    }
    guard container.kind == .object else {
      throw YAML.EmitError.invalidEvent("Key outside object")
    }
    guard container.expectingKey else {
      throw YAML.EmitError.invalidEvent("Unexpected key")
    }
    let scalarStyle = try consumePendingScalarStyle()
    let allowImplicitTyping = options.allowImplicitTyping
    let isEmptyKey = isEmptyStringValue(key)
    let isColonKey = isColonOnlyString(key)
    if container.style == .flow {
      if container.hasEntries {
        try appendString(", ")
      }
      if let properties = consumePendingNodeProperties() {
        try appendString(properties)
        try appendString(" ")
      }
      let renderedKey: String
      if isEmptyKey, (scalarStyle == nil || scalarStyle == .plain), allowImplicitTyping {
        renderedKey = ""
      } else if isColonKey, (scalarStyle == nil || scalarStyle == .plain), allowImplicitTyping {
        renderedKey = ":"
      } else {
        renderedKey = serializeValue(
          key,
          indent: container.indent,
          allowBlock: false,
          scalarStyle: scalarStyle,
          allowImplicitTyping: allowImplicitTyping
        )
      }
      try appendString(renderedKey)
      try appendString(":")
      container.expectingKey = false
      container.hasEntries = true
      container.lastKeyWasEmpty = isEmptyStringValue(key)
      container.explicitValuePending = false
      containers.append(container)
      return
    }
    try openContainerIfNeeded(&container)
    try prepareForBlockEntry(&container)
    let requiresExplicit = requiresExplicitKey(key, scalarStyle: scalarStyle)
    if requiresExplicit {
      let properties = consumePendingNodeProperties()
      try writeExplicitKey(key, properties: properties, indent: container.indent, scalarStyle: scalarStyle)
      container.expectingKey = false
      container.hasEntries = true
      container.lastKeyWasEmpty = isEmptyStringValue(key)
      container.explicitValuePending = true
      containers.append(container)
      return
    }
    if let properties = consumePendingNodeProperties() {
      try appendString(properties)
      try appendString(" ")
    }
    let renderedKey: String
    if isEmptyKey, (scalarStyle == nil || scalarStyle == .plain), allowImplicitTyping {
      renderedKey = ""
    } else if isColonKey, (scalarStyle == nil || scalarStyle == .plain), allowImplicitTyping {
      renderedKey = ":"
    } else {
      renderedKey = serializeValue(
        key,
        indent: container.indent,
        allowBlock: false,
        scalarStyle: scalarStyle,
        allowImplicitTyping: allowImplicitTyping
      )
    }
    try appendString(renderedKey)
    try appendString(":")
    container.expectingKey = false
    container.hasEntries = true
    container.lastKeyWasEmpty = isEmptyStringValue(key)
    container.explicitValuePending = false
    containers.append(container)
  }

  private mutating func writeScalar(_ value: Value) throws {
    let scalarStyle = try consumePendingScalarStyle()
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw YAML.EmitError.invalidState("Multiple root values")
      }
      let allowImplicitTyping = options.allowImplicitTyping
      let properties = consumePendingNodeProperties()
      let rendered = serializeValue(
        value,
        indent: 0,
        allowBlock: true,
        scalarStyle: scalarStyle,
        allowImplicitTyping: allowImplicitTyping
      )
      if let properties {
        try appendString(properties)
        if !rendered.isEmpty {
          try appendString(" ")
          try appendString(rendered)
        }
      } else {
        try appendString(rendered)
      }
      rootState = .complete
      return
    }

    guard var container = containers.popLast() else {
      throw YAML.EmitError.invalidState("Invalid container state")
    }

    switch container.kind {
    case .array:
      if container.style == .flow {
        if container.hasEntries {
          try appendString(", ")
        }
        let allowImplicitTyping = options.allowImplicitTyping
        if let properties = consumePendingNodeProperties() {
          try appendString(properties)
          try appendString(" ")
        }
        try appendString(
          serializeValue(
            value,
            indent: container.indent,
            allowBlock: false,
            scalarStyle: scalarStyle,
            allowImplicitTyping: allowImplicitTyping
          )
        )
        container.hasEntries = true
        containers.append(container)
        try finishValue()
        return
      }
      try openContainerIfNeeded(&container)
      try prepareForBlockEntry(&container)
      let allowImplicitTyping = options.allowImplicitTyping
      let properties = consumePendingNodeProperties()
      let rendered = serializeValue(
        value,
        indent: container.indent,
        allowBlock: true,
        scalarStyle: scalarStyle,
        allowImplicitTyping: allowImplicitTyping
      )
      if rendered.isEmpty {
        if let properties {
          try appendString("- ")
          try appendString(properties)
        } else {
          try appendString("-")
        }
      } else {
        try appendString("- ")
        if let properties {
          try appendString(properties)
          try appendString(" ")
        }
        try appendString(rendered)
      }
      container.hasEntries = true
      container.opened = true
      containers.append(container)
      try finishValue()

    case .object:
      guard !container.expectingKey else {
        throw YAML.EmitError.invalidEvent("Unexpected value before key")
      }
      if container.style == .flow {
        try appendString(" ")
        let allowImplicitTyping = options.allowImplicitTyping
        let forceIndentIndicator = isOnlyNewlines(value)
        let properties = consumePendingNodeProperties()
        if let properties {
          try appendString(properties)
          try appendString(" ")
        }
        let rendered = renderMappingValue(
          value,
          scalarStyle: scalarStyle,
          indent: container.indent,
          allowBlock: false,
          lastKeyWasEmpty: container.lastKeyWasEmpty,
          isSetMapping: container.isSetMapping,
          hasProperties: properties != nil,
          forceNullForEmpty: false,
          allowImplicitTyping: allowImplicitTyping,
          forceIndentIndicator: forceIndentIndicator
        )
        try appendString(rendered)
        containers.append(container)
        try finishValue()
        return
      }
      container.opened = true
      let allowImplicitTyping = options.allowImplicitTyping
      let forceIndentIndicator = isOnlyNewlines(value)
      let properties = consumePendingNodeProperties()
      let rendered = renderMappingValue(
        value,
        scalarStyle: scalarStyle,
        indent: container.indent,
        allowBlock: true,
        lastKeyWasEmpty: container.lastKeyWasEmpty,
        isSetMapping: container.isSetMapping,
        hasProperties: properties != nil,
        forceNullForEmpty: false,
        allowImplicitTyping: allowImplicitTyping,
        forceIndentIndicator: forceIndentIndicator
      )
      let normalizedRendered: String
      if rendered == "null", (scalarStyle == nil || scalarStyle == .plain), properties == nil {
        normalizedRendered = ""
      } else {
        normalizedRendered = rendered
      }
      if normalizedRendered.isEmpty {
        if let properties {
          try appendString(" ")
          try appendString(properties)
        }
      } else {
        try appendString(" ")
        if let properties {
          try appendString(properties)
          try appendString(" ")
        }
        try appendString(normalizedRendered)
      }
      containers.append(container)
      try finishValue()
    }
  }

  private mutating func writeAlias(_ name: String) throws {
    guard pendingTags.isEmpty, pendingAnchor == nil, pendingStyle == nil else {
      throw YAML.EmitError.invalidEvent("Alias cannot have tags or anchors")
    }

    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw YAML.EmitError.invalidState("Multiple root values")
      }
      try appendString("*\(name)")
      rootState = .complete
      return
    }

    guard var container = containers.popLast() else {
      throw YAML.EmitError.invalidState("Invalid container state")
    }

    switch container.kind {
    case .array:
      if container.style == .flow {
        if container.hasEntries {
          try appendString(", ")
        }
        try appendString("*\(name)")
        container.hasEntries = true
        containers.append(container)
        try finishValue()
        return
      }
      try openContainerIfNeeded(&container)
      try prepareForBlockEntry(&container)
      try appendString("- *\(name)")
      container.hasEntries = true
      container.opened = true
      containers.append(container)
      try finishValue()

    case .object:
      if container.style == .flow {
        if container.expectingKey {
          if container.hasEntries {
            try appendString(", ")
          }
          try appendString("*\(name)")
          try appendString(" :")
          container.expectingKey = false
          container.hasEntries = true
          containers.append(container)
        } else {
          try appendString(" ")
          try appendString("*\(name)")
          containers.append(container)
          try finishValue()
        }
        return
      }
      if container.expectingKey {
        try openContainerIfNeeded(&container)
        try prepareForBlockEntry(&container)
        try appendString("*\(name) :")
        container.expectingKey = false
        container.hasEntries = true
        container.lastKeyWasEmpty = false
        container.explicitValuePending = false
        containers.append(container)
      } else {
        container.opened = true
        try appendString(" ")
        try appendString("*\(name)")
        containers.append(container)
        try finishValue()
      }
    }
  }

  private mutating func beginContainer(kind: ContainerKind) throws {
    let context = try prepareForContainerValue(kind: kind)
    let tags = pendingTags
    pendingTags.removeAll(keepingCapacity: true)
    let anchor = pendingAnchor
    pendingAnchor = nil
    let style = try consumePendingCollectionStyle()
    let outputStyle: ValueCollectionStyle = options.forceBlockCollections ? .block : style
    let isSetMapping = kind == .object && tags.contains(where: isSetTag)
    let state = ContainerState(
      kind: kind,
      indent: context.indent,
      inlinePrefix: context.inlinePrefix,
      allowInline: context.allowInline,
      style: outputStyle,
      originalStyle: style,
      pendingTags: tags,
      pendingAnchor: anchor,
      opened: false,
      expectingKey: kind == .object,
      hasEntries: false,
      inlineActive: false,
      lastKeyWasEmpty: false,
      explicitValuePending: false,
      isSetMapping: isSetMapping
    )
    if outputStyle == .flow {
      if !context.inlinePrefix.isEmpty, !atLineStart {
        try appendString(context.inlinePrefix)
      } else {
        try ensureLineStart(indent: context.indent)
      }
      if let properties = formatNodeProperties(tags: tags, anchor: anchor) {
        try appendString(properties)
        try appendString(" ")
      }
      try appendString(kind == .array ? "[" : "{")
      var updated = state
      updated.pendingTags.removeAll(keepingCapacity: true)
      updated.pendingAnchor = nil
      updated.inlinePrefix = ""
      updated.opened = true
      containers.append(updated)
    } else {
      containers.append(state)
    }
  }

  private mutating func endContainer(kind: ContainerKind) throws {
    guard pendingTags.isEmpty, pendingStyle == nil else {
      throw YAML.EmitError.invalidEvent("Tag or style without value")
    }
    guard var container = containers.popLast() else {
      throw YAML.EmitError.invalidEvent(kind == .array ? "Unexpected endArray" : "Unexpected endObject")
    }
    guard container.kind == kind else {
      throw YAML.EmitError.invalidEvent(kind == .array ? "Unexpected endArray" : "Unexpected endObject")
    }
    if kind == .object, !container.expectingKey {
      throw YAML.EmitError.invalidEvent("Missing value for key")
    }
    if container.style == .flow {
      try appendString(kind == .array ? "]" : "}")
      try finishValue()
      return
    }
    if container.opened {
      if !container.pendingTags.isEmpty {
        throw YAML.EmitError.invalidEvent("Tag without value")
      }
      if container.pendingAnchor != nil {
        throw YAML.EmitError.invalidEvent("Anchor without value")
      }
    } else {
      if !container.inlinePrefix.isEmpty {
        try appendString(container.inlinePrefix)
      }
      if let properties = formatNodeProperties(tags: container.pendingTags, anchor: container.pendingAnchor) {
        try appendString(properties)
        try appendString(" ")
        container.pendingTags.removeAll(keepingCapacity: true)
        container.pendingAnchor = nil
      }
      try appendString(kind == .array ? "[]" : "{}")
    }
    try finishValue()
  }

  private mutating func prepareForContainerValue(kind: ContainerKind) throws -> ContainerContext {
    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw YAML.EmitError.invalidState("Multiple root values")
      }
      return ContainerContext(indent: 0, inlinePrefix: "", allowInline: false)
    }

    guard var container = containers.popLast() else {
      throw YAML.EmitError.invalidState("Invalid container state")
    }

    switch container.kind {
    case .array:
      if container.style == .flow {
        if container.hasEntries {
          try appendString(", ")
        }
        container.hasEntries = true
        containers.append(container)
        return ContainerContext(indent: container.indent, inlinePrefix: "", allowInline: true)
      }
      try openContainerIfNeeded(&container)
      try prepareForBlockEntry(&container)
      try appendString("-")
      container.opened = true
      container.hasEntries = true
      containers.append(container)
      return ContainerContext(indent: container.indent + options.indent, inlinePrefix: " ", allowInline: false)

    case .object:
      guard !container.expectingKey else {
        throw YAML.EmitError.invalidEvent("Unexpected value before key")
      }
      containers.append(container)
      let indent = container.indent + options.indent
      return ContainerContext(indent: indent, inlinePrefix: " ", allowInline: false)
    }
  }

  private mutating func openContainerIfNeeded(_ container: inout ContainerState) throws {
    guard !container.opened else { return }
    if container.style == .flow {
      container.opened = true
      return
    }
    container.opened = true
    if let properties = formatNodeProperties(tags: container.pendingTags, anchor: container.pendingAnchor) {
      if !container.inlinePrefix.isEmpty, !atLineStart {
        try appendString(container.inlinePrefix)
        container.inlinePrefix = ""
      } else {
        try ensureLineStart(indent: container.indent)
      }
      try appendString(properties)
      try appendString("\n")
      container.pendingTags.removeAll(keepingCapacity: true)
      container.pendingAnchor = nil
    } else if container.allowInline, !container.inlinePrefix.isEmpty, !atLineStart {
      try appendString(container.inlinePrefix)
      container.inlinePrefix = ""
      container.inlineActive = true
    } else if !atLineStart {
      try appendString("\n")
    }
  }

  private mutating func ensureLineStart(indent: Int) throws {
    if !atLineStart {
      buffer.append(0x0A) // newline
      atLineStart = true
    }
    for _ in 0..<indent {
      buffer.append(0x20) // space
    }
    if indent > 0 {
      atLineStart = false
    }
  }

  private mutating func prepareForBlockEntry(_ container: inout ContainerState) throws {
    if container.inlineActive {
      container.inlineActive = false
      return
    }
    try ensureLineStart(indent: container.indent)
  }

  private mutating func finishValue() throws {
    if containers.isEmpty {
      rootState = .complete
      return
    }
    guard var container = containers.popLast() else {
      return
    }
    switch container.kind {
    case .array:
      containers.append(container)
    case .object:
      guard !container.expectingKey else {
        throw YAML.EmitError.invalidEvent("Unexpected value")
      }
      container.expectingKey = true
      container.explicitValuePending = false
      containers.append(container)
    }
  }

  private mutating func consumePendingNodeProperties() -> String? {
    let properties = formatNodeProperties(tags: pendingTags, anchor: pendingAnchor)
    pendingTags.removeAll(keepingCapacity: true)
    pendingAnchor = nil
    return properties
  }

  private mutating func consumePendingScalarStyle() throws -> ValueScalarStyle? {
    guard let pendingStyle else {
      return nil
    }
    switch pendingStyle {
    case .scalar(let style):
      self.pendingStyle = nil
      return style
    case .collection:
      throw YAML.EmitError.invalidEvent("Collection style cannot apply to scalar")
    }
  }

  private mutating func consumePendingCollectionStyle() throws -> ValueCollectionStyle {
    guard let pendingStyle else {
      return .block
    }
    switch pendingStyle {
    case .collection(let style):
      self.pendingStyle = nil
      return style
    case .scalar:
      throw YAML.EmitError.invalidEvent("Scalar style cannot apply to collection")
    }
  }

  private func formatTags(_ tags: [Value]) -> String {
    tags.map { formatTag($0) }.joined(separator: " ")
  }

  private func isSetTag(_ value: Value) -> Bool {
    let tag = value.stringified
    return tag == "tag:yaml.org,2002:set"
  }

  private func formatNodeProperties(tags: [Value], anchor: String?) -> String? {
    var parts: [String] = []
    if let anchor {
      parts.append("&\(anchor)")
    }
    if !tags.isEmpty {
      parts.append(formatTags(tags))
    }
    guard !parts.isEmpty else {
      return nil
    }
    return parts.joined(separator: " ")
  }

  private func anchorName(from tag: Value) -> String? {
    guard case .string(let text) = tag else {
      return nil
    }
    guard text.hasPrefix(Self.anchorTagPrefix) else {
      return nil
    }
    return String(text.dropFirst(Self.anchorTagPrefix.count))
  }

  private func serializeAnchoredValue(
    _ anchor: String,
    value: Value,
    indent: Int,
    allowBlock: Bool,
    scalarStyle: ValueScalarStyle?
  ) -> String {
    let rendered = serializeValue(value, indent: indent, allowBlock: allowBlock, scalarStyle: scalarStyle)
    if rendered.isEmpty {
      return "&\(anchor)"
    }
    return "&\(anchor) \(rendered)"
  }

  // MARK: - Serialization

  private func renderMappingValue(
    _ value: Value,
    scalarStyle: ValueScalarStyle?,
    indent: Int,
    allowBlock: Bool,
    lastKeyWasEmpty: Bool,
    isSetMapping: Bool,
    hasProperties: Bool,
    forceNullForEmpty: Bool,
    allowImplicitTyping: Bool,
    forceIndentIndicator: Bool
  ) -> String {
    if case .string(let string) = value, string.isEmpty, allowImplicitTyping {
      if hasProperties {
        return ""
      }
      if isSetMapping {
        return ""
      }
      if (scalarStyle == nil || scalarStyle == .plain) && !lastKeyWasEmpty && !isSetMapping {
        return forceNullForEmpty ? "null" : ""
      }
    }
    return serializeValue(
      value,
      indent: indent,
      allowBlock: allowBlock,
      scalarStyle: scalarStyle,
      allowImplicitTyping: allowImplicitTyping,
      forceIndentIndicator: forceIndentIndicator
    )
  }

  private func serializeValue(
    _ value: Value,
    indent: Int,
    allowBlock: Bool,
    scalarStyle: ValueScalarStyle? = nil,
    allowImplicitTyping: Bool = true,
    forceIndentIndicator: Bool = false
  ) -> String {
    switch value {
    case .null:
      return "null"
    case .bool(let bool):
      return bool ? "true" : "false"
    case .number(let number):
      return number.description
    case .bytes(let data):
      let encoded = serializeString(
        data.baseEncoded(using: .base64),
        indent: indent,
        allowBlock: allowBlock,
        style: scalarStyle
      )
      let tag = formatTag(.string("tag:yaml.org,2002:binary"))
      return "\(tag) \(encoded)"
    case .string(let string):
      return serializeString(
        string,
        indent: indent,
        allowBlock: allowBlock,
        style: scalarStyle,
        allowImplicitTyping: allowImplicitTyping,
        forceIndentIndicator: forceIndentIndicator
      )
    case .array(let array):
      if array.isEmpty {
        return "[]"
      }
      let contents = array.map { serializeValue($0, indent: indent + options.indent, allowBlock: false) }
      return "[\(contents.joined(separator: ", "))]"
    case .object(let object):
      if object.isEmpty {
        return "{}"
      }
      let contents = object.map { key, val in
        let keyText = serializeValue(key, indent: indent + options.indent, allowBlock: false)
        let valText = serializeValue(val, indent: indent + options.indent, allowBlock: false)
        return "\(keyText): \(valText)"
      }
      return "{\(contents.joined(separator: ", "))}"
    case .tagged(let tags, let inner):
      if let tag = tags.first, let anchor = anchorName(from: tag) {
        return serializeAnchoredValue(
          anchor,
          value: inner,
          indent: indent,
          allowBlock: allowBlock,
          scalarStyle: scalarStyle
        )
      }
      let tagText = tags.map { formatTag($0) }.joined(separator: " ")
      let innerText: String
      if case .string(let string) = inner {
        innerText = serializeString(
          string,
          indent: indent,
          allowBlock: allowBlock,
          style: scalarStyle,
          allowImplicitTyping: false,
          forceIndentIndicator: forceIndentIndicator
        )
      } else {
        innerText = serializeValue(inner, indent: indent, allowBlock: allowBlock, scalarStyle: scalarStyle)
      }
      return "\(tagText) \(innerText)"
    }
  }

  private func serializeString(
    _ string: String,
    indent: Int,
    allowBlock: Bool,
    style: ValueScalarStyle?,
    allowImplicitTyping: Bool = true,
    forceIndentIndicator: Bool = false
  ) -> String {
    if string.isEmpty, style == .plain || (style == nil && allowImplicitTyping) {
      return ""
    }
    return YAMLStringEncoder.render(
      string,
      indent: indent,
      indentSize: options.indent,
      allowBlock: allowBlock,
      preferredStyle: style,
      allowImplicitTyping: allowImplicitTyping,
      forceIndentIndicator: forceIndentIndicator,
      allowDocumentMarkerPrefix: options.allowDocumentMarkerPrefix
    )
  }

  private func formatTag(_ value: Value) -> String {
    let tag = value.stringified
    if tag == "!" {
      return "!"
    }
    let corePrefix = "tag:yaml.org,2002:"
    if tag.hasPrefix(corePrefix) {
      let suffix = String(tag.dropFirst(corePrefix.count))
      if isSimpleTagText(suffix) {
        return "!!\(suffix)"
      }
    }
    if tag.hasPrefix("!") {
      let suffix = String(tag.dropFirst())
      if !suffix.isEmpty, isSimpleTagText(suffix) {
        return "!\(suffix)"
      }
    }
    if isSimpleTagText(tag) {
      return "!\(tag)"
    }
    return "!<\(tag)>"
  }

  private func isSimpleTagText(_ text: String) -> Bool {
    text.allSatisfy { $0.isLetter || $0.isNumber || $0 == ":" || $0 == "-" || $0 == "_" || $0 == "/" || $0 == "." }
  }

  private func requiresExplicitKey(_ value: Value, scalarStyle: ValueScalarStyle?) -> Bool {
    if scalarStyle == .literal || scalarStyle == .folded {
      return true
    }
    if isMultilineString(value) {
      return true
    }
    if isMappingValue(value) {
      return true
    }
    if isSequenceValue(value) {
      return false
    }
    return !isSimpleKeyValue(value)
  }

  private func canInlineImplicitKey(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return canInlineImplicitKey(inner)

    case .array(let array):
      return array.isEmpty
    case .object(let object):
      return object.isEmpty
    default:
      return false
    }
  }

  private func isMultilineString(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isMultilineString(inner)
    case .string(let string):
      return string.contains("\n") || string.contains("\r")
    default:
      return false
    }
  }

  private func isEmptyStringValue(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isEmptyStringValue(inner)
    case .string(let string):
      return string.isEmpty
    default:
      return false
    }
  }

  private func isColonOnlyString(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isColonOnlyString(inner)
    case .string(let string):
      return string == ":"
    default:
      return false
    }
  }

  private func isOnlyNewlines(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isOnlyNewlines(inner)
    case .string(let string):
      guard string.contains("\n") else {
        return false
      }
      return string.trimmingCharacters(in: .newlines).isEmpty
    default:
      return false
    }
  }

  private func isSimpleKeyValue(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isSimpleKeyValue(inner)
    case .array, .object:
      return false
    case .string(let string):
      return !string.contains("\n") && !string.contains("\r")
    default:
      return true
    }
  }

  private func isCollectionValue(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isCollectionValue(inner)
    case .array, .object:
      return true
    default:
      return false
    }
  }

  private func isMappingValue(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isMappingValue(inner)
    case .object:
      return true
    default:
      return false
    }
  }

  private func isSequenceValue(_ value: Value) -> Bool {
    switch value {
    case .tagged(_, let inner):
      return isSequenceValue(inner)
    case .array:
      return true
    default:
      return false
    }
  }

  private func renderBlockValueLines(_ value: Value, scalarStyle: ValueScalarStyle? = nil) -> [String] {
    switch value {
    case .tagged(let tags, let inner):
      if let tag = tags.first, let anchor = anchorName(from: tag) {
        let innerLines = renderBlockValueLines(inner, scalarStyle: scalarStyle)
        guard !innerLines.isEmpty else {
          return ["&\(anchor)"]
        }
        var lines = innerLines
        if lines[0].isEmpty {
          lines[0] = "&\(anchor)"
        } else {
          lines[0] = "&\(anchor) \(lines[0])"
        }
        return lines
      }
      let tagText = tags.map { formatTag($0) }.joined(separator: " ")
      let innerLines = renderBlockValueLines(inner, scalarStyle: scalarStyle)
      if innerLines.isEmpty {
        return [tagText]
      }
      if innerLines.count == 1 {
        let first = innerLines[0]
        return first.isEmpty ? [tagText] : ["\(tagText) \(first)"]
      }
      let padding = indentString
      return [tagText] + innerLines.map { "\(padding)\($0)" }

    case .string(let string):
      let rendered = serializeString(string, indent: 0, allowBlock: true, style: scalarStyle)
      return rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    case .array(let array):
      guard !array.isEmpty else { return ["[]"] }
      var lines: [String] = []
      for item in array {
        let itemLines = renderBlockValueLines(item)
        if itemLines.isEmpty {
          lines.append("-")
          continue
        }
        let first = itemLines[0]
        if first.isEmpty {
          lines.append("-")
        } else {
          lines.append("- \(first)")
        }
        if itemLines.count > 1 {
          let padding = indentString
          for line in itemLines.dropFirst() {
            lines.append("\(padding)\(line)")
          }
        }
      }
      return lines

    case .object(let object):
      guard !object.isEmpty else { return ["{}"] }
      var lines: [String] = []
      for (key, val) in object {
        let padding = indentString
        if requiresExplicitKey(key, scalarStyle: nil), !canInlineImplicitKey(key) {
          let keyLines = renderBlockValueLines(key)
          if keyLines.isEmpty {
            lines.append("?")
          } else {
            let firstKey = keyLines[0]
            lines.append(firstKey.isEmpty ? "?" : "? \(firstKey)")
            for line in keyLines.dropFirst() {
              lines.append("\(padding)\(line)")
            }
          }

          let valLines = renderBlockValueLines(val)
          if valLines.isEmpty {
            lines.append(":")
          } else {
            let firstVal = valLines[0]
            lines.append(firstVal.isEmpty ? ":" : ": \(firstVal)")
            for line in valLines.dropFirst() {
              lines.append("\(padding)\(line)")
            }
          }
          continue
        }

        let keyText = serializeValue(key, indent: 0, allowBlock: false)
        let valLines = renderBlockValueLines(val)
        if valLines.isEmpty {
          lines.append("\(keyText):")
          continue
        }
        let first = valLines[0]
        if valLines.count == 1 {
          if first.isEmpty {
            lines.append("\(keyText):")
          } else {
            lines.append("\(keyText): \(first)")
          }
        } else {
          lines.append("\(keyText): \(first)")
          for line in valLines.dropFirst() {
            lines.append("\(padding)\(line)")
          }
        }
      }
      return lines

    default:
      return [serializeValue(value, indent: 0, allowBlock: false)]
    }
  }

  private mutating func writeExplicitKey(
    _ key: Value,
    properties: String?,
    indent: Int,
    scalarStyle: ValueScalarStyle?
  ) throws {
    try appendString("?")
    if let properties {
      try appendString(" ")
      try appendString(properties)
    }
    let lines = renderBlockValueLines(key, scalarStyle: scalarStyle)
    if !lines.isEmpty {
      let inlineIndex = lines.firstIndex { !$0.isEmpty }
      let firstLine = inlineIndex.map { lines[$0] } ?? lines[0]
      let hasProperties = properties != nil
      let isSequenceLine = firstLine.hasPrefix("-")
      let shouldInline = !firstLine.isEmpty && !firstLine.hasPrefix("?") && !(isSequenceLine && hasProperties)
      if shouldInline, let inlineIndex {
        try appendString(" ")
        try appendString(lines[inlineIndex])
      }
      let bodyLines: [String] = {
        if shouldInline, let inlineIndex {
          var remaining = lines
          remaining.remove(at: inlineIndex)
          return remaining
        }
        return lines
      }()
      if !bodyLines.isEmpty {
        let isBlockScalar = firstLine.hasPrefix("|") || firstLine.hasPrefix(">")
        let lineIndent = indent + options.indent
        let blockIndent = indentString
        for line in bodyLines {
          try appendString("\n")
          var renderedLine = line
          if isBlockScalar, renderedLine.hasPrefix(blockIndent) {
            renderedLine = String(renderedLine.dropFirst(blockIndent.count))
          }
          if !renderedLine.isEmpty {
            if lineIndent > 0 {
              appendIndent(count: lineIndent)
            }
            try appendString(renderedLine)
          }
        }
      }
    }
    try ensureLineStart(indent: indent)
    try appendString(":")
  }

  // MARK: - Output helpers

  private mutating func appendString(_ string: String) throws {
    guard !string.isEmpty else { return }
    buffer.append(contentsOf: string.utf8)
    atLineStart = string.utf8.last == 0x0A
  }

  private mutating func appendIndent(count: Int) {
    for _ in 0..<count {
      buffer.append(0x20)
    }
    if count > 0 {
      atLineStart = false
    }
  }

}
