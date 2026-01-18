import ArgumentParser
import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif


@main
struct TestReport: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "test-report",
    abstract: "Generate and merge test reports for CI",
    subcommands: [Generate.self, Merge.self],
    defaultSubcommand: Generate.self
  )

}

struct Generate: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "generate",
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

  @Flag(name: .long, help: "Generate reports suitable for later merging (no standalone headers)")
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
      let testSummaryReport = ReportGenerator.generateTestSummary(results: testResults, mergeable: mergeable)
      let testSummaryReportURL = outputURL.appendingPathComponent("test-summary.md")
      try testSummaryReport.write(to: testSummaryReportURL, atomically: true, encoding: .utf8)
    }

    if testDetail || all {
      print("  Generating\(mergeable ? " (mergeable)" : "") test detail report")
      let testDetailReport = ReportGenerator.generateTestDetail(results: testResults, mergeable: mergeable)
      let testDetailReportURL = outputURL.appendingPathComponent("test-detail.md")
      try testDetailReport.write(to: testDetailReportURL, atomically: true, encoding: .utf8)
    }

    if let coverage = coverageData {

      if coverageSummary || all {
        print("  Generating\(mergeable ? " (mergeable)" : "") code coverage summary report")
        let coverageSummaryReport = ReportGenerator.generateCoverageSummary(coverage: coverage, mergeable: mergeable)
        let coverageSummaryReportURL = outputURL.appendingPathComponent("coverage-summary.md")
        try coverageSummaryReport.write(to: coverageSummaryReportURL, atomically: true, encoding: .utf8)
      }

      if coverageDetail || all {
        print("  Generating\(mergeable ? " (mergeable)" : "") code coverage detail report")
        let coverageDetailReport = ReportGenerator.generateCoverageDetail(coverage: coverage, mergeable: mergeable)
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

}


struct Merge: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "merge",
    abstract: "Merge reports from multiple platforms into combined PR comment and GitHub Actions summary"
  )

  @Option(name: .long, help: "Output directory for merged reports")
  var output: String = "."

  @Argument(help: "Paths to platform report directories (e.g., test-reports-macos test-reports-linux)")
  var reportDirs: [String]

  func run() async throws {
    let outputURL = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    print("Merging reports from: \(reportDirs.joined(separator: ", "))")

    var platformResults: [(name: String, results: TestResultsJSON)] = []

    for dir in reportDirs {
      let dirURL = URL(fileURLWithPath: dir)
      let resultsURL = dirURL.appendingPathComponent("results.json")

      let platformName = extractPlatformName(from: dir)

      if FileManager.default.fileExists(atPath: resultsURL.path) {
        let data = try Data(contentsOf: resultsURL)
        let results = try JSONDecoder().decode(TestResultsJSON.self, from: data)
        platformResults.append((name: platformName, results: results))
        print("  Loaded results for \(platformName)")
      } else {
        print("  Warning: No results.json found in \(dir)")
      }
    }

    let prComment = generatePRComment(platformResults: platformResults)
    let prCommentURL = outputURL.appendingPathComponent("pr-comment.md")
    try prComment.write(to: prCommentURL, atomically: true, encoding: .utf8)
    print("  Generated PR comment: pr-comment.md")

    let actionsSummary = generateActionsSummary(platformResults: platformResults)
    let actionsSummaryURL = outputURL.appendingPathComponent("actions-summary.md")
    try actionsSummary.write(to: actionsSummaryURL, atomically: true, encoding: .utf8)
    print("  Generated Actions summary: actions-summary.md")
  }

  func extractPlatformName(from path: String) -> String {
    let components = path.components(separatedBy: "/")
    let dirName = components.last ?? path

    if dirName.contains("macos") || dirName.contains("macOS") {
      return "macOS"
    } else if dirName.contains("linux") || dirName.contains("Linux") {
      return "Linux"
    } else if dirName.contains("windows") || dirName.contains("Windows") {
      return "Windows"
    }

    return dirName.replacingOccurrences(of: "test-reports-", with: "").capitalized
  }

  func generatePRComment(platformResults: [(name: String, results: TestResultsJSON)]) -> String {
    var report = "## Test Results\n\n"

    let allPassed = platformResults.allSatisfy { platform in
      platform.results.results.allSatisfy { $0.status == .success || $0.status == .skipped }
    }

    if allPassed {
      report += "All tests passed across all platforms.\n\n"
    }

    report += "| Platform | Passed | Failed | Skipped |\n"
    report += "|----------|-------:|-------:|--------:|\n"

    for (name, results) in platformResults {
      let passed = results.results.filter { $0.status == .success }.count
      let failed = results.results.filter { $0.status == .failure }.count
      let skipped = results.results.filter { $0.status == .skipped }.count

      let statusIcon = failed > 0 ? "🔴" : "🟢"
      report += "| \(statusIcon) \(name) | \(passed) | \(failed) | \(skipped) |\n"
    }

    let failedTests = platformResults.flatMap { platform in
      platform.results.results.filter { $0.status == .failure }.map { (platform.name, $0) }
    }

    if !failedTests.isEmpty {
      report += "\n### Failed Tests\n\n"
      for (platform, test) in failedTests {
        report += "- **\(platform)**: `\(test.module).\(test.suite).\(test.name)`\n"
      }
    }

    if let macOSResults = platformResults.first(where: { $0.name == "macOS" }),
      let coverage = macOSResults.results.coverage
    {
      report += "\n---\n\n"
      report += "### Coverage\n\n"
      let totalPercent = String(format: "%.1f%%", coverage.totalCoverage * 100)
      report += "**\(totalPercent)** overall line coverage\n\n"
      report += "_See the [CI workflow run](../../actions) for detailed coverage by module._\n"
    }

    return report
  }

  func generateActionsSummary(platformResults: [(name: String, results: TestResultsJSON)]) -> String {
    var report = "## Test Results\n\n"

    for (index, (platformName, results)) in platformResults.enumerated() {
      let passed = results.results.filter { $0.status == .success }.count
      let failed = results.results.filter { $0.status == .failure }.count
      let skipped = results.results.filter { $0.status == .skipped }.count
      let total = results.results.count

      if index > 0 {
        report += "---\n\n"
      }

      let platformIcon = failed > 0 ? "🔴" : "🟢"
      report += "### \(platformIcon) \(platformName)\n\n"

      report += "| 🟢 Passed | 🔴 Failed | ⏭️ Skipped | Total |\n"
      report += "|----------:|----------:|-----------:|------:|\n"
      report += "| \(passed) | \(failed) | \(skipped) | \(total) |\n\n"

      let failedTests = results.results.filter { $0.status == .failure }
      if !failedTests.isEmpty {
        report += "#### Failed Tests\n\n"
        for test in failedTests {
          report += "- `\(test.module).\(test.suite).\(test.name)`\n"
          if let message = test.message, !message.isEmpty {
            let truncatedMessage =
              message.count > 200 ? String(message.prefix(200)) + "..." : message
            let escapedMessage =
              truncatedMessage
              .replacingOccurrences(of: "\n", with: " ")
              .replacingOccurrences(of: "|", with: "\\|")
            report += "  > \(escapedMessage)\n"
          }
        }
        report += "\n"
      }

      let groupedByModule = Dictionary(grouping: results.results) { $0.module }

      for (module, moduleResults) in groupedByModule.sorted(by: { $0.key < $1.key }) {
        let modulePassed = moduleResults.filter { $0.status == .success }.count
        let moduleFailed = moduleResults.filter { $0.status == .failure }.count
        let moduleSkipped = moduleResults.filter { $0.status == .skipped }.count
        let moduleTotal = moduleResults.count

        let moduleIcon = moduleFailed > 0 ? "🔴" : "🟢"

        report += "#### \(moduleIcon) \(module)\n\n"
        report += "**\(modulePassed)** passed"
        if moduleFailed > 0 {
          report += " · **\(moduleFailed)** failed"
        }
        if moduleSkipped > 0 {
          report += " · **\(moduleSkipped)** skipped"
        }
        report += " · **\(moduleTotal)** total\n\n"

        let moduleFailedTests = moduleResults.filter { $0.status == .failure }
        if !moduleFailedTests.isEmpty {
          report += "**Failed:**\n"
          for test in moduleFailedTests {
            report += "- `\(test.suite).\(test.name)`\n"
          }
          report += "\n"
        }

        report += "<details>\n"
        report += "<summary>View all tests</summary>\n\n"

        let groupedBySuite = Dictionary(grouping: moduleResults) { $0.suite }

        for (suite, suiteResults) in groupedBySuite.sorted(by: { $0.key < $1.key }) {
          report += "**\(suite)**\n\n"
          report += "| Test | Status | Duration |\n"
          report += "|------|:------:|---------:|\n"

          for result in suiteResults.sorted(by: { $0.name < $1.name }) {
            let statusIcon = result.status.icon
            let duration = String(format: "%.3fs", result.duration)
            let testName = result.name.replacingOccurrences(of: "|", with: "\\|")
            report += "| \(testName) | \(statusIcon) | \(duration) |\n"
          }

          report += "\n"
        }

        report += "</details>\n\n"
      }
    }

    if let macOSResults = platformResults.first(where: { $0.name == "macOS" }),
      let coverage = macOSResults.results.coverage
    {
      report += "---\n\n"
      report += "## Coverage\n\n"

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
    }

    return report
  }

}


