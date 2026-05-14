//
//  ContainerStackTests.swift
//  SolidFoundation
//
//  Created by Codex on 4/27/26.
//

import SolidData
import Testing


@Suite("ContainerStack Tests")
struct ContainerStackTests {

  @Test("ContainerStack handles deep nesting")
  func deepNesting() throws {
    var stack = ContainerStack(reservingCapacity: 128)

    for _ in 0..<128 {
      stack.pushArray(count: nil)
    }

    #expect(stack.count == 128)

    for _ in 0..<128 {
      _ = try stack.pop()
    }

    #expect(stack.isEmpty)
  }

  @Test("Object alternates between key and value positions")
  func objectKeyValueAlternation() throws {
    var stack = ContainerStack()
    stack.pushObject(count: nil)

    #expect(stack.isExpectingObjectKey)
    #expect(!stack.isExpectingObjectValue)
    #expect(stack.canAcceptValue(isKey: true))
    #expect(!stack.canAcceptValue(isKey: false))

    stack.didFinishScalarValue()

    #expect(!stack.isExpectingObjectKey)
    #expect(stack.isExpectingObjectValue)
    #expect(!stack.canAcceptValue(isKey: true))
    #expect(stack.canAcceptValue(isKey: false))

    stack.didFinishScalarValue()

    #expect(stack.isExpectingObjectKey)
    #expect(!stack.isExpectingObjectValue)
  }

  @Test("Definite containers report completion only at legal boundaries")
  func definiteContainerCompletion() {
    var arrayStack = ContainerStack()
    arrayStack.pushArray(count: 2)
    #expect(arrayStack.completedDefiniteContainer == nil)

    arrayStack.didFinishScalarValue()
    #expect(arrayStack.completedDefiniteContainer == nil)

    arrayStack.didFinishScalarValue()
    #expect(arrayStack.completedDefiniteContainer == .array(remaining: 0))

    var objectStack = ContainerStack()
    objectStack.pushObject(count: 1)
    #expect(objectStack.completedDefiniteContainer == nil)

    objectStack.didFinishScalarValue()
    #expect(objectStack.completedDefiniteContainer == nil)

    objectStack.didFinishScalarValue()
    #expect(objectStack.completedDefiniteContainer == .object(remaining: 0, expectingKey: true))
  }

  @Test("Break eligibility follows indefinite container boundaries")
  func breakEligibility() {
    var stack = ContainerStack()
    #expect(!stack.canConsumeBreak)

    stack.pushArray(count: nil)
    #expect(stack.canConsumeBreak)

    stack.pushObject(count: nil)
    #expect(stack.canConsumeBreak)

    stack.didFinishScalarValue()
    #expect(!stack.canConsumeBreak)

    stack.didFinishScalarValue()
    #expect(stack.canConsumeBreak)
  }

  @Test("Invalid value positions are rejected")
  func invalidValuePositions() {
    var stack = ContainerStack()

    #expect(!stack.canAcceptValue(isKey: true))
    #expect(stack.canAcceptValue(isKey: false))
    #expect(throws: ContainerStackError.invalidValuePosition) {
      try stack.validateCanAcceptValue(isKey: true)
    }

    stack.pushArray(count: 0)
    #expect(!stack.canAcceptValue(isKey: false))
    #expect(!stack.canAcceptValue(isKey: true))
    #expect(throws: ContainerStackError.invalidValuePosition) {
      try stack.validateCanAcceptValue(isKey: false)
    }
  }

  @Test("Unbalanced pop throws")
  func unbalancedPopThrows() {
    var stack = ContainerStack()

    #expect(throws: ContainerStackError.unbalancedEnd) {
      _ = try stack.pop()
    }
  }

  @Test("Explicit capacity stack remains reusable after becoming empty")
  func explicitCapacityStackRemainsReusable() throws {
    var stack = ContainerStack(reservingCapacity: 1)

    stack.pushArray(count: nil)
    _ = try stack.pop()
    #expect(stack.isEmpty)

    stack.pushObject(count: nil)
    #expect(stack.current == .object(remaining: nil, expectingKey: true))
    _ = try stack.pop()
    #expect(stack.isEmpty)
  }
}
