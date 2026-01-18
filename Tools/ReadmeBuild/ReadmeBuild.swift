import ArgumentParser
import Foundation
import Markdown

@main
struct ReadmeBuild: AsyncParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "readme-build",
    abstract: "Build README from template and validated Swift snippets"
  )

  @Option(name: .long, help: "Path to README template file")
  var template: String = "Documentation/README.template.md"

  @Option(name: .long, help: "Path to snippets directory")
  var snippets: String = "ReadmeExamples"

  @Option(name: .long, help: "Output README path")
  var output: String = "README.md"

  @Flag(name: .long, help: "Check that README is up to date (don't write)")
  var check: Bool = false

  @Flag(name: .long, help: "Compile snippets to validate")
  var compile: Bool = false

  func run() async throws {
    let templateURL = URL(fileURLWithPath: template)
    let snippetsURL = URL(fileURLWithPath: snippets)
    let outputURL = URL(fileURLWithPath: output)

    // Read the template
    print("Reading template from '\(template)'")
    let templateContent = try String(contentsOf: templateURL, encoding: .utf8)

    // Find all snippet references in the template
    let snippetPattern = /<!--\s*snippet:\s*(\w+)\s*-->/
    let matches = templateContent.matches(of: snippetPattern)
    print("Found \(matches.count) snippet references")

    // Load and process snippets
    var generatedContent = templateContent
    for match in matches {
      let snippetName = String(match.1)
      let snippetFile = snippetsURL.appendingPathComponent("\(snippetName).swift")

      guard FileManager.default.fileExists(atPath: snippetFile.path) else {
        print("  Warning: Snippet file not found: \(snippetName).swift")
        continue
      }

      let snippetContent = try String(contentsOf: snippetFile, encoding: .utf8)
      let extractedCode = extractVisibleCode(from: snippetContent)

      // Replace the snippet placeholder with a Swift code block
      let codeBlock = "```swift\n\(extractedCode)\n```"
      generatedContent = generatedContent.replacingOccurrences(
        of: String(match.0),
        with: codeBlock
      )
      print("  Injected snippet: \(snippetName)")
    }

    // Check mode: compare with existing README
    if check {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        let existingContent = try String(contentsOf: outputURL, encoding: .utf8)
        if existingContent == generatedContent {
          print("\nREADME is up to date!")
        } else {
          print("\nREADME is out of date! Run without --check to update.")
          throw ExitCode.failure
        }
      } else {
        print("\nREADME does not exist! Run without --check to generate.")
        throw ExitCode.failure
      }
    } else {
      // Write the generated README
      try generatedContent.write(to: outputURL, atomically: true, encoding: .utf8)
      print("\nGenerated README at '\(output)'")
    }

    // Compile snippets if requested
    if compile {
      print("\nCompiling snippets...")
      let success = try await compileSnippets()
      if success {
        print("All snippets compiled successfully!")
      } else {
        print("Compilation failed - see errors above")
        throw ExitCode.failure
      }
    }
  }

  /// Extract visible code from a snippet file, respecting show/hide markers
  func extractVisibleCode(from content: String) -> String {
    let lines = content.components(separatedBy: .newlines)
    var visibleLines: [String] = []
    var isVisible = true

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed == "// snippet.hide" {
        isVisible = false
        continue
      } else if trimmed == "// snippet.show" {
        isVisible = true
        continue
      }

      if isVisible {
        visibleLines.append(line)
      }
    }

    // Trim leading/trailing empty lines
    let result = visibleLines
      .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
      .reversed()
      .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
      .reversed()
      .map { String($0) }

    return result.joined(separator: "\n")
  }

  /// Compile all snippets using swift build
  func compileSnippets() async throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "build", "--target", "ReadmeExamples"]
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
      print(output)
    }

    return process.terminationStatus == 0
  }
}
