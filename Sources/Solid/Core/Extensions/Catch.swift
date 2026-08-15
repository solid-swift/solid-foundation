//
//  Catch.swift
//  SolidFoundation
//
//  Created by Kevin Wooten on 4/17/25.
//

/// Executes a block, returning its value as a `success` result and any caught error as a `failure` result.
///
/// - Parameter block: Closure to execute
/// - Returns: The return value of `block` as a `Result.success` unless an error is thrown, in which
///   case the error is returned as a `Result.faulure`.
///
package func catchThrow<R, E>(block: @autoclosure () throws(E) -> R) -> Result<R, E> {
  do {
    return .success(try block())
  } catch {
    return .failure(error)
  }
}

/// Asserts that a function never throws and maps any thrown errors to `fatalError`.
///
/// This function is for calls that are known to always succeed but would otherwise
/// require a `do {...} catch {...}` block or use of `try?` (which causes the
/// result to be unconditionally optional), adding unnecessary complexity to what would
/// be simple statements. E.g., calling global and/or static initializers with known valid
/// parameters.
///
/// - Important: The result of using `neverThrow` on statements that are
/// susceptible to runtime errors, is a `fatalError`,  terminating the program. This
/// is not a substitute for proper error handling. Additionally, failures leak information
/// about the source file and line number, which may be useful for debugging, but
/// should not be presented to end users.
///
/// - Parameters:
///   - block: The block to execute.
///   - file: The file in which the call to `neverThrow` was made.
///   - line: The line number on which the call to `neverThrow` was made.
/// - Returns: The result of the block.
///
public func neverThrow<T>(
  _ block: @autoclosure () throws -> T,
  _ file: StaticString = #file,
  _ line: UInt = #line
) -> T {
  return neverThrow("A block asserted to never throw an error, threw an error.", try block(), file, line)
}

/// Asserts that a function never throws and maps any thrown errors to `fatalError`
/// with a custom message.
///
/// This function is for calls that are known to always succeed but would otherwise
/// require a `do {...} catch {...}` block or use of `try?` (which causes the
/// result to be unconditionally optional), adding unnecessary complexity to what would
/// be simple statements. E.g., calling global and/or static initializers with known valid
/// parameters.
///
/// - Important: The result of using `neverThrow` on statements that are
/// susceptible to runtime errors, is a `fatalError`,  terminating the program. This
/// is not a substitute for proper error handling. Additionally, failures leak information
/// about the source file and line number, which may be useful for debugging, but
/// should not be presented to end users.
///
/// - Parameters:
///   - message: The message to display when the block throws an error.
///   - block: The block to execute.
///   - file: The file in which the call to `neverThrow` was made.
///   - line: The line number on which the call to `neverThrow` was made.
/// - Returns: The result of the block.
///
public func neverThrow<T>(
  _ message: String,
  _ block: @autoclosure () throws -> T,
  _ file: StaticString = #file,
  _ line: UInt = #line
) -> T {
  do {
    return try block()
  } catch {
    fatalError("\(message):\n\(error)", file: file, line: line)
  }
}
