import Benchmark
import SolidJPEGBenchmarkSupport

let benchmarks: @Sendable () -> Void = {
  let backend: JPEGBenchmarkBackend
  let workloads: [JPEGBenchmarkWorkload]
  do {
    backend = try JPEGBenchmarkBackend.current()
    workloads = try JPEGBenchmarkFixtures.all()
  } catch {
    fatalError("Unable to prepare SolidJPEG benchmarks: \(error)")
  }

  let diagnosticThresholds = BenchmarkThresholds.none
  let configuration = Benchmark.Configuration(
    metrics: [
      .wallClock,
      .cpuTotal,
      .throughput,
      .mallocCountTotal,
      .retainCount,
      .peakMemoryResidentDelta,
    ],
    warmupIterations: 3,
    scalingFactor: .one,
    maxDuration: .seconds(10),
    maxIterations: 100,
    thresholds: [
      .wallClock: BenchmarkThresholds(relative: [.p50: 100]),
      .cpuTotal: diagnosticThresholds,
      .throughput: diagnosticThresholds,
      .mallocCountTotal: diagnosticThresholds,
      .retainCount: diagnosticThresholds,
      .peakMemoryResidentDelta: diagnosticThresholds,
    ]
  )

  for workload in workloads {
    Benchmark("JPEG Encode \(workload.name)", configuration: configuration) { benchmark in
      benchmark.startMeasurement()
      for _ in benchmark.scaledIterations {
        blackHole(try! JPEGBenchmarkFixtures.encode(workload, backend: backend))
      }
    }
    Benchmark("JPEG Decode \(workload.name)", configuration: configuration) { benchmark in
      benchmark.startMeasurement()
      for _ in benchmark.scaledIterations {
        blackHole(try! JPEGBenchmarkFixtures.decode(workload, backend: backend))
      }
    }
  }
}
