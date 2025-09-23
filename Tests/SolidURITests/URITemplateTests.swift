import Testing
import SolidURI

typealias V = URI.Template.Value

@Suite
struct URITemplateTests {

  // Shared sample values from RFC 6570 Section 3.2 examples
  let values: [String: V] = [
    "count": .list(["one", "two", "three"]),
    "dom": .list(["example", "com"]),
    "dub": .scalar("me/too"),
    "hello": .scalar("Hello World!"),
    "half": .scalar("50%"),
    "var": .scalar("value"),
    "who": .scalar("fred"),
    "base": .scalar("http://example.com/home/"),
    "path": .scalar("/foo/bar"),
    "list": .list(["red", "green", "blue"]),
    "keys": .assoc(["semi": ";", "dot": ".", "comma": ","]),
    "v": .scalar("6"),
    "x": .scalar("1024"),
    "y": .scalar("768"),
    "empty": .scalar(""),
    "empty_keys": .assoc([:]),
  ]

  @Test(arguments: level1Cases)
  func level1(template: String, expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let level1Cases: [(String, String)] = [
    ("{var}", "value"),
    ("{hello}", "Hello%20World%21"),
    ("{x,y}", "1024,768"),
  ]

  @Test(arguments: level2Cases)
  func level2(template: String, expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let level2Cases: [(String, String)] = [
    ("{+var}", "value"),
    ("{+hello}", "Hello%20World!"),
    ("{+path}/here", "/foo/bar/here"),
    ("here?ref={+path}", "here?ref=/foo/bar"),
    ("X{#var}", "X#value"),
  ]

  @Test(arguments: level3Cases)
  func level3(template: String, expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let level3Cases: [(String, String)] = [
    ("map?{x,y}", "map?1024,768"),
    ("{x,hello,y}", "1024,Hello%20World%21,768"),
    ("X{.var}", "X.value"),
    ("{/var}", "/value"),
    ("{;x,y}", ";x=1024;y=768"),
    ("{?x,y}", "?x=1024&y=768"),
    ("?fixed=yes{&x}", "?fixed=yes&x=1024"),
  ]

  @Test(arguments: level4Cases)
  func level4(template: String, expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let level4Cases: [(String, String)] = [
    ("{var:3}", "val"),
    ("{list}", "red,green,blue"),
    ("{list*}", "red,green,blue"),
    ("{keys}", "comma,%2C,dot,.,semi,%3B"),
    ("{keys*}", "comma=%2C,dot=.,semi=%3B"),
    ("{+path:6}/here", "/foo/b/here"),
    ("{+list}", "red,green,blue"),
    ("{+list*}", "red,green,blue"),
    ("{+keys}", "comma,,,dot,.,semi,;"),
    ("{+keys*}", "comma=,,dot=.,semi=;"),
    ("X{.list*}", "X.red.green.blue"),
    ("{/list*}", "/red/green/blue"),
    ("{/list*,path:4}", "/red/green/blue/%2Ffoo"),
    ("{;list*}", ";list=red;list=green;list=blue"),
    ("{?list*}", "?list=red&list=green&list=blue"),
    ("{&list*}", "&list=red&list=green&list=blue"),
  ]

  @Test
  func expandURIParsing() throws {
    let tmpl = URI.Template("http://www.example.com/foo{?query,number}")
    let uri = try tmpl.expandURI(["query": .scalar("mycelium"), "number": .scalar("100")], requirements: .uri)
    #expect(uri.encoded == "http://www.example.com/foo?query=mycelium&number=100")
  }

  @Test(arguments: partialQueryCases)
  func partialQuery(
    template: String,
    partial: [String: V],
    expectedPartial: String,
    finalInput: [String: V],
    expectedFinal: String
  ) throws {
    let tmpl = try URI.Template(template)
    let partially = try tmpl.expandPartially(partial)
    #expect(partially.raw == expectedPartial)
    let final = try partially.expandString(finalInput)
    #expect(final == expectedFinal)
  }

  static let partialQueryCases: [(String, [String: V], String, [String: V], String)] = [
    (
      "/search{?q,lang}", ["q": .scalar("cat")], "/search?q=cat{&lang}", ["lang": .scalar("en")],
      "/search?q=cat&lang=en"
    )
  ]

  @Test(arguments: partialFragmentCases)
  func partialFragment(
    template: String,
    partial: [String: V],
    expectedPartial: String,
    finalInput: [String: V],
    expectedFinal: String
  ) throws {
    let tmpl = try URI.Template(template)
    let partially = try tmpl.expandPartially(partial)
    #expect(partially.raw == expectedPartial)
    let final = try partially.expandString(finalInput)
    #expect(final == expectedFinal)
  }

  static let partialFragmentCases: [(String, [String: V], String, [String: V], String)] = [
    (
      "doc{#section,title}", ["section": .scalar("intro")], "doc#intro{+title}", ["title": .scalar("overview")],
      "doc#introoverview"
    )
  ]

  @Test(arguments: partialSimpleCases)
  func partialSimple(
    template: String,
    partial: [String: V],
    expectedPartial: String,
    finalInput: [String: V],
    expectedFinal: String
  ) throws {
    let tmpl = try URI.Template(template)
    let partially = try tmpl.expandPartially(partial)
    #expect(partially.raw == expectedPartial)
    let final = try partially.expandString(finalInput)
    #expect(final == expectedFinal)
  }

  static let partialSimpleCases: [(String, [String: V], String, [String: V], String)] = [
    ("X{var,who}Y", ["var": .scalar("value")], "Xvalue,{who}Y", ["who": .scalar("fred")], "Xvalue,fredY")
  ]

  // MARK: - Edge cases

  @Test(arguments: unicodePrefixCases)
  func unicodePrefix(template: String, values: [String: V], expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let unicodePrefixCases: [(String, [String: V], String)] = [
    // Prefix with multi-byte Unicode; should not split and must percent-encode
    ("{word:2}", ["word": .scalar("élan")], "%C3%A9l"),
    // Prefix should treat %xx as a single unit if present in the value
    ("{v:2}", ["v": .scalar("a%20b")], "a%2520"),
  ]

  @Test(arguments: explodeAssocEmptyCases)
  func explodeAssocEmpty(template: String, values: [String: V], expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let explodeAssocEmptyCases: [(String, [String: V], String)] = [
    ("{;kv*}", ["kv": .assoc(["a": "", "b": "x"])], ";a;b=x"),
    ("{?kv*}", ["kv": .assoc(["a": "", "b": "x"])], "?a=&b=x"),
  ]

  @Test(arguments: listWithEmptyCases)
  func listWithEmpty(template: String, values: [String: V], expected: String) throws {
    #expect(try URI.Template(template).expandString(values) == expected)
  }

  static let listWithEmptyCases: [(String, [String: V], String)] = [
    ("{?list}", ["list": .list(["", "x"])], "?list=,x"),
    ("{;list*}", ["list": .list(["", "x"])], ";list;list=x"),
  ]

  // IRI-oriented: ensure percent-encoding occurs and parsing as IRI succeeds
  @Test(arguments: iriCases)
  func iriExpansionParses(template: String, values: [String: V], expectedEncoded: String) throws {
    let t = try URI.Template(template)
    let s = try t.expandString(values)
    #expect(s == expectedEncoded)
    let u = try t.expandURI(values, requirements: .iriReference)
    #expect(u.encoded == expectedEncoded)
  }

  static let iriCases: [(String, [String: V], String)] = [
    ("/path/{name}", ["name": .scalar("こんにちは")], "/path/%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF"),
    ("{?q}", ["q": .scalar("café")], "?q=caf%C3%A9"),
    ("{#frag}", ["frag": .scalar("niño")], "#ni%C3%B1o"),
  ]

  // Negative/malformed templates
  @Test(arguments: malformedTemplates)
  func malformed(template: String) {
    #expect(throws: Error.self) { try _ = URI.Template(template) }
  }

  static let malformedTemplates: [String] = [
    // Unterminated or empty
    "{",
    "{var",
    "{}",

    // Unknown/reserved operators (not supported): should be rejected at parse
    "{=var}",
    "{,var}",
    "{!var}",
    "{@var}",
    "{|var}",

    // Bad modifiers
    "{var:}",
    "{var:0}",
    "{var:10000}",
    "{var:abc}",
    "{var**}",
    "{*var}",

    // Invalid varname characters or structure
    "{va-r}",
    "{va%GZr}",
    "{var,}",
    "{var{nested}}",
    "{{var}}",
  ]
}
