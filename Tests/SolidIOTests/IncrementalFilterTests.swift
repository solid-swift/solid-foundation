//
//  IncrementalFilterTests.swift
//  SolidIOTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
import Synchronization
@testable import SolidIO
import Testing

@Suite
struct IncrementalFilterTests {

  @Test
  func existingFilterAdapterStopsAtEndOfData() throws {
    let filter = SentinelFilter()

    let output = try filter.process(data: Data("one!trailing".utf8))

    #expect(output == Data("ONE".utf8))
    #expect(filter.trailingInput == Data("trailing".utf8))
  }

  @Test
  func sharedCodecSerializesConcurrentCalls() async throws {
    let filter = ASCIIHexEncoder()

    let consumed = try await withThrowingTaskGroup(of: Int.self, returning: Int.self) { group in
      for value in UInt8(0)..<64 {
        group.addTask {
          let result = try filter.process(input: Data(repeating: value, count: 16))
          #expect(result.progress == .needsInput)
          return result.consumedInput
        }
      }

      var total = 0
      for try await count in group {
        total += count
      }
      return total
    }

    #expect(consumed == 1_024)
    #expect(try filter.finish() == Data([0x3E]))
  }

}

private final class SentinelFilter: IncrementalFilter {

  private let state = Mutex(Data())

  var trailingInput: Data {
    state.withLock { $0 }
  }

  func process(input: Data) throws -> IncrementalFilterResult {
    guard let marker = input.firstIndex(of: Character("!").asciiValue!) else {
      return IncrementalFilterResult(
        output: Data(input.map { byte in
          byte >= 97 && byte <= 122 ? byte - 32 : byte
        }),
        consumedInput: input.count,
        progress: .needsInput
      )
    }

    state.withLock { $0 = input.suffix(from: input.index(after: marker)) }
    return IncrementalFilterResult(
      output: Data(input[..<marker].map { byte in
        byte >= 97 && byte <= 122 ? byte - 32 : byte
      }),
      consumedInput: input.distance(from: input.startIndex, to: input.index(after: marker)),
      progress: .finished
    )
  }

  func finish() throws -> Data? {
    nil
  }

}
