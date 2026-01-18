import SolidID

// snippet.hide
func idExample() {
  // snippet.show
  // Local counter IDs for simple sequential identifiers
  let counter = AtomicCounterSource<UInt64>()
  let localId = counter.next()  // 1, 2, 3, ...

  // Generate UUIDs
  let v4 = UUID.v4()  // Random UUID
  let v7 = UUID.v7()  // Time-ordered UUID (great for databases)

  // Version 5: Name-based with SHA-1
  let domainId = UUID.v5(namespace: .dns, name: "example.com")
  // snippet.hide
  _ = (localId, v4, v7, domainId)
}
// snippet.show
