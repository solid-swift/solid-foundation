//
//  UUIDv5Tests.swift
//

import Testing
@testable import SolidID


@Suite struct `UUIDv5 Tests` {

  private let name = "example.org"

  @Test func `version & variant`() {
    let u = UUID.v5(namespace: .dns, name: name)
    #expect(u.version == .v5)
    #expect(u.variant == .rfc)
  }

  @Test func deterministic() throws {
    let a = UUID.v5(namespace: .dns, name: name)
    let b = UUID.v5(namespace: .dns, name: name)
    #expect(a.description == b.description)
    // Change name -> different
    let c = UUID.v5(namespace: .dns, name: "example.com")
    #expect(a.description != c.description)
  }

  @Test(arguments: [
    (UUID.Namespace.dns, "www.example.com", "2ed6657d-e927-568b-95e1-2665a8aea6a2")
  ])
  func `rfc test vectors`(args: (ns: UUID.Namespace, name: String, expected: String)) throws {

    #expect(UUID.v5(namespace: args.ns, name: args.name).encode(using: .canonical) == args.expected)
  }
}
