//
//  CanonicalUUIDStringEncoding.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 9/23/25.
//


/// Canonical UUID encoding (8-4-4-4-12 lowercase hex with hyphens) restricted to UUID only.
public enum CanonicalUUIDStringEncoding: UniqueIDStringEncoding {
  case instance

  public typealias ID = UUID

  public enum Error: Swift.Error {
    case invalidLength
    case invalidCharacter(at: Int)
    case invalidString
  }

  @inline(__always)
  private func hexNibble(_ c: UInt8, at pos: Int) throws -> UInt8 {
    switch c {
    case 48...57: return c &- 48    // '0'...'9'
    case 97...102: return c &- 87    // 'a'...'f'
    case 65...70: return c &- 55    // 'A'...'F'
    default:
      throw Error.invalidCharacter(at: pos)
    }
  }

  public func encode(_ id: UUID) -> String {
    // Assuming `id.storage` is `[UInt8]` length 16 in RFC 4122 byte order.
    let bytes = id.storage
    let digits = Array("0123456789abcdef".utf8)

    return String(unsafeUninitializedCapacity: 36) { ptr in
      var i = 0
      for bIndex in 0..<16 {
        // Hyphens after byte 4, 6, 8, 10 (8-4-4-4-12 hex digits)
        if bIndex == 4 || bIndex == 6 || bIndex == 8 || bIndex == 10 {
          ptr[i] = 45    // '-'
          i += 1
        }

        let byte = bytes[bIndex]
        ptr[i] = digits[Int(byte >> 4)]
        i += 1
        ptr[i] = digits[Int(byte & 0x0F)]
        i += 1
      }
      return i    // should be 36
    }
  }

  public func decode(_ string: String) throws -> UUID {
    let utf8 = Array(string.utf8)
    guard utf8.count == 36 else { throw Error.invalidLength }

    // Canonical hyphen positions
    if utf8[8] != 45 { throw Error.invalidCharacter(at: 8) }
    if utf8[13] != 45 { throw Error.invalidCharacter(at: 13) }
    if utf8[18] != 45 { throw Error.invalidCharacter(at: 18) }
    if utf8[23] != 45 { throw Error.invalidCharacter(at: 23) }

    return try UUID { out in
      var i = 0

      while i < 36 {
        if i == 8 || i == 13 || i == 18 || i == 23 {
          i += 1
          continue
        }

        // Two hex chars per byte
        let hi = try hexNibble(utf8[i], at: i)
        let lo = try hexNibble(utf8[i + 1], at: i + 1)
        out.append((hi << 4) | lo)
        i += 2
      }

      guard out.count == 16 else { throw Error.invalidString }
    }
  }
}

public extension UniqueIDStringEncoding where Self == CanonicalUUIDStringEncoding {

  static var canonical: Self { Self.instance }

}
