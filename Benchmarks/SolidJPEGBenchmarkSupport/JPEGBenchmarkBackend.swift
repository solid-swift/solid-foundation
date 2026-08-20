import Foundation
import SolidIO
import SolidJPEG

#if canImport(JPEG)
  import JPEG
#endif

/// Codec backend selected for a SolidJPEG comparison run.
public enum JPEGBenchmarkBackend: String, CaseIterable, Sendable {
  case native
  case swiftJPEG = "swift-jpeg"
  case imageIO = "imageio"

  /// Reads and validates `SOLID_JPEG_BENCHMARK_BACKEND`.
  public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
    let value = environment["SOLID_JPEG_BENCHMARK_BACKEND"] ?? Self.native.rawValue
    guard let backend = Self(rawValue: value) else {
      throw JPEGBenchmarkError.invalidBackend(value)
    }
    #if !canImport(JPEG)
      if backend == .swiftJPEG { throw JPEGBenchmarkError.unavailableBackend(value) }
    #endif
    #if !canImport(ImageIO)
      if backend == .imageIO { throw JPEGBenchmarkError.unavailableBackend(value) }
    #endif
    return backend
  }
}

/// A fixed JPEG encode/decode comparison workload.
public struct JPEGBenchmarkWorkload: Sendable {
  public let name: String
  public let width: Int
  public let height: Int
  public let samples: [UInt8]
  public let components: [SolidJPEG.JPEGComponent]
  public let colorTransform: JPEGColorTransform
  public let encoded: [UInt8]

  public var componentCount: Int { components.count }
}

/// Errors preparing a cross-backend JPEG benchmark.
public enum JPEGBenchmarkError: Error {
  case invalidBackend(String)
  case unavailableBackend(String)
  case invalidFixture
}

/// Stable fixtures and replay helpers shared by every benchmark backend.
public enum JPEGBenchmarkFixtures {

  /// Creates grayscale, YCbCr 4:4:4, and YCbCr 4:2:0 workloads.
  public static func all(width: Int = 512, height: Int = 512) throws -> [JPEGBenchmarkWorkload] {
    try [
      make(name: "Grayscale 512x512", width: width, height: height, sampling: [(1, 1)]),
      make(name: "YCbCr 4:4:4 512x512", width: width, height: height, sampling: [(1, 1), (1, 1), (1, 1)]),
      make(name: "YCbCr 4:2:0 512x512", width: width, height: height, sampling: [(2, 2), (1, 1), (1, 1)]),
    ]
  }

  /// Encodes one fixture with the selected backend.
  public static func encode(_ workload: JPEGBenchmarkWorkload, backend: JPEGBenchmarkBackend) throws -> [UInt8] {
    switch backend {
    case .native:
      return try nativeEncode(workload)
    case .imageIO:
      let options = try DCTEncodeOptions(
        columns: workload.width,
        rows: workload.height,
        colors: workload.componentCount,
        horizontalSamples: workload.components.map(\.sampling.horizontal),
        verticalSamples: workload.components.map(\.sampling.vertical),
        colorTransform: workload.colorTransform.rawValue
      )
      let encoder = DCTEncoder(options: options)
      let result = try encoder.process(input: Data(workload.samples))
      return Array(result.output + (try encoder.finish() ?? Data()))
    case .swiftJPEG:
      #if canImport(JPEG)
        return try swiftJPEGEncode(workload)
      #else
        throw JPEGBenchmarkError.unavailableBackend(backend.rawValue)
      #endif
    }
  }

  /// Decodes one fixture with the selected backend.
  public static func decode(_ workload: JPEGBenchmarkWorkload, backend: JPEGBenchmarkBackend) throws -> [UInt8] {
    switch backend {
    case .native:
      var decoder = SolidJPEG.JPEGDecoder(
        options: try JPEGDecodingOptions(expectedComponents: workload.componentCount)
      )
      let result = try workload.encoded.withUnsafeBufferPointer {
        try decoder.process(Span(_unsafeElements: $0))
      }
      return result.rows.flatMap(\.samples)
    case .imageIO:
      let decoder = DCTDecoder(
        options: try DCTDecodeOptions(
          columns: workload.width,
          rows: workload.height,
          colors: workload.componentCount
        )
      )
      return Array(try decoder.process(input: Data(workload.encoded)).output)
    case .swiftJPEG:
      #if canImport(JPEG)
        var source = JPEGByteSource(bytes: workload.encoded)
        let image: JPEG.Data.Rectangular<JPEG.Common> = try .decompress(stream: &source)
        let pixels = image.unpack(as: JPEG.RGB.self)
        if workload.componentCount == 1 {
          return pixels.map(\.r)
        }
        return pixels.flatMap { [$0.r, $0.g, $0.b] }
      #else
        throw JPEGBenchmarkError.unavailableBackend(backend.rawValue)
      #endif
    }
  }

