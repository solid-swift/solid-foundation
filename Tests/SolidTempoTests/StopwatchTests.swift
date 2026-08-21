//
//  StopwatchTests.swift
//  SolidFoundation
//

@testable import SolidTempo
import Testing


@Suite("Stopwatch Tests")
struct StopwatchTests {

  @Test("Stopwatch starts stopped and accumulates running intervals")
  func accumulatesRunningIntervals() throws {
    let source = ManualInstantSource()
    let stopwatch = Stopwatch(source: source)

    #expect(!stopwatch.isRunning)
    #expect(stopwatch.elapsed == .zero)

    stopwatch.start()
    try source.advance(by: .milliseconds(125))
    #expect(stopwatch.elapsed == .milliseconds(125))

    stopwatch.stop()
    try source.advance(by: .seconds(1))
    #expect(stopwatch.elapsed == .milliseconds(125))

    stopwatch.start()
    try source.advance(by: .milliseconds(75))
    stopwatch.stop()
    #expect(stopwatch.elapsed == .milliseconds(200))
  }

  @Test("Start and stop are idempotent")
  func startAndStopAreIdempotent() throws {
    let source = ManualInstantSource()
    let stopwatch = Stopwatch(source: source)

    stopwatch.start()
    try source.advance(by: .milliseconds(10))
    stopwatch.start()
    try source.advance(by: .milliseconds(5))
    stopwatch.stop()
    stopwatch.stop()

    #expect(stopwatch.elapsed == .milliseconds(15))
  }

  @Test("Reset stops and restart starts")
  func resetAndRestart() throws {
    let source = ManualInstantSource()
    let stopwatch = Stopwatch(source: source)
    stopwatch.start()
    try source.advance(by: .seconds(1))

    stopwatch.reset()
    #expect(!stopwatch.isRunning)
    #expect(stopwatch.elapsed == .zero)

    stopwatch.restart()
    try source.advance(by: .milliseconds(25))
    #expect(stopwatch.isRunning)
    #expect(stopwatch.elapsed == .milliseconds(25))
  }

  @Test("Sub-millisecond precision is retained across runs")
  func retainsSubMillisecondPrecision() throws {
    let source = ManualInstantSource()
    let stopwatch = Stopwatch(source: source)

    stopwatch.start()
    try source.advance(by: .microseconds(400))
    stopwatch.stop()
    stopwatch.start()
    try source.advance(by: .microseconds(600))
    stopwatch.stop()

    #expect(stopwatch.elapsed == .milliseconds(1))
  }

  @Test("Constant source produces a constant elapsed duration")
  func constantSourceDoesNotAdvance() {
    let stopwatch = Stopwatch(source: ConstantInstantSource(instant: .epoch))

    stopwatch.start()

    #expect(stopwatch.elapsed == .zero)
  }

  @Test("Concurrent source advancement and elapsed reads are safe")
  func concurrentAccess() async throws {
    let source = ManualInstantSource()
    let stopwatch = Stopwatch(source: source)
    stopwatch.start()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask {
          try source.advance(by: .milliseconds(1))
          _ = stopwatch.elapsed
        }
      }
      try await group.waitForAll()
    }
    stopwatch.stop()

    #expect(stopwatch.elapsed == .milliseconds(100))
  }
}
