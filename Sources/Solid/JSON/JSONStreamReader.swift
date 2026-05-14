//
//  JSONStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/14/26.
//

import SolidData

/// Synchronous JSON stream reader that produces ``ParseEvent`` values.
///
/// A typealias for ``BufferedStreamDecoder`` wrapping ``JSONEventReader``,
/// conforming to ``FormatStreamReader``.
public typealias JSONStreamReader = BufferedStreamDecoder<JSONEventReader>
public typealias JSONDocumentEventReader = DocumentFramedStreamReader<JSONStreamReader>

extension BufferedStreamDecoder where Reader == JSONEventReader {

  /// Create a JSON stream reader with default settings.
  public init() {
    self.init(reader: JSONEventReader())
  }
}

extension DocumentFramedStreamReader where Reader == JSONStreamReader {

  /// Create a JSON document event reader that wraps one root value in a
  /// synthetic document boundary.
  public init() {
    self.init(reader: JSONStreamReader())
  }
}
