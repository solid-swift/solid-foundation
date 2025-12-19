//
//  UUID-V6Format.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//

import SolidTempo


public extension UUID {

  enum V6Format {

    public static func pack(
      timestamp: UInt64,
      clockSequence: UInt16,
      nodeID: NodeID,
      out: inout OutputSpan<UInt8>
    ) {

      var timestampBE = timestamp.bigEndian
      Swift.withUnsafeBytes(of: &timestampBE) { ptr in
        // time_high (32) big-endian + time_mid (16) big-endian
        for i in 0..<6 { out.append((ptr[i] << 4) | (ptr[i + 1] >> 4)) }
        // version (4) + time_low (12) big-endian
        out.append((ptr[6] & 0x0f) | 0x60)    // version: 6
        out.append(ptr[7])
      }

      var currentclockSequenceBE = clockSequence.bigEndian
      Swift.withUnsafeBytes(of: &currentclockSequenceBE) { ptr in
        // clock_seq (14)
        out.append((ptr[0] & 0x3f) | 0x80)    // variant: rfc
        out.append(ptr[1])
      }

      // node (48) big-endian
      for i in 0..<6 { out.append(nodeID[i]) }
    }

    public static func unpack(in span: Span<UInt8>, timestamp: inout UInt64, clockSequence: inout UInt16) {

      var timestampBE: UInt64 = 0
      withUnsafeMutableBytes(of: &timestampBE) { ptr in
        ptr[0] = span[0] >> 4
        for idx in 1..<6 {
          ptr[idx] = (span[idx - 1] << 4) | (span[idx] >> 4)
        }
        ptr[6] = ((span[5] & 0x0f) << 4) | (span[6] & 0x0f)
        ptr[7] = span[7]
      }
      timestamp = UInt64(bigEndian: timestampBE)

      var clockSequenceBE: UInt16 = 0
      withUnsafeMutableBytes(of: &clockSequenceBE) { ptr in
        ptr[0] = span[8] & 0x3f
        ptr[1] = span[9]
      }
      clockSequence = UInt16(bigEndian: clockSequenceBE)
    }

  }
}
