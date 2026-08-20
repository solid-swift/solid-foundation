import Foundation

/// Configuration for a deterministic mutation campaign.
public struct DeterministicFuzzConfiguration: Sendable {

  /// Initial pseudo-random seed.
  public let seed: UInt64

  /// First iteration to execute.
  public let firstIteration: Int

  /// Number of iterations to execute.
  public let iterationCount: Int

  /// Largest generated input.
  public let maximumInputBytes: Int

  /// Optional campaign deadline in seconds.
  public let timeout: Duration?

  /// Directory containing seed inputs.
  public let corpusDirectory: URL?

  /// Directory receiving the active reproducer.
  public let artifactDirectory: URL

  /// Creates a deterministic campaign configuration.
  public init(
    seed: UInt64,
    firstIteration: Int,
    iterationCount: Int,
    maximumInputBytes: Int,
    timeout: Duration?,
    corpusDirectory: URL?,
    artifactDirectory: URL
  ) {
    self.seed = seed
    self.firstIteration = firstIteration
    self.iterationCount = iterationCount
    self.maximumInputBytes = maximumInputBytes
    self.timeout = timeout
    self.corpusDirectory = corpusDirectory
    self.artifactDirectory = artifactDirectory
  }

  /// Parses common fuzz-runner command-line options.
  public static func commandLine(arguments: [String] = CommandLine.arguments) throws -> Self {
    var seed: UInt64 = 0x534F_4C49_4446_555A
    var firstIteration = 0
    var iterationCount = 1_000
    var maximumInputBytes = 1 << 20
    var timeout: Duration?
    var corpusDirectory: URL?
    var artifactDirectory = URL(fileURLWithPath: ".fuzz-artifacts", isDirectory: true)
    var index = 1
    while index < arguments.count {
      let option = arguments[index]
      guard index + 1 < arguments.count else { throw DeterministicFuzzError.invalidArguments }
      let value = arguments[index + 1]
      switch option {
      case "--seed":
        guard let parsed = UInt64(value) else { throw DeterministicFuzzError.invalidArguments }
        seed = parsed
      case "--resume":
        guard let parsed = Int(value), parsed >= 0 else { throw DeterministicFuzzError.invalidArguments }
        firstIteration = parsed
      case "--iterations":
        guard let parsed = Int(value), parsed > 0 else { throw DeterministicFuzzError.invalidArguments }
        iterationCount = parsed
      case "--max-input":
        guard let parsed = Int(value), parsed > 0 else { throw DeterministicFuzzError.invalidArguments }
        maximumInputBytes = parsed
      case "--timeout":
        guard let parsed = Double(value), parsed > 0 else { throw DeterministicFuzzError.invalidArguments }
        timeout = .milliseconds(Int64((parsed * 1_000).rounded()))
      case "--corpus":
        corpusDirectory = URL(fileURLWithPath: value, isDirectory: true)
      case "--artifacts":
        artifactDirectory = URL(fileURLWithPath: value, isDirectory: true)
      default:
        throw DeterministicFuzzError.invalidArguments
      }
      index += 2
    }
    return Self(
      seed: seed,
      firstIteration: firstIteration,
      iterationCount: iterationCount,
      maximumInputBytes: maximumInputBytes,
      timeout: timeout,
      corpusDirectory: corpusDirectory,
      artifactDirectory: artifactDirectory
    )
  }

}

/// Errors raised by the deterministic mutation runner itself.
public enum DeterministicFuzzError: Error {
  case invalidArguments
  case emptyCorpus
}

/// A deterministic, resumable mutation runner suitable for sanitizer builds.
public struct DeterministicFuzzRunner {

  private let configuration: DeterministicFuzzConfiguration
  private let builtInCorpus: [[UInt8]]

  /// Creates a runner with built-in seed inputs used when no corpus is supplied.
  public init(configuration: DeterministicFuzzConfiguration, builtInCorpus: [[UInt8]]) {
    self.configuration = configuration
    self.builtInCorpus = builtInCorpus
  }

  /// Runs the campaign and invokes the body once for each mutated input.
  public func run(_ body: (borrowing [UInt8], Int) throws -> Void) throws {
    let corpus = try loadCorpus()
    guard !corpus.isEmpty else { throw DeterministicFuzzError.emptyCorpus }
    let iterations = try iterationRange()
    try FileManager.default.createDirectory(
      at: configuration.artifactDirectory,
      withIntermediateDirectories: true
    )
    let activeURL = configuration.artifactDirectory.appendingPathComponent("active-input.bin")
    let iterationURL = configuration.artifactDirectory.appendingPathComponent("active-iteration.txt")
    let clock = ContinuousClock()
    let deadline = configuration.timeout.map { clock.now.advanced(by: $0) }
    for iteration in iterations {
      if let deadline, clock.now >= deadline { break }
      var random = randomGenerator(for: iteration)
      let first = corpus[Int(random.next() % UInt64(corpus.count))]
      let second = corpus[Int(random.next() % UInt64(corpus.count))]
      let input = mutate(first, crossingWith: second, random: &random)
      try Data(input).write(to: activeURL, options: .atomic)
      try Data(String(iteration).utf8).write(to: iterationURL, options: .atomic)
      do {
        try body(input, iteration)
      } catch {
        // Typed rejection is the expected outcome for malformed fuzz inputs.
      }
    }
    try? FileManager.default.removeItem(at: activeURL)
    try? FileManager.default.removeItem(at: iterationURL)
  }

