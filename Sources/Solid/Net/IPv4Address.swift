//
//  IPv4Address.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

/// A structure representing an IPv4 address as four 8‑bit octets.
public struct IPv4Address {
  /// The first octet of the IPv4 address.
  public var a: UInt8
  /// The second octet of the IPv4 address.
  public var b: UInt8
  /// The third octet of the IPv4 address.
  public var c: UInt8
  /// The fourth octet of the IPv4 address.
  public var d: UInt8

  /// The four octets of the IPv4 address as a tuple.
  public var octets: (UInt8, UInt8, UInt8, UInt8) {
    get { (a, b, c, d) }
    set {
      a = newValue.0
      b = newValue.1
      c = newValue.2
      d = newValue.3
    }
  }

  /// Initializes an IPv4Address with the given octets.
  /// - Parameters:
  ///   - a: The first octet (0-255).
  ///   - b: The second octet (0-255).
  ///   - c: The third octet (0-255).
  ///   - d: The fourth octet (0-255).
  public init(a: UInt8, b: UInt8, c: UInt8, d: UInt8) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
  }

  /// Initializes an IPv4Address with the given octets.
  /// - Parameters:
  ///  - octets: A tuple containing four octets (0-255).
  public init(octets: (UInt8, UInt8, UInt8, UInt8)) {
    self.a = octets.0
    self.b = octets.1
    self.c = octets.2
    self.d = octets.3
  }

  public init(initializer: (inout OutputSpan<UInt8>) -> Void) {
    var address = Self(a: 0, b: 0, c: 0, d: 0)
    withUnsafeMutableBytes(of: &address) { rawBuf in
      let buf = rawBuf.assumingMemoryBound(to: UInt8.self)
      var out = OutputSpan(buffer: buf, initializedCount: 0)
      initializer(&out)
      _ = out.finalize(for: buf)
    }
    self = address
  }

  /// Encoded string representation of the address.
  public var encoded: String { "\(a).\(b).\(c).\(d)" }

  private static nonisolated(unsafe) let parseRegex =
    #/^(?<a>25[0-5]|2[0-4]\d|1\d{2}|[1-9]\d|\d)\.(?<b>25[0-5]|2[0-4]\d|1\d{2}|[1-9]\d|\d)\.(?<c>25[0-5]|2[0-4]\d|1\d{2}|[1-9]\d|\d)\.(?<d>25[0-5]|2[0-4]\d|1\d{2}|[1-9]\d|\d)$/#

  /// Parses an IPv4Address from a string if it matches the RFC 2673 dotted‑quad syntax.
  ///
  /// The ABNF for a dotted‑quad is roughly:
  ///    dotted-quad  = dec-octet "." dec-octet "." dec-octet "." dec-octet
  ///    dec-octet    = DIGIT / ( %x31-39 DIGIT ) / ( "1" 2DIGIT ) / ( "2" ( %x30-34 DIGIT / "5" %x30-35 ) )
  ///
  /// The following regex uses named capture groups for each octet ("a", "b", "c", "d")
  /// and validates each to be in the range 0–255, rejecting leading zeros.
  ///
  /// - Parameter string: The IPv4 address string in dotted-quad format.
  /// - Returns: An IPv4Address instance if the input is valid; otherwise, nil.
  public static func parse(string: String) -> IPv4Address? {

    // Ensure the entire input matches the pattern.
    guard let match = string.wholeMatch(of: Self.parseRegex) else {
      return nil
    }

    // Extract the octet components.
    guard
      let a = UInt8(match.output.a),
      let b = UInt8(match.output.b),
      let c = UInt8(match.output.c),
      let d = UInt8(match.output.d)
    else {
      return nil
    }

    return IPv4Address(octets: (a, b, c, d))
  }
}

extension IPv4Address: Equatable {}

extension IPv4Address: Hashable {}

extension IPv4Address: Sendable {}

extension IPv4Address: CustomStringConvertible {

  public var description: String { encoded }

}
