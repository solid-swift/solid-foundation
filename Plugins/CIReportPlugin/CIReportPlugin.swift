import Foundation
import PackagePlugin

@main
struct CIReportPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    var argExtractor = ArgumentExtractor(arguments)

    let xcresultPaths = argExtractor.extractOption(named: "xcresult")
    let outputDir = argExtractor.extractOption(named: "output").first ?? "."
    let platform = argExtractor.extractOption(named: "platform").first ?? "unknown"
    let coverageJsonPath = argExtractor.extractOption(named: "coverage-json").first

    let reportTool = try context.tool(named: "ci-report-tool")

    var toolArgs: [String] = []

    if !xcresultPaths.isEmpty {
      for path in xcresultPaths {
        toolArgs.append("--xcresult")
        toolArgs.append(path)
      }
    }

    toolArgs.append("--output")
    toolArgs.append(outputDir)

    toolArgs.append("--platform")
    toolArgs.append(platform)

    if let coverageJson = coverageJsonPath {
      toolArgs.append("--coverage-json")
      toolArgs.append(coverageJson)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: reportTool.url.path)
    process.arguments = toolArgs

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      Diagnostics.error("CI report tool failed with exit code \(process.terminationStatus)")
    }
  }
}
