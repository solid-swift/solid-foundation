//
//  YAMLTestSuite.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 5/12/25.
//

@testable import SolidData
@testable import SolidJSON
@testable import SolidYAML
import Foundation
import Testing


@Suite("YAML Test Suite")
struct YAMLTestSuite {

  struct Case: Sendable {
    let id: String
    let directory: URL
    let shouldFail: Bool
  }

  private static let suiteDirectory: URL = {
    // Resolve relative to this source file so it works on Linux and simulators.
    let fileURL = URL(fileURLWithPath: #filePath)
    return fileURL
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/yaml-test-suite", isDirectory: true)
  }()

  private static let cases: [Case] = {
    let root = suiteDirectory
    var results: [Case] = []
    let fm = FileManager.default
    if let enumerator = fm.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      for case let url as URL in enumerator {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
          continue
        }
        let yamlPath = url.appendingPathComponent("in.yaml")
        guard fm.fileExists(atPath: yamlPath.path) else { continue }
        let id = url.path.replacingOccurrences(of: root.path + "/", with: "")
        let shouldFail = fm.fileExists(atPath: url.appendingPathComponent("error").path)
        results.append(.init(id: id, directory: url, shouldFail: shouldFail))
      }
    }
    return results.sorted { $0.id < $1.id }
  }()

  @Test("Suite availability")
  func suiteAvailability() {
    #expect(!Self.cases.isEmpty, "No YAML test suite cases discovered")
  }

  @Test("Parse against json expectations")
  func parse() throws {
    let allow = Set(["229Q"])
    let passingCases = Self.cases.filter { !$0.shouldFail }
    #expect(!passingCases.isEmpty, "No allowed YAML test cases discovered")

    for testCase in passingCases {
      let yamlURL = testCase.directory.appendingPathComponent("in.yaml")
      let jsonURL = testCase.directory.appendingPathComponent("in.json")
      let yamlData = try Data(contentsOf: yamlURL)
      let jsonData = try Data(contentsOf: jsonURL)

      let value = try YAMLValueReader(data: yamlData).read()
      let expected = try JSONValueReader(data: jsonData).read()
      #expect(Self.stripTags(from: value) == expected, "\(testCase.id): value mismatch")
    }
  }

  private static func stripTags(from value: Value) -> Value {
    switch value {
    case .tagged(_, let inner):
      return stripTags(from: inner)
    case .array(let array):
      return .array(array.map { stripTags(from: $0) })
    case .object(let object):
      var stripped = Value.Object()
      stripped.reserveCapacity(object.count)
      for (key, val) in object {
        stripped[stripTags(from: key)] = stripTags(from: val)
      }
      return .object(stripped)
    default:
      return value
    }
  }
}
