//
//  JSONStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
/// Synchronous JSON stream reader that produces ``ValueEvent`` values.
public final class JSONStreamReader: FormatStreamReader {

  private var parser = JSONPushParser()
  private var finished = false

  public init() {}

  public var format: Format { JSON.format }

  public func read(
    input: Data,
    isFinal: Bool,
    output: inout OutputSpan<ValueEvent>
  ) throws -> FormatStreamReadStatus {
    guard !finished else { return .endOfStream }

    if !input.isEmpty || isFinal {
      parser.feed(input, isFinal: isFinal)
    }

    var produced = false
    while !output.isFull {
      if let event = try parser.nextEvent() {
        output.append(event)
        produced = true
        continue
      }
      if parser.isFinished {
        finished = true
        return produced ? .producedOutput : .endOfStream
      }
      return produced ? .producedOutput : .needMoreInput
    }

    return .producedOutput
  }
}
