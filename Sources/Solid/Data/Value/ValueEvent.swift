//
//  ValueEvent.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

/// Streaming event for writing ``Value`` data to a format encoder.
///
/// Event streams describe a single value using begin/end container events.
/// Tags are emitted as one or more `.tag` events that apply to the next value
/// (scalar or container). For stacked tags, the first tag event is the
/// outermost tag. Anchors apply to the next value event and aliases reference
/// a previously anchored node (YAML-only).
///
/// After ``beginObject(count:)``, scalars alternate implicitly between keys and
/// values — the first scalar is a key, the next is its value, and so on until
/// ``endObject``. No explicit key event is needed.
///
/// For reading/parsing, see ``ParseEvent`` which carries ``ScalarRef`` for
/// lazy/zero-copy scalar access.
public enum EmitEvent: Sendable, Equatable {

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
  ///
  /// - Parameter count: Optional item count hint for the array.
  case beginArray(count: Int?)
  /// End of an array.
  case endArray

  /// Start of an object.
  ///
  /// - Parameter count: Optional entry count hint for the object.
  case beginObject(count: Int?)
  /// End of an object.
  case endObject
}

/// Backward-compatibility aliases.
public typealias ValueEvent = EmitEvent
public typealias ValueEventDecoder = EmitEventDecoder
public typealias ValueEventEncoder = EmitEventEncoder
