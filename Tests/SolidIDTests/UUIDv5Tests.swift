//
//  UUIDv5Tests.swift
//

import Testing
@testable import SolidID


@Suite struct UUIDv5Suite {

  private let name = "example.org"

  @Test func versionAndVariant() {
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
}
