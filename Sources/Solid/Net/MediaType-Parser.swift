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
    let parts = splitOutsideQuotes(source, separator: ";")
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

      let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        name != "q",
        MediaType.isToken(name),
        let parsedValue = MediaType.parseParameterValue(value)
      else {
        throw MediaType.Error.invalid(source)
      }
      parameters[name] = parsedValue
    }

    return MediaType(
      type: type,
      tree: subtypeComponents.tree,
      subtype: subtypeComponents.subtype,
      suffix: subtypeComponents.suffix,
      parameters: parameters
    )
  }

  private func parseSubtype(_ source: String) throws -> (tree: MediaType.Tree, subtype: String, suffix: String?) {
    let suffixParts = source.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    guard suffixParts.count <= 2 else {
      throw MediaType.Error.invalid(self.source)
    }

    let fullSubtype = String(suffixParts[0])
    let suffix = suffixParts.count == 2 ? String(suffixParts[1]) : nil
    guard !fullSubtype.isEmpty, suffix.map({ !$0.isEmpty && MediaType.isToken($0) }) ?? true else {
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
    else {
      tree = .standard
      subtype = fullSubtype
    }

    guard !subtype.isEmpty, subtype == "*" || MediaType.isToken(subtype) else {
      throw MediaType.Error.invalid(self.source)
    }
    return (tree, subtype, suffix)
  }

  private func splitOutsideQuotes(_ value: String, separator: Character) -> [String] {
    var parts: [String] = []
    var current = ""
    var isQuoted = false
    var isEscaped = false

    for character in value {
      if character == separator, !isQuoted {
        parts.append(current)
        current = ""
      }
      else {
        current.append(character)
        if character == "\"" && !isEscaped {
          isQuoted.toggle()
        }
        isEscaped = character == "\\" && !isEscaped
      }
    }

    parts.append(current)
    return parts
  }

}
