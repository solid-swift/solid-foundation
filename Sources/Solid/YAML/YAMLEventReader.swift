//
//  YAMLEventReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 3/22/26.
//

import Foundation
import SolidData

/// A push parser for YAML that produces ``ParseEvent`` values.
///
/// Implements ``FormatEventReader`` using ``YAMLTokenizer`` and
/// ``YAMLTokenEventAdapter``. Input is consumed incrementally as bytes and
/// converted directly into parse events without first building a ``YAMLNode``
/// document tree.
///
/// Plain scalars without explicit tags are emitted as lazy ``ScalarRef``
/// values backed by a ``ParseBuffer/Region``; type inference (null / bool /
/// number / string) is deferred to materialisation time via
/// ``YAMLScalarResolver``.
public struct YAMLEventReader: ~Copyable, FormatEventReader, Sendable {

  // MARK: - State

  private var stream = YAMLTokenDocumentStream()
  private let _resolver = YAMLScalarResolver()

  // MARK: - FormatEventReader

  public init() {}

  public var format: Format { YAML.format }
  public var scalarResolver: any ScalarResolver { _resolver }
  public var isFinished: Bool { stream.isFinished }

  public mutating func feedInput(_ data: consuming Data, isFinal: Bool) {
    stream.feedInput(data, isFinal: isFinal)
  }

  public mutating func readEvent() throws -> ParseEvent? {
    try stream.readEvent()
  }
}
