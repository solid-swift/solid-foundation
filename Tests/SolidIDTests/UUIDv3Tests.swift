//
//  UUIDv3Tests.swift
//

import Testing
@testable import SolidID


@Suite struct `UUIDv3 Tests` {

  private let name = "example.org"

  @Test func `version & variant`() {
    let u = UUID.v3(namespace: .dns, name: name)
    #expect(u.version == .v3)
    #expect(u.variant == .rfc)
  }

  @Test func deterministic() throws {
    let a = UUID.v3(namespace: .dns, name: name)
    let b = UUID.v3(namespace: .dns, name: name)
    #expect(a.description == b.description)
    // Change name -> different
    let c = UUID.v3(namespace: .dns, name: "example.com")
    #expect(a.description != c.description)
  }

  @Test(arguments: [
    (UUID.Namespace.dns, "www.example.com", "5df41881-3aed-3515-88a7-2f4a814cf09e")
  ])
  func `rfc test vectors`(args: (ns: UUID.Namespace, name: String, expected: String)) throws {

    #expect(UUID.v3(namespace: args.ns, name: args.name).encode(using: .canonical) == args.expected)
  }
}
