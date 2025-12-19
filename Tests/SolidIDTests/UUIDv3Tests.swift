//
//  UUIDv3Tests.swift
//

import Testing
@testable import SolidID


@Suite struct UUIDv3Suite {

  private let name = "example.org"

  @Test func versionAndVariant() {
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
}
