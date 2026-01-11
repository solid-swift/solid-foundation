//
//  IPv6AddressTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidNet
import Testing
import Foundation


@Suite("IPv6 Address Tests")
final class IPv6AddressTests {

  // MARK: - Initialization

  @Test func `init groups`() {

    let a = IPv6Address(groups: [0x2001, 0x0db8, 0x85a3, 0xffff, 0xffff, 0x8a2e, 0x0370, 0x7334])

    #expect(a.groups[0] == 0x2001)
    #expect(a.groups[1] == 0x0db8)
    #expect(a.groups[2] == 0x85a3)
    #expect(a.groups[3] == 0xffff)
    #expect(a.groups[4] == 0xffff)
    #expect(a.groups[5] == 0x8a2e)
    #expect(a.groups[6] == 0x0370)
    #expect(a.groups[7] == 0x7334)
  }

  // MARK: - Parsing

  @Test("Parse standard IPv6 addresses")
  func parseStandardIPv6Addresses() {
    #expect(IPv6Address.parse(string: "2001:0db8:85a3:0000:0000:8a2e:0370:7334") != nil)
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334") != nil)
    #expect(IPv6Address.parse(string: "2001:db8:85a3::8a2e:370:7334") != nil)
    #expect(IPv6Address.parse(string: "::1") != nil)
    #expect(IPv6Address.parse(string: "::") != nil)
  }

  @Test("Parse IPv6 addresses with embedded IPv4")
  func parseIPv6WithEmbeddedIPv4() {
    #expect(IPv6Address.parse(string: "::ffff:192.168.1.1") != nil)
    #expect(IPv6Address.parse(string: "2001:db8::192.168.1.1") != nil)
    #expect(IPv6Address.parse(string: "::192.168.1.1") != nil)
  }

  @Test("Reject invalid IPv6 addresses")
  func rejectInvalidIPv6Addresses() {
    #expect(IPv6Address.parse(string: "") == nil)
    #expect(IPv6Address.parse(string: "2001:db8::1::2") == nil)    // Multiple :: not allowed
    #expect(IPv6Address.parse(string: "2001:db8:85a3:00000:0000:8a2e:0370:7334") == nil)    // Too many digits
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334:1234") == nil)    // Too many groups
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370") == nil)    // Too few groups
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334:") == nil)    // Trailing colon
    #expect(IPv6Address.parse(string: ":2001:db8:85a3:0:0:8a2e:370:7334") == nil)    // Leading colon
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334:") == nil)    // Trailing colon
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334:") == nil)    // Trailing colon
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334:") == nil)    // Trailing colon
  }

  @Test("Verify group values after parsing")
  func verifyGroupValues() throws {
    let address = try #require(IPv6Address.parse(string: "2001:0db8:85a3:0000:0000:8a2e:0370:7334"))
    #expect(address.groups[0] == 0x2001)
    #expect(address.groups[1] == 0x0db8)
    #expect(address.groups[2] == 0x85a3)
    #expect(address.groups[3] == 0x0000)
    #expect(address.groups[4] == 0x0000)
    #expect(address.groups[5] == 0x8a2e)
    #expect(address.groups[6] == 0x0370)
    #expect(address.groups[7] == 0x7334)
  }

  @Test("Verify compressed address expansion")
  func verifyCompressedAddressExpansion() throws {
    let address = try #require(IPv6Address.parse(string: "2001:db8::8a2e:370:7334"))
    #expect(address.groups[0] == 0x2001)
    #expect(address.groups[1] == 0x0db8)
    #expect(address.groups[2] == 0x0000)
    #expect(address.groups[3] == 0x0000)
    #expect(address.groups[4] == 0x0000)
    #expect(address.groups[5] == 0x8a2e)
    #expect(address.groups[6] == 0x0370)
    #expect(address.groups[7] == 0x7334)
  }

  @Test("Verify embedded IPv4 conversion")
  func verifyEmbeddedIPv4Conversion() throws {
    let address = try #require(IPv6Address.parse(string: "::ffff:192.168.1.1"))
    #expect(address.groups[0] == 0x0000)
    #expect(address.groups[1] == 0x0000)
    #expect(address.groups[2] == 0x0000)
    #expect(address.groups[3] == 0x0000)
    #expect(address.groups[4] == 0x0000)
    #expect(address.groups[5] == 0xffff)
    #expect(address.groups[6] == 0xc0a8)    // 192.168
    #expect(address.groups[7] == 0x0101)    // 1.1
  }

