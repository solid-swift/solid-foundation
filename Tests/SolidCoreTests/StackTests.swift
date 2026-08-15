//
//  StackTests.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 8/15/26.
//

import SolidCore
import Testing

@Suite
struct StackTests {

  @Test
  func `initial elements are ordered top to bottom`() {
    let stack: Stack = [1, 2, 3]

    #expect(stack.peek() == 1)
    #expect(stack.depth == 3)
    #expect(Array(stack) == [1, 2, 3])
    #expect(Array(stack[stack.startIndex..<stack.endIndex]) == [1, 2, 3])
  }

  @Test
  func `push and pop operate at the top`() {
    var stack: Stack = [2, 3]

    stack.push(1)

    #expect(stack.pop() == 1)
    #expect(stack.pop(2) == [2, 3])
    #expect(stack.isEmpty)
  }

  @Test
  func `pushing a sequence preserves its order`() {
    var stack: Stack = [4]

    stack.push(contentsOf: [1, 2, 3])

    #expect(Array(stack) == [1, 2, 3, 4])
    #expect(stack.pop(3) == [1, 2, 3])
    #expect(stack.peek() == 4)
  }

  @Test
  func `collection indices address top first`() {
    let stack: Stack = [10, 20, 30]
    let second = stack.index(after: stack.startIndex)
    let last = stack.index(stack.endIndex, offsetBy: -1)

    #expect(stack[stack.startIndex] == 10)
    #expect(stack[second] == 20)
    #expect(stack[last] == 30)
  }

  @Test
  func `pop all clears the stack`() {
    var stack: Stack = [1, 2, 3]

    stack.popAll()

    #expect(stack.isEmpty)
    #expect(stack.depth == 0)
  }
}
