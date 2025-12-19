//
//  UUID-HashedNameFormat.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/21/25.
//

import Foundation
import Crypto


public extension UUID {

  /// Source for Hashed Namespace/Name UUID.
  ///
  struct HashedNameFormat<Hash: Sequence<UInt8>>: Sendable {

    public typealias Hasher = @Sendable (Data) -> Hash

    public let version: Version
    public let hasher: Hasher

    public func pack(namespace: UUID, name: Data, out: inout OutputSpan<UInt8>) {
      precondition([.v3, .v5].contains(version))

      var data = Data(capacity: UUID.byteCount + name.count)
      namespace.withUnsafeBytes { data.append($0) }
      data.append(name)

      let hash = hasher(data).prefix(16)

      for (idx, byte) in hash.enumerated() {
        let modByte =
          switch idx {
          case 6: (byte & 0x0f) | version.nibble
          case 8: (byte & 0x3f) | 0x80
          default: byte
          }
        out.append(modByte)
      }

      assert(out.count == 16, "Hash produced \(out.count) bytes, expected 16")
    }
  }
}
