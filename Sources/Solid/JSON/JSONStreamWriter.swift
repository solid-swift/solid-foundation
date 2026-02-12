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

  private var driver: FormatStreamWriterDriver<JSONStreamEncoder>
  private var finished = false

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.driver = FormatStreamWriterDriver(
      encoder: JSONStreamEncoder(options: options),
      sink: sink,
      bufferSize: bufferSize
    )
  }

  public var format: Format { JSON.format }

  public func write(_ event: ValueEvent) async throws {
    guard !finished else { throw Error.alreadyFinished }
    try await driver.write(event)
  }

  public func finish() async throws {
    guard !finished else { throw Error.alreadyFinished }
    try await driver.finish()
    finished = true
  }

  public func close() async throws {
    try await finish()
    try await driver.close()
  }
}
