//
//  CBORStreamReader.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 2/17/26.
//

import SolidData

/// Synchronous CBOR stream reader that produces ``ParseEvent`` values.
///
/// A typealias for ``BufferedStreamDecoder`` wrapping ``CBOREventReader``,
/// conforming to ``FormatStreamReader``.
public typealias CBORStreamReader = BufferedStreamDecoder<CBOREventReader>
public typealias CBORDocumentEventReader = DocumentFramedStreamReader<CBORStreamReader>

extension BufferedStreamDecoder where Reader == CBOREventReader {

  /// Create a CBOR stream reader with default settings.
  public init(options: CBORValueReader.Options = CBORValueReader.Options()) {
    self.init(reader: CBOREventReader(options: options))
  }
}

extension DocumentFramedStreamReader where Reader == CBORStreamReader {

  /// Create a CBOR document event reader. Each root item is framed as one
  /// synthetic document.
  public init(options: CBORValueReader.Options = CBORValueReader.Options()) {
    self.init(reader: CBORStreamReader(options: options))
  }
}
