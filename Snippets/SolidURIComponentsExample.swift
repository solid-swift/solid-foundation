import SolidURI

// snippet.hide
func uriComponentsExample() {
  // snippet.show
  // Update components individually
  let uri = URI(encoded: "http://example.com/path?query=value#fragment")!

  let secured = uri.updating(.scheme("https"))
  let newHost = uri.updating(.host("api.example.com"), .port(8080))
  let cleaned = uri.removing(.query, .fragment)
  // snippet.hide
  _ = (secured, newHost, cleaned)
}
// snippet.show
