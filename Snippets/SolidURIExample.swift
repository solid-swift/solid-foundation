import SolidURI

// snippet.hide
func uriExample() {
  // snippet.show
  // Parse URIs
  let uri = URI(encoded: "https://example.com/path?query=value#fragment")!

  // Access components
  print(uri.scheme ?? "")       // "https"
  print(uri.authority?.host ?? "")  // "example.com"
  print(uri.encodedPath)        // "/path"

  // Resolve relative references
  let base = URI(valid: "https://example.com/a/b/c")
  let relative = URI(encoded: "../d")!
  let resolved = relative.resolved(against: base)
  print(resolved.encoded)  // "https://example.com/a/d"

  // Build URIs programmatically
  let newUri = URI.absolute(
      scheme: "https",
      authority: .host("api.example.com", port: 8080),
      path: [.decoded("v1"), .decoded("users")],
      query: [URI.QueryItem(name: "limit", value: "10")]
  )
  // snippet.hide
  _ = newUri
}
// snippet.show
