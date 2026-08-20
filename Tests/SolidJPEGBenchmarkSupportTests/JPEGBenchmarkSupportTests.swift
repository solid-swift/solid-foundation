import SolidJPEGBenchmarkSupport
import Testing

@Suite
struct JPEGBenchmarkSupportTests {

  @Test
  func backendParsingIsStrict() throws {
    #expect(try JPEGBenchmarkBackend.current(environment: [:]) == .native)
    #expect(try JPEGBenchmarkBackend.current(environment: [
      "SOLID_JPEG_BENCHMARK_BACKEND": "native"
    ]) == .native)
    #expect(throws: JPEGBenchmarkError.self) {
      try JPEGBenchmarkBackend.current(environment: [
        "SOLID_JPEG_BENCHMARK_BACKEND": "unknown"
      ])
    }
  }

  @Test
  func workloadNamesAndNativeReplayAreStable() throws {
    let workloads = try JPEGBenchmarkFixtures.all(width: 32, height: 24)
    #expect(workloads.map(\.name) == [
      "Grayscale 512x512",
      "YCbCr 4:4:4 512x512",
      "YCbCr 4:2:0 512x512",
    ])
    for workload in workloads {
      #expect(try JPEGBenchmarkFixtures.encode(workload, backend: .native).suffix(2) == [0xFF, 0xD9])
      #expect(try JPEGBenchmarkFixtures.decode(workload, backend: .native).count == workload.samples.count)
    }
  }

}