  private static func make(
    name: String,
    width: Int,
    height: Int,
    sampling: [(Int, Int)]
  ) throws -> JPEGBenchmarkWorkload {
    let count = sampling.count
    let samples = (0..<(width * height * count)).map { index in
      let pixel = index / count
      let component = index % count
      return UInt8(truncatingIfNeeded: (pixel % width) * 17 + (pixel / width) * 31 + component * 73)
    }
    let components = try sampling.enumerated().map { index, factor in
      try SolidJPEG.JPEGComponent(
        identifier: UInt8(index + 1),
        sampling: JPEGSampling(horizontal: factor.0, vertical: factor.1),
        quantizationTable: index == 0 ? 0 : 1
      )
    }
    let transform: JPEGColorTransform = count == 3 ? .yCbCr : .none
    let provisional = JPEGBenchmarkWorkload(
      name: name,
      width: width,
      height: height,
      samples: samples,
      components: components,
      colorTransform: transform,
      encoded: []
    )
    let encoded = try nativeEncode(provisional)
    return JPEGBenchmarkWorkload(
      name: name,
      width: width,
      height: height,
      samples: samples,
      components: components,
      colorTransform: transform,
      encoded: encoded
    )
  }

  private static func nativeEncode(_ workload: JPEGBenchmarkWorkload) throws -> [UInt8] {
    var encoder = SolidJPEG.JPEGEncoder(
      options: try JPEGEncodingOptions(
        width: workload.width,
        height: workload.height,
        components: workload.components,
        colorTransform: workload.colorTransform
      )
    )
    let result = try workload.samples.withUnsafeBufferPointer {
      try encoder.process(Span(_unsafeElements: $0))
    }
    return result.bytes + (try encoder.finish())
  }

  #if canImport(JPEG)
    private static func swiftJPEGEncode(_ workload: JPEGBenchmarkWorkload) throws -> [UInt8] {
      let pixels: [JPEG.RGB]
      if workload.componentCount == 1 {
        pixels = workload.samples.map(JPEG.RGB.init)
      } else {
        pixels = stride(from: 0, to: workload.samples.count, by: 3).map {
          JPEG.RGB(workload.samples[$0], workload.samples[$0 + 1], workload.samples[$0 + 2])
        }
      }
      let layout: JPEG.Layout<JPEG.Common>
      if workload.componentCount == 1 {
        layout = .init(
          format: .y8,
          process: .baseline,
          components: [1: (factor: (1, 1), qi: 0 as JPEG.Table.Quantization.Key)],
          scans: [.sequential((1, \.0, \.0))]
        )
      } else {
        let first = workload.components[0].sampling
        layout = .init(
          format: .ycc8,
          process: .baseline,
          components: [
            1: (factor: (first.horizontal, first.vertical), qi: 0 as JPEG.Table.Quantization.Key),
            2: (factor: (1, 1), qi: 1 as JPEG.Table.Quantization.Key),
            3: (factor: (1, 1), qi: 1 as JPEG.Table.Quantization.Key),
          ],
          scans: [.sequential((1, \.0, \.0), (2, \.1, \.1), (3, \.1, \.1))]
        )
      }
      let image: JPEG.Data.Rectangular<JPEG.Common> = .pack(
        size: (workload.width, workload.height),
        layout: layout,
        metadata: [],
        pixels: pixels
      )
      var destination = JPEGByteDestination()
      try image.compress(
        stream: &destination,
        quanta: [
          0: JPEG.CompressionLevel.luminance(1).quanta,
          1: JPEG.CompressionLevel.chrominance(1).quanta,
        ]
      )
      return destination.bytes
    }
  #endif
}

#if canImport(JPEG)
  private struct JPEGByteSource: JPEG.Bytestream.Source {
    let bytes: [UInt8]
    private var offset = 0

    init(bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func read(count: Int) -> [UInt8]? {
      guard count >= 0, count <= bytes.count - offset else { return nil }
      defer { offset += count }
      return Array(bytes[offset..<(offset + count)])
    }
  }

  private struct JPEGByteDestination: JPEG.Bytestream.Destination {
    var bytes: [UInt8] = []

    mutating func write(_ bytes: [UInt8]) -> Void? {
      self.bytes.append(contentsOf: bytes)
      return ()
    }
  }
#endif
