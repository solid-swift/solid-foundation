//
//  YAMLTokenizerTests.swift
//  SolidFoundation
//
//  Created by Codex on 4/24/26.
//

import Foundation
import SolidData
@testable import SolidYAML
import Testing


@Suite("YAML Tokenizer Tests")
struct YAMLTokenizerTests {

  @Test("plain scalar line can be split across chunks")
  func chunkSplitPlainScalarLine() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("hel".utf8), isFinal: false)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("lo\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.style.isPlain)
    #expect(scalar.kind == .number)
    #expect(scalar.region.bytes == Data("hello".utf8))
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("directives comments and explicit document markers are tokenized")
  func directivesCommentsAndDocumentMarkers() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("%YAML 1.2\n--- # start\nvalue # comment\n...\n".utf8), isFinal: true)

    try expectDirective(try tokenizer.readToken(), name: "YAML", value: "1.2")
    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.region.bytes == Data("value".utf8))
    try expectDocumentEnd(try tokenizer.readToken(), explicit: true)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("plain block line scalars retain source regions")
  func plainBlockLineScalarsRetainSourceRegions() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("key: value # comment\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken())
    try expectRetainedScalar(try tokenizer.readToken(), text: "key")
    try expectRetainedScalar(try tokenizer.readToken(), text: "value")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("sequence explicit mapping and decorated scalars retain source regions")
  func structuralPlainScalarsRetainSourceRegions() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("- item # comment\n---\n? explicit\n: value\n---\n!local &a tagged\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken())
    try expectRetainedScalar(try tokenizer.readToken(), text: "item")
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    try expectBeginMapping(try tokenizer.readToken())
    try expectRetainedScalar(try tokenizer.readToken(), text: "explicit")
    try expectRetainedScalar(try tokenizer.readToken(), text: "value")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    try expectTag(try tokenizer.readToken(), "!local")
    try expectAnchor(try tokenizer.readToken(), "a")
    try expectRetainedScalar(try tokenizer.readToken(), text: "tagged")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("same-line flow scalars retain source regions")
  func sameLineFlowScalarsRetainSourceRegions() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[a, {b: c}]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "a")
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "b")
    try expectRetainedScalar(try tokenizer.readToken(), text: "c")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("document event reader preserves explicit boundary metadata")
  func documentEventReaderPreservesExplicitBoundaryMetadata() throws {
    let yaml = """
    ---
    a: 1
    ...
    ---
    - two
    """

    var reader = YAMLDocumentEventReader()
    var decoder = ParseDocumentEventDecoder(resolver: YAMLScalarResolver())
    var input = Data(yaml.utf8)
    var documents: [FormatValueDocument] = []
    var done = false

    try withUnsafeTemporaryAllocation(of: ParseDocumentEvent.self, capacity: 8) { buffer in
      while !done {
        var output = OutputSpan<ParseDocumentEvent>(buffer: buffer, initializedCount: 0)
        let status = try reader.read(input: input, isFinal: true, output: &output)
        input = Data()
        let count = output.finalize(for: buffer)
        for event in buffer[..<count] {
          if let document = try decoder.append(event) {
            documents.append(document)
          }
        }
        if status == .endOfStream {
          done = true
        }
      }
    }
    try decoder.finish()

    #expect(documents == [
      FormatValueDocument(
        value: .object([.string("a"): .number(1)]),
        explicitStart: true,
        explicitEnd: true
      ),
      FormatValueDocument(
        value: .array([.string("two")]),
        explicitStart: true,
        explicitEnd: false
      ),
    ])
  }

  @Test("document event reader streams document start before final input")
  func documentEventReaderStreamsDocumentStartBeforeFinalInput() throws {
    var reader = YAMLDocumentEventReader()
    let input = Data("---\n".utf8)

    try withUnsafeTemporaryAllocation(of: ParseDocumentEvent.self, capacity: 1) { buffer in
      var output = OutputSpan<ParseDocumentEvent>(buffer: buffer, initializedCount: 0)
      let status = try reader.read(input: input, isFinal: false, output: &output)

      let count = output.finalize(for: buffer)
      #expect(status == .producedOutput)
      #expect(count == 1)
      guard case .startDocument(let metadata) = buffer[0] else {
        Issue.record("Expected startDocument event, got \(buffer[0])")
        return
      }
      #expect(metadata.explicit)
    }
  }

  @Test("document marker can be split across chunks")
  func chunkSplitDocumentMarker() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("--".utf8), isFinal: false)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("-\nvalue".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(try scalar.region.string() == "value")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("simple block sequence emits collection tokens")
  func simpleBlockSequence() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("- one\n- two\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "one")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "two")
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("simple block mapping emits collection tokens")
  func simpleBlockMapping() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("a: 1\nb: two\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "a")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "1")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "b")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "two")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("compact mappings inside block sequences emit nested mappings")
  func compactMappingsInsideBlockSequence() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("- a: 1\n- b: two\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken())
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "a")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "1")
    try expectEndMapping(try tokenizer.readToken())
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "b")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "two")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("bare block sequence entries adopt indented child nodes")
  func bareBlockSequenceEntriesAdoptIndentedChildNodes() throws {
    let yaml = """
    -
      name: Mark McGwire
      hr: 65
    -
      - nested
    -
    """

    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))
    try expectTokenizerEventLineParity(yaml)
  }

  @Test("empty block entries emit empty scalar values")
  func emptyBlockEntries() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("-\n- value\n---\na:\nb: 1\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "value")
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "a")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "b")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "1")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("explicit block mapping entries emit pending key value pairs")
  func explicitBlockMappingEntries() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("? explicit key\n: explicit value\n? empty value\n?\n: empty key\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "explicit key")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "explicit value")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "empty value")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "empty key")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("token adapter decodes simple values through ParseEvent")
  func tokenAdapterDecodesSimpleValues() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("a: 1\nb: two\n".utf8), isFinal: true)

    var adapter = YAMLTokenEventAdapter()
    var events: [ParseEvent] = []
    while let token = try tokenizer.readToken() {
      try adapter.append(token, into: &events)
    }

    var decoder = ParseEventDecoder(resolver: YAMLScalarResolver())
    for event in events {
      try decoder.append(event)
    }
    #expect(try decoder.finish() == ["a": 1, "b": "two"])
  }

  @Test("quoted scalars preserve style and decoded text")
  func quotedScalars() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("'it''s'\n---\n\"line\\nfeed\"\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    let single = try expectScalar(try tokenizer.readToken())
    #expect(single.style.isSingleQuoted)
    #expect(try single.region.string() == "it's")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    let double = try expectScalar(try tokenizer.readToken())
    #expect(double.style.isDoubleQuoted)
    #expect(try double.region.string() == "line\nfeed")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("double quoted scalars preserve tab behavior before folded line breaks")
  func doubleQuotedEscapedTabsBeforeFoldedBreaks() throws {
    for id in ["DE56/00", "DE56/01", "DE56/02", "DE56/03", "DE56/04", "DE56/05"] {
      let yaml = try loadYamlTestSuiteInput(id)
      let actualEvents = try renderTokenizerEventLines(yaml)
      let expectedEvents = try loadYamlTestSuiteEventLines(id)
      #expect(
        actualEvents == expectedEvents,
        "\(id): actual \(actualEvents), expected \(expectedEvents)"
      )
      let actualValues = try decodeTokenizerValues(yaml)
      let expectedValues = try decodeProductionDocumentValues(yaml)
      #expect(actualValues == expectedValues, "\(id): actual \(actualValues), expected \(expectedValues)")
    }
  }

  @Test("quoted scalar trailing whitespace stays on the quoted normalization path", arguments: [
    "'single'   \n",
    "\"line\\nfeed\"   \n",
    "'key'   : value\n",
  ])
  func quotedTrailingWhitespaceParity(_ yaml: String) throws {
    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))
    try expectTokenizerEventLineParity(yaml)
  }

  @Test("document start marker is rejected inside multiline quoted scalar continuation")
  func documentStartMarkerRejectedInsidePendingQuotedScalar() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("\"open\n---\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    #expect(throws: YAML.ParseError.self) {
      _ = try tokenizer.readToken()
    }
  }

  @Test("document end marker is rejected inside multiline quoted scalar continuation")
  func documentEndMarkerRejectedInsidePendingQuotedScalar() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("'open\n...\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    #expect(throws: YAML.ParseError.self) {
      _ = try tokenizer.readToken()
    }
  }

  @Test("quoted scalar continuation keeps marker-looking content when not a boundary")
  func quotedContinuationAllowsMarkerLikeText() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("\"open\n---value\"\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectScalarText(try tokenizer.readToken(), "open ---value")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("multiline quoted scalars can be split across chunks")
  func chunkSplitMultilineQuotedScalars() throws {
    let singleChunks = ["'one\n", "  two'\n"]
    let doubleChunks = ["\"one\n", "  two\"\n"]

    #expect(try decodeTokenizerChunkedValue(singleChunks) == decodeProductionReaderValue(singleChunks))
    #expect(try decodeTokenizerChunkedValue(doubleChunks) == decodeProductionReaderValue(doubleChunks))

    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("'one\n".utf8), isFinal: false)
    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("  two'\n".utf8), isFinal: true)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.style.isSingleQuoted)
    if case .string(let expected) = try decodeProductionReaderValue(singleChunks) {
      #expect(try scalar.region.string() == expected)
    } else {
      Issue.record("Expected production reader to decode a string")
    }
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  }

  @Test("multiline plain scalars fold across continuation lines")
  func multilinePlainScalars() throws {
    let yaml = """
    single multiline
      scalar

      with blank
    """

    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))
    try expectTokenizerEventLineParity(yaml)
  }

  @Test("multiline plain scalars stop at structural lines")
  func multilinePlainScalarsStopAtStructure() throws {
    let sequence = """
    - single multiline
      sequence entry
    - next
    """
    let mapping = """
    mapping: value line
      continuation
    next: value
    """

    #expect(try decodeTokenizerValues(sequence) == decodeProductionDocumentValues(sequence))
    try expectTokenizerEventLineParity(sequence)
    #expect(try decodeTokenizerValues(mapping) == decodeProductionDocumentValues(mapping))
    try expectTokenizerEventLineParity(mapping)
  }

  @Test("multiline plain scalar comments match production folding")
  func multilinePlainScalarComments() throws {
    let yaml = """
    key: plain
      continuation # comment
    next: value
    """

    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))
    try expectTokenizerEventLineParity(yaml)
  }

  @Test("multiline plain scalar can be split across chunks")
  func chunkSplitMultilinePlainScalar() throws {
    let chunks = ["single multiline\n", "  scalar\n"]

    #expect(try decodeTokenizerChunkedValue(chunks) == decodeProductionReaderValue(chunks))

    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("single multiline\n".utf8), isFinal: false)
    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("  scalar\n".utf8), isFinal: true)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.style.isPlain)
    if case .string(let expected) = try decodeProductionReaderValue(chunks) {
      #expect(try scalar.region.string() == expected)
    } else {
      Issue.record("Expected production reader to decode a string")
    }
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  }

  @Test("literal and folded block scalars are accumulated across lines")
  func blockScalars() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("literal: |\n  one\n  two\nfolded: >\n  three\n  four\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "literal")
    let literal = try expectScalar(try tokenizer.readToken())
    #expect(literal.style.isLiteral)
    #expect(try literal.region.string() == "one\ntwo\n")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "folded")
    let folded = try expectScalar(try tokenizer.readToken())
    #expect(folded.style.isFolded)
    #expect(try folded.region.string() == "three four\n")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("block scalar body can be split across chunks")
  func chunkSplitBlockScalar() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("a: |\n  on".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "a")
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("e\n  two\n".utf8), isFinal: true)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.style.isLiteral)
    #expect(try scalar.region.string() == "one\ntwo\n")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("root literal block scalar honors explicit indent indicator")
  func rootLiteralBlockScalarExplicitIndent() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("|1\n value\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.style.isLiteral)
    #expect(scalar.style.indent == 1)
    #expect(try scalar.region.string() == "value\n")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("root folded block scalar honors explicit indent indicator")
  func rootFoldedBlockScalarExplicitIndent() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data(">1\n value\n next\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(scalar.style.isFolded)
    #expect(scalar.style.indent == 1)
    #expect(try scalar.region.string() == "value next\n")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("tags anchors and aliases are raw tokens")
  func tagsAnchorsAndAliases() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("!local &a value\n---\n*a\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectTag(try tokenizer.readToken(), "!local")
    try expectAnchor(try tokenizer.readToken(), "a")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "value")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    try expectAlias(try tokenizer.readToken(), "a")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("anchors and aliases allow colon in names")
  func anchorsAndAliasesAllowColonInNames() throws {
    let yaml = try loadYamlTestSuiteInput("2SXE")
    let actualEvents = try renderTokenizerEventLines(yaml)
    let expectedEvents = try loadYamlTestSuiteEventLines("2SXE")

    #expect(
      actualEvents == expectedEvents,
      """
      tokenizer events:
      \(actualEvents.joined(separator: "\n"))
      expected events:
      \(expectedEvents.joined(separator: "\n"))
      """
    )
    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))
  }

  @Test("tag directives resolve tag handles")
  func tagDirectivesResolveHandles() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("%TAG !e! tag:example.com,2026:\n---\n!e!thing value\n...\n---\n!!str text\n".utf8), isFinal: true)

    try expectDirective(try tokenizer.readToken(), name: "TAG", value: "!e! tag:example.com,2026:")
    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    try expectTag(try tokenizer.readToken(), "tag:example.com,2026:thing")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "value")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: true)
    try expectDocumentStart(try tokenizer.readToken(), explicit: true)
    try expectTag(try tokenizer.readToken(), "tag:yaml.org,2002:str")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "text")
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("document start marker can carry the root node")
  func documentStartMarkerWithRootNode() throws {
    try expectTokenizerEventLineParity("--- text\n")
    #expect(try decodeTokenizerValues("--- |1-\n") == decodeProductionDocumentValues("--- |1-\n"))
  }

  @Test("compact nested block sequences stay open for continuation entries")
  func compactNestedBlockSequenceContinuation() throws {
    let yaml = """
    - - s1_i1
      - s1_i2
    - s2
    """

    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))
    try expectTokenizerEventLineParity(yaml)
  }

  @Test("tag directives require a document boundary before later directives")
  func tagDirectiveRequiresDocumentBoundary() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("%TAG !e! tag:example.com,2026:\n---\nvalue\n%TAG !f! tag:example.net,2026:\n".utf8), isFinal: true)

    #expect(throws: YAML.ParseError.self) {
      while try tokenizer.readToken() != nil {}
    }
  }

  @Test("basic flow collections emit flow style tokens")
  func basicFlowCollections() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[a, {b: \"c\"}]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    let first = try expectScalar(try tokenizer.readToken())
    #expect(try first.region.string() == "a")
    #expect(first.region.segmentIndex != nil)
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    let key = try expectScalar(try tokenizer.readToken())
    #expect(try key.region.string() == "b")
    #expect(key.region.segmentIndex != nil)
    let value = try expectScalar(try tokenizer.readToken())
    #expect(value.style.isDoubleQuoted)
    #expect(try value.region.string() == "c")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow scalar token bursts drain in source order")
  func flowScalarTokenBurstsDrainInSourceOrder() throws {
    let values = (0..<128).map(String.init)
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[\(values.joined(separator: ", "))]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    for value in values {
      #expect(try expectScalar(try tokenizer.readToken()).region.string() == value)
    }
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow collections support empty entries and decorators")
  func flowCollectionsWithEmptyEntriesAndDecorators() throws {
    #expect(try decodeTokenizerValues("{a:, : empty, b: 2}\n") == decodeProductionDocumentValues("{a:, : empty, b: 2}\n"))
    #expect(try decodeTokenizerValues("{a: [1, {b: 2}], c: []}\n") == decodeProductionDocumentValues("{a: [1, {b: 2}], c: []}\n"))

    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[!local &a one, *a]\n".utf8), isFinal: true)
    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectTag(try tokenizer.readToken(), "!local")
    try expectAnchor(try tokenizer.readToken(), "a")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "one")
    try expectAlias(try tokenizer.readToken(), "a")
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow collection line can be split across chunks")
  func chunkSplitFlowCollection() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[a, ".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "a")
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("{b: \"c\"}]\n".utf8), isFinal: true)

    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "b")
    let value = try expectScalar(try tokenizer.readToken())
    #expect(value.style.isDoubleQuoted)
    #expect(try value.region.string() == "c")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow tokenizer emits safe tokens before the full flow collection closes")
  func flowTokenizerEmitsSafeTokensBeforeCollectionCloses() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[a, ".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "a")
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("{b: c}".utf8), isFinal: false)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("]\n".utf8), isFinal: true)
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "b")
    try expectRetainedScalar(try tokenizer.readToken(), text: "c")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow mapping streams value collection after colon before entry closes")
  func flowMappingStreamsValueCollectionAfterColon() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("{key: [a, ".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "key")
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "a")
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("b]}\n".utf8), isFinal: true)

    try expectRetainedScalar(try tokenizer.readToken(), text: "b")
    try expectEndSequence(try tokenizer.readToken())
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("same-line flow plain scalars keep retained source regions after direct scanner emission")
  func directFlowScannerKeepsRetainedSameLinePlainScalars() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[alpha, {beta: gamma}]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "alpha")
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "beta")
    try expectRetainedScalar(try tokenizer.readToken(), text: "gamma")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow structure adapter handles implicit mapping candidates")
  func flowStructureAdapterHandlesImplicitMappingCandidates() throws {
    try assertSingleDocumentTokens("[foo: bar]\n") { tokenizer in
      try expectBeginSequence(try tokenizer.readToken(), style: .flow)
      try expectBeginMapping(try tokenizer.readToken(), style: .flow)
      try expectRetainedScalar(try tokenizer.readToken(), text: "foo")
      try expectRetainedScalar(try tokenizer.readToken(), text: "bar")
      try expectEndMapping(try tokenizer.readToken())
      try expectEndSequence(try tokenizer.readToken())
    }

    try assertSingleDocumentTokens("[[a]: b]\n") { tokenizer in
      try expectBeginSequence(try tokenizer.readToken(), style: .flow)
      try expectBeginMapping(try tokenizer.readToken(), style: .flow)
      try expectBeginSequence(try tokenizer.readToken(), style: .flow)
      try expectRetainedScalar(try tokenizer.readToken(), text: "a")
      try expectEndSequence(try tokenizer.readToken())
      try expectRetainedScalar(try tokenizer.readToken(), text: "b")
      try expectEndMapping(try tokenizer.readToken())
      try expectEndSequence(try tokenizer.readToken())
    }

    try assertSingleDocumentTokens("[{a: b}: c]\n") { tokenizer in
      try expectBeginSequence(try tokenizer.readToken(), style: .flow)
      try expectBeginMapping(try tokenizer.readToken(), style: .flow)
      try expectBeginMapping(try tokenizer.readToken(), style: .flow)
      try expectRetainedScalar(try tokenizer.readToken(), text: "a")
      try expectRetainedScalar(try tokenizer.readToken(), text: "b")
      try expectEndMapping(try tokenizer.readToken())
      try expectRetainedScalar(try tokenizer.readToken(), text: "c")
      try expectEndMapping(try tokenizer.readToken())
      try expectEndSequence(try tokenizer.readToken())
    }

    try assertSingleDocumentTokens("[!tag &a key: *a]\n") { tokenizer in
      try expectBeginSequence(try tokenizer.readToken(), style: .flow)
      try expectBeginMapping(try tokenizer.readToken(), style: .flow)
      try expectTag(try tokenizer.readToken(), "!tag")
      try expectAnchor(try tokenizer.readToken(), "a")
      try expectRetainedScalar(try tokenizer.readToken(), text: "key")
      try expectAlias(try tokenizer.readToken(), "a")
      try expectEndMapping(try tokenizer.readToken())
      try expectEndSequence(try tokenizer.readToken())
    }

    try assertSingleDocumentTokens("[foo, bar]\n") { tokenizer in
      try expectBeginSequence(try tokenizer.readToken(), style: .flow)
      try expectRetainedScalar(try tokenizer.readToken(), text: "foo")
      try expectRetainedScalar(try tokenizer.readToken(), text: "bar")
      try expectEndSequence(try tokenizer.readToken())
    }
  }

  @Test("flow structure adapter preserves normal sequence items without colon")
  func flowStructureAdapterPreservesNormalSequenceItems() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[foo, [bar], {baz: qux}]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectScalarText(try tokenizer.readToken(), "foo")
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    try expectScalarText(try tokenizer.readToken(), "bar")
    try expectEndSequence(try tokenizer.readToken())
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectScalarText(try tokenizer.readToken(), "baz")
    try expectScalarText(try tokenizer.readToken(), "qux")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow tokenizer delays only ambiguous sequence candidates")
  func flowTokenizerDelaysOnlyAmbiguousSequenceCandidates() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[foo".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data(", bar]\n".utf8), isFinal: true)
    try expectRetainedScalar(try tokenizer.readToken(), text: "foo")
    try expectRetainedScalar(try tokenizer.readToken(), text: "bar")
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow tokenizer converts ambiguous candidate to mapping across chunks")
  func flowTokenizerConvertsAmbiguousCandidateToMappingAcrossChunks() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[foo".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data(": bar]\n".utf8), isFinal: true)
    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    try expectRetainedScalar(try tokenizer.readToken(), text: "foo")
    try expectRetainedScalar(try tokenizer.readToken(), text: "bar")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow lexer accepts splits at indicators decorators and scalars", arguments: [
    ["[", "a", "]\n"],
    ["[a", ",", " b", "]\n"],
    ["{", "a", ":", " b", "}\n"],
    ["[", "!local ", "&a ", "one", ", ", "*a", "]\n"],
    ["[", "'single quoted'", ", ", "\"double quoted\"", "]\n"],
    ["[", "plain", " scalar", ", next", "]\n"],
  ])
  func flowLexerChunkBoundaryParity(_ chunks: [String]) throws {
    #expect(try decodeTokenizerChunkedValue(chunks) == decodeProductionReaderValue(chunks))
  }

  @Test("highly chunked multiline flow parses through incremental lexer")
  func highlyChunkedMultilineFlowParsesThroughIncrementalLexer() throws {
    let yaml = "[\n  alpha,\n  {beta: [gamma, delta]},\n  epsilon\n]\n"
    let chunks = yaml.map(String.init)

    #expect(try decodeTokenizerChunkedValue(chunks) == decodeProductionReaderValue(chunks))
  }

  @Test("multiline flow plain scalar uses generated region only for joined scalar")
  func multilineFlowPlainScalarUsesGeneratedRegion() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[\n  folded\n  scalar\n]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    let scalar = try expectScalar(try tokenizer.readToken())
    #expect(try scalar.region.string() == "folded scalar")
    #expect(scalar.region.segmentIndex == nil)
    #expect(scalar.region.segmentRange == nil)
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("flow collections can span multiple lines")
  func multilineFlowCollection() throws {
    let yaml = """
    [
      a,
      {b: "c"}
    ]
    """

    #expect(try decodeTokenizerValues(yaml) == decodeProductionDocumentValues(yaml))

    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[\n  a,\n".utf8), isFinal: false)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "a")
    #expect(try tokenizer.readToken() == nil)

    tokenizer.feedInput(Data("  {b: \"c\"}\n]\n".utf8), isFinal: true)

    try expectBeginMapping(try tokenizer.readToken(), style: .flow)
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "b")
    let value = try expectScalar(try tokenizer.readToken())
    #expect(value.style.isDoubleQuoted)
    #expect(try value.region.string() == "c")
    try expectEndMapping(try tokenizer.readToken())
    try expectEndSequence(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("unterminated multiline flow reports incomplete input at final chunk")
  func unterminatedMultilineFlow() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[\n  a\n".utf8), isFinal: true)

    #expect(throws: YAML.ParseError.self) {
      while try tokenizer.readToken() != nil {}
    }
  }

  @Test("block scalar chomp and indent indicators are preserved")
  func blockScalarIndicators() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("strip: |-\n  one\nkeep: >+\n  two\n\nindent: |2\n  three\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginMapping(try tokenizer.readToken())
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "strip")
    let strip = try expectScalar(try tokenizer.readToken())
    #expect(strip.style.chomp == .strip)
    #expect(try strip.region.string() == "one")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "keep")
    let keep = try expectScalar(try tokenizer.readToken())
    #expect(keep.style.chomp == .keep)
    #expect(try keep.region.string() == "two\n\n")
    #expect(try expectScalar(try tokenizer.readToken()).region.string() == "indent")
    let indent = try expectScalar(try tokenizer.readToken())
    #expect(indent.style.indent == 2)
    #expect(try indent.region.string() == "three\n")
    try expectEndMapping(try tokenizer.readToken())
    try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
    #expect(try tokenizer.readToken() == nil)
  }

  @Test("Block scalar chomp behavior remains stable")
  func blockScalarChompBehavior() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("a: |-\n  one\n  two\nb: >+\n  three\n  four\n\n".utf8), isFinal: true)

    var scalarTexts: [String] = []
    while let token = try tokenizer.readToken() {
      if case .scalar(let scalar) = token {
        scalarTexts.append(try scalar.region.string())
      }
    }

    #expect(scalarTexts.contains("one\ntwo"))
    #expect(scalarTexts.contains("three four\n\n"))
  }

  @Test("node document reader preserves YAML block scalar style metadata")
  func nodeDocumentReaderPreservesBlockScalarStyleMetadata() throws {
    let yaml = """
    stripLiteral: |-
      one
    keepLiteral: |+
      two

    stripFolded: >-
      three
      four
    keepFolded: >+
      five
      six

    explicitIndent: |2
      seven
    explicitFoldIndent: >4
        eight
    """
    let reader = try YAMLNodeDocumentReader(data: Data(yaml.utf8))
    let document = try #require(try reader.readAll().first)
    guard case .mapping(let pairs, _, _, _) = document.node else {
      Issue.record("Expected mapping root")
      return
    }

    #expect(scalarStyle(named: "stripLiteral", in: pairs)?.chomp == .strip)
    #expect(scalarStyle(named: "stripLiteral", in: pairs)?.isLiteral == true)
    #expect(scalarStyle(named: "keepLiteral", in: pairs)?.chomp == .keep)
    #expect(scalarStyle(named: "keepLiteral", in: pairs)?.isLiteral == true)
    #expect(scalarStyle(named: "stripFolded", in: pairs)?.chomp == .strip)
    #expect(scalarStyle(named: "stripFolded", in: pairs)?.isFolded == true)
    #expect(scalarStyle(named: "keepFolded", in: pairs)?.chomp == .keep)
    #expect(scalarStyle(named: "keepFolded", in: pairs)?.isFolded == true)
    #expect(scalarStyle(named: "explicitIndent", in: pairs)?.indent == 2)
    #expect(scalarStyle(named: "explicitIndent", in: pairs)?.isLiteral == true)
    #expect(scalarStyle(named: "explicitFoldIndent", in: pairs)?.indent == 4)
    #expect(scalarStyle(named: "explicitFoldIndent", in: pairs)?.isFolded == true)
  }

  @Test("raw token node builder rejects missing mapping value")
  func rawTokenNodeBuilderRejectsMissingMappingValue() throws {
    var builder = YAMLRawTokenNodeBuilder()
    try builder.append(.beginMapping(style: .block))
    try builder.append(.scalar(YAMLRawScalar(
      style: .plain,
      kind: .number,
      region: ParseBuffer.Region(data: Data("key".utf8))
    )))
    #expect(throws: YAMLRawTokenNodeBuilder.Error.self) {
      try builder.append(.endMapping)
    }
  }

  @Test("invalid flow separators are rejected")
  func invalidFlowSeparators() throws {
    for yaml in ["[a,, b]\n", "{a: 1,, b: 2}\n"] {
      var tokenizer = YAMLTokenizer()
      tokenizer.feedInput(Data(yaml.utf8), isFinal: true)
      #expect(throws: YAML.ParseError.self) {
        while try tokenizer.readToken() != nil {}
      }
    }
  }

  @Test("multiline flow invalid close reports offending line")
  func multilineFlowInvalidCloseReportsOffendingLine() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[\n  a\n}\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)

    do {
      while try tokenizer.readToken() != nil {}
      Issue.record("Expected invalid flow close")
    } catch let error as YAML.ParseError {
      guard case .invalidSyntax(_, let location) = error else {
        Issue.record("Expected invalidSyntax, got \(error)")
        return
      }
      #expect(location?.line == 3)
      #expect(location?.column == 1)
    }
  }

  @Test("multiline flow invalid separator reports current line")
  func multilineFlowInvalidSeparatorReportsCurrentLine() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("[\n  a,,\n]\n".utf8), isFinal: true)

    try expectDocumentStart(try tokenizer.readToken(), explicit: false)
    try expectBeginSequence(try tokenizer.readToken(), style: .flow)

    do {
      while try tokenizer.readToken() != nil {}
      Issue.record("Expected invalid separator error")
    } catch let error as YAML.ParseError {
      guard case .invalidSyntax(_, let location) = error else {
        Issue.record("Expected invalidSyntax, got \(error)")
        return
      }
      #expect(location?.line == 2)
    }
  }

  @Test("tokenizer rejects invalid yaml-test-suite fixtures", arguments: [
    "236B",  // invalid value after mapping
    "2CMS",  // invalid mapping in plain multiline scalar
    "3HFZ",  // content after explicit document end marker
    "4EJS",  // tab indentation in mapping
    "4H7K",  // extra flow sequence close
    "4HVU",  // wrong sequence indentation
    "4JVG",  // invalid anchor placement
    "55WF",  // invalid double-quoted escape
    "5LLU",  // block scalar indentation error
    "5TRB",  // document marker inside double-quoted scalar
    "5U3A",  // sequence on same line as mapping key
    "62EZ",  // invalid content after flow mapping value
    "6JTT",  // flow sequence without closing bracket
    "6S55",  // invalid scalar at end of sequence
    "7LBH",  // multiline double-quoted implicit key
    "7MNF",  // missing colon
    "8XDJ",  // comment in plain multiline value
    "9C9N",  // wrong indented flow sequence
    "9CWY",  // invalid scalar at end of mapping
    "9HCY",  // directive after content
    "9JBA",  // invalid comment after flow sequence
    "9KBC",  // mapping on document start line
    "9MAG",  // leading comma in flow sequence
    "9MMA",  // directive without document
    "MUS6/00",  // invalid YAML directive without separated comment
    "B63P",  // directive followed by document end only
    "BD7L",  // mapping after sequence
    "BF9H",  // trailing comment in multiline plain scalar
    "BS4K",  // comment between plain scalar lines
    "C2SP",  // flow mapping key over two lines
    "CML9",  // missing comma in flow
    "CQ3W",  // missing closing double quote
    "CTN5",  // extra comma in flow sequence
    "CVW2",  // invalid comment after comma
    "CXX2",  // mapping with anchor on document start line
    "D49Q",  // multiline single-quoted implicit key
    "DK4H",  // implicit flow key followed by newline
    "DK95/01",  // tab indentation in pending double-quoted scalar
    "DK95/06",  // tab indentation before nested mapping key
    "DMG6",  // bad mapping indentation
    "EB22",  // directive after scalar content
    "EW3V",  // bad mapping indentation
    "G5U8",  // invalid plain indicators in flow
    "G7JE",  // multiline plain implicit key
    "G9HC",  // anchor before block sequence
    "GDY7",  // invalid plain/comment mapping transition
    "GT5M",  // anchor before block sequence item
    "H7J7",  // tag after anchor on next line
    "H7TQ",  // invalid YAML directive
    "HRE5",  // invalid double-quoted escape
    "HU3P",  // mapping in plain multiline value
    "JKF3",  // multiline quoted key in nested sequence
    "JY7Z",  // trailing content after quoted scalar
    "KS4U",  // trailing content after flow sequence
    "LHL4",  // invalid tag
    "N4JP",  // bad mapping indentation
    "N782",  // document markers inside flow style
    "P2EQ",  // invalid content after flow mapping value
    "Q4CL",  // trailing content after quoted scalar
    "QB6E",  // unterminated double-quoted scalar
    "QLJ7",  // invalid tag directive reuse
    "RHX7",  // directive after content
    "RXY3",  // document marker inside single-quoted scalar
    "S4GJ",  // invalid block scalar header
    "S98Z",  // invalid empty block scalar indentation
    "SF5V",  // duplicate YAML directive
    "SR86",  // alias with anchor
    "SU5Z",  // missing separation before comment
    "SU74",  // alias key with extra content
    "SY6V",  // anchor before sequence entry on same line
    "T833",  // flow mapping missing separating comma
    "TD5N",  // scalar after block sequence
    "U44R",  // bad mapping indentation
    "U99R",  // invalid tag syntax in sequence
    "W9L4",  // invalid block scalar indentation
    "X4QW",  // invalid block scalar header
    "Y79Y/004",  // tab before nested sequence indicator
    "Y79Y/005",  // tab after sequence indicator separation
    "Y79Y/006",  // tab after explicit mapping indicator
    "Y79Y/007",  // tab before nested sequence after explicit value
    "Y79Y/008",  // tab after explicit mapping indicator before key
    "Y79Y/009",  // tab before nested mapping after explicit value
    "YJV2",  // invalid plain indicator in flow
    "ZCZ6",  // repeated mapping separators
    "ZL4Z",  // trailing content after quoted scalar key
    "ZVH3",  // bad sequence indentation
    "ZXT5",  // invalid flow mapping separator
  ])
  func tokenizerRejectsInvalidYamlTestSuiteFixture(_ id: String) throws {
    let yaml = try loadYamlTestSuiteInput(id)
    #expect(throws: Error.self) {
      _ = try renderTokenizerEventLines(yaml)
    }
  }

  @Test("tab indentation reports indentation error location")
  func tabIndentationErrorLocation() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("\tkey: value\n".utf8), isFinal: true)

    do {
      _ = try tokenizer.readToken()
      Issue.record("Expected indentation error")
    } catch YAML.ParseError.invalidIndentation(let location) {
      #expect(location == .init(line: 1, column: 2))
    } catch {
      Issue.record("Expected indentation error, got \(error)")
    }
  }

  @Test("tab indentation inside pending quoted scalar is rejected")
  func tabIndentationInsidePendingQuotedScalarIsRejected() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("foo: \"bar\n\tbaz\"\n".utf8), isFinal: true)

    #expect(throws: YAML.ParseError.self) {
      while try tokenizer.readToken() != nil {}
    }
  }

  @Test("tabs separate block sequence indicators from values")
  func tabsSeparateBlockSequenceIndicatorsFromValues() throws {
    for id in ["6BCT", "A2M4"] {
      let yaml = try loadYamlTestSuiteInput(id)
      let actualEvents = try renderTokenizerEventLines(yaml)
      let expectedEvents = try loadYamlTestSuiteEventLines(id)
      #expect(
        actualEvents == expectedEvents,
        "\(id): actual \(actualEvents), expected \(expectedEvents)"
      )
      let actualValues = try decodeTokenizerValues(yaml)
      let expectedValues = try decodeProductionDocumentValues(yaml)
      #expect(actualValues == expectedValues, "\(id): actual \(actualValues), expected \(expectedValues)")
    }
  }

  @Test("unterminated double quote reports incomplete input")
  func unterminatedDoubleQuote() throws {
    var tokenizer = YAMLTokenizer()
    tokenizer.feedInput(Data("\"foo".utf8), isFinal: true)

    #expect(throws: YAML.ParseError.self) {
      while try tokenizer.readToken() != nil {}
    }
  }

  @Test("tokenizer decoded values match production document path", arguments: [
    "hello\n",
    "- one\n- 2\n",
    "a: 1\nb: two\n",
    "- a: 1\n- b: two\n",
    "parent:\n  - one\n  - two\n",
    "-\n- value\n",
    "a:\nb: 1\n",
    "parent:\n  child: value\n",
    "? explicit key\n: explicit value\n? empty value\n",
    ": empty key\n",
    "single multiline\n  scalar\n",
    "- single multiline\n  sequence entry\n- next\n",
    "mapping:\n  value line\n  continuation\nnext: value\n",
    "'it''s'\n",
    "literal: |\n  one\n  two\n",
    "folded: >\n  three\n  four\n",
    "[a, {b: \"c\"}]\n",
    "{a:, : empty, b: 2}\n",
    "{a: [1, {b: 2}], c: []}\n",
  ])
  func tokenizerValueParityWithProductionDocuments(_ yaml: String) throws {
    let tokenizerValues = try decodeTokenizerValues(yaml)
    let productionValues = try decodeProductionDocumentValues(yaml)
    #expect(tokenizerValues == productionValues)
  }

  @Test("tokenizer rendered event lines match production document path", arguments: [
    "a: 1\nb: two\n",
    "- a: 1\n- b: two\n",
    "a:\nb: 1\n",
    "? explicit key\n: explicit value\n? empty value\n",
  ])
  func tokenizerEventLineParityWithProductionDocuments(_ yaml: String) throws {
    try expectTokenizerEventLineParity(yaml)
  }

  @Test("tokenizer backed chunked events match production reader", arguments: [
    ["a: 1\n", "b: two\n"],
    ["%TAG !e! tag:example.com,2026:\n---\n", "!e!thing value\n"],
  ])
  func tokenizerBackedChunkedEventsMatchProductionReader(_ chunks: [String]) throws {
    #expect(try renderTokenizerChunkedEventLines(chunks) == renderProductionReaderEventLines(chunks))
  }

  @Test("tokenizer backed chunked values match production reader", arguments: [
    ["[\n  a,\n", "  {b: \"c\"}\n]\n"],
    ["[", "a", ",", "{", "b", ":", "\"c\"", "}", "]\n"],
    ["[", "!local ", "&a ", "one", ", ", "*a", "]\n"],
    ["literal: |-\n  on", "e\n"],
    ["[&a one, *a]\n"],
  ])
  func tokenizerBackedChunkedValuesMatchProductionReader(_ chunks: [String]) throws {
    #expect(try decodeTokenizerChunkedValue(chunks) == decodeProductionReaderValue(chunks))
  }

  @Test("tokenizer backed event reader matches production reader", arguments: [
    ["---\na: 1\n...\n---\nb: 2\n"],
    ["%TAG !e! tag:example.com,2026:\n---\n", "!e!thing value\n"],
    ["literal: |-\n  on", "e\nfolded: >\n  two\n  three\n"],
    ["[\n  a,\n", "  {b: \"c\"}\n]\n"],
  ])
  func tokenizerBackedEventReaderMatchesProductionReader(_ chunks: [String]) throws {
    let actual = try renderTokenizerBackedReaderEventSignatures(chunks)
    let expected = try renderProductionReaderEventSignatures(chunks)
    #expect(
      actual == expected,
      """
      tokenizer-backed reader:
      \(actual.joined(separator: "\n"))
      production reader:
      \(expected.joined(separator: "\n"))
      """
    )
  }

  @Test("tokenizer document stream preserves document metadata")
  func tokenizerDocumentStreamPreservesDocumentMetadata() throws {
    var stream = YAMLTokenDocumentStream()
    stream.feedInput(Data("---\na: 1\n...\n---\nb: 2\n".utf8), isFinal: true)

    let first = try #require(try stream.readDocument())
    #expect(first.explicitStart)
    #expect(first.explicitEnd)
    #expect(try decodeEvents(first.events) == ["a": 1])

    let second = try #require(try stream.readDocument())
    #expect(second.explicitStart)
    #expect(!second.explicitEnd)
    #expect(try decodeEvents(second.events) == ["b": 2])

    #expect(try stream.readDocument() == nil)
  }

  @Test("tokenizer document stream value documents match production reader", arguments: [
    "229Q",
    "36F6",
    "TS54",
    "U3C3",
    "3GZX",
    "X38W",
    "5TYM",
    "NKF9",
    "P2AD",
    "MJS9",
    "6FWR",
    "7ZZ5",
    "EHF6",
    "CN3R",
    "27NA",
    "35KP",
    "2XXW",
    "6KGN",
    "7BUB",
    "FTA2",
    "GH63",
    "RR7F",
    "X8DW",
    "W42U",
    "W4TN",
    "M5DY",
    "V9D5",
    "CT4Q",
    "6BCT",
    "A2M4",
    "WZ62",
    "L383",
    "K858",
    "M5C3",
    "DBG4",
    "HM87/00",
    "M7A3",
    "6CA3",
    "DK95/03",
    "DK95/04",
    "DK95/05",
    "DK95/07",
    "HS5T",
    "NB6Z",
    "Q5MG",
    "UV7Q",
    "8CWC",
    "DK95/00",
    "UKK6/01",
    "NP9H",
    "Q8AD",
    "RZP5",
    "XW4D",
    "DE56/00",
    "DE56/01",
    "DE56/02",
    "DE56/03",
    "DE56/04",
    "DE56/05",
    "57H4",
    "M6YH",
    "FH7J",
    "G4RS",
    "PW8X",
    "KK5P",
    "M2N8/01",
  ])
  func tokenizerDocumentStreamValueDocumentsMatchProductionReader(_ id: String) throws {
    let yaml = try loadYamlTestSuiteInput(id)
    let actual = try tokenizerValueDocuments(yaml)
    let expected = try productionValueDocuments(yaml)
    #expect(actual == expected, "\(id): actual \(actual), expected \(expected)")
  }

  @Test("tokenizer document stream node documents match production reader", arguments: [
    "229Q",
    "36F6",
    "TS54",
    "U3C3",
    "3GZX",
    "X38W",
    "5TYM",
    "NKF9",
    "P2AD",
    "MJS9",
    "6FWR",
    "7ZZ5",
    "EHF6",
    "CN3R",
    "27NA",
    "35KP",
    "2XXW",
    "6KGN",
    "7BUB",
    "FTA2",
    "GH63",
    "RR7F",
    "X8DW",
    "W42U",
    "W4TN",
    "M5DY",
    "V9D5",
    "CT4Q",
    "6BCT",
    "A2M4",
    "WZ62",
    "L383",
    "K858",
    "M5C3",
    "DBG4",
    "HM87/00",
    "M7A3",
    "6CA3",
    "DK95/03",
    "DK95/04",
    "DK95/05",
    "DK95/07",
    "HS5T",
    "NB6Z",
    "Q5MG",
    "UV7Q",
    "8CWC",
    "DK95/00",
    "UKK6/01",
    "NP9H",
    "Q8AD",
    "RZP5",
    "XW4D",
    "DE56/00",
    "DE56/01",
    "DE56/02",
    "DE56/03",
    "DE56/04",
    "DE56/05",
    "57H4",
    "M6YH",
    "FH7J",
    "G4RS",
    "PW8X",
    "KK5P",
    "M2N8/01",
  ])
  func tokenizerDocumentStreamNodeDocumentsMatchProductionReader(_ id: String) throws {
    let yaml = try loadYamlTestSuiteInput(id)
    let actual = try renderTokenizerDocumentStreamNodeLines(yaml)
    let expected = try renderProductionDocumentNodeLines(yaml)
    #expect(
      actual == expected,
      """
      tokenizer documents:
      \(actual.joined(separator: "\n"))
      production documents:
      \(expected.joined(separator: "\n"))
      """
    )
  }

  @Test("tokenizer event lines match yaml-test-suite fixtures", arguments: [
    "229Q",  // sequence entries with indented mapping nodes
    "36F6",  // multiline plain scalar with empty line
    "AB8U",  // sequence entry folded from a continuation line
    "TS54",  // folded block scalar
    "TL85",  // multiline double quoted flow folding
    "U3C3",  // TAG directive
    "2EBW",  // allowed punctuation in plain mapping keys
    "4GC6",  // single quoted characters
    "5WE3",  // comments after compact sequence entries
    "3UYS",  // escaped slash in double quotes
    "4UYU",  // colon in double quoted string
    "9SHH",  // quoted scalar indicators
    "7A4E",  // double quoted lines
    "9TFX",  // double quoted lines with explicit document start
    "6SLA",  // quoted mapping keys
    "87E4",  // single quoted implicit keys
    "3GZX",  // anchors and aliases in block mapping
    "X38W",  // aliases in flow objects
    "4CQQ",  // multiline plain and quoted mapping values
    "58MP",  // adjacent colon in flow mapping scalar
    "5TYM",  // local tag prefix across documents
    "SKE5",  // anchor before zero-indented sequence
    "NKF9",  // empty keys in block and flow mappings
    "4QFQ",  // block indentation indicator
    "R4YG",  // block indentation indicator with tab content
    "P2AD",  // block scalar headers
    "MJS9",  // block folding
    "4WA9",  // literal scalars in mappings
    "6JQW",  // literal document scalar
    "6FWR",  // block scalar keep
    "753E",  // block scalar strip
    "A6F9",  // block scalar chomping comparison
    "B3HG",  // folded scalar
    "4Q9F",  // folded block scalar
    "96L6",  // folded scalar line folding
    "7T8X",  // folded lines and final empty lines
    "6VJK",  // folded scalar with more-indented lines
    "6HB6",  // separated comments inside flow sequence lines
    "7ZZ5",  // empty flow collections
    "5C5M",  // flow mappings
    "54T7",  // flow mapping
    "4ABK",  // flow mapping separate values
    "4MUZ/00",  // flow mapping colon on next line after quoted key
    "4MUZ/01",  // flow mapping colon on next line after quoted key
    "4MUZ/02",  // flow mapping colon on next line after plain key
    "652Z",  // question mark at start of flow key
    "8KB6",  // multiline plain flow mapping key without value
    "9BXH",  // multiline double quoted flow mapping key without value
    "9SA2",  // multiline double quoted flow mapping key
    "NJ66",  // multiline plain flow mapping key
    "LX3P",  // implicit flow mapping key on one line
    "9MMW",  // single pair implicit entries
    "QF4Y",  // single-pair flow mappings
    "DFF7",  // explicit and implicit flow mapping entries
    "CT4Q",  // multiline explicit flow mapping key in flow sequence
    "8UDB",  // multiline flow sequence entries
    "M7NX",  // nested flow collections
    "R52L",  // nested flow mapping sequence and mappings
    "SBG9",  // flow sequence in flow mapping
    "EHF6",  // tags for flow objects
    "CN3R",  // anchors in flow sequence
    "LE5A",  // flow nodes
    "UDR7",  // flow collection indicators
    "Q88A",  // flow content
    "WZ62",  // empty tagged nodes in flow mappings
    "5KJE",  // flow sequence
    "DHP8",  // simple flow sequence
    "FUP4",  // nested flow sequence
    "F3CP",  // nested flow collections on one line
    "9KAX",  // tag and anchor ordering
    "F2C7",  // anchors and tags
    "2SXE",  // anchors with colon in name
    "27NA",  // document start marker with root node
    "35KP",  // tags for root objects
    "2XXW",  // tagged set mapping
    "3ALJ",  // nested block sequence continuation
    "4FJ6",  // nested implicit complex keys
    "M5DY",  // explicit sequence keys with nested sequence values
    "V9D5",  // compact explicit mapping entries
    "6BCT",  // tabs separating block sequence entries
    "A2M4",  // tab-separated compact nested block sequence entries
    "6BFJ",  // anchors on mapping, key, and flow sequence item
    "6PBE",  // zero-indented sequences in explicit mapping keys
    "6KGN",  // anchor for empty node
    "7BUB",  // block sequence anchor and alias reuse
    "3R3P",  // anchor before block sequence
    "FTA2",  // anchor on explicit document start sequence
    "GH63",  // mixed block mapping explicit to implicit
    "RR7F",  // mixed block mapping implicit to explicit
    "X8DW",  // explicit key and value separated by comment
    "K3WX",  // flow mapping colon after intervening comment
    "3MYT",  // plain scalar that resembles key/comment/anchor/tag
    "QT73",  // comment followed by document end marker
    "7TMG",  // comment inside flow sequence before comma
    "ZWK4",  // key with anchor after missing explicit mapping value
    "K54U",  // tab after document header
    "7Z25",  // bare document after explicit document end
    "L383",  // scalar documents with trailing comments
    "26DV",  // whitespace around mapping colons with aliases
    "W42U",  // comments after nested compact block entries
    "33X3",  // sequence items with explicit int tags
    "5T43",  // adjacent flow scalar starting with colon
    "W4TN",  // document boundaries terminate root block scalars
    "K858",  // empty block scalar chomping
    "M5C3",  // block scalar node with tag and explicit indent indicator
    "M7A3",  // bare document followed by literal content after document end
    "CFD4",  // empty implicit key in single-pair flow sequences
    "UDM2",  // plain URL in flow mapping
    "DBG4",  // plain scalars starting with colon in flow and block sequences
    "HM87/00",  // leading colon plain scalar in flow sequence
    "DE56/00",  // literal tab before folded double-quoted line break
    "DE56/01",  // trailing tab before folded double-quoted line break
    "DE56/02",  // escaped tab before folded double-quoted line break
    "DE56/03",  // escaped tab with trailing spaces before folded double-quoted line break
    "DE56/04",  // escaped line break with trailing tab and spaces
    "DE56/05",  // escaped line break with separated trailing tab
    "NP9H",  // double quoted line breaks
    "Q8AD",  // double quoted line breaks with escaped spaces
    "RZP5",  // separated comments after quoted scalars
    "XW4D",  // separated comments after quoted scalars
    "6CA3",  // tabs before root flow sequence
    "DK95/03",  // tab-only separation line before mapping
    "DK95/04",  // tab-only separation line inside mapping
    "DK95/05",  // mixed blank separation line inside mapping
    "DK95/07",  // tab-only separation line after directive
    "HS5T",  // tab-indented plain continuation after blank line
    "NB6Z",  // tab-indented plain continuation in mapping value
    "Q5MG",  // tab before root flow mapping
    "UV7Q",  // legal tab after block sequence indentation
    "8CWC",  // mapping key ending with repeated colons
    "DK95/00",  // tab separation before block mapping value
    "UKK6/01",  // syntax-character plain scalar key
    "57H4",  // tags on block sequence and mapping values
    "M6YH",  // one-space nested block collection values in sequence
    "FH7J",  // empty tagged scalars in block sequence and mapping entries
    "G4RS",  // hash characters inside single-quoted mapping values
    "PW8X",  // anchors on empty scalars
    "KK5P",  // explicit block mapping entries with complex keys
    "M2N8/01",  // explicit key with flow sequence mapping key
  ])
  func tokenizerEventLineParityWithYamlTestSuiteFixture(_ id: String) throws {
    let yaml = try loadYamlTestSuiteInput(id)
    let actual = try renderTokenizerEventLines(yaml)
    let expected = try loadYamlTestSuiteEventLines(id)
    #expect(
      actual == expected,
      """
      tokenizer events:
      \(actual.joined(separator: "\n"))
      expected events:
      \(expected.joined(separator: "\n"))
      """
    )
  }

  @Test("tokenizer values match yaml-test-suite fixtures", arguments: [
    "229Q",
    "36F6",
    "AB8U",
    "TS54",
    "TL85",
    "U3C3",
    "2EBW",
    "4GC6",
    "5WE3",
    "3UYS",
    "4UYU",
    "9SHH",
    "7A4E",
    "9TFX",
    "6SLA",
    "87E4",
    "3GZX",
    "4CQQ",
    "58MP",
    "SKE5",
    "NKF9",
    "4QFQ",
    "R4YG",
    "P2AD",
    "MJS9",
    "4WA9",
    "6JQW",
    "6FWR",
    "753E",
    "A6F9",
    "B3HG",
    "4Q9F",
    "96L6",
    "7T8X",
    "6VJK",
    "6HB6",
    "7ZZ5",
    "5C5M",
    "54T7",
    "4ABK",
    "4MUZ/00",
    "4MUZ/01",
    "4MUZ/02",
    "652Z",
    "8KB6",
    "9BXH",
    "9SA2",
    "NJ66",
    "LX3P",
    "9MMW",
    "QF4Y",
    "DFF7",
    "CT4Q",
    "8UDB",
    "M7NX",
    "R52L",
    "SBG9",
    "EHF6",
    "CN3R",
    "LE5A",
    "UDR7",
    "Q88A",
    "WZ62",
    "5KJE",
    "DHP8",
    "FUP4",
    "F3CP",
    "9KAX",
    "F2C7",
    "2SXE",
    "27NA",
    "35KP",
    "2XXW",
    "3ALJ",
    "M5DY",
    "V9D5",
    "6BCT",
    "A2M4",
    "6KGN",
    "7BUB",
    "3R3P",
    "FTA2",
    "GH63",
    "RR7F",
    "X8DW",
    "K3WX",
    "3MYT",
    "7TMG",
    "ZWK4",
    "K54U",
    "7Z25",
    "L383",
    "26DV",
    "W42U",
    "33X3",
    "5T43",
    "W4TN",
    "K858",
    "M5C3",
    "M7A3",
    "UDM2",
    "DBG4",
    "HM87/00",
    "DE56/00",
    "DE56/01",
    "DE56/02",
    "DE56/03",
    "DE56/04",
    "DE56/05",
    "NP9H",
    "Q8AD",
    "RZP5",
    "XW4D",
    "6CA3",
    "DK95/03",
    "DK95/04",
    "DK95/05",
    "DK95/07",
    "HS5T",
    "NB6Z",
    "Q5MG",
    "UV7Q",
    "8CWC",
    "DK95/00",
    "UKK6/01",
    "57H4",
    "M6YH",
    "FH7J",
    "G4RS",
    "PW8X",
    "KK5P",
    "M2N8/01",
  ])
  func tokenizerValueParityWithYamlTestSuiteFixture(_ id: String) throws {
    let yaml = try loadYamlTestSuiteInput(id)
    let actual = try decodeTokenizerValues(yaml)
    let expected = try decodeProductionDocumentValues(yaml)
    #expect(actual == expected, "\(id): actual \(actual), expected \(expected)")
  }

}