enum ReportGenerator {

  static func generateTestSummary(results: [TestResult], mergeable: Bool) -> String {
    let passed = results.filter { $0.status == .success }.count
    let failed = results.filter { $0.status == .failure }.count
    let skipped = results.filter { $0.status == .skipped }.count
    let total = results.count

    var report = ""

    if !mergeable {
      report += "# Test Summary\n\n"
    }

    let statusIcon = failed > 0 ? "🔴" : "🟢"
    report += "\(statusIcon) **\(passed)** passed"
    if failed > 0 {
      report += " · **\(failed)** failed"
    }
    if skipped > 0 {
      report += " · **\(skipped)** skipped"
    }
    report += " · **\(total)** total\n\n"

    if failed > 0 {
      report += "### Failed Tests\n\n"
      let failedTests = results.filter { $0.status == .failure }
      for test in failedTests {
        report += "- `\(test.module).\(test.suite).\(test.name)`\n"
      }
      report += "\n"
    }

    return report
  }

  static func generateTestDetail(results: [TestResult], mergeable: Bool) -> String {
    var report = ""

    if !mergeable {
      report += "# Test Results\n\n"
    }

    let passed = results.filter { $0.status == .success }.count
    let failed = results.filter { $0.status == .failure }.count
    let skipped = results.filter { $0.status == .skipped }.count
    let total = results.count

    let overallIcon = failed > 0 ? "🔴" : "🟢"
    report += "\(overallIcon) **\(passed)** passed"
    if failed > 0 {
      report += " · **\(failed)** failed"
    }
    if skipped > 0 {
      report += " · **\(skipped)** skipped"
    }
    report += " · **\(total)** total\n\n"

    let groupedByModule = Dictionary(grouping: results) { $0.module }

    for (module, moduleResults) in groupedByModule.sorted(by: { $0.key < $1.key }) {
      let modulePassed = moduleResults.filter { $0.status == .success }.count
      let moduleFailed = moduleResults.filter { $0.status == .failure }.count
      let moduleSkipped = moduleResults.filter { $0.status == .skipped }.count
      let moduleTotal = moduleResults.count

      let moduleIcon = moduleFailed > 0 ? "🔴" : "🟢"

      report += "### \(moduleIcon) \(module)\n\n"
      report += "**\(modulePassed)** passed"
      if moduleFailed > 0 {
        report += " · **\(moduleFailed)** failed"
      }
      if moduleSkipped > 0 {
        report += " · **\(moduleSkipped)** skipped"
      }
      report += " · **\(moduleTotal)** total\n\n"

      let moduleFailedTests = moduleResults.filter { $0.status == .failure }
      if !moduleFailedTests.isEmpty {
        report += "**Failed:**\n"
        for test in moduleFailedTests {
          report += "- `\(test.suite).\(test.name)`\n"
          if let message = test.message, !message.isEmpty {
            let truncatedMessage =
              message.count > 200 ? String(message.prefix(200)) + "..." : message
            let escapedMessage =
              truncatedMessage
              .replacingOccurrences(of: "\n", with: " ")
              .replacingOccurrences(of: "|", with: "\\|")
            report += "  > \(escapedMessage)\n"
          }
        }
        report += "\n"
      }

      report += "<details>\n"
      report += "<summary>View all tests</summary>\n\n"

      let groupedBySuite = Dictionary(grouping: moduleResults) { $0.suite }

      for (suite, suiteResults) in groupedBySuite.sorted(by: { $0.key < $1.key }) {
        report += "**\(suite)**\n\n"
        report += "| Test | Status | Duration |\n"
        report += "|------|:------:|---------:|\n"

        for result in suiteResults.sorted(by: { $0.name < $1.name }) {
          let statusIcon = result.status.icon
          let duration = String(format: "%.3fs", result.duration)
          let testName = result.name.replacingOccurrences(of: "|", with: "\\|")
          report += "| \(testName) | \(statusIcon) | \(duration) |\n"
        }

        report += "\n"
      }

      report += "</details>\n\n"
    }

    return report
  }

  static func generateCoverageSummary(coverage: CoverageData, mergeable: Bool) -> String {

    var report = ""

    if !mergeable {
      report += "# Code Coverage Summary\n\n"
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

  static func generateCoverageDetail(coverage: CoverageData, mergeable: Bool) -> String {

    var report = ""

    if !mergeable {
      report += "# Code Coverage Report\n\n"
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
    case .success: return "🟢"
    case .failure: return "🔴"
    case .skipped: return "⏭️"
    case .expectedFailure: return "🟡"
    case .mixed: return "🟠"
    case .unknown: return "⚪"
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
