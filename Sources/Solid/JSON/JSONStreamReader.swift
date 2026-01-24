//
//  JSONStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import Foundation
import SolidData
import SolidIO


/// Async JSON stream reader that produces ``ValueEvent`` values.
public final class JSONStreamReader: FormatStreamReader {

  private let source: any Source
  private let bufferSize: Int
  private var parser = JSONPushParser()
  private var reachedEOF = false
  private var finished = false

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize) {
    self.source = source
    self.bufferSize = bufferSize
  }

  public var format: Format { JSON.format }

  public func next() async throws -> ValueEvent? {
    guard !finished else { return nil }

    while true {
      if let event = try parser.nextEvent() {
        return event
      }

      if reachedEOF {
        finished = true
        return nil
      }

      guard let data = try await source.read(max: bufferSize) else {
        reachedEOF = true
        parser.feed(Data(), isFinal: true)
        continue
      }

      if !data.isEmpty {
        parser.feed(data)
      }
    }
  }
}