private func loadYamlTestSuiteInput(_ id: String) throws -> String {
  let url = yamlTestSuiteCaseDirectory(id).appendingPathComponent("in.yaml")
  return try String(contentsOf: url, encoding: .utf8)
}

private func loadYamlTestSuiteEventLines(_ id: String) throws -> [String] {
  let url = yamlTestSuiteCaseDirectory(id).appendingPathComponent("test.event")
  let text = try String(contentsOf: url, encoding: .utf8)
  return text.split(whereSeparator: \.isNewline).map(String.init)
}

private func yamlTestSuiteCaseDirectory(_ id: String) -> URL {
  yamlTestSuiteRootDirectory().appendingPathComponent(id, isDirectory: true)
}

private func yamlTestSuiteRootDirectory() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/yaml-test-suite", isDirectory: true)
}

private func decodeTokenizerValues(_ yaml: String) throws -> [Value] {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data(yaml.utf8), isFinal: true)
  var adapter = YAMLTokenEventAdapter()
  var decoder: ParseEventDecoder?
  var values: [Value] = []

  while let token = try tokenizer.readToken() {
    switch token {
    case .documentStart:
      decoder = ParseEventDecoder(resolver: YAMLScalarResolver())
    case .documentEnd:
      if let active = decoder {
        var finished = active
        values.append(try finished.finish())
      }
      decoder = nil
    default:
      var events: [ParseEvent] = []
      try adapter.append(token, into: &events)
      if decoder == nil {
        decoder = ParseEventDecoder(resolver: YAMLScalarResolver())
      }
      for event in events {
        try decoder?.append(event)
      }
    }
  }

  return values
}

