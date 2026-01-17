import ArgumentParser
import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif


@main
struct TestReport: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "test-report",
    abstract: "Generate reports for tests and code coverage"
  )

  @Option(name: .long, help: "Output directory for reports")
  var output: String = "."

  @Option(name: .long, help: "Path to coverage JSON file (llvm-cov export format)")
  var coveragePath: String?

  @Option(name: .long, help: "Path to xUnit XML test results file (xunit mode)")
  var xunitPath: String?

  @Flag(name: .long, help: "Generate test summary report")
  var testSummary: Bool = false

  @Flag(name: .long, help: "Generate detailed test report")
  var testDetail: Bool = false

  @Flag(name: .long, help: "Generate code coverage summary report")
  var coverageSummary: Bool = false

  @Flag(name: .long, help: "Generate detailed code coverage report")
  var coverageDetail: Bool = false

  @Flag(name: .long, help: "Generate all reports")
  var all: Bool = false

  @Flag(name: .long, help: "Don't add headers and/or footers to generated reports")
  var mergeable: Bool = false

  func run() async throws {
    let outputURL = URL(fileURLWithPath: output)

    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let testResults: [TestResult]
    if let xunitPath {

      print("Parsing (xUnit) test results from '\(xunitPath)'")

      testResults = try parseXUnitXML(at: xunitPath)

    } else {
      testResults = []
    }

    let coverageData: CoverageData?
    if let coveragePath {

      print("Parsing (JSON) code coverage from '\(coveragePath)'")

      let jsonURL = URL(fileURLWithPath: coveragePath)
      let jsonData = try Data(contentsOf: jsonURL)
      let llvmCoverage = try JSONDecoder().decode(LLVMCoverageExport.self, from: jsonData)

      coverageData = parseLLVMCoverage(llvmCoverage)

    } else {
      coverageData = nil
    }

    print("Generating reports in '\(output)'")

    if testSummary || all {
      print("  Generating\(mergeable ? " (mergeable)" : "") test summary report")
      let testSummaryReport = generateTestSummary(results: testResults, mergeable: mergeable)
      let testSummaryReportURL = outputURL.appendingPathComponent("test-summary.md")
      try testSummaryReport.write(to: testSummaryReportURL, atomically: true, encoding: .utf8)
    }

    if testDetail || all  {
      print("  Generating\(mergeable ? " (mergeable)" : "") test detail report")
      let testDetailReport = generateTestDetail(results: testResults, mergeable: mergeable)
      let testDetailReportURL = outputURL.appendingPathComponent("test-detail.md")
      try testDetailReport.write(to: testDetailReportURL, atomically: true, encoding: .utf8)
    }

    if let coverage = coverageData {

      if coverageSummary || all  {
        print("  Generating\(mergeable ? " (mergeable)" : "") code coverage summary report")
        let coverageSummaryReport = generateCoverageSummary(coverage: coverage, mergeable: mergeable)
        let coverageSummaryReportURL = outputURL.appendingPathComponent("coverage-summary.md")
        try coverageSummaryReport.write(to: coverageSummaryReportURL, atomically: true, encoding: .utf8)
      }

      if coverageDetail || all  {
        print("  Generating\(mergeable ? " (mergeable)" : "") code coverage detail report")
        let coverageDetailReport = generateCoverageDetail(coverage: coverage, mergeable: mergeable)
        let coverageDetailReportURL = outputURL.appendingPathComponent("coverage-detail.md")
        try coverageDetailReport.write(to: coverageDetailReportURL, atomically: true, encoding: .utf8)
      }
    }

    let jsonResults = TestResultsJSON(
      results: testResults,
      coverage: coverageData
    )
    let jsonData = try JSONEncoder().encode(jsonResults)
    let jsonURL = outputURL.appendingPathComponent("results.json")
    try jsonData.write(to: jsonURL)
  }

  func parseXUnitXML(at path: String) throws -> [TestResult] {
    let url = URL(fileURLWithPath: path)
    let data = fixXMLSyntax(of: try Data(contentsOf: url))
    let parser = XUnitParser(data: data)
    return try parser.parse()
  }

  func fixXMLSyntax(of data: Data) -> Data {
    guard let string = String(data: data, encoding: .utf8) else {
      return data
    }
    let fixed = string.replacingOccurrences(of: #"(\W)&(\W)"#, with: "$1&amp;$2", options: .regularExpression)
    return Data(fixed.utf8)
  }

  func parseLLVMCoverage(_ export: LLVMCoverageExport) -> CoverageData {
    var moduleCoverages: [ModuleCoverage] = []
    var totalCovered = 0
    var totalLines = 0

    for data in export.data {
      for file in data.files {
        if isExternalDependency(file.filename) {
          continue
        }

        let moduleName = extractModuleName(from: file.filename)
        let covered = file.summary.lines.covered
        let total = file.summary.lines.count

        if let index = moduleCoverages.firstIndex(where: { $0.name == moduleName }) {
          moduleCoverages[index].linesCovered += covered
          moduleCoverages[index].linesTotal += total
        } else {
          moduleCoverages.append(
            ModuleCoverage(name: moduleName, linesCovered: covered, linesTotal: total, files: [])
          )
        }

        totalCovered += covered
        totalLines += total
      }
    }

    let totalCoverage = totalLines > 0 ? Double(totalCovered) / Double(totalLines) : 0.0

    return CoverageData(totalCoverage: totalCoverage, modules: moduleCoverages)
  }

  func isExternalDependency(_ filename: String) -> Bool {
    let externalPaths = [
      ".build/checkouts/",
      "SourcePackages/checkouts/",
      "/usr/",
      "/Library/",
    ]
    return externalPaths.contains { filename.contains($0) }
  }

  func parseSwiftTestOutput(_ output: String) -> [TestResult] {
    var results: [TestResult] = []
    let lines = output.components(separatedBy: .newlines)

    // Regex patterns for swift test output
    // Swift Testing format: "✔ Test "name" passed after X.XXX seconds."
    // Swift Testing format: "✘ Test "name" failed after X.XXX seconds."
    // XCTest format: "Test Case '-[Module.Suite testName]' passed (X.XXX seconds)."
    // XCTest format: "Test Case '-[Module.Suite testName]' failed (X.XXX seconds)."

    let swiftTestingPattern =
      #"^[✔✘◇] (?:Test|Suite) ["\"]?(.+?)["\"]? (passed|failed|skipped) after ([\d.]+) seconds"#
    let xcTestPattern =
      #"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (passed|failed) \(([\d.]+) seconds\)"#

    let swiftTestingRegex = try? NSRegularExpression(pattern: swiftTestingPattern, options: [])
    let xcTestRegex = try? NSRegularExpression(pattern: xcTestPattern, options: [])

    var currentSuite = "Unknown"

    for line in lines {
      let range = NSRange(line.startIndex..., in: line)

      // Try Swift Testing format
      if let match = swiftTestingRegex?.firstMatch(in: line, options: [], range: range) {
        if let nameRange = Range(match.range(at: 1), in: line),
          let statusRange = Range(match.range(at: 2), in: line),
          let durationRange = Range(match.range(at: 3), in: line)
        {
          let name = String(line[nameRange])
          let statusStr = String(line[statusRange])
          let duration = Double(line[durationRange]) ?? 0.0

          // Check if this is a Suite line (skip it but track the suite name)
          if line.contains("Suite ") {
            currentSuite = name
            continue
          }

          let status: TestStatus =
            switch statusStr {
            case "passed": .success
            case "failed": .failure
            case "skipped": .skipped
            default: .unknown
            }

          results.append(
            TestResult(
              module: "SolidFoundation",
              suite: currentSuite,
              name: name,
              status: status,
              duration: duration,
              message: nil
            )
          )
        }
      }

      // Try XCTest format
      if let match = xcTestRegex?.firstMatch(in: line, options: [], range: range) {
        if let moduleRange = Range(match.range(at: 1), in: line),
          let suiteRange = Range(match.range(at: 2), in: line),
          let nameRange = Range(match.range(at: 3), in: line),
          let statusRange = Range(match.range(at: 4), in: line),
          let durationRange = Range(match.range(at: 5), in: line)
        {
          let module = String(line[moduleRange])
          let suite = String(line[suiteRange])
          let name = String(line[nameRange])
          let statusStr = String(line[statusRange])
          let duration = Double(line[durationRange]) ?? 0.0

          let status: TestStatus = statusStr == "passed" ? .success : .failure

          results.append(
            TestResult(
              module: module,
              suite: suite,
              name: name,
              status: status,
              duration: duration,
              message: nil
            )
          )
        }
      }
    }

    return results
  }

  func extractModuleName(from filename: String) -> String {
    let components = filename.components(separatedBy: "/")

    if let sourcesIndex = components.firstIndex(of: "Sources"),
      sourcesIndex + 1 < components.count
    {
      let nextComponent = components[sourcesIndex + 1]
      if nextComponent == "Solid", sourcesIndex + 2 < components.count {
        return "Solid" + components[sourcesIndex + 2]
      }
      return nextComponent
    }

    if let solidIndex = components.firstIndex(of: "Solid"), solidIndex + 1 < components.count {
      return "Solid" + components[solidIndex + 1]
    }

    if let testsIndex = components.firstIndex(of: "Tests"), testsIndex + 1 < components.count {
      return components[testsIndex + 1]
    }

    return "Unknown"
  }

  func generateTestSummary(results: [TestResult], mergeable: Bool) -> String {
    let passed = results.filter { $0.status == .success }.count
    let failed = results.filter { $0.status == .failure }.count
    let skipped = results.filter { $0.status == .skipped }.count
    let total = results.count

    var report = ""

    if mergeable {
      report += "## Test Summary\n\n"
    }

    if failed > 0 {
      report += "| Status | Count |\n"
      report += "|--------|-------|\n"
      report += "| ✅ | \(passed) |\n"
      report += "| ⚠️ | \(failed) |\n"
      report += "| ➡️ | \(skipped) |\n"
      report += "| **Total** | **\(total)** |\n"
    } else {
      report += "| ✅ | ⚠️ | ➡️ | Total |\n"
      report += "|--------|--------|---------|-------|\n"
      report += "| \(passed) | \(failed) | \(skipped) | \(total) |\n"
    }

    return report
  }

  func generateTestDetail(results: [TestResult], mergeable: Bool) -> String {
    var report = ""

    if mergeable {
      report += "## Test Results\n\n"
    }

    let groupedByModule = Dictionary(grouping: results) { $0.module }

    for (module, moduleResults) in groupedByModule.sorted(by: { $0.key < $1.key }) {
      report += "### \(module)\n\n"

      let groupedBySuite = Dictionary(grouping: moduleResults) { $0.suite }

      for (suite, suiteResults) in groupedBySuite.sorted(by: { $0.key < $1.key }) {
        report += "#### \(suite)\n\n"
        report += "| Test | Status | Duration |\n"
        report += "|------|--------|----------|\n"

        for result in suiteResults.sorted(by: { $0.name < $1.name }) {
          let statusIcon = result.status.icon
          let duration = String(format: "%.3fs", result.duration)
          report += "| \(result.name) | \(statusIcon) | \(duration) |\n"
        }

        report += "\n"
      }
    }

    return report
  }

  func generateCoverageSummary(coverage: CoverageData, mergeable: Bool) -> String {

    var report = ""

    if mergeable {
      report += "## Code Coverage Summary\n\n"
    }

    let totalPercent = String(format: "%.1f%%", coverage.totalCoverage * 100)
    report += "**Total Coverage: \(totalPercent)**\n\n"

    report += "| Module | Coverage | Lines |\n"
    report += "|--------|----------|-------|\n"

    for module in coverage.modules.sorted(by: { $0.name < $1.name }) {
      let percent =
        module.linesTotal > 0
        ? String(format: "%.1f%%", Double(module.linesCovered) / Double(module.linesTotal) * 100)
        : "N/A"
      report += "| \(module.name) | \(percent) | \(module.linesCovered)/\(module.linesTotal) |\n"
    }

    return report
  }

  func generateCoverageDetail(coverage: CoverageData, mergeable: Bool) -> String {

    var report = ""

    if mergeable {
      report += "## Code Coverage Report\n\n"
    }

    let totalPercent = String(format: "%.1f%%", coverage.totalCoverage * 100)
    report += "**Total Coverage: \(totalPercent)**\n\n"

    report += "| Module | File | Coverage | Lines |\n"
    report += "|--------|----------|-------|-------|\n"

    for module in coverage.modules.sorted(by: { $0.name < $1.name }) {
      let percent =
      module.linesTotal > 0
      ? String(format: "%.1f%%", Double(module.linesCovered) / Double(module.linesTotal) * 100)
      : "N/A"
      report += "| \(module.name) | | \(percent) | \(module.linesCovered)/\(module.linesTotal) |\n"
    }

    return report
  }

}

