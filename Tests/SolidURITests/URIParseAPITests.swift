import Testing
import SolidURI

@Suite
struct URIParseAPITests {

  @Test(arguments: errorCases)
  func throwingParseReportsCode(input: String, requirements: Set<URI.Requirement>, expected: URI.ParseError.Code) {
    #expect(throws: URI.ParseError.self) {
      _ = try URI(parsing: input, options: .init(requirements: requirements))
    }

    // Non-throwing also reports diagnostics
    let res = URI.parse(input, options: .init(requirements: requirements))
    #expect(res.value == nil)
    #expect(!res.diagnostics.isEmpty)
  }

  static let errorCases: [(String, Set<URI.Requirement>, URI.ParseError.Code)] = [
    // invalid scheme (normalization requires lowercase)
    (
      "HTTP://example.com",
      Set<URI.Requirement>([.normalized]).union(Set<URI.Requirement>.uriReference),
      .invalidScheme
    ),
    // invalid IPv6 host (unclosed)
    ("http://[::1", Set<URI.Requirement>.uriReference, .invalidIPv6),
    // invalid port
    ("http://example.com:abc", Set<URI.Requirement>.uriReference, .invalidPort),
    // invalid host (invalid character)
    ("http://exa_mple.com", Set<URI.Requirement>.uriReference, .invalidHost),
    // invalid path under normalization (disallowed '.' in non-initial segment)
    (
      "http://example.com/a/./b",
      Set<URI.Requirement>([.normalized]).union(Set<URI.Requirement>.uriReference),
      .invalidPath
    ),
    // bad percent triplet in path
    ("http://example.com/%GZ", Set<URI.Requirement>.uriReference, .badPercentTriplet),
    // ended at authority marker
    ("http://", Set<URI.Requirement>.uriReference, .invalidAuthority),
    // fragment requirement violation
    (
      "http://example.com#frag",
      Set<URI.Requirement>.uriReference.union(Set([.fragment(.disallowed)])),
      .requirementViolation
    ),
    // bad percent triplet in query key
    ("http://example.com?%GZ=1", Set<URI.Requirement>.uriReference, .badPercentTriplet),
    // bad percent triplet in fragment
    ("http://example.com#%GZ", Set<URI.Requirement>.uriReference, .badPercentTriplet),
  ]

  @Test(arguments: successCases)
  func successParses(input: String, requirements: Set<URI.Requirement>) throws {
    let u = try URI(parsing: input, options: .init(requirements: requirements))
    #expect(u.encoded == input)
    let res = URI.parse(input, options: .init(requirements: requirements))
    #expect(res.value != nil)
    #expect(res.diagnostics.isEmpty)
  }

  static let successCases: [(String, Set<URI.Requirement>)] = [
    ("http://example.com", Set<URI.Requirement>.uriReference),
    ("http://example.com/a/b", Set<URI.Requirement>.uriReference),
    ("http://example.com?x=1", Set<URI.Requirement>.uriReference),
    ("http://example.com#frag", Set<URI.Requirement>.uriReference),
  ]
}