private func decodeProductionDocumentValues(_ yaml: String) throws -> [Value] {
  try productionValueDocuments(yaml).map(\.value)
}

private func expectTokenizerEventLineParity(_ yaml: String) throws {
  let actual = try renderTokenizerEventLines(yaml)
  let expected = try renderProductionDocumentNodeLines(yaml)
  #expect(
    actual == expected,
    """
    tokenizer events:
    \(actual.joined(separator: "\n"))
    production events:
    \(expected.joined(separator: "\n"))
    """
  )
}

private func renderTokenizerEventLines(_ yaml: String) throws -> [String] {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data(yaml.utf8), isFinal: true)
  var adapter = YAMLTokenEventAdapter()
  var lines = ["+STR"]
  var builder: YAMLNodeBuilder?
  var explicitStart = false

  while let token = try tokenizer.readToken() {
    switch token {
    case .directive:
      continue

    case .documentStart(let explicit):
      builder = YAMLNodeBuilder()
      explicitStart = explicit

    case .documentEnd(let explicit):
      guard var active = builder else {
        continue
      }
      let node = try active.finish()
      appendDocumentEventLines(
        node: node,
        explicitStart: explicitStart,
        explicitEnd: explicit,
        into: &lines
      )
      builder = nil

    default:
      if builder == nil {
        builder = YAMLNodeBuilder()
        explicitStart = false
      }
      var events: [ParseEvent] = []
      try adapter.append(token, into: &events)
      for event in events {
        try builder?.append(event)
      }
    }
  }

  lines.append("-STR")
  return lines
}

