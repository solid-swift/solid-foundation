//
//  Datas.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/3/25.
//

import Foundation

extension Data {

  /// Decodes a base encoded string accordiing to specified encoding.
  ///
  /// - Parameters:
  ///   - string: The base encoded string to decode.
  ///   - encoding: The base encoding to use for decoding.
  ///
  public init?(baseEncodedString string: String, encoding: BaseEncoding) {
    do {
      let size = try encoding.decodedSize(of: string)
      var data = Data(repeating: 0, count: size)
      try data.withUnsafeMutableBytes { rawBuf in
        let buf = rawBuf.bindMemory(to: UInt8.self)
        var out = OutputSpan<UInt8>(buffer: buf, initializedCount: 0)
        try encoding.decode(string, into: &out)
        _ = out.finalize(for: buf)
      }
      self = data
    } catch {
      return nil
    }
  }

  /// Encodes the data using the specified base encoding.
  ///
  /// - Parameter encoding: The base encoding to use for encoding.
  /// - Returns: The base encoded string.
  ///
  public func baseEncoded(using encoding: BaseEncoding) -> String {
    return encoding.encode(data: self)
  }
}
