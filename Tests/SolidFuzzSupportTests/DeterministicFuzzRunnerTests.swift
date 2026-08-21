import Foundation
import SolidFuzzSupport
import Testing

@Suite
struct DeterministicFuzzRunnerTests {

  @Test
  func commandLineParsingIsStrict() throws {
    let configuration = try DeterministicFuzzConfiguration.commandLine(arguments: [
      "fuzzer",
      "--seed", "42",
      "--resume", "7",
      "--iterations", "3",
      "--max-input", "64",
      "--timeout", "0.5",
      "--artifacts", "/tmp/artifacts",
    ])
    #expect(configuration.seed == 42)
    #expect(configuration.firstIteration == 7)
    #expect(configuration.iterationCount == 3)
    #expect(configuration.maximumInputBytes == 64)
    #expect(throws: DeterministicFuzzError.self) {
      _ = try DeterministicFuzzConfiguration.commandLine(arguments: ["fuzzer", "--unknown", "1"])
    }
  }

  @Test
  func identicalSeedsProduceIdenticalMutations() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let corpus: [[UInt8]] = [[0xFF, 0xD8, 0xFF, 0xD9], [0, 1, 2, 3, 4, 5]]

    func execute(suffix: String) throws -> [[UInt8]] {
      let configuration = DeterministicFuzzConfiguration(
        seed: 123,
        firstIteration: 4,
        iterationCount: 8,
        maximumInputBytes: 32,
        timeout: nil,
        corpusDirectory: nil,
        artifactDirectory: root.appendingPathComponent(suffix, isDirectory: true)
      )
      var generated: [[UInt8]] = []
      try DeterministicFuzzRunner(configuration: configuration, builtInCorpus: corpus).run { input, _ in
        generated.append(input)
      }
      return generated
    }

    #expect(try execute(suffix: "first") == execute(suffix: "second"))
  }

  @Test
  func resumedIterationsMatchAnUninterruptedCampaign() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let corpus: [[UInt8]] = [[0xFF, 0xD8, 0xFF, 0xD9], [0, 1, 2, 3, 4, 5]]

    func execute(firstIteration: Int, count: Int, suffix: String) throws -> [[UInt8]] {
      let configuration = DeterministicFuzzConfiguration(
        seed: 123,
        firstIteration: firstIteration,
        iterationCount: count,
        maximumInputBytes: 32,
        timeout: nil,
        corpusDirectory: nil,
        artifactDirectory: root.appendingPathComponent(suffix, isDirectory: true)
      )
      var generated: [[UInt8]] = []
      try DeterministicFuzzRunner(configuration: configuration, builtInCorpus: corpus).run { input, _ in
        generated.append(input)
      }
      return generated
    }

    let uninterrupted = try execute(firstIteration: 0, count: 12, suffix: "uninterrupted")
    let resumed = try execute(firstIteration: 7, count: 5, suffix: "resumed")
    #expect(Array(uninterrupted.dropFirst(7)) == resumed)
  }

}