private func renderTokenizerChunkedEventLines(_ chunks: [String]) throws -> [String] {
  var tokenizer = YAMLTokenizer()
  var adapter = YAMLTokenEventAdapter()
  var builder = YAMLNodeBuilder()

  for (index, chunk) in chunks.enumerated() {
    tokenizer.feedInput(Data(chunk.utf8), isFinal: index == chunks.count - 1)
    while let token = try tokenizer.readToken() {
      var events: [ParseEvent] = []
      try adapter.append(token, into: &events)
      for event in events {
        try builder.append(event)
      }
    }
  }

  return renderSingleDocumentEventLines(try builder.finish())
}

private func renderProductionReaderEventLines(_ chunks: [String]) throws -> [String] {
  var reader = YAMLEventReader()
  var builder = YAMLNodeBuilder()

  for (index, chunk) in chunks.enumerated() {
    reader.feedInput(Data(chunk.utf8), isFinal: index == chunks.count - 1)
  }

  while let event = try reader.readEvent() {
    try builder.append(event)
  }

  return renderSingleDocumentEventLines(try builder.finish())
}

private func renderTokenizerBackedReaderEventSignatures(_ chunks: [String]) throws -> [String] {
  var reader = YAMLTokenDocumentStream()
  var events: [ParseEvent] = []

  for (index, chunk) in chunks.enumerated() {
    reader.feedInput(Data(chunk.utf8), isFinal: index == chunks.count - 1)
  }

  while let event = try reader.readEvent() {
    events.append(event)
  }
  if !reader.isFinished {
    Issue.record("Tokenizer-backed reader did not finish")
  }
  return try renderEventSignatures(events)
}

