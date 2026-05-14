//
//  ParseEvent.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/21/26.
//

/// Streaming event produced by format parsers with lazy scalar materialization.
///
/// Unlike ``EmitEvent`` (used for writing), scalars and tags carry ``ScalarRef``
/// values that defer materialization until requested by the consumer. This enables
/// zero-copy parsing where unused values are never decoded.
///
/// After ``beginObject(count:)``, events implicitly alternate between keys and values.
/// The first event is a key, the next is its value, then the next is a key, etc.,
/// until ``endObject``. Keys can be any event sequence (scalar, nested container, etc.).
public enum ParseEvent: Sendable {

  /// A style hint that applies to the next value event.
  case style(ValueStyle)

  /// A tag that applies to the next value event.
  case tag(ScalarRef)

  /// An anchor that applies to the next value event (YAML-only).
  case anchor(String)

  /// An alias that references a previously anchored node (YAML-only).
  case alias(String)

  /// A scalar value with deferred materialization.
  case scalar(ScalarRef)

  /// Start of an array.
  ///
  /// - Parameter count: Optional item count hint for pre-allocation.
  case beginArray(count: Int?)

  /// End of an array.
  case endArray

  /// Start of an object.
  ///
  /// After this event, subsequent events alternate key/value until ``endObject``.
  ///
  /// - Parameter count: Optional entry count hint for pre-allocation.
  case beginObject(count: Int?)

  /// End of an object.
  case endObject

  /// Convert an ``EmitEvent`` to a ``ParseEvent`` by wrapping values in
  /// pre-materialized ``ScalarRef`` instances.
  public init(from emitEvent: EmitEvent) {
    switch emitEvent {
    case .style(let style):
      self = .style(style)
    case .tag(let value):
      self = .tag(.materialized(value))
    case .anchor(let name):
      self = .anchor(name)
    case .alias(let name):
      self = .alias(name)
    case .scalar(let value):
      self = .scalar(.materialized(value))
    case .beginArray(let count):
      self = .beginArray(count: count)
    case .endArray:
      self = .endArray
    case .beginObject(let count):
      self = .beginObject(count: count)
    case .endObject:
      self = .endObject
    }
  }
}
