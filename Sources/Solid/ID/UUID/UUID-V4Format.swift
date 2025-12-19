//
//  UUID-V4Format.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public extension UUID {

  enum V4Format {

    public static func pack(
      randomGenerator: inout any RandomNumberGenerator,
      out: inout OutputSpan<UInt8>
    ) {

      for idx in 0..<16 {
        let byte: UInt8 = randomGenerator.next()
        let modByte =
          switch idx {
          case 6: (byte & 0x0F) | 0x40    // version: 4
          case 8: (byte & 0x3F) | 0x80    // variant: rfc
          default: byte
          }
        out.append(modByte)
      }
    }
  }
}