  @Test("Parse special IPv6 addresses")
  func parseSpecialIPv6Addresses() {
    // Link-local addresses
    #expect(IPv6Address.parse(string: "fe80::1") != nil)
    #expect(IPv6Address.parse(string: "fe80::1234:5678:9abc:def0") != nil)

    // Multicast addresses
    #expect(IPv6Address.parse(string: "ff02::1") != nil)    // All nodes
    #expect(IPv6Address.parse(string: "ff02::2") != nil)    // All routers

    // Deprecated site-local addresses
    #expect(IPv6Address.parse(string: "fec0::1") != nil)

    // IPv6-compatible IPv4 addresses (deprecated)
    #expect(IPv6Address.parse(string: "::192.168.1.1") != nil)
  }

  @Test("Parse IPv6 addresses with mixed case")
  func parseIPv6AddressesWithMixedCase() {
    #expect(IPv6Address.parse(string: "2001:0DB8:85a3:0000:0000:8a2e:0370:7334") != nil)
    #expect(IPv6Address.parse(string: "2001:db8:85A3:0:0:8A2E:370:7334") != nil)
    #expect(IPv6Address.parse(string: "2001:DB8:85a3::8a2e:370:7334") != nil)
  }

  @Test("Parse IPv6 addresses with edge cases")
  func parseIPv6AddressesWithEdgeCases() {
    // Maximum digits in a group (4)
    #expect(IPv6Address.parse(string: "2001:0db8:85a3:0000:0000:8a2e:0370:7334") != nil)

    // Minimum digits in a group (1)
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0:0:8a2e:370:7334") != nil)

    // All zeros in a group
    #expect(IPv6Address.parse(string: "2001:db8:85a3:0000:0000:8a2e:370:7334") != nil)

    // All ones in a group
    #expect(IPv6Address.parse(string: "2001:db8:85a3:ffff:ffff:8a2e:370:7334") != nil)
  }

  @Test("Verify special address group values")
  func verifySpecialAddressGroupValues() throws {
    // Verify loopback address
    let loopback = try #require(IPv6Address.parse(string: "::1"))
    #expect(loopback.groups[0] == 0x0000)
    #expect(loopback.groups[1] == 0x0000)
    #expect(loopback.groups[2] == 0x0000)
    #expect(loopback.groups[3] == 0x0000)
    #expect(loopback.groups[4] == 0x0000)
    #expect(loopback.groups[5] == 0x0000)
    #expect(loopback.groups[6] == 0x0000)
    #expect(loopback.groups[7] == 0x0001)

    // Verify unspecified address
    let unspecified = try #require(IPv6Address.parse(string: "::"))
    for i in 0..<8 {
      #expect(unspecified.groups[i] == 0x0000)
    }
  }

  // MARK: - Formatting

  @Test("Canonical compression and lowercase hex")
  func testCanonicalBasic() {
    let a = IPv6Address(groups: [0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334])
    let expected = ["2001", "db8", "85a3", "", "8a2e", "370", "7334"].joined(separator: ":")
    #expect(a.encoded == expected)
  }

  @Test("Compress longest run of zeros")
  func testCompressLongestRun() {
    let a = IPv6Address(groups: [0x2001, 0x0db8, 0x0000, 0x0000, 0x0000, 0x0000, 0x0002, 0x0001])
    let expected = ["2001", "db8", "", "2", "1"].joined(separator: ":")
    #expect(a.encoded == expected)
  }

  @Test("Prefer first run on tie; only one run compressed")
  func testTiePrefersFirstRun() {
    let a = IPv6Address(groups: [0x2001, 0x0db8, 0x0000, 0x0000, 0x0001, 0x0000, 0x0000, 0x0001])
    let expected = ["2001", "db8", "", "1", "0", "0", "1"].joined(separator: ":")
    #expect(a.encoded == expected)
  }

  @Test("Do not compress a single zero group")
  func testDoNotCompressSingleZero() {
    let a = IPv6Address(groups: [0x2001, 0x0db8, 0x85a3, 0x0000, 0x8a2e, 0x0370, 0x7334, 0x0000])
    let expected = ["2001", "db8", "85a3", "0", "8a2e", "370", "7334", "0"].joined(separator: ":")
    #expect(a.encoded == expected)
  }

  @Test("Loopback ::1 and unspecified ::")
  func testLoopbackAndUnspecified() {
    let loopback = IPv6Address(groups: [0, 0, 0, 0, 0, 0, 0, 1])
    #expect(loopback.encoded == "::1")
    let unspecified = IPv6Address(groups: [0, 0, 0, 0, 0, 0, 0, 0])
    #expect(unspecified.encoded == "::")
  }

  @Test("IPv4-mapped renders as hex groups in canonical form")
  func testIPv4Mapped() {
    let a = IPv6Address(groups: [0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xffff, 0xc0a8, 0x0101])
    #expect(a.encoded == "::ffff:c0a8:101")
  }

}
