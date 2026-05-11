//
//  YAMLScalarAnalysisTests.swift
//  SolidFoundation
//
//  Created by Codex on 5/11/26.
//

import Testing
@testable import SolidYAML


@Suite("YAML Scalar Analysis Tests")
struct YAMLScalarAnalysisTests {

  @Test("Ordinary strings do not resolve through implicit typing")
  func ordinaryStringsDoNotResolveThroughImplicitTyping() {
    let analysis = YAMLScalarAnalysis.analyze(
      "MICROSCOPIC AEROSOL BUBBLES OF LIQUID OXYGEN",
      allowImplicitTyping: false,
      allowDocumentMarkerPrefix: false,
      quoteTrailingColon: true
    )

    #expect(!analysis.resolvesToNonString)
    #expect(!analysis.needsQuotes)
  }

  @Test("Typed-looking strings require quotes when implicit typing is disabled")
  func typedLookingStringsRequireQuotesWhenImplicitTypingIsDisabled() {
    let scalars = ["", "~", "null", "true", "false", "1", "+12", "12.5", "1e9", "0x10", "0b1010"]

    for scalar in scalars {
      let analysis = YAMLScalarAnalysis.analyze(
        scalar,
        allowImplicitTyping: false,
        allowDocumentMarkerPrefix: false,
        quoteTrailingColon: true
      )

      #expect(analysis.needsQuotes, "\(scalar) should require quotes")
    }
  }

  @Test("Trailing colon is quoteable by value context")
  func trailingColonIsQuoteableByValueContext() {
    let valueAnalysis = YAMLScalarAnalysis.analyze(
      "They follow, snapping at his heel:",
      allowImplicitTyping: false,
      allowDocumentMarkerPrefix: false,
      quoteTrailingColon: true
    )
    let keyAnalysis = YAMLScalarAnalysis.analyze(
      "They follow, snapping at his heel:",
      allowImplicitTyping: false,
      allowDocumentMarkerPrefix: false,
      quoteTrailingColon: false
    )

    #expect(valueAnalysis.needsQuotes)
    #expect(!keyAnalysis.needsQuotes)
  }
}
