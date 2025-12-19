//
//  UUID-V7Format.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//


public extension UUID {

  enum V7Format {

    public static func pack(
      timestamp: UInt64,
      clockSequence: UInt16,
      randomGenerator: inout some RandomNumberGenerator,
      out: inout OutputSpan<UInt8>
    ) {

      var timestampBE = timestamp.bigEndian
      Swift.withUnsafeBytes(of: &timestampBE) { buf in
        // time (48)
        for i in 2..<8 { out.append(buf[i]) }
      }

      var clockSequenceBE = clockSequence.bigEndian
      Swift.withUnsafeBytes(of: &clockSequenceBE) { buf in
        // version (4) + rand_a (12)
        out.append((buf[0] & 0x0f) | 0x70)    // version: 7
        out.append(buf[1])
      }

      // variant (2) + rand_b (62)
      out.append((randomGenerator.next() & 0x3F) | 0x80)    // variant: rfc
      for _ in 1..<8 { out.append(randomGenerator.next()) }
    }

    public static func unpack(in span: Span<UInt8>, timestamp: inout UInt64, clockSequence: inout UInt16) {

      var timestampBE: UInt64 = 0
      withUnsafeMutableBytes(of: &timestampBE) { ptr in
        for i in 0..<6 { ptr[i + 2] = span[i] }
      }
      timestamp = UInt64(bigEndian: timestampBE)

      var clockSequenceBE: UInt16 = 0
      withUnsafeMutableBytes(of: &clockSequenceBE) { ptr in
        ptr[0] = span[6] & 0x0f
        ptr[1] = span[7]
      }
      clockSequence = UInt16(bigEndian: clockSequenceBE)
    }

  }
}
