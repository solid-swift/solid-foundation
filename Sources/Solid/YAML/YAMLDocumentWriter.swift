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
  private var output = Data()
  private var wroteDocument = false

  public init(options: Options = .default) {
    self.options = options
  }

  public func write(_ document: YAMLValueDocument) throws {
    if !output.isEmpty, output.last != 0x0A {
      output.append(0x0A)
    }
    try append(document: document)
  }

  public func writeAll(_ documents: [YAMLValueDocument]) throws {
    for document in documents {
      try write(document)
    }
  }

  public func data() -> Data {
    output
  }

  private func append(document: YAMLValueDocument) throws {
    let needsStart = document.explicitStart || wroteDocument
    let writer = YAMLValueWriter(options: .init(indent: options.indent))

    if needsStart {
      output.append(contentsOf: "---\n".utf8)
    }
    output.append(try writer.write(document.value))
    if output.last != 0x0A {
      output.append(0x0A)
    }
    if document.explicitEnd {
      output.append(contentsOf: "...\n".utf8)
    }
    wroteDocument = true
  }
}
