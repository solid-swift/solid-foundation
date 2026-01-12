import ArgumentParser
import Foundation

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

  func run() async throws {
    let outputURL = URL(fileURLWithPath: output)

    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    var testResults: [TestResult] = []
    var coverageData: CoverageData?

    #if canImport(PeekieSDK)
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
    #endif

    if let coverageJsonPath = coverageJson {
      let jsonURL = URL(fileURLWithPath: coverageJsonPath)
      let jsonData = try Data(contentsOf: jsonURL)
      let llvmCoverage = try JSONDecoder().decode(LLVMCoverageExport.self, from: jsonData)
      coverageData = parseLLVMCoverage(llvmCoverage)
    }

    let testReport = generateTestReport(results: testResults, platform: platform)
    let testReportURL = outputURL.appendingPathComponent("test-results-\(platform).md")
    try testReport.write(to: testReportURL, atomically: true, encoding: .utf8)

    let detailedReport = generateDetailedTestReport(results: testResults, platform: platform)
    let detailedReportURL = outputURL.appendingPathComponent("test-details-\(platform).md")
    try detailedReport.write(to: detailedReportURL, atomically: true, encoding: .utf8)

    if let coverage = coverageData {
      let coverageReport = generateCoverageReport(coverage: coverage)
      let coverageReportURL = outputURL.appendingPathComponent("coverage-\(platform).md")
      try coverageReport.write(to: coverageReportURL, atomically: true, encoding: .utf8)
    }

    let failedTests = testResults.filter { $0.status == .failure }
    if !failedTests.isEmpty {
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

  func parseLLVMCoverage(_ export: LLVMCoverageExport) -> CoverageData {
    var moduleCoverages: [ModuleCoverage] = []
    var totalCovered = 0
    var totalLines = 0

    for data in export.data {
      for file in data.files {
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

  func extractModuleName(from filename: String) -> String {
    let components = filename.components(separatedBy: "/")
    if let sourcesIndex = components.firstIndex(of: "Sources"),
      sourcesIndex + 1 < components.count
    {
      return components[sourcesIndex + 1]
    }
    if let solidIndex = components.firstIndex(of: "Solid"), solidIndex + 1 < components.count {
      return "Solid" + components[solidIndex + 1]
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
