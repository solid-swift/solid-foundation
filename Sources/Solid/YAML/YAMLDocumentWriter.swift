//
//  YAMLDocumentWriter.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData

/// Synchronous YAML writer that emits full document streams.
public final class YAMLDocumentWriter {

  public struct Options: Sendable {
    public static let `default` = Self()
    public var indent: Int

    public init(indent: Int = 2) {
      self.indent = indent
    }
  }

  private let options: Options
  private var output = ""
  private var wroteDocument = false

  public init(options: Options = .default) {
    self.options = options
  }

  public func write(_ document: YAMLValueDocument) throws {
    if !output.isEmpty, !output.hasSuffix("\n") {
      output.append("\n")
    }
    let rendered = try render(document: document)
    output.append(rendered)
  }

  public func writeAll(_ documents: [YAMLValueDocument]) throws {
    for document in documents {
      try write(document)
    }
  }

  public func data() -> Data {
    Data(output.utf8)
  }

  private func render(document: YAMLValueDocument) throws -> String {
    let needsStart = document.explicitStart || wroteDocument
    let writer = YAMLValueWriter(options: .init(indent: options.indent))
    try writer.write(document.value)
    let body = String(decoding: writer.data(), as: UTF8.self)

    var chunk = ""
    if needsStart {
      chunk.append("---\n")
    }
    chunk.append(body)
    if !chunk.hasSuffix("\n") {
      chunk.append("\n")
    }
    if document.explicitEnd {
      chunk.append("...\n")
    }
    wroteDocument = true
    return chunk
  }
}
