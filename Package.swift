// swift-tools-version: 6.0

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
    .library(name: "SolidIO", targets: ["SolidCore"]),
    .library(name: "SolidNumeric", targets: ["SolidNumeric"]),
    .library(name: "SolidTempo", targets: ["SolidTempo"]),
    .library(name: "SolidURI", targets: ["SolidURI"]),
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
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    .package(url: "https://github.com/StarLard/SwiftFormatPlugins.git", from: "1.1.1"),
    .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.29.7")),
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
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidNumeric",
      dependencies: [
        "SolidCore",
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Solid/Numeric",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidNet",
      dependencies: [
        "SolidCore"
      ],
      path: "Sources/Solid/Net",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidURI",
      dependencies: [
        "SolidCore",
        "SolidNet",
      ],
      path: "Sources/Solid/URI",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidID",
      dependencies: [
        "SolidCore",
        "SolidTempo",
        "SolidNet",
      ],
      path: "Sources/Solid/ID",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidTempo",
      dependencies: [
        "SolidCore",
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/Solid/Tempo",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SwiftCompression",
      dependencies: [
        .product(name: "SWCompression", package: "SWCompression", condition: .when(platforms: [.linux])),
      ],
      path: "Sources/SwiftCompression"
    ),
    .target(
      name: "SolidIO",
      dependencies: [
        "SolidCore",
        "SwiftCompression",
      ],
      path: "Sources/Solid/IO",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidData",
      dependencies: [
        "SolidCore",
        "SolidNumeric",
        "SolidURI",
      ],
      path: "Sources/Solid/Data",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
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
    ),
    .target(
      name: "SolidJSON",
      dependencies: ["SolidData", "SolidIO"],
      path: "Sources/Solid/JSON",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidYAML",
      dependencies: ["SolidData"],
      path: "Sources/Solid/YAML",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidCBOR",
      dependencies: ["SolidData"],
      path: "Sources/Solid/CBOR",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "SolidTesting",
      dependencies: ["Solid"],
      path: "Tests/SolidTesting",
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidCoreTests",
      dependencies: [
        "SolidCore",
        "SolidTesting",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidDataTests",
      dependencies: [
        "SolidData",
        "SolidTesting",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidIDTests",
      dependencies: [
        "SolidID",
        "SolidTesting",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidIOTests",
      dependencies: [
        "SolidIO",
        "SolidTesting",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidNetTests",
      dependencies: [
        "SolidNet",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
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
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
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
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidJSONTests",
      dependencies: [
        "SolidJSON",
        "SolidData",
        "SolidIO",
        "SolidTesting",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
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
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .testTarget(
      name: "SolidURITests",
      dependencies: [
        "SolidURI",
        "SolidTesting",
      ],
      plugins: [
        .plugin(name: "Lint", package: "swiftformatplugins")
      ]
    ),
    .target(
      name: "Snippets",
      dependencies: [
        "Solid",
      ],
      path: "Snippets"
    ),
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
  ],
  swiftLanguageModes: [.v6],
)

// Benchmarking
let benchmarkEnableEnv = ProcessInfo.processInfo.environment["BENCHMARK_ENABLE"]?.lowercased()
let benchmarkEnbled =
  if let benchmarkEnableEnv, benchmarkEnableEnv == "1" || benchmarkEnableEnv == "true" || benchmarkEnableEnv == "t" {
    true
  } else {
    false
  }
if benchmarkEnbled {
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
  ]
}