private func renderProductionReaderEventSignatures(_ chunks: [String]) throws -> [String] {
  var reader = YAMLEventReader()
  var events: [ParseEvent] = []

  for (index, chunk) in chunks.enumerated() {
    reader.feedInput(Data(chunk.utf8), isFinal: index == chunks.count - 1)
  }

  while let event = try reader.readEvent() {
    events.append(event)
  }
  if !reader.isFinished {
    Issue.record("Production reader did not finish")
  }
  return try renderEventSignatures(events)
}

private func renderEventSignatures(_ events: [ParseEvent]) throws -> [String] {
  let resolver = YAMLScalarResolver()
  var signatures: [String] = []
  for event in events {
    switch event {
    case .style(let style):
      _ = style
    case .tag(let ref):
      signatures.append("tag:\(try ref.materialize(using: resolver))")
    case .anchor(let anchor):
      _ = anchor
    case .alias(let alias):
      signatures.append("alias:\(alias)")
    case .scalar(let ref):
      signatures.append("scalar:\(try ref.materialize(using: resolver))")
    case .beginArray:
      signatures.append("beginArray")
    case .endArray:
      signatures.append("endArray")
    case .beginObject:
      signatures.append("beginObject")
    case .endObject:
      signatures.append("endObject")
    }
  }
  return signatures
}

