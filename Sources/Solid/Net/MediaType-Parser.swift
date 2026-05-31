//
//  MediaType-Parser.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/28/26.
//

struct MediaTypeParser {

  private let source: String

  init(_ source: String) {
    self.source = source
  }

  func parse() throws -> MediaType {
    let parts = MediaTypeTokens.splitOutsideQuotes(source, separator: ";")
    guard let name = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      throw MediaType.Error.invalid(source)
    }

    let slashParts = name.split(separator: "/", omittingEmptySubsequences: false)
    guard slashParts.count == 2 else {
      throw MediaType.Error.invalid(source)
    }

    let typeName = slashParts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let subtypeName = slashParts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    guard
      let type = MediaType.Kind(rawValue: typeName),
      MediaType.isToken(typeName),
      !subtypeName.isEmpty
    else {
      throw MediaType.Error.invalid(source)
    }

    let subtypeComponents = try parseSubtype(subtypeName)
    var parameters: [String: String] = [:]

    for rawParameter in parts.dropFirst() {
      let parameter = rawParameter.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !parameter.isEmpty else {
        throw MediaType.Error.invalid(source)
      }

      let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard pair.count == 2 else {
        throw MediaType.Error.invalid(source)
      }

      let name = String(pair[0]).lowercased()
      let value = String(pair[1])
      guard
        name != "q",
        MediaType.isToken(name),
        let parsedValue = MediaType.parseParameterValue(value)
      else {
        throw MediaType.Error.invalid(source)
      }
      parameters[name] = parsedValue
    }

    guard type != .any || (subtypeComponents.tree == .standard && subtypeComponents.subtype == "*") else {
      throw MediaType.Error.invalid(source)
    }

    return MediaType(
      type: type,
      tree: subtypeComponents.tree,
      subtype: subtypeComponents.subtype,
      suffix: subtypeComponents.suffix,
      parameters: parameters
    )
  }

  private func parseSubtype(_ source: String) throws -> (tree: MediaType.Tree, subtype: String, suffix: MediaType.Suffix?) {
    let suffixStart = source.lastIndex(of: "+")
    let fullSubtype = suffixStart.map { String(source[..<$0]) } ?? source
    let suffix = try suffixStart.map { index -> MediaType.Suffix in
      let suffix = String(source[source.index(after: index)...])
      guard let parsedSuffix = MediaType.Suffix(rawValue: suffix) else {
        throw MediaType.Error.invalid(self.source)
      }
      return parsedSuffix
    }
    guard !fullSubtype.isEmpty else {
      throw MediaType.Error.invalid(self.source)
    }

    let tree: MediaType.Tree
    let subtype: String
    if fullSubtype == "*" {
      tree = .standard
      subtype = "*"
    }
    else if fullSubtype.hasPrefix(MediaType.Tree.vendor.rawValue) {
      tree = .vendor
      subtype = String(fullSubtype.dropFirst(MediaType.Tree.vendor.rawValue.count))
    }
    else if fullSubtype.hasPrefix(MediaType.Tree.personal.rawValue) {
      tree = .personal
      subtype = String(fullSubtype.dropFirst(MediaType.Tree.personal.rawValue.count))
    }
    else if fullSubtype.hasPrefix(MediaType.Tree.unregistered.rawValue) {
      tree = .unregistered
      subtype = String(fullSubtype.dropFirst(MediaType.Tree.unregistered.rawValue.count))
    }
    else if fullSubtype.hasPrefix(MediaType.Tree.obsolete.rawValue) {
      tree = .obsolete
      subtype = String(fullSubtype.dropFirst(MediaType.Tree.obsolete.rawValue.count))
    }
    else if let firstDot = fullSubtype.firstIndex(of: ".") {
      let treePrefix = String(fullSubtype[...firstDot])
      guard let parsedTree = MediaType.Tree(rawValue: treePrefix) else {
        throw MediaType.Error.invalid(self.source)
      }
      tree = parsedTree
      subtype = String(fullSubtype[fullSubtype.index(after: firstDot)...])
    }
    else {
      tree = .standard
      subtype = fullSubtype
    }

    guard
      !subtype.isEmpty,
      subtype == "*" || MediaType.isToken(subtype),
      tree == .standard || subtype != "*"
    else {
      throw MediaType.Error.invalid(self.source)
    }
    return (tree, subtype, suffix)
  }

}
