import ArgumentParser
import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

#if canImport(PeekieSDK)
  import PeekieSDK
#endif

@main
struct CIReportTool: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ci-report-tool",
    abstract: "Generate CI reports from test results and coverage data"
  )

  @Option(name: .long, parsing: .upToNextOption, help: "Paths to .xcresult files")
  var xcresult: [String] = []

  @Option(name: .long, help: "Output directory for reports")
  var output: String = "."

  @Option(name: .long, help: "Platform name (e.g., macOS, Linux)")
  var platform: String = "unknown"

  @Option(name: .long, help: "Path to coverage JSON file (llvm-cov export format)")
  var coverageJson: String?

  @Option(name: .long, help: "Path to xUnit XML test results file (xunit mode)")
  var xunit: String?

  @Flag(name: .long, help: "Generate test summary report")
  var testSummary: Bool = false

  @Flag(name: .long, help: "Generate detailed test report")
  var testDetails: Bool = false

  @Flag(name: .long, help: "Generate coverage summary report")
  var coverageSummary: Bool = false

  @Flag(name: .long, help: "Generate failed tests report")
  var failedTestsReport: Bool = false

  func run() async throws {
    let outputURL = URL(fileURLWithPath: output)

    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    var testResults: [TestResult] = []
    var coverageData: CoverageData?

    let generateAll = !testSummary && !testDetails && !coverageSummary && !failedTestsReport

    if let xunitPath = xunit {
      testResults = try parseXUnitXML(at: xunitPath)
    }

    #if canImport(PeekieSDK)
      if testResults.isEmpty {
        for xcresultPath in xcresult {
          let xcresultURL = URL(fileURLWithPath: xcresultPath)
          let report = try await Report(xcresultPath: xcresultURL)

          for module in report.modules {
            for suite in module.suites {
              for repeatableTest in suite.repeatableTests {
                for test in repeatableTest.tests {
                  let durationInSeconds = test.duration.converted(to: .seconds).value
                  let result = TestResult(
                    module: module.name,
                    suite: suite.name,
                    name: repeatableTest.name,
                    status: mapStatus(test.status),
                    duration: durationInSeconds,
                    message: test.message
                  )
                  testResults.append(result)
                }
              }
            }
          }

          if let coverage = report.coverage {
            var moduleCoverages: [ModuleCoverage] = []
            for module in report.modules {
              var totalLines = 0
              var coveredLines = 0
              for file in module.files {
                if let fileCoverage = file.coverage {
                  totalLines += fileCoverage.totalLines
                  coveredLines += fileCoverage.coveredLines
                }
              }
              if totalLines > 0 {
                moduleCoverages.append(
                  ModuleCoverage(
                    name: module.name,
                    linesCovered: coveredLines,
                    linesTotal: totalLines
                  )
                )
              }
            }
            coverageData = CoverageData(
              totalCoverage: coverage,
              modules: moduleCoverages
            )
          }
        }
      }
    #endif

    if let coverageJsonPath = coverageJson {
      let jsonURL = URL(fileURLWithPath: coverageJsonPath)
      let jsonData = try Data(contentsOf: jsonURL)
      let llvmCoverage = try JSONDecoder().decode(LLVMCoverageExport.self, from: jsonData)
      coverageData = parseLLVMCoverage(llvmCoverage)
    }

    if generateAll || testSummary {
      let testReport = generateTestReport(results: testResults, platform: platform)
      let testReportURL = outputURL.appendingPathComponent("test-results-\(platform).md")
      try testReport.write(to: testReportURL, atomically: true, encoding: .utf8)
    }

    if generateAll || testDetails {
      let detailedReport = generateDetailedTestReport(results: testResults, platform: platform)
      let detailedReportURL = outputURL.appendingPathComponent("test-details-\(platform).md")
      try detailedReport.write(to: detailedReportURL, atomically: true, encoding: .utf8)
    }

    if let coverage = coverageData, generateAll || coverageSummary {
      let coverageReport = generateCoverageReport(coverage: coverage)
      let coverageReportURL = outputURL.appendingPathComponent("coverage-\(platform).md")
      try coverageReport.write(to: coverageReportURL, atomically: true, encoding: .utf8)
    }

    let failedTests = testResults.filter { $0.status == .failure }
    if !failedTests.isEmpty && (generateAll || failedTestsReport) {
      let failedReport = generateFailedTestsReport(results: failedTests, platform: platform)
      let failedReportURL = outputURL.appendingPathComponent("failed-tests-\(platform).md")
      try failedReport.write(to: failedReportURL, atomically: true, encoding: .utf8)
    }

    let jsonResults = TestResultsJSON(
      platform: platform,
      results: testResults,
      coverage: coverageData
    )
    let jsonData = try JSONEncoder().encode(jsonResults)
    let jsonURL = outputURL.appendingPathComponent("results-\(platform).json")
    try jsonData.write(to: jsonURL)

    print("Reports generated in \(output)")
  }

  #if canImport(PeekieSDK)
    func mapStatus(_ status: Report.Module.Suite.RepeatableTest.Test.Status) -> TestStatus {
      switch status {
      case .success: return .success
      case .failure: return .failure
      case .skipped: return .skipped
      case .expectedFailure: return .expectedFailure
      case .mixed: return .mixed
      case .unknown: return .unknown
      }
    }
  #endif

  func parseXUnitXML(at path: String) throws -> [TestResult] {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let parser = XUnitParser(data: data)
    return try parser.parse()
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
            ModuleCoverage(name: moduleName, linesCovered: covered, linesTotal: total)
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

  func generateTestReport(results: [TestResult], platform: String) -> String {
    let passed = results.filter { $0.status == .success }.count
    let failed = results.filter { $0.status == .failure }.count
    let skipped = results.filter { $0.status == .skipped }.count
    let total = results.count

    var report = "## Test Results - \(platform)\n\n"

    if failed > 0 {
      report += "| Status | Count |\n"
      report += "|--------|-------|\n"
      report += "| Passed | \(passed) |\n"
      report += "| Failed | \(failed) |\n"
      report += "| Skipped | \(skipped) |\n"
      report += "| **Total** | **\(total)** |\n"
    } else {
      report += "| Passed | Failed | Skipped | Total |\n"
      report += "|--------|--------|---------|-------|\n"
      report += "| \(passed) | \(failed) | \(skipped) | \(total) |\n"
    }

    return report
  }

  func generateDetailedTestReport(results: [TestResult], platform: String) -> String {
    var report = "## Detailed Test Results - \(platform)\n\n"

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

  func generateCoverageReport(coverage: CoverageData) -> String {
    var report = "## Code Coverage Overview\n\n"

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

  func generateFailedTestsReport(results: [TestResult], platform: String) -> String {
    var report = "## Failed Tests - \(platform)\n\n"

    for result in results {
      report += "### \(result.module) / \(result.suite) / \(result.name)\n\n"
      if let message = result.message {
        report += "```\n\(message)\n```\n\n"
      }
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
    case .success: return "Passed"
    case .failure: return "Failed"
    case .skipped: return "Skipped"
    case .expectedFailure: return "Expected Failure"
    case .mixed: return "Mixed"
    case .unknown: return "Unknown"
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

struct ModuleCoverage: Codable {
  let name: String
  var linesCovered: Int
  var linesTotal: Int
}

struct CoverageData: Codable {
  let totalCoverage: Double
  let modules: [ModuleCoverage]
}

struct TestResultsJSON: Codable {
  let platform: String
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
      if let testCase = currentTestCase {
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
      }
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
