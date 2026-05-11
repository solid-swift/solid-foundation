//
//  BalancedEmitEventSequenceBuilder.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

/// Collects exactly one balanced ``EmitEvent`` value sequence.
///
/// A complete sequence is either one scalar event or one container event tree
/// from its begin event through its matching end event. Metadata events such as
/// tags, anchors, aliases, and styles are retained as part of the sequence and
/// do not complete it by themselves.
public struct BalancedEmitEventSequenceBuilder: Sendable {

  public enum Error: Swift.Error, Sendable {
    case unexpectedContainerEnd
  }

  public private(set) var events: [EmitEvent] = []
  private var depth = 0
  public private(set) var isComplete = false

  public init() {}

  public mutating func append(_ event: EmitEvent) throws {
    events.append(event)
    switch event {
    case .beginArray, .beginObject:
      depth += 1

    case .endArray, .endObject:
      depth -= 1
      guard depth >= 0 else {
        throw Error.unexpectedContainerEnd
      }
      if depth == 0 {
        isComplete = true
      }

    case .scalar:
      if depth == 0 {
        isComplete = true
      }

    case .style, .tag, .anchor, .alias:
      break
    }
  }
}
