//
//  YAMLStreamWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Async YAML stream writer that consumes ``ValueEvent`` values.
public final class YAMLStreamWriter: FormatStreamWriter {

  static let anchorTagPrefix = YAMLStreamEncoder.anchorTagPrefix

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

  private var driver: FormatStreamWriterDriver<YAMLStreamEncoder>
  private var finished = false

  public init(sink: any Sink, bufferSize: Int = BufferedSink.segmentSize, options: Options = .default) {
    self.driver = FormatStreamWriterDriver(
      encoder: YAMLStreamEncoder(options: options),
      sink: sink,
      bufferSize: bufferSize
    )
  }

  public var format: Format { YAML.format }

  public func write(_ event: ValueEvent) async throws {
    guard !finished else { throw YAML.EmitError.invalidState("Writer already finished") }
    try await driver.write(event)
  }

  public func finish() async throws {
    guard !finished else { return }
    try await driver.finish()
    finished = true
  }

  public func close() async throws {
    try await finish()
    try await driver.close()
  }
}
