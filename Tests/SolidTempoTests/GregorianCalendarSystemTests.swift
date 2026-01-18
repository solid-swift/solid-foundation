//
//  GregorianCalendarSystemTests.swift
//  SolidFoundation
//
//  Created by Devin AI on 1/18/26.
//

@testable import SolidTempo
import Testing

@Suite("GregorianCalendarSystem Tests")
struct GregorianCalendarSystemTests {

  @Test("dayOfYear regression test - cumulative days algorithm")
  func testDayOfYearRegression() throws {
    // This test verifies the fix for the dayOfYear calculation.
    // The old algorithm used a March-based formula that was incorrect:
    //   let adjustedMonth = month <= 2 ? month + 12 : month
    //   return (153 * (adjustedMonth - 3) + 2) / 5 + day - 1
    //
    // For March 15, 2024, the old algorithm returned:
    //   adjustedMonth = 3 (no adjustment needed)
    //   (153 * (3 - 3) + 2) / 5 + 15 - 1 = (0 + 2) / 5 + 14 = 0 + 14 = 14  (WRONG!)
    //
    // The correct value is 75 (31 days in Jan + 29 days in Feb + 15 days in Mar)
    //
    // The fix uses cumulative days lookup tables which correctly compute:
    //   cumulativeDays[2] + 15 = 60 + 15 = 75  (CORRECT!)

    let cal = GregorianCalendarSystem.default

    // Test case that exposed the bug: March 15, 2024
    let march15 = try LocalDate(year: 2024, month: 3, day: 15)
    let dayOfYear = cal.dayOfYear(for: march15)
    #expect(dayOfYear == 75, "March 15, 2024 should be day 75 (31 Jan + 29 Feb + 15 Mar)")

    // Verify the old algorithm would have returned 14 (the bug)
    let oldAlgorithmResult = oldDayOfYearAlgorithm(month: 3, day: 15)
    #expect(oldAlgorithmResult == 14, "Old algorithm should return 14 (the bug)")
    #expect(dayOfYear != oldAlgorithmResult, "New algorithm should differ from old buggy algorithm")

    // Additional test cases to ensure correctness across months
    let testCases: [(year: Int, month: Int, day: Int, expected: Int)] = [
      (2024, 1, 1, 1),      // First day of year
      (2024, 1, 31, 31),    // Last day of January
      (2024, 2, 1, 32),     // First day of February
      (2024, 2, 29, 60),    // Last day of February (leap year)
      (2024, 3, 1, 61),     // First day of March (leap year)
      (2024, 6, 15, 167),   // Mid-year
      (2024, 12, 31, 366),  // Last day of leap year
      (2023, 2, 28, 59),    // Last day of February (non-leap year)
      (2023, 3, 1, 60),     // First day of March (non-leap year)
      (2023, 12, 31, 365),  // Last day of non-leap year
    ]

    for (year, month, day, expected) in testCases {
      let date = try LocalDate(year: year, month: month, day: day)
      let result = cal.dayOfYear(for: date)
      #expect(result == expected, "dayOfYear for \(year)-\(month)-\(day) should be \(expected), got \(result)")
    }
  }

  @Test("dayOfYear works for both calendar variants")
  func testDayOfYearBothVariants() throws {
    // dayOfYear should return the same value for both iso8601 and gregorian variants
    // because day-of-year is a fundamental property of the Gregorian calendar
    // that doesn't change based on week numbering conventions.

    let iso8601Cal = GregorianCalendarSystem.iso8601
    let gregorianCal = GregorianCalendarSystem.gregorian

    let testCases: [(year: Int, month: Int, day: Int, expected: Int)] = [
      (2024, 1, 1, 1),
      (2024, 3, 15, 75),
      (2024, 12, 31, 366),
      (2023, 12, 31, 365),
    ]

    for (year, month, day, expected) in testCases {
      let date = try LocalDate(year: year, month: month, day: day)

      let iso8601Result = iso8601Cal.dayOfYear(for: date)
      let gregorianResult = gregorianCal.dayOfYear(for: date)

      #expect(iso8601Result == expected, "iso8601 dayOfYear for \(year)-\(month)-\(day) should be \(expected)")
      #expect(gregorianResult == expected, "gregorian dayOfYear for \(year)-\(month)-\(day) should be \(expected)")
      #expect(iso8601Result == gregorianResult, "Both variants should return the same dayOfYear")
    }
  }

  // Helper function that replicates the old buggy algorithm for comparison
  private func oldDayOfYearAlgorithm(month: Int, day: Int) -> Int {
    let adjustedMonth = month <= 2 ? month + 12 : month
    return (153 * (adjustedMonth - 3) + 2) / 5 + day - 1
  }
}
