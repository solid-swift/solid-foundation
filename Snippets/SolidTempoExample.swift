import SolidTempo

// snippet.hide
func tempoExample() throws {
  // snippet.show
  // Get the current time in a specific timezone
  let now = try ZonedDateTime.now()
  let tokyo = try now.at(zone: Zone(identifier: "Asia/Tokyo"))

  // Create specific dates and times
  let meeting = try ZonedDateTime(
      year: 2026, month: 3, day: 15,
      hour: 14, minute: 30, second: 0, nanosecond: 0,
      zone: Zone(identifier: "America/New_York")
  )

  // Duration arithmetic that makes sense
  let duration = Duration.hours(2) + Duration.minutes(30)
  let later = Instant.now() + duration
  // snippet.hide
  _ = (tokyo, meeting, later)
}
// snippet.show