private func decodeTokenizerChunkedValue(_ chunks: [String]) throws -> Value {
  var tokenizer = YAMLTokenizer()
  var adapter = YAMLTokenEventAdapter()
  var decoder = ParseEventDecoder(resolver: YAMLScalarResolver())

  for (index, chunk) in chunks.enumerated() {
    tokenizer.feedInput(Data(chunk.utf8), isFinal: index == chunks.count - 1)
    while let token = try tokenizer.readToken() {
      var events: [ParseEvent] = []
      try adapter.append(token, into: &events)
      for event in events {
        try decoder.append(event)
      }
    }
  }

  return try decoder.finish()
}

private func decodeEvents(_ events: [ParseEvent]) throws -> Value {
  var decoder = ParseEventDecoder(resolver: YAMLScalarResolver())
  for event in events {
    try decoder.append(event)
  }
  return try decoder.finish()
}

private func decodeProductionReaderValue(_ chunks: [String]) throws -> Value {
  var reader = YAMLEventReader()
  var decoder = ParseEventDecoder(resolver: YAMLScalarResolver())

  for (index, chunk) in chunks.enumerated() {
    reader.feedInput(Data(chunk.utf8), isFinal: index == chunks.count - 1)
  }
  while let event = try reader.readEvent() {
    try decoder.append(event)
  }

  return try decoder.finish()
}