  /// Runs an asynchronous campaign for actor-isolated or asynchronous parsers.
  public func runAsync(
    _ body: (borrowing [UInt8], Int) async throws -> Void
  ) async throws {
    let corpus = try loadCorpus()
    guard !corpus.isEmpty else { throw DeterministicFuzzError.emptyCorpus }
    let iterations = try iterationRange()
    try FileManager.default.createDirectory(
      at: configuration.artifactDirectory,
      withIntermediateDirectories: true
    )
    let activeURL = configuration.artifactDirectory.appendingPathComponent("active-input.bin")
    let iterationURL = configuration.artifactDirectory.appendingPathComponent("active-iteration.txt")
    let clock = ContinuousClock()
    let deadline = configuration.timeout.map { clock.now.advanced(by: $0) }
    for iteration in iterations {
      if let deadline, clock.now >= deadline { break }
      var random = randomGenerator(for: iteration)
      let first = corpus[Int(random.next() % UInt64(corpus.count))]
      let second = corpus[Int(random.next() % UInt64(corpus.count))]
      let input = mutate(first, crossingWith: second, random: &random)
      try Data(input).write(to: activeURL, options: .atomic)
      try Data(String(iteration).utf8).write(to: iterationURL, options: .atomic)
      do {
        try await body(input, iteration)
      } catch {
        // Typed rejection is the expected outcome for malformed fuzz inputs.
      }
    }
    try? FileManager.default.removeItem(at: activeURL)
    try? FileManager.default.removeItem(at: iterationURL)
  }

  private func iterationRange() throws -> Range<Int> {
    guard configuration.firstIteration >= 0,
          configuration.iterationCount > 0,
          configuration.maximumInputBytes > 0
    else {
      throw DeterministicFuzzError.invalidArguments
    }
    let (lastIteration, overflow) = configuration.firstIteration.addingReportingOverflow(
      configuration.iterationCount
    )
    guard !overflow else { throw DeterministicFuzzError.invalidArguments }
    return configuration.firstIteration..<lastIteration
  }

  private func randomGenerator(for iteration: Int) -> SplitMix64 {
    var mixer = SplitMix64(seed: UInt64(iteration))
    return SplitMix64(seed: configuration.seed ^ mixer.next())
  }

  private func loadCorpus() throws -> [[UInt8]] {
    guard let directory = configuration.corpusDirectory else { return builtInCorpus }
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    let loaded = try urls.compactMap { url -> [UInt8]? in
      guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        return nil
      }
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      return Array(data.prefix(configuration.maximumInputBytes))
    }
    return loaded.isEmpty ? builtInCorpus : loaded
  }

  private func mutate(
    _ source: [UInt8],
    crossingWith other: [UInt8],
    random: inout SplitMix64
  ) -> [UInt8] {
    var bytes = Array(source.prefix(configuration.maximumInputBytes))
    let mutationCount = Int(random.next() % 8) + 1
    for _ in 0..<mutationCount {
      switch random.next() % 8 {
      case 0 where !bytes.isEmpty:
        bytes[Int(random.next() % UInt64(bytes.count))] ^= UInt8(1 << (random.next() % 8))
      case 1 where !bytes.isEmpty:
        bytes[Int(random.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: random.next())
      case 2 where !bytes.isEmpty:
        bytes.removeLast(Int(random.next() % UInt64(bytes.count + 1)))
      case 3 where !bytes.isEmpty:
        bytes.remove(at: Int(random.next() % UInt64(bytes.count)))
      case 4 where bytes.count < configuration.maximumInputBytes:
        bytes.insert(
          UInt8(truncatingIfNeeded: random.next()),
          at: Int(random.next() % UInt64(bytes.count + 1))
        )
      case 5 where !bytes.isEmpty && bytes.count < configuration.maximumInputBytes:
        let start = Int(random.next() % UInt64(bytes.count))
        let count = min(bytes.count - start, Int(random.next() % 32) + 1)
        bytes.insert(contentsOf: bytes[start..<(start + count)], at: start)
      case 6 where !other.isEmpty && bytes.count < configuration.maximumInputBytes:
        let start = Int(random.next() % UInt64(other.count))
        let count = min(other.count - start, Int(random.next() % 64) + 1)
        let insertion = min(bytes.count, Int(random.next() % UInt64(bytes.count + 1)))
        bytes.insert(contentsOf: other[start..<(start + count)], at: insertion)
      default:
        corruptMarkerLength(in: &bytes, random: &random)
      }
      if bytes.count > configuration.maximumInputBytes {
        bytes.removeLast(bytes.count - configuration.maximumInputBytes)
      }
    }
    return bytes
  }

  private func corruptMarkerLength(in bytes: inout [UInt8], random: inout SplitMix64) {
    guard bytes.count >= 4 else { return }
    let candidates = (0..<(bytes.count - 3)).filter {
      bytes[$0] == 0xFF && bytes[$0 + 1] != 0 && !(0xD0...0xD9).contains(bytes[$0 + 1])
    }
    guard let marker = candidates.randomElement(using: &random) else { return }
    bytes[marker + 2] = UInt8(truncatingIfNeeded: random.next())
    bytes[marker + 3] = UInt8(truncatingIfNeeded: random.next())
  }

}

private struct SplitMix64: RandomNumberGenerator {

  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

}
