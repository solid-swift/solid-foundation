//
//  IPv6Address.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

import Foundation

/// A structure representing an IPv6 address as eight 16‑bit groups.
public struct IPv6Address {
  /// Groups of the IPv6 address, each represented as a 16-bit unsigned integer.
  ///
  /// - Note: The array contains exactly 8 elements.
  public var groups: [UInt16]

  /// Initializes an IPv6Address with the 8 specified groups.
  public init(groups: [UInt16]) {
    // Ensure that the array contains exactly 8 elements.
    precondition(groups.count == 8, "IPv6 address must have exactly 8 groups.")
    self.groups = groups
  }

  public init(initializer: (inout OutputSpan<UInt8>) -> Void) {
    groups =
      Array(unsafeUninitializedCapacity: 8) { elementBuffer, initializedCount in
        elementBuffer.withMemoryRebound(to: UInt8.self) { byteBuffer in
          var span = OutputSpan(buffer: byteBuffer, initializedCount: 0)
          initializer(&span)
          initializedCount = span.finalize(for: byteBuffer) / 2
        }
      }
  }

  /// Encoded string representation of the address.
  ///
  /// Encoded the address into RFC 5952 canonical form:
  /// - Use lowercase hex without leading zeros for each 16-bit group
  /// - Compress the longest run of consecutive zero groups with "::" (length >= 2)
  ///   If there are ties, compress the first such run. Do not compress a single zero group.
  /// - The all-zero address is represented as "::".
  ///
  public var encoded: String {

    // Find the longest run of zeros
    var bestStart: Int? = nil
    var bestLen = 0
    var i = 0
    while i < 8 {
      if groups[i] == 0 {
        let start = i
        var len = 0
        while i < 8 && groups[i] == 0 {
          len += 1
          i += 1
        }
        if len > bestLen {
          bestLen = len
          bestStart = start
        }
      } else {
        i += 1
      }
    }

    // Only compress if run length >= 2
    if bestLen < 2 { bestStart = nil }

    // Build the string
    var result = ""
    i = 0
    while i < 8 {
      if let s = bestStart, i == s {
        // Insert the compression marker
        result += "::"
        i += bestLen
        // If compression reaches the end, we're done
        if i >= 8 { break }
        continue
      }

      let groupStr = String(groups[i], radix: 16)    // lowercase, no leading zeros
      if !result.isEmpty && !result.hasSuffix(":") {
        result += ":"
      }
      result += groupStr
      i += 1
    }

    return result.isEmpty ? "::" : result
  }

  /// Initializes an IPv6Address from a string using RFC 4291 section 2.2 rules.
  ///
  /// This initializer supports:
  /// - Standard notation: eight groups of 1–4 hex digits separated by colons.
  /// - Compressed notation: a single "::" that represents one or more groups of zeros.
  /// - Mixed notation: an embedded IPv4 address in the last 32 bits.
  ///
  /// - Parameter string: The IPv6 address string.
  /// - Returns: An IPv6Address instance if the string is valid; otherwise, nil.
  public static func parse(string: String) -> IPv6Address? {
    // Handle empty string
    if string.isEmpty {
      return nil
    }

    // Handle special cases
    if string == "::" {
      return IPv6Address(groups: Array(repeating: 0, count: 8))
    }
    if string == "::1" {
      var groups = Array(repeating: 0 as UInt16, count: 8)
      groups[7] = 1
      return IPv6Address(groups: groups)
    }

    // An IPv6 address must contain at least one colon.
    guard string.contains(":") else {
      return nil
    }

    // Check for an embedded IPv4 address (look for a dot).
    var ipv4Embedded: IPv4Address? = nil
    var addressPart = string

    if string.contains(".") {
      // Split the string at the last colon
      let components = string.split(separator: ":", omittingEmptySubsequences: false)

      // Find the component containing dots (IPv4 part)
      guard let ipv4Index = components.firstIndex(where: { $0.contains(".") }) else {
        return nil
      }

      // Extract the IPv4 part
      let ipv4String = String(components[ipv4Index])
      guard let ipv4 = IPv4Address.parse(string: ipv4String) else {
        return nil
      }

      ipv4Embedded = ipv4

      // Reconstruct the IPv6 part
      let ipv6Components = components[..<ipv4Index]
      addressPart = ipv6Components.joined(separator: ":")
      if addressPart.isEmpty {
        addressPart = ":"
      }
      if addressPart.hasSuffix(":") {
        addressPart.append(":")
      }
    }

    // Split on "::" (which may occur at most once).
    let parts = addressPart.split(separator: "::", omittingEmptySubsequences: false)
    if parts.count > 2 {
      return nil    // More than one "::" is not allowed.
    }

    var head: [String] = []
    var tail: [String] = []
    if parts.count == 2 {
      // Handle leading or trailing "::"
      if !parts[0].isEmpty {
        head = parts[0].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
      }
      if !parts[1].isEmpty {
        tail = parts[1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
      }
    } else {
      head = addressPart.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    }

    // Determine the total number of groups so far.
    // If an IPv4 address is embedded, it will contribute 2 groups.
    let totalGroups = head.count + tail.count + (ipv4Embedded != nil ? 2 : 0)
    if totalGroups > 8 {
      return nil
    }

    // Calculate how many groups are omitted by the "::" compression.
    let missingGroups = 8 - totalGroups

    // Build an array of group strings.
    var groupsStr: [String] = []
    groupsStr.append(contentsOf: head)
    if parts.count == 2 {
      groupsStr.append(contentsOf: Array(repeating: "0", count: missingGroups))
    }
    groupsStr.append(contentsOf: tail)

    // If an IPv4 address was present, convert it into two 16-bit groups.
    if let ipv4 = ipv4Embedded {
      let group1 = UInt16(ipv4.octets.0) << 8 | UInt16(ipv4.octets.1)
      let group2 = UInt16(ipv4.octets.2) << 8 | UInt16(ipv4.octets.3)
      groupsStr.append(String(group1, radix: 16))
      groupsStr.append(String(group2, radix: 16))
    }

    // We must now have exactly 8 groups.
    if groupsStr.count != 8 {
      return nil
    }

    // Convert each group from hex string to UInt16.
    var groups: [UInt16] = []
    for group in groupsStr {
      // Each group must be 1 to 4 hex digits.
      if group.isEmpty || group.count > 4 {
        return nil
      }
      guard let value = UInt16(group, radix: 16) else {
        return nil
      }
      groups.append(value)
    }

    if groups.count != 8 {
      return nil
    }
    return IPv6Address(groups: groups)
  }
}

extension IPv6Address: Equatable {}

extension IPv6Address: Hashable {}

extension IPv6Address: Sendable {}

extension IPv6Address: CustomStringConvertible {

  public var description: String { encoded }

}