enum TestStatus: String, Codable {
  case success
  case failure
  case skipped
  case expectedFailure
  case mixed
  case unknown

  var icon: String {
    switch self {
    case .success: return "✅"
    case .failure: return "⚠️"
    case .skipped: return "➡️"
    case .expectedFailure: return "☑️"
    case .mixed: return "✅⚠️"
    case .unknown: return "❔"
    }
  }
}

struct TestResult: Codable {
  let module: String
  let suite: String
  let name: String
  let status: TestStatus
  let duration: Double
  let message: String?
}

struct FileCoverage: Codable {
  let name: String
  var linesCovered: Int
  var linesTotal: Int
}

struct ModuleCoverage: Codable {
  let name: String
  var linesCovered: Int
  var linesTotal: Int
  var files: [FileCoverage]
}

struct CoverageData: Codable {
  let totalCoverage: Double
  let modules: [ModuleCoverage]
}

struct TestResultsJSON: Codable {
  let results: [TestResult]
  let coverage: CoverageData?
}

struct LLVMCoverageExport: Codable {
  let data: [LLVMCoverageData]
  let type: String
  let version: String
}

struct LLVMCoverageData: Codable {
  let files: [LLVMCoverageFile]
}

struct LLVMCoverageFile: Codable {
  let filename: String
  let summary: LLVMCoverageSummary
}

