# Tempo Wire Formats

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

`SolidTempo` should parse and format every date/time representation the coding vocabulary can
select. Each must be complete against its standard, round-trip exactly, and report precise errors.
Today parsing returns an `Optional` with no diagnostics, and formatting is only `description`.
`LocalDateTime.description` joins date and time with a space, so `OffsetDateTime.description` is
neither RFC 3339 nor something `parse` accepts.

| Representation | Standard | Types |
| --- | --- | --- |
| Internet date/time | [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) §5.6, as updated by [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) §2 | `OffsetDateTime`, `Instant`, `LocalDate`, `OffsetTime` |
| Date/time with suffix tags | [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) (IXDTF) | `ZonedDateTime` |
| Local forms | ISO 8601-1:2019 extended format, RFC 3339 profile without offset | `LocalDateTime`, `LocalTime` |
| Durations | ISO 8601-1:2019 durations (RFC 3339 Appendix A grammar) | `PeriodDuration`, `Period`, `Duration` |
| HTTP-date | [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) §5.6.7 | `Instant` |
| Epoch numbers | Coding vocabulary `units`: `s`, `ms`, `us`, `ns`, `d` | `Instant`, `OffsetDateTime` (UTC), `LocalDate` (days) |
| CBOR tags | [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) §3.4.1–3.4.2 (tags 0 and 1); [RFC 8943](https://www.rfc-editor.org/rfc/rfc8943) (tags 100 and 1004) | as above |

## API

Each format is a `FormatStyle`/`ParseStrategy` pair for discoverability, plus direct initializers.
`SolidNumeric` already uses `FormatStyle` (`DecimalFormatStyle`), so this follows existing practice.

```swift
let text = dateTime.formatted(.rfc3339(fractionalDigits: .upTo(9)))
let parsed = try OffsetDateTime(rfc3339: text)
let zoned = try ZonedDateTime(ixdtf: "2026-10-01T09:00:00-07:00[America/Los_Angeles]")
let http = instant.formatted(.httpDate)                       // "Thu, 01 Oct 2026 16:00:00 GMT"
let when = try Instant(httpDate: "Thursday, 01-Oct-26 16:00:00 GMT")
let epoch = try Instant(epoch: 1_790_000_000_123, units: .milliseconds)
let ms: Int64 = try instant.epoch(in: .milliseconds)          // throws on overflow
```

- Parsing throws `TempoParseError` with the character offset and the expected production. The
  existing `parse(string:) -> Self?` methods stay as thin wrappers.
- `description` becomes the canonical extended ISO form with `T`, matching the RFC 3339 output, so
  `description` and parsing round-trip. This is a behaviour change, so record it in release notes.
- Fix the typo `LocalTime.parseReportingRollver` → `parseReportingRollover`. Keep a deprecated
  alias.

## RFC 3339 Details

- **Case and separator.** Accept lowercase `t` and `z` (§5.6 note). Accepting a space instead of
  `T` is opt-in (`.allowSpaceSeparator`), because §5.6 allows it only "for the sake of
  readability".
- **Fractions.** Any number of fractional digits is accepted. Beyond nanoseconds, the
  `ParseStrategy` option chooses truncation or an error. Output uses `.fractionalDigits`:
  `.none`, `.exactly(n)`, or `.upTo(n)` with trailing zeros trimmed.
- **Leap seconds.** `60` is accepted (§5.7) and reported through the existing rollover mechanism
  (`LocalTime.parseReportingRollover`). The strategy option `.leapSecond` is `.rollover` (default)
  or `.reject`.
- **Offsets.** RFC 9557 §2 revises RFC 3339 §4.3. `Z` now carries the "local offset unknown"
  meaning that RFC 3339 gave to `-00:00`, while `+00:00` states that local time is UTC.
  - The parser keeps the distinction in a `ZoneOffset` flag, so it round-trips.
  - `-00:00` is handled as RFC 9557 §2 specifies.
- **Ranges.** Day-of-month is checked against the month and leap year (§5.7). Offsets are limited
  to `±23:59`.

## RFC 9557 (IXDTF)

- **Time zone suffix.** `[Zone/ID]` or `[+hh:mm]`. A `!` prefix marks it critical.
- **Offset vs. zone.** If both are present and disagree, the `ResolutionStrategy` decides:
  `.reject`, `.preferOffset`, or `.preferZone`. This mirrors the Temporal proposal's `offset` option.
- **Tagged suffixes.** `[key=value]` tags such as `u-ca=` are parsed and preserved. Unknown tags
  are kept unless marked critical (`!`), in which case they are rejected, as the RFC requires.
  Calendars other than `iso8601` are rejected until Tempo supports them.
- **Formatting** writes the zone suffix, and the offset unless told to omit it.

## Durations (ISO 8601)

- **Grammar.** Full `PnYnMnDTnHnMnS` and `PnW`, with fractional seconds; the fractional part is
  only on the smallest unit. A sign prefix (`-P1D`) is accepted as an extension and is opt-in.
- **Representations.**
  - `PeriodDuration` keeps the calendar and exact parts separate.
  - `Duration` accepts only exact parts (`PT…`), unless `.allowDays(as: 24h)` is set.
- **Canonical output** omits zero components and always writes at least `PT0S`.

## HTTP-date (RFC 9110 §5.6.7)

- **Generation.** Only IMF-fixdate: `Sun, 06 Nov 1994 08:49:37 GMT`. Always GMT, two-digit day.
- **Parsing.** All three forms:
  - IMF-fixdate
  - obsolete RFC 850 (`Sunday, 06-Nov-94 08:49:37 GMT`)
  - asctime (`Sun Nov  6 08:49:37 1994`)
- **RFC 850 two-digit years.** A year that would be more than 50 years in the future is taken as
  the most recent past year with the same last two digits, as §5.6.7 requires, relative to a
  `Clock` the caller can inject.
- **Leniency.** Day-name and date mismatches are accepted on parse, as the spec recommends.

## Epoch Units

- **Units.** `s`, `ms`, `us`, `ns`, and `d` (days, for `LocalDate`).
- **Range.** Conversions use `Int128` nanoseconds (Tempo's `Duration`) and throw on overflow, never
  wrap.
- **Fractions.** A `number` (not `integer`) shape with fractional seconds is accepted when the
  schema type allows `number`. The fraction is rounded to the nearest nanosecond, half to even.
- **CBOR tag 1.** Integer or float seconds. **Tag 0** is an RFC 3339 string. **Tag 100** is epoch
  days. **Tag 1004** is an RFC 3339 `full-date`.

## Testing

- Every example in RFC 3339 §5.8, RFC 9557, and RFC 9110 §5.6.7.
- The RFC 9557 string parsing cases from [test262](https://github.com/tc39/test262) Temporal tests,
  where they apply to the supported calendars.
- Round-trip property tests: format → parse → equal, for random values across the full range,
  including leap days and all offsets.

## Open Questions

1. Should `ZonedDateTime` formatting default to including the offset? RFC 9557 recommends it for
   robustness against zone database changes.
2. Should `Instant` get its own `description` (RFC 3339 `Z`) or keep printing the raw duration?
