// swift-tools-version: 6.2

import PackageDescription
import class Foundation.ProcessInfo

let package = Package(
  name: "SolidFoundation",
  platforms: [
    .macOS("26"),
    .iOS("26"),
    .tvOS("26"),
    .watchOS("26"),
  ],
  products: [
    .library(name: "Solid", targets: ["Solid"]),
    .library(name: "SolidCore", targets: ["SolidCore"]),
    .library(name: "SolidIO", targets: ["SolidIO"]),
    .library(name: "SolidNumeric", targets: ["SolidNumeric"]),
    .library(name: "SolidTempo", targets: ["SolidTempo"]),
    .library(name: "SolidURI", targets: ["SolidURI"]),
    .library(name: "SolidNet", targets: ["SolidNet"]),
    .library(name: "SolidHTTP", targets: ["SolidHTTP"]),
    .library(name: "SolidID", targets: ["SolidID"]),
    .library(name: "SolidData", targets: ["SolidData"]),
    .library(name: "SolidSchema", targets: ["SolidSchema"]),
    .library(name: "SolidJSON", targets: ["SolidJSON"]),
    .library(name: "SolidYAML", targets: ["SolidYAML"]),
    .library(name: "SolidCBOR", targets: ["SolidCBOR"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-algorithms.git", .upToNextMinor(from: "1.2.1")),
    .package(url: "https://github.com/apple/swift-collections.git", .upToNextMinor(from: "1.3.0")),
    .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "4.2.0")),
    .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.8.0")),
    .package(url: "https://github.com/apple/swift-http-types.git", .upToNextMinor(from: "1.5.1")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    .package(url: "https://github.com/StarLard/SwiftFormatPlugins.git", from: "1.1.1"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3"),
    .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
  ],
  targets: [
    .target(
      name: "Solid",
      dependencies: [
        "SolidCore",
        "SolidNumeric",
        "SolidIO",
        "SolidID",
        "SolidURI",
        "SolidNet",
        "SolidHTTP",
        "SolidTempo",
        "SolidData",
        "SolidSchema",
        "SolidJSON",
        "SolidYAML",
        "SolidCBOR",
      ],
      path: "Sources/Solid/Root",
    ),
    .target(
      name: "SolidCore",
      dependencies: [
        .product(name: "Algorithms", package: "swift-algorithms"),
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "Logging", package: "swift-log", condition: .when(platforms: [.linux])),
      ],
      path: "Sources/Solid/Core",
      swiftSettings: debugSwiftSettings,
      plugins: lintPlugins
    ),
    .target(
      name: "SolidNumeric",
      dependencies: [
        "SolidCore",
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Solid/Numeric",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidNet",
      dependencies: [
        "SolidCore"
      ],
      path: "Sources/Solid/Net",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidURI",
      dependencies: [
        "SolidCore",
        "SolidNet",
      ],
      path: "Sources/Solid/URI",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidHTTP",
      dependencies: [
        "SolidCore",
        "SolidNet",
        .product(name: "HTTPTypes", package: "swift-http-types"),
      ],
      path: "Sources/Solid/HTTP",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidID",
      dependencies: [
        "SolidCore",
        "SolidTempo",
        "SolidNet",
      ],
      path: "Sources/Solid/ID",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidTempo",
      dependencies: [
        "SolidCore",
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Solid/Tempo",
      swiftSettings: debugSwiftSettings,
      plugins: lintPlugins
    ),
    .target(
      name: "SolidIO",
      dependencies: [
        "SolidCore",
        "SwiftCompression",
      ],
      path: "Sources/Solid/IO",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidData",
      dependencies: [
        "SolidCore",
        "SolidIO",
        "SolidNumeric",
        "SolidURI",
      ],
      path: "Sources/Solid/Data",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidSchema",
      dependencies: [
        "SolidData",
        "SolidID",
        "SolidJSON",
        "SolidNet",
        "SolidNumeric",
        "SolidTempo",
        "SolidURI",
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Solid/Schema",
      swiftSettings: debugSwiftSettings,
      plugins: lintPlugins
    ),
    .target(
      name: "SolidJSON",
      dependencies: ["SolidData", "SolidIO"],
      path: "Sources/Solid/JSON",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidYAML",
      dependencies: ["SolidData", "SolidIO"],
      path: "Sources/Solid/YAML",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidCBOR",
      dependencies: ["SolidData", "SolidIO"],
      path: "Sources/Solid/CBOR",
      plugins: lintPlugins
    ),
    .target(
      name: "SolidTesting",
      dependencies: ["Solid"],
      path: "Tests/SolidTesting",
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidCoreTests",
      dependencies: [
        "SolidCore",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidDataTests",
      dependencies: [
        "SolidData",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidIDTests",
      dependencies: [
        "SolidID",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidIOTests",
      dependencies: [
        "SolidIO",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidNetTests",
      dependencies: [
        "SolidNet"
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidHTTPTests",
      dependencies: [
        "SolidHTTP"
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidNumericTests",
      dependencies: [
        "SolidNumeric",
        "SolidTesting",
      ],
      resources: [
        .copy("Resources")
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidSchemaTests",
      dependencies: [
        "SolidSchema",
        "SolidTesting",
      ],
      resources: [
        .copy("Resources")
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidJSONTests",
      dependencies: [
        "SolidJSON",
        "SolidData",
        "SolidIO",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidYAMLTests",
      dependencies: [
        "SolidYAML",
        "SolidData",
        "SolidTesting",
      ],
      resources: [
        .copy("Fixtures/yaml-test-suite")
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidCBORTests",
      dependencies: [
        "SolidCBOR",
        "SolidData",
        "SolidIO",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidTempoTests",
      dependencies: [
        "SolidTempo",
        "SolidTesting",
      ],
      resources: [
        .copy("Resources")
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidURITests",
      dependencies: [
        "SolidURI",
        "SolidTesting",
      ],
      plugins: lintPlugins
    ),

    // - MARK: Shims

    .target(
      name: "SwiftCompression",
      dependencies: [
        .product(name: "SWCompression", package: "SWCompression", condition: .when(platforms: [.linux]))
      ],
      path: "Sources/SwiftCompression"
    ),

    // - MARK: Build Tools

    .executableTarget(
      name: "test-report",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      path: "Tools/TestReport"
    ),
    .executableTarget(
      name: "readme-build",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      path: "Tools/ReadmeBuild"
    ),
    .target(
      name: "Snippets",
      dependencies: [
        "Solid"
      ],
      path: "Snippets"
    ),
  ],
  swiftLanguageModes: [.v6],
)

// Build Debugging
let debugSwiftSettings: [SwiftSetting] = [
  .unsafeFlags(
    [
      "-Xfrontend", "-warn-long-function-bodies=200",
      "-Xfrontend", "-warn-long-expression-type-checking=200",
    ],
    .when(configuration: .debug)
  )
]

// Linting
let lintEnableEnv = ProcessInfo.processInfo.environment["ENABLE_LINT"]?.lowercased()
let lintEnabled =
  if let lintEnableEnv, lintEnableEnv == "1" || lintEnableEnv == "true" || lintEnableEnv == "t" {
    true
  } else {
    false
  }
let lintPlugins: [Target.PluginUsage] =
  lintEnabled
  ? [.plugin(name: "Lint", package: "swiftformatplugins")]
  : []

// Benchmarking
let benchmarkEnableEnv = ProcessInfo.processInfo.environment["BENCHMARK_ENABLE"]?.lowercased()
let benchmarkEnabled =
  if let benchmarkEnableEnv, benchmarkEnableEnv == "1" || benchmarkEnableEnv == "true" || benchmarkEnableEnv == "t" {
    true
  } else {
    false
  }
if benchmarkEnabled {
  package.dependencies += [
    .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.29.7")),
  ]
  package.products += [
    .executable(
      name: "SolidBench",
      targets: [
        "SolidBench"
      ],
    )
  ]
  package.targets += [
    .executableTarget(
      name: "SolidBench",
      dependencies: [
        "Solid",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
    ),
    .executableTarget(
      name: "SolidNumericBenchmark",
      dependencies: [
        "Solid",
        .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: "Benchmarks/SolidNumericBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    ),
    .executableTarget(
      name: "SolidCBORBenchmark",
      dependencies: [
        "Solid",
        .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: "Benchmarks/SolidCBORBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    ),
    .executableTarget(
      name: "SolidYAMLBenchmark",
      dependencies: [
        "Solid",
        .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: "Benchmarks/SolidYAMLBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    ),
    .executableTarget(
      name: "SolidJSONBenchmark",
      dependencies: [
        "Solid",
        .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: "Benchmarks/SolidJSONBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    ),
  ]
}
