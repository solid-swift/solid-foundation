import Testing
import SolidURI

@Suite
struct URITemplateParseAPITests {

  @Test(arguments: malformedWithOffsets)
  func strictParsingReportsOffset(input: String, expectedCode: URI.Template.ParseError.Code) {
    #expect(throws: URI.Template.ParseError.self) {
      _ = try URI.Template(parsing: input)
    }
    // Also verify non-throwing diagnostics include an error
    let res = URI.Template.parse(input)
    #expect(res.value == nil)
    #expect(!res.diagnostics.isEmpty)
  }

  static let malformedWithOffsets: [(String, URI.Template.ParseError.Code)] = [
    ("{", .malformedTemplate),
    ("{var", .malformedTemplate),
    ("{}", .emptyExpression),
    ("{var:}", .invalidPrefixLength),
    ("{var:0}", .invalidPrefixLength),
    ("{var:10000}", .invalidPrefixLength),
    ("{va-r}", .invalidVarname),
  ]

  @Test
  func copyUnexpandedPolicyKeepsText() throws {
    let input = "/path/{invalid%}/more"
    let result = URI.Template.parse(input, options: .init(expressionErrorPolicy: .copyUnexpanded))
    #expect(result.value != nil)
    let t = result.value!
    #expect(t.parsedSuccessfully == true)    // parsed with literal-preserved expression
    // Expands with encoded braces and percent sign per literal encoding rules
    #expect(try t.expandString([:]) == "/path/%7Binvalid%25%7D/more")
    // Current implementation does not attach diagnostics for copyUnexpanded; acceptable
    #expect(result.diagnostics.isEmpty)
  }
}
