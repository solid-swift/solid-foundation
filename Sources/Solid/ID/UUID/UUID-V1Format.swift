//
//  UUID-V1Format.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 12/23/25.
//

import SolidTempo


public extension UUID {

  enum V1Format {

    public static func pack(
      timestamp: UInt64,
      clockSequence: UInt16,
      nodeID: NodeID,
      out: inout OutputSpan<UInt8>
    ) {

      var timestampBE = timestamp.bigEndian
      Swift.withUnsafeBytes(of: &timestampBE) { ptr in
        // time_low (32) big-endian
        for i in 4..<8 { out.append(ptr[i]) }
        // time_mid (16) big-endian
        for i in 2..<4 { out.append(ptr[i]) }
        // version (4) + time_high (12) big-endian
        out.append((ptr[0] & 0x0f) | 0x10)    // version: 1
        out.append(ptr[1])
      }

      var currentclockSequenceBE = clockSequence.bigEndian
      Swift.withUnsafeBytes(of: &currentclockSequenceBE) { ptr in
        // variant (2) + clock_seq (14) big-endian
        out.append((ptr[0] & 0x3f) | 0x80)    // variant: rfc
        out.append(ptr[1])
      }

      // node (48) big-endian
      for i in 0..<6 { out.append(nodeID[i]) }
    }

    public static func unpack(in span: borrowing Span<UInt8>, timestamp: inout UInt64, clockSequence: inout UInt16) {

      var timestampBE: UInt64 = 0
      withUnsafeMutableBytes(of: &timestampBE) { ptr in
        for idx in 4..<8 { ptr[idx] = span[idx - 4] }
        for idx in 2..<4 { ptr[idx] = span[idx + 2] }
        ptr[0] = span[6] & 0x0f
        ptr[1] = span[7]
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
