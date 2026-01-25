//
//  YAMLStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation
import SolidData
import SolidIO

/// Async YAML stream reader that produces ``ValueEvent`` values.
public final class YAMLStreamReader: FormatStreamReader {

  private let source: any Source
  private let bufferSize: Int
  private var emitter = YAMLEventEmitter()
  private var queue: [ValueEvent] = []
  private var finished = false

  public init(source: any Source, bufferSize: Int = BufferedSource.segmentSize) {
    self.source = source
    self.bufferSize = bufferSize
  }

  public var format: Format { YAML.format }

  public func next() async throws -> ValueEvent? {
    if !queue.isEmpty {
      return queue.removeFirst()
    }
    guard !finished else { return nil }

    let data = try await readAll()
    guard let text = String(data: data, encoding: .utf8) else {
      throw YAML.Error.invalidUTF8
    }

    var parser = try YAMLParser(text: text)
    let node = try parser.parseFirstDocument()
    queue = try emitter.emit(node: node)
    finished = true
    return queue.isEmpty ? nil : queue.removeFirst()
  }

  private func readAll() async throws -> Data {
    var buffer = Data()
    while let chunk = try await source.read(max: bufferSize) {
      buffer.append(chunk)
    }
    return buffer
  }
}
