//
//  MediaTypeTokens.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/30/26.
//

package enum MediaTypeTokens {

  package static func parseParameterValue(_ value: String) -> String? {
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
      return isToken(value) ? value : nil
    }

    var result = ""
    var isEscaped = false
    for character in value.dropFirst().dropLast() {
      if isEscaped {
        result.append(character)
        isEscaped = false
      }
      else if character == "\\" {
        isEscaped = true
      }
      else if character == "\"" {
        return nil
      }
      else {
        result.append(character)
      }
    }
    return isEscaped ? nil : result
  }

  package static func serializeParameterValue(_ value: String) -> String {
    guard !isToken(value) else {
      return value
    }

    var result = "\""
    for character in value {
      if character == "\\" || character == "\"" {
        result.append("\\")
      }
      result.append(character)
    }
    result.append("\"")
    return result
  }

  package static func isToken(_ value: String) -> Bool {
    guard !value.isEmpty else {
      return false
    }
    return value.utf8.allSatisfy(isTokenByte)
  }

  private static func isTokenByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A:
      true
    case 0x21, 0x23 ... 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E:
      true
    default:
      false
    }
  }
}
