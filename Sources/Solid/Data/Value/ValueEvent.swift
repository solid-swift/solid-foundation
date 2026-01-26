//
//  ValueEvent.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Streaming representation of a ``Value``.
///
/// Event streams describe a single value using begin/end container events.
/// Tags are emitted as one or more `.tag` events that apply to the next value
/// (scalar or container). For stacked tags, the first tag event is the
/// outermost tag. Anchors apply to the next value event and aliases reference
/// a previously anchored node (YAML-only).
public enum ValueEvent: Sendable, Equatable {

  /// A style hint that applies to the next value event.
  case style(ValueStyle)

  /// A tag that applies to the next value event.
  case tag(Value)

  /// An anchor that applies to the next value event.
  case anchor(String)

  /// An alias that references a previously anchored node.
  case alias(String)

  /// A scalar value.
  ///
  /// - Note: This should be one of: `.null`, `.bool`, `.number`, `.bytes`, `.string`.
  case scalar(Value)

  /// Start of an array.
  case beginArray
  /// End of an array.
  case endArray

  /// Start of an object.
  case beginObject
  /// End of an object.
  case endObject

  /// A key for an object entry.
  ///
  /// - Note: Tags can be applied to keys by emitting `.tag` events before `.key`.
  case key(Value)
}
