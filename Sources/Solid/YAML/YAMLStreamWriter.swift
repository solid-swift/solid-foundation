//
//  YAMLStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidCore
import SolidData
import SolidIO

/// Async YAML stream writer that consumes ``ValueEvent`` values.
public final class YAMLStreamWriter: FormatStreamWriter {

  static let anchorTagPrefix = "tag:solid.foundation,2025:anchor:"

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int
    public var forceBlockCollections: Bool
    public var allowImplicitTyping: Bool
    public var allowDocumentMarkerPrefix: Bool

    public init(
      indent: Int = 2,
      forceBlockCollections: Bool = false,
      allowImplicitTyping: Bool = true,
      allowDocumentMarkerPrefix: Bool = false
    ) {
      self.indent = indent
      self.forceBlockCollections = forceBlockCollections
      self.allowImplicitTyping = allowImplicitTyping
      self.allowDocumentMarkerPrefix = allowDocumentMarkerPrefix
    }
  }

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

  private let sink: any Sink
  private let bufferSize: Int
  private let options: Options

  private var buffer = Data()
  private var containers: [ContainerState] = []
  private var pendingTags: [Value] = []
  private var pendingAnchor: String?
  private var pendingStyle: ValueStyle?
  private var rootState: RootState = .expectingValue
  private var finished = false
  private var atLineStart = true

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.sink = sink
    self.bufferSize = bufferSize
    self.options = options
  }

  public var format: Format { YAML.format }

  public func write(_ event: ValueEvent) async throws {
    guard !finished else { throw YAML.EmitError.invalidState("Writer already finished") }

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
      try await writeAlias(name)

    case .key(let key):
      try await writeKey(key)

    case .scalar(let value):
      try await writeScalar(value)

    case .beginArray:
      try await beginContainer(kind: .array)

    case .endArray:
      try await endContainer(kind: .array)

    case .beginObject:
      try await beginContainer(kind: .object)

    case .endObject:
      try await endContainer(kind: .object)
    }
  }

  public func finish() async throws {
    guard !finished else { return }
    guard
      containers.isEmpty, pendingTags.isEmpty,
      pendingAnchor == nil, pendingStyle == nil,
      rootState == .complete
    else {
      throw YAML.EmitError.invalidState("Incomplete YAML document")
    }
    if !buffer.isEmpty, !atLineStart {
      try await appendString("\n")
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

  // MARK: - Preparation

  private func indentString(count: Int) -> String {
    String(repeating: " ", count: count)
  }

  private func writeKey(_ key: Value) async throws {
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
        try await appendString(", ")
      }
      if let properties = consumePendingNodeProperties() {
        try await appendString(properties)
        try await appendString(" ")
      }
      let renderedKey: String
      if isEmptyKey, (scalarStyle == nil || scalarStyle == .plain) {
        renderedKey = ""
      } else if isColonKey, (scalarStyle == nil || scalarStyle == .plain) {
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
      try await appendString(renderedKey)
      try await appendString(":")
      container.expectingKey = false
      container.hasEntries = true
      container.lastKeyWasEmpty = isEmptyStringValue(key)
      container.explicitValuePending = false
      containers.append(container)
      return
    }
    try await openContainerIfNeeded(&container)
    try await prepareForBlockEntry(&container)
    let requiresExplicit = requiresExplicitKey(key, scalarStyle: scalarStyle)
    if requiresExplicit {
      let properties = consumePendingNodeProperties()
      try await writeExplicitKey(key, properties: properties, indent: container.indent, scalarStyle: scalarStyle)
      container.expectingKey = false
      container.hasEntries = true
      container.lastKeyWasEmpty = isEmptyStringValue(key)
      container.explicitValuePending = true
      containers.append(container)
      return
    }
    if let properties = consumePendingNodeProperties() {
      try await appendString(properties)
      try await appendString(" ")
    }
    let renderedKey: String
    if isEmptyKey, (scalarStyle == nil || scalarStyle == .plain) {
      renderedKey = ""
    } else if isColonKey, (scalarStyle == nil || scalarStyle == .plain) {
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
    try await appendString(renderedKey)
    try await appendString(":")
    container.expectingKey = false
    container.hasEntries = true
    container.lastKeyWasEmpty = isEmptyStringValue(key)
    container.explicitValuePending = false
    containers.append(container)
  }

  private func writeScalar(_ value: Value) async throws {
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
        try await appendString(properties)
        if !rendered.isEmpty {
          try await appendString(" ")
          try await appendString(rendered)
        }
      } else {
        try await appendString(rendered)
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
          try await appendString(", ")
        }
        let allowImplicitTyping = options.allowImplicitTyping
        if let properties = consumePendingNodeProperties() {
          try await appendString(properties)
          try await appendString(" ")
        }
        try await appendString(
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
      try await openContainerIfNeeded(&container)
      try await prepareForBlockEntry(&container)
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
          try await appendString("- ")
          try await appendString(properties)
        } else {
          try await appendString("-")
        }
      } else {
        try await appendString("- ")
        if let properties {
          try await appendString(properties)
          try await appendString(" ")
        }
        try await appendString(rendered)
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
        try await appendString(" ")
        let allowImplicitTyping = options.allowImplicitTyping
        let forceIndentIndicator = isOnlyNewlines(value)
        let properties = consumePendingNodeProperties()
        if let properties {
          try await appendString(properties)
          try await appendString(" ")
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
        try await appendString(rendered)
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
          try await appendString(" ")
          try await appendString(properties)
        }
      } else {
        try await appendString(" ")
        if let properties {
          try await appendString(properties)
          try await appendString(" ")
        }
        try await appendString(normalizedRendered)
      }
      containers.append(container)
      try finishValue()
    }
  }

  private func writeAlias(_ name: String) async throws {
    guard pendingTags.isEmpty, pendingAnchor == nil, pendingStyle == nil else {
      throw YAML.EmitError.invalidEvent("Alias cannot have tags or anchors")
    }

    if containers.isEmpty {
      guard rootState == .expectingValue else {
        throw YAML.EmitError.invalidState("Multiple root values")
      }
      try await appendString("*\(name)")
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
          try await appendString(", ")
        }
        try await appendString("*\(name)")
        container.hasEntries = true
        containers.append(container)
        try finishValue()
        return
      }
      try await openContainerIfNeeded(&container)
      try await prepareForBlockEntry(&container)
      try await appendString("- *\(name)")
      container.hasEntries = true
      container.opened = true
      containers.append(container)
      try finishValue()

    case .object:
      if container.style == .flow {
        if container.expectingKey {
          if container.hasEntries {
            try await appendString(", ")
          }
          try await appendString("*\(name)")
          try await appendString(" :")
          container.expectingKey = false
          container.hasEntries = true
          containers.append(container)
        } else {
          try await appendString(" ")
          try await appendString("*\(name)")
          containers.append(container)
          try finishValue()
        }
        return
      }
      if container.expectingKey {
        try await openContainerIfNeeded(&container)
        try await prepareForBlockEntry(&container)
        try await appendString("*\(name) :")
        container.expectingKey = false
        container.hasEntries = true
        container.lastKeyWasEmpty = false
        container.explicitValuePending = false
        containers.append(container)
      } else {
        container.opened = true
        try await appendString(" ")
        try await appendString("*\(name)")
        containers.append(container)
        try finishValue()
      }
    }
  }

  private func beginContainer(kind: ContainerKind) async throws {
    let context = try await prepareForContainerValue(kind: kind)
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
        try await appendString(context.inlinePrefix)
      } else {
        try await ensureLineStart(indent: context.indent)
      }
      if let properties = formatNodeProperties(tags: tags, anchor: anchor) {
        try await appendString(properties)
        try await appendString(" ")
      }
      try await appendString(kind == .array ? "[" : "{")
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

  private func endContainer(kind: ContainerKind) async throws {
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
      try await appendString(kind == .array ? "]" : "}")
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
        try await appendString(container.inlinePrefix)
      }
      if let properties = formatNodeProperties(tags: container.pendingTags, anchor: container.pendingAnchor) {
        try await appendString(properties)
        try await appendString(" ")
        container.pendingTags.removeAll(keepingCapacity: true)
        container.pendingAnchor = nil
      }
      try await appendString(kind == .array ? "[]" : "{}")
    }
    try finishValue()
  }

  private func prepareForContainerValue(kind: ContainerKind) async throws -> ContainerContext {
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
          try await appendString(", ")
        }
        container.hasEntries = true
        containers.append(container)
        return ContainerContext(indent: container.indent, inlinePrefix: "", allowInline: true)
      }
      try await openContainerIfNeeded(&container)
      try await prepareForBlockEntry(&container)
      try await appendString("-")
      container.opened = true
      container.hasEntries = true
      containers.append(container)
      return ContainerContext(indent: container.indent + options.indent, inlinePrefix: " ", allowInline: true)

    case .object:
      guard !container.expectingKey else {
        throw YAML.EmitError.invalidEvent("Unexpected value before key")
      }
      let allowInline = container.explicitValuePending
      containers.append(container)
      let indent = container.indent + options.indent
      return ContainerContext(indent: indent, inlinePrefix: " ", allowInline: allowInline)
    }
  }

  private func openContainerIfNeeded(_ container: inout ContainerState) async throws {
    guard !container.opened else { return }
    if container.style == .flow {
      container.opened = true
      return
    }
    container.opened = true
    if let properties = formatNodeProperties(tags: container.pendingTags, anchor: container.pendingAnchor) {
      if !container.inlinePrefix.isEmpty, !atLineStart {
        try await appendString(container.inlinePrefix)
        container.inlinePrefix = ""
      } else {
        try await ensureLineStart(indent: container.indent)
      }
      try await appendString(properties)
      try await appendString("\n")
      container.pendingTags.removeAll(keepingCapacity: true)
      container.pendingAnchor = nil
    } else if container.allowInline, !container.inlinePrefix.isEmpty, !atLineStart {
      try await appendString(container.inlinePrefix)
      container.inlinePrefix = ""
      container.inlineActive = true
    } else if !atLineStart {
      try await appendString("\n")
    }
  }

  private func ensureLineStart(indent: Int) async throws {
    if !atLineStart {
      try await appendString("\n")
    }
    if indent > 0 {
      try await appendString(indentString(count: indent))
    }
  }

  private func prepareForBlockEntry(_ container: inout ContainerState) async throws {
    if container.inlineActive {
      container.inlineActive = false
      return
    }
    try await ensureLineStart(indent: container.indent)
  }

  private func finishValue() throws {
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

  private func consumePendingNodeProperties() -> String? {
    let properties = formatNodeProperties(tags: pendingTags, anchor: pendingAnchor)
    pendingTags.removeAll(keepingCapacity: true)
    pendingAnchor = nil
    return properties
  }

  private func consumePendingScalarStyle() throws -> ValueScalarStyle? {
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

  private func consumePendingCollectionStyle() throws -> ValueCollectionStyle {
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
    if case .string(let string) = value, string.isEmpty {
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
    case .tagged(let tag, let inner):
      if let anchor = anchorName(from: tag) {
        return serializeAnchoredValue(
          anchor,
          value: inner,
          indent: indent,
          allowBlock: allowBlock,
          scalarStyle: scalarStyle
        )
      }
      let tagText = formatTag(tag)
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
    if string.isEmpty, style == nil {
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
    if isCollectionValue(value) {
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

  private func renderBlockValueLines(_ value: Value, scalarStyle: ValueScalarStyle? = nil) -> [String] {
    switch value {
    case .tagged(let tag, let inner):
      if let anchor = anchorName(from: tag) {
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
      let innerLines = renderBlockValueLines(inner, scalarStyle: scalarStyle)
      if innerLines.isEmpty {
        return [formatTag(tag)]
      }
      if innerLines.count == 1 {
        let first = innerLines[0]
        return first.isEmpty ? [formatTag(tag)] : ["\(formatTag(tag)) \(first)"]
      }
      let padding = String(repeating: " ", count: options.indent)
      return [formatTag(tag)] + innerLines.map { "\(padding)\($0)" }

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
          let padding = String(repeating: " ", count: options.indent)
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
        let padding = String(repeating: " ", count: options.indent)
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

  private func writeExplicitKey(
    _ key: Value,
    properties: String?,
    indent: Int,
    scalarStyle: ValueScalarStyle?
  ) async throws {
    try await appendString("?")
    if let properties {
      try await appendString(" ")
      try await appendString(properties)
    }
    let lines = renderBlockValueLines(key, scalarStyle: scalarStyle)
    if !lines.isEmpty {
      let inlineIndex = lines.firstIndex { !$0.isEmpty }
      let firstLine = inlineIndex.map { lines[$0] } ?? lines[0]
      let hasProperties = properties != nil
      let isSequenceLine = firstLine.hasPrefix("-")
      let shouldInline = !firstLine.isEmpty && !firstLine.hasPrefix("?") && !(isSequenceLine && hasProperties)
      if shouldInline, let inlineIndex {
        try await appendString(" ")
        try await appendString(lines[inlineIndex])
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
        let padding = indentString(count: lineIndent)
        let blockIndent = indentString(count: options.indent)
        for line in bodyLines {
          try await appendString("\n")
          var renderedLine = line
          if isBlockScalar, renderedLine.hasPrefix(blockIndent) {
            renderedLine = String(renderedLine.dropFirst(blockIndent.count))
          }
          if !renderedLine.isEmpty {
            if !padding.isEmpty {
              try await appendString(padding)
            }
            try await appendString(renderedLine)
          }
        }
      }
    }
    try await ensureLineStart(indent: indent)
    try await appendString(":")
  }

  // MARK: - Output helpers

  private func appendString(_ string: String) async throws {
    guard let data = string.data(using: .utf8) else {
      throw YAML.DataError.invalidEncoding(.utf8)
    }
    buffer.append(data)
    if let last = string.last {
      atLineStart = last == "\n"
    }
    if buffer.count >= bufferSize {
      try await flushIfNeeded()
    }
  }

  private func flushIfNeeded() async throws {
    if buffer.count >= bufferSize {
      try await sink.write(data: buffer)
      buffer.removeAll(keepingCapacity: true)
    }
  }
}