private func tokenizerValueDocuments(_ yaml: String) throws -> [YAMLValueDocument] {
  var stream = YAMLTokenDocumentStream()
  stream.feedInput(Data(yaml.utf8), isFinal: true)

  var documents: [YAMLValueDocument] = []
  while let document = try stream.readValueDocument() {
    documents.append(document)
  }
  return documents
}

private func productionValueDocuments(_ yaml: String) throws -> [YAMLValueDocument] {
  try YAMLDocumentReader(data: Data(yaml.utf8)).readAll()
}

private func renderTokenizerDocumentStreamNodeLines(_ yaml: String) throws -> [String] {
  var stream = YAMLTokenDocumentStream()
  stream.feedInput(Data(yaml.utf8), isFinal: true)

  var lines = ["+STR"]
  while let document = try stream.readNodeDocument() {
    appendDocumentEventLines(
      node: document.node,
      explicitStart: document.explicitStart,
      explicitEnd: document.explicitEnd,
      into: &lines
    )
  }
  lines.append("-STR")
  return lines
}

private func renderProductionDocumentNodeLines(_ yaml: String) throws -> [String] {
  let documents = try YAMLNodeDocumentReader(data: Data(yaml.utf8)).readAll()

  var lines = ["+STR"]
  for document in documents {
    appendDocumentEventLines(
      node: document.node,
      explicitStart: document.explicitStart,
      explicitEnd: document.explicitEnd,
      into: &lines
    )
  }
  lines.append("-STR")
  return lines
}

