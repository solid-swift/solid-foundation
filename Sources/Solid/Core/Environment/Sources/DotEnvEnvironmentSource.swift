//
//  DotEnvSource.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 7/29/25.
//

import Foundation


public struct DotEnvEnvironmentSource: ProcessEnvironmentSource {

  public static let log = LogFactory.for(type: Self.self, level: .warning, privacy: .private)

  public enum Error: Swift.Error {
    case malformedKeyPair(file: URL, line: Int)
  }

  public let priority: Int
  public let entries: [String: String]

  public init(from url: URL = URL(fileURLWithPath: ".env"), delimiter: String = "=", priority: Int) {
    do {
      self.priority = priority
      self.entries = try Self.load(from: url, delimiter: delimiter)
    } catch {
      Self.log.info("Failed to load dotenv file: \(error)")
      self.entries = [:]
    }
  }

  public func value(forNames names: [String]) -> String? {
    for name in names {
      if let value = entries[name] {
        return value
      }
    }
    return nil
  }

  /// Loads the environment values from the environment file.
  /// - Parameters:
  ///   - url: URL for the environment file, defaults to `.env`.
  ///   - delimiter: Name/Value delimiter, defaults to `=`.
  /// - Returns: All environment values discovered in the fule at `url`.
  /// - Throws: Error if the data cannot be loaded or an invalid format is encountered.
  public static func load(from url: URL, delimiter: String) throws -> [String: String] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let lines = contents.split(separator: "\n")
    // we loop over all the entries in the file which are already separated by a newline
    var entries: [String: String] = [:]
    for (lineIdx, line) in lines.enumerated() {
      // ignore comments
      if line.starts(with: "#") {
        continue
      }
      // split by the delimiter
      let substrings = line.split(separator: delimiter)

      // make sure we can grab two and only two string values
      guard
        let key = substrings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
        let value = substrings.last?.trimmingCharacters(in: .whitespacesAndNewlines),
        substrings.count == 2,
        !key.isEmpty,
        !value.isEmpty
      else {
        throw Error.malformedKeyPair(file: url, line: lineIdx)
      }
      entries[key] = value
    }
    return entries
  }


}
