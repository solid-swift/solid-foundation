//
//  main.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/24/25.
//

import Foundation
import SolidData
import SolidNumeric
import SolidJSON
import SolidYAML
import ArgumentParser

@main
struct ExcerciseNumerics: ParsableCommand {

  static let configuration = CommandConfiguration(
    abstract: "Excerise Numerics",
    subcommands: [
      ExceriseBigDecimal.self,
      ExceriseBigUInt.self,
      ExceriseBigInt.self,
      ExceriseYAMLDecode.self,
      ExceriseJSONDecode.self,
    ]
  )
}

struct ExceriseBigDecimal: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-bigdecimal",
    abstract: "Excerise BigDecimal",
    discussion: """
    Excerise BigDecimal

    This command is used to exercise the BigDecimal type. It performs a multiplication,
    division, and remainder operation on `iterations` of random BigDecimal values.
    """,
    aliases: ["ebd"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 10_000_000

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      let s = BigDecimal(UInt.random(in: .min ... .max))
      let t = BigDecimal(UInt.random(in: .min ... .max))
      let p = s * t
      let q = p / s
      let r = p.remainder(dividingBy: s)
      blackHole(q)
      blackHole(r)
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      print("Duration: \(duration)")
    }
  }
}

struct ExceriseBigUInt: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-biguint",
    abstract: "Excerise BigUInt",
    discussion: """
    Excerise BigUInt

    This command is used to exercise the BigUInt type. It performs a multiplication,
    division/remainder operation on `iterations` of random BigUInt values.
    """,
    aliases: ["ebu"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 10_000_000

  @Flag(help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      let s = BigUInt(UInt.random(in: .min ... .max))
      let t = BigUInt(UInt.random(in: .min ... .max))
      let p = s * t
      let (q, r) = p.quotientAndRemainder(dividingBy: s)
      blackHole(q)
      blackHole(r)
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      print("Duration: \(duration)")
    }
  }
}

struct ExceriseBigInt: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-bigint",
    abstract: "Excerise BigInt",
    discussion: """
    Excerise BigInt

    This command is used to exercise the BigInt type. It performs a multiplication,
    division/remainder operation on `iterations` of random BigInt values.
    """,
    aliases: ["ebi"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 10_000_000

  @Flag(help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      let s = BigInt(Int.random(in: .min ... .max))
      let t = BigInt(Int.random(in: .min ... .max))
      let p = s * t
      let (q, r) = p.quotientAndRemainder(dividingBy: s)
      blackHole(q)
      blackHole(r)
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      print("Duration: \(duration)")
    }
  }
}

struct ExceriseYAMLDecode: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-yaml-decode",
    abstract: "Excerise YAML Decode",
    discussion: """
    Excerise YAML decoding of a large array.

    This command is used to exercise the YAML decode path. It decodes a large YAML
    array (10k integers) for the specified number of iterations.
    """,
    aliases: ["eyd"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 20

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let largeArray: Value = .array((0..<10_000).map { .number($0) })
    let largeArrayYaml = try YAMLValueWriter.write(largeArray)

    // Warm up
    var warmupReader = try YAMLValueReader(data: largeArrayYaml)
    blackHole(try warmupReader.read())

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      var reader = try YAMLValueReader(data: largeArrayYaml)
      blackHole(try reader.read())
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      let perIteration = duration / iterations
      print("Duration: \(duration) (\(perIteration) per iteration)")
    }
  }
}

struct ExceriseJSONDecode: ParsableCommand {

  static let configuration = CommandConfiguration(
    commandName: "excercise-json-decode",
    abstract: "Excerise JSON Decode",
    discussion: """
    Excerise JSON decoding of a large array.

    This command is used to exercise the JSON decode path. It decodes a large JSON
    array (10k integers) for the specified number of iterations.
    """,
    aliases: ["ejd"]
  )

  @Argument(help: "The number of iterations to run")
  var iterations: Int = 20

  @Flag(name: .shortAndLong, help: "Print the duration of the operation")
  var printDuration: Bool = false

  func run() throws {

    let largeArray: Value = .array((0..<10_000).map { .number($0) })
    let largeArrayJson = JSONValueWriter.write(largeArray)

    // Warm up
    var warmupReader = JSONValueReader(data: largeArrayJson)
    blackHole(try warmupReader.read())

    let clock = ContinuousClock()
    let start = clock.now

    for _ in 0..<iterations {
      var reader = JSONValueReader(data: largeArrayJson)
      blackHole(try reader.read())
    }

    let end = clock.now
    let duration = end - start

    if printDuration {
      let perIteration = duration / iterations
      print("Duration: \(duration) (\(perIteration) per iteration)")
    }
  }
}