private func renderSingleDocumentEventLines(_ node: YAMLNode) -> [String] {
  var lines = ["+STR", "+DOC"]
  appendNodeEventLines(node, into: &lines)
  lines.append("-DOC")
  lines.append("-STR")
  return lines
}

private func appendDocumentEventLines(
  node: YAMLNode,
  explicitStart: Bool,
  explicitEnd: Bool,
  into lines: inout [String]
) {
  lines.append(explicitStart ? "+DOC ---" : "+DOC")
  appendNodeEventLines(node, into: &lines)
  lines.append(explicitEnd ? "-DOC ..." : "-DOC")
}

private func appendNodeEventLines(_ node: YAMLNode, into lines: inout [String]) {
  switch node {
  case .alias(let name):
    lines.append("=ALI *\(name)")

  case .scalar(let scalar, let tag, let anchor):
    lines.append(formatScalarEventLine(scalar, tag: tag, anchor: anchor))

  case .sequence(let items, let style, let tag, let anchor):
    lines.append(formatCollectionEventLine(kind: "+SEQ", style: style, tag: tag, anchor: anchor))
    for item in items {
      appendNodeEventLines(item, into: &lines)
    }
    lines.append("-SEQ")

  case .mapping(let pairs, let style, let tag, let anchor):
    lines.append(formatCollectionEventLine(kind: "+MAP", style: style, tag: tag, anchor: anchor))
    for (key, value) in pairs {
      appendNodeEventLines(key, into: &lines)
      appendNodeEventLines(value, into: &lines)
    }
    lines.append("-MAP")
  }
}

private func scalarStyle(
  named name: String,
  in pairs: [(YAMLNode, YAMLNode)]
) -> YAMLScalarStyle? {
  for (key, value) in pairs {
    guard case .scalar(let keyScalar, _, _) = key, keyScalar.text == name else {
      continue
    }
    guard case .scalar(let valueScalar, _, _) = value else {
      return nil
    }
    return valueScalar.style
  }
  return nil
}

private func formatCollectionEventLine(
  kind: String,
  style: YAMLCollectionStyle,
  tag: String?,
  anchor: String?
) -> String {
  var parts = [kind]
  if style.matches(.flow) {
    parts.append(kind == "+SEQ" ? "[]" : "{}")
  }
  if let anchor {
    parts.append("&\(anchor)")
  }
  if let tag {
    parts.append("<\(tag)>")
  }
  return parts.joined(separator: " ")
}

private func formatScalarEventLine(_ scalar: YAMLScalar, tag: String?, anchor: String?) -> String {
  var parts = ["=VAL"]
  if let anchor {
    parts.append("&\(anchor)")
  }
  if let tag {
    parts.append("<\(tag)>")
  }
  parts.append("\(scalarStyleToken(scalar.style))\(escapeEventScalarText(scalar.text))")
  return parts.joined(separator: " ")
}

private func scalarStyleToken(_ style: YAMLScalarStyle) -> String {
  switch style {
  case .plain:
    return ":"
  case .singleQuoted:
    return "'"
  case .doubleQuoted:
    return "\""
  case .literal:
    return "|"
  case .folded:
    return ">"
  }
}

private func escapeEventScalarText(_ text: String) -> String {
  var output = ""
  output.reserveCapacity(text.count)
  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 0x5C: output.append("\\\\")
    case 0x0A: output.append("\\n")
    case 0x09: output.append("\\t")
    case 0x0D: output.append("\\r")
    case 0x08: output.append("\\b")
    case 0x0C: output.append("\\f")
    default: output.unicodeScalars.append(scalar)
    }
  }
  return output
}

private func assertSingleDocumentTokens(
  _ yaml: String,
  body: (inout YAMLTokenizer) throws -> Void
) throws {
  var tokenizer = YAMLTokenizer()
  tokenizer.feedInput(Data(yaml.utf8), isFinal: true)

  try expectDocumentStart(try tokenizer.readToken(), explicit: false)
  try body(&tokenizer)
  try expectDocumentEnd(try tokenizer.readToken(), explicit: false)
  #expect(try tokenizer.readToken() == nil)
}

private func expectDirective(
  _ token: YAMLRawToken?,
  name: String,
  value: String?
) throws {
  guard case .directive(let actualName, let actualValue) = token else {
    Issue.record("Expected directive token, got \(String(describing: token))")
    return
  }
  #expect(actualName == name)
  #expect(actualValue == value)
}

private func expectDocumentStart(_ token: YAMLRawToken?, explicit: Bool) throws {
  guard case .documentStart(let actual) = token else {
    Issue.record("Expected documentStart token, got \(String(describing: token))")
    return
  }
  #expect(actual == explicit)
}

private func expectDocumentEnd(_ token: YAMLRawToken?, explicit: Bool) throws {
  guard case .documentEnd(let actual) = token else {
    Issue.record("Expected documentEnd token, got \(String(describing: token))")
    return
  }
  #expect(actual == explicit)
}

private func expectScalar(_ token: YAMLRawToken?) throws -> YAMLRawScalar {
  guard case .scalar(let scalar) = token else {
    Issue.record("Expected scalar token, got \(String(describing: token))")
    throw YAML.ParseError.invalidSyntax("Expected scalar token", location: nil)
  }
  return scalar
}

private func expectRetainedScalar(_ token: YAMLRawToken?, text expected: String) throws {
  let scalar = try expectScalar(token)
  #expect(try scalar.region.string() == expected)
  #expect(scalar.region.segmentIndex != nil)
  #expect(scalar.region.segmentRange != nil)
  #expect(scalar.region.isCopied == false)
}

private func expectScalarText(_ token: YAMLRawToken?, _ expected: String) throws {
  let scalar = try expectScalar(token)
  #expect(try scalar.region.string() == expected)
}

private func expectBeginSequence(
  _ token: YAMLRawToken?,
  style expectedStyle: YAMLCollectionStyle = .block
) throws {
  guard case .beginSequence(let style) = token, style.matches(expectedStyle) else {
    Issue.record("Expected beginSequence token, got \(String(describing: token))")
    return
  }
}

private func expectEndSequence(_ token: YAMLRawToken?) throws {
  guard case .endSequence = token else {
    Issue.record("Expected endSequence token, got \(String(describing: token))")
    return
  }
}

private func expectBeginMapping(
  _ token: YAMLRawToken?,
  style expectedStyle: YAMLCollectionStyle = .block
) throws {
  guard case .beginMapping(let style) = token, style.matches(expectedStyle) else {
    Issue.record("Expected beginMapping token, got \(String(describing: token))")
    return
  }
}

private func expectEndMapping(_ token: YAMLRawToken?) throws {
  guard case .endMapping = token else {
    Issue.record("Expected endMapping token, got \(String(describing: token))")
    return
  }
}

private func expectTag(_ token: YAMLRawToken?, _ expected: String) throws {
  guard case .tag(let tag) = token else {
    Issue.record("Expected tag token, got \(String(describing: token))")
    return
  }
  #expect(tag == expected)
}

private func expectAnchor(_ token: YAMLRawToken?, _ expected: String) throws {
  guard case .anchor(let anchor) = token else {
    Issue.record("Expected anchor token, got \(String(describing: token))")
    return
  }
  #expect(anchor == expected)
}

private func expectAlias(_ token: YAMLRawToken?, _ expected: String) throws {
  guard case .alias(let alias) = token else {
    Issue.record("Expected alias token, got \(String(describing: token))")
    return
  }
  #expect(alias == expected)
}

private extension YAMLScalarStyle {
  var isPlain: Bool {
    if case .plain = self { return true }
    return false
  }

  var isSingleQuoted: Bool {
    if case .singleQuoted = self { return true }
    return false
  }

  var isDoubleQuoted: Bool {
    if case .doubleQuoted = self { return true }
    return false
  }

  var isLiteral: Bool {
    if case .literal = self { return true }
    return false
  }

  var isFolded: Bool {
    if case .folded = self { return true }
    return false
  }

  var chomp: YAMLScalarChomp? {
    switch self {
    case .literal(let chomp, _), .folded(let chomp, _):
      return chomp
    default:
      return nil
    }
  }

  var indent: Int? {
    switch self {
    case .literal(_, let indent), .folded(_, let indent):
      return indent
    default:
      return nil
    }
  }
}

private extension YAMLCollectionStyle {
  func matches(_ other: YAMLCollectionStyle) -> Bool {
    switch (self, other) {
    case (.block, .block), (.flow, .flow):
      return true
    default:
      return false
    }
  }
}