struct LLVMCoverageSummary: Codable {
  let lines: LLVMCoverageLines
}

struct LLVMCoverageLines: Codable {
  let count: Int
  let covered: Int
  let percent: Double
}

class XUnitParser: NSObject, XMLParserDelegate {
  private let data: Data
  private var results: [TestResult] = []
  private var currentTestSuite: String = ""
  private var currentTestCase: (name: String, classname: String, time: Double)?
  private var currentFailureMessage: String?
  private var isInFailure = false
  private var failureText = ""
  private var parseError: Error?

  init(data: Data) {
    self.data = data
  }

  func parse() throws -> [TestResult] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    _ = parser.parse()

    if let error = parseError {
      throw error
    }

    return results
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch elementName {
    case "testsuite":
      currentTestSuite = attributeDict["name"] ?? "Unknown"

    case "testcase":
      let name = attributeDict["name"] ?? "Unknown"
      let classname = attributeDict["classname"] ?? currentTestSuite
      let time = Double(attributeDict["time"] ?? "0") ?? 0.0
      currentTestCase = (name: name, classname: classname, time: time)
      currentFailureMessage = nil

    case "failure", "error":
      isInFailure = true
      failureText = ""
      if let message = attributeDict["message"] {
        failureText = message
      }

    case "skipped":
      guard let testCase = currentTestCase else { return }
      let (module, suite) = extractModuleAndSuite(from: testCase.classname)
      results.append(
        TestResult(
          module: module,
          suite: suite,
          name: testCase.name,
          status: .skipped,
          duration: testCase.time,
          message: nil
        )
      )
      currentTestCase = nil

    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if isInFailure {
      failureText += string
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch elementName {
    case "testcase":
      if let testCase = currentTestCase {
        let (module, suite) = extractModuleAndSuite(from: testCase.classname)
        let status: TestStatus = currentFailureMessage != nil ? .failure : .success
        results.append(
          TestResult(
            module: module,
            suite: suite,
            name: testCase.name,
            status: status,
            duration: testCase.time,
            message: currentFailureMessage
          )
        )
        currentTestCase = nil
        currentFailureMessage = nil
      }
    case "failure", "error":
      isInFailure = false
      currentFailureMessage = failureText.trimmingCharacters(in: .whitespacesAndNewlines)
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
    print("\(currentTestSuite.nilToEmpty ?? "<unknown>").\(currentTestCase?.name.nilToEmpty ?? "<unknown>")")
    self.parseError = parseError
  }

  private func extractModuleAndSuite(from classname: String) -> (module: String, suite: String) {
    let components = classname.components(separatedBy: ".")
    if components.count >= 2 {
      return (module: components[0], suite: components.dropFirst().joined(separator: "."))
    }
    return (module: "Unknown", suite: classname)
  }
}

extension String {

  var nilToEmpty: String? { return isEmpty ? nil : self }

}
