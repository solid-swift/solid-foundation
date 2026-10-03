# Tempo Date/Time Formatting and Parsing

Part of the [SolidCoding design set](2026-09-30-solid-coding-design.md).

## Goal

`SolidTempo` should have a complete date/time formatting and parsing library, comparable in scope
to `java.time.format`, and native to Swift:

- **Custom formats** written with **string interpolation**, type-checked against what the value
  being formatted can provide.
- **Predefined formats** for every standard representation: the ISO 8601 family, RFC 3339,
  RFC 9557, HTTP-date, RFC 5322, epoch numbers, and durations. Each is complete against its
  standard.
- **UTS #35 pattern strings** (`yyyy-MM-dd'T'HH:mm`) for interoperability with ICU, Foundation,
  and Java-style configuration.
- **Many on decode, one on encode.** Accept several variants when parsing; always write one
  preferred form.
- **Bridging** to Swift and Apple standards:
  - Tempo formats are Foundation `FormatStyle`/`ParseStrategy`s and Swift `Regex` components.
  - Foundation's formatters (including localized and relative ones) accept Tempo values.
  - Localized text and patterns come from Foundation (ICU) instead of bundled CLDR data.
- **Precision and range.** Formatting and parsing never lose nanoseconds or narrow the year
  range, unless a format explicitly delegates to Foundation.

Today parsing returns an `Optional` with no diagnostics, and formatting is only `description`.
`LocalDateTime.description` joins date and time with a space, so `OffsetDateTime.description` is
neither RFC 3339 nor something `parse` accepts.

### Non-goals (for now)

- **Non-Gregorian calendars.** Tempo has only `GregorianCalendarSystem`. Fields read through the
  value's `CalendarSystem`, so other calendars plug in later without format changes.
- **Bundled CLDR data.** Localization comes from Foundation, which uses ICU on every platform.
- **Relative and interval formatting** ("3 days ago", "Oct 1 – 3"). Provided only by bridging to
  Foundation's styles.

## Concepts

| Concept | Role |
| --- | --- |
| `DateTimeFormat<Subject>` | A compiled, immutable, `Sendable` program of elements: literals, fields, optional sections, alternatives. It formats a `Subject` and parses into one. |
| Subject capability protocols | `DateFieldProviding`, `TimeFieldProviding`, `OffsetFieldProviding`, `ZoneFieldProviding`. They decide which fields a format for that subject may use, checked at compile time. |
| `ParsedFields` | The raw field values a parse produced, before resolution. |
| `Resolver` | Turns `ParsedFields` into a subject: validation, cross-field checks, defaults, zone resolution. |
| `DateTimeCodec<Subject>` | One primary format for encoding plus ordered alternative formats accepted when decoding. |
| `DateTimeTextProvider` | Month, weekday, era, and day-period names: a fixed POSIX English set, or localized through Foundation. |

### Subjects

| Subject | Date | Time | Offset | Zone |
| --- | --- | --- | --- | --- |
| `LocalDate` | ✓ | | | |
| `LocalTime` | | ✓ | | |
| `LocalDateTime` | ✓ | ✓ | | |
| `OffsetTime` | | ✓ | ✓ | |
| `OffsetDateTime` | ✓ | ✓ | ✓ | |
| `ZonedDateTime` | ✓ | ✓ | ✓ | ✓ |
| `Instant` | ✓ | ✓ | ✓ | ✓ (formatted in a zone; UTC unless `.in(zone)`) |

Formatting reads fields through typed accessors on these protocols, not through the existential
`ComponentContainer` API. Field ranges and identities come from Tempo's existing component kinds
(`DateComponentKind`, `TimeComponent`, …), so formats and components share one vocabulary.

## Defining Formats

### String interpolation

`DateTimeFormat` is `ExpressibleByStringInterpolation`.
- Literal segments become literals.
- Interpolations take **field values**, or nested formats for optional and alternative sections.
- Field interpolations are declared in constrained extensions. A field the subject can't provide
  is a compile error, because the interpolation overload doesn't exist:

```swift
let us: DateTimeFormat<LocalDate> = "\(.twoDigitMonth)/\(.twoDigitDay)/\(.year)"

let stamp: DateTimeFormat<OffsetDateTime> = """
  \(.year)-\(.twoDigitMonth)-\(.twoDigitDay)T\(.twoDigitHour):\(.twoDigitMinute)\
  \(optional: ":\(.twoDigitSecond)\(optional: ".\(.fraction(digits: 1...9))")")\
  \(.offset(.isoExtended, utc: "Z"))
  """

let log: DateTimeFormat<ZonedDateTime> =
  "\(.weekdayName(.abbreviated)) \(.monthName(.abbreviated)) \(.day(.padded(2, with: " "))) \
  \(.twoDigitHour):\(.twoDigitMinute):\(.twoDigitSecond) \(.zoneName(.shortStandard)) \(.year)"

let bad: DateTimeFormat<LocalTime> = "\(.year)"      // ❌ compile error: LocalTime provides no date fields
```

```swift
extension DateTimeFormat.StringInterpolation where Subject: DateFieldProviding {
  public mutating func appendInterpolation(_ field: DateField)
}
extension DateTimeFormat.StringInterpolation where Subject: TimeFieldProviding {
  public mutating func appendInterpolation(_ field: TimeField)
}
extension DateTimeFormat.StringInterpolation {
  public mutating func appendInterpolation(optional section: DateTimeFormat<Subject>)
  public mutating func appendInterpolation(oneOf first: DateTimeFormat<Subject>, _ rest: DateTimeFormat<Subject>...)
  public mutating func appendInterpolation(literal text: String, caseSensitive: Bool = true)  // explicit literal options
}
```

- **Optional sections** (`\(optional: …)`). On format, the section is written when every field in
  it has a value: a `nil` fraction or a zero second under `.omitIfZero`. On parse, it is matched if
  present.
- **Alternatives** (`\(oneOf: a, b)`). On format, the first alternative is used. On parse, they are
  tried in order. This handles local variation, such as `T` or a space separator.
- **Formats compose.** `"\(DateTimeFormat<LocalDate>.isoDate)T\(DateTimeFormat<LocalTime>.isoTime)"`
  works, because a date-only or time-only format can be interpolated into a format whose subject
  provides those fields.

### Field catalog

Every field has a short alias for the common styles (`.twoDigitMonth` ≡ `.month(.twoDigits)`).

| Category | Fields | Numeric styles | Text styles |
| --- | --- | --- | --- |
| Era | `.era` | — | `.abbreviated`, `.wide`, `.narrow` |
| Year | `.year`, `.yearOfEra`, `.weekBasedYear` (ISO), `.twoDigitYear(pivot:)` | `.minimal`, `.digits(min:max:)`, `.expanded` (ISO sign + ≥4 digits outside 0000–9999) | — |
| Quarter | `.quarter` | `.minimal` | `.abbreviated`, `.wide` |
| Month | `.month`, `.monthName(_:)` | `.minimal`, `.twoDigits` | `.abbreviated`, `.wide`, `.narrow`; `.standalone` context |
| Week | `.weekOfWeekBasedYear` (ISO), `.weekOfMonth` | `.minimal`, `.twoDigits` | — |
| Day | `.day`, `.dayOfYear` | `.minimal`, `.twoDigits`, `.threeDigits` | — |
| Weekday | `.weekday` (ISO 1–7, Monday = 1), `.localWeekday` (locale first day), `.weekdayName(_:)` | `.minimal` | `.abbreviated`, `.wide`, `.short`, `.narrow`; `.standalone` |
| Day period | `.amPM`, `.dayPeriod` (flexible periods, through Foundation) | — | `.abbreviated`, `.wide`, `.narrow` |
| Hour | `.hour` (0–23), `.hour24` (1–24), `.hour12` (1–12), `.hour11` (0–11) | `.minimal`, `.twoDigits` | — |
| Minute, second | `.minute`, `.second` | `.minimal`, `.twoDigits`, `.omitIfZero` | — |
| Fraction | `.fraction(digits: ClosedRange)` | output: `.exactly(n)`, `.upTo(n)` (trims zeros); input: any count within range, truncate or reject beyond nanoseconds | — |
| Of-day | `.milliOfDay`, `.nanoOfDay` | `.minimal`, `.digits(min:max:)` | — |
| Epoch | `.epochSeconds`, `.epochMillis`, `.epochMicros`, `.epochNanos`, `.epochDays` | signed, `.minimal` | — |
| Offset | `.offset(_:utc:)` | `.isoBasic` (`+HHMM`), `.isoExtended` (`+HH:MM`), `.hoursOnly` (`+HH`), `.withSeconds`, `.localizedGMT` (`GMT+5`), `.localizedGMTLong` (`GMT+05:00`); `utc:` sets the zero-offset text (`Z`, `+00:00`, `GMT`) | — |
| Zone | `.zoneID`, `.zoneName(_:)`, `.genericZoneName(_:)` | — | `.shortStandard`, `.longStandard`, `.shortGeneric`, `.longGeneric` (through Foundation) |
| Padding | `.padded(_ width:, with:)` modifier on any field | | |

- **Numeric fields** take a `SignStyle`: `.negativeOnly` (default), `.always`, `.never`, or
  `.exceedsWidth` (ISO expanded years).
- **Adjacent value parsing** follows `java.time`'s rule. A variable-width numeric field may be
  followed directly by numeric fields only if those are fixed width, so `yyyyMMdd` parses
  unambiguously. Formats that break the rule fail when built for parsing.

### Text and locale

```swift
public protocol DateTimeTextProvider: Sendable {
  func text(for field: TextField, value: Int, style: TextStyle, context: TextContext) -> String
  func parseText(for field: TextField, style: TextStyle, context: TextContext,
                 in input: Substring, caseInsensitive: Bool) -> (value: Int, length: Int)?
}

extension DateTimeTextProvider where Self == POSIXTextProvider {
  public static var posix: Self       // fixed English names; what HTTP-date and RFC 5322 require
}
extension DateTimeTextProvider where Self == FoundationTextProvider {
  public static func localized(_ locale: Locale) -> Self
}
```

- **`.posix`** is built in and has no Foundation dependency. It is the default for every
  predefined wire format, so wire output never varies by locale.
- **`.localized(locale)`** reads names from Foundation:
  - month and weekday names in format and standalone forms, at every width, from
    `Calendar.monthSymbols`, `shortMonthSymbols`, `veryShortMonthSymbols`, `standaloneMonthSymbols`,
    `weekdaySymbols`, and the other symbol arrays;
  - `eraSymbols`/`longEraSymbols`, `amSymbol`/`pmSymbol`, and `quarterSymbols`;
  - zone names from `TimeZone.localizedName(for:locale:)`.

  The tables are built once per locale and cached.
- **Choosing a provider:** `format.text(.localized(.current))`, or set it per call.
- **Parsing localized text** matches the longest name first. Names match case-insensitively by
  default ([Case sensitivity](#case-sensitivity)).

### Pattern strings (UTS #35)

```swift
let f = try DateTimeFormat<OffsetDateTime>(pattern: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
f.pattern                 // "yyyy-MM-dd'T'HH:mm:ss.SSSXXX" (nil if the format has no UTS #35 equivalent)
```

- Implements the [UTS #35 date field symbol table](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table)
  for every field in the catalog. That includes quoting, `''`, and width semantics (`M`/`MM`/`MMM`
  /`MMMM`/`MMMMM`).
- **Optional sections** use `[` `]`, as in `java.time`. That is an extension to UTS #35 and is
  accepted only with `.allowOptionalSections`.
- **Unsupported symbols** (for example `U` cyclic years, `g` modified Julian day) are a
  `PatternError` with the symbol's offset. They are never ignored.
- **`pattern` output** lets formats travel through configuration and the coding vocabulary's
  `dateTimeFormat` keyword (below).

## Predefined Formats

All predefined formats use the `.posix` text provider and are exposed as static members:
`DateTimeFormat<OffsetDateTime>.rfc3339`, and `.rfc3339(...)` for options.

| Format | Standard | Subjects |
| --- | --- | --- |
| `.isoDate`, `.isoTime`, `.isoDateTime`, `.isoOffsetDateTime`, `.isoOffsetTime` | ISO 8601-1:2019 extended | matching types |
| `.isoBasic…` variants (`20261002T153000Z`) | ISO 8601-1:2019 basic | matching types |
| `.isoOrdinalDate` (`2026-275`), `.isoWeekDate` (`2026-W40-5`) | ISO 8601-1:2019 | `LocalDate` and up |
| `.rfc3339(...)` | [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) §5.6, updated by [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) §2 | `OffsetDateTime`, `Instant`, `LocalDate` (`full-date`), `OffsetTime` (`full-time`) |
| `.ixdtf(...)` | [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) | `ZonedDateTime` |
| `.httpDate` | [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) §5.6.7 | `Instant` |
| `.rfc5322` | [RFC 5322](https://www.rfc-editor.org/rfc/rfc5322) §3.3 (email `date-time`) | `OffsetDateTime` |
| `.epoch(units)` | Coding vocabulary `units` (`s`, `ms`, `us`, `ns`, `d`) | `Instant`, `OffsetDateTime` (UTC), `LocalDate` (days) |
| `DurationFormat.iso8601` | ISO 8601-1:2019 durations (RFC 3339 Appendix A grammar) | `PeriodDuration`, `Period`, `Duration` |

Predefined formats are ordinary `DateTimeFormat` values: they can be interpolated into custom
formats and used as codec variants. RFC 3339 and HTTP-date also have hand-written fast paths (see
[Performance](#output-and-performance)), which must produce output identical to their element
programs.

### RFC 3339

- **Case and separator.** Accept lowercase `t` and `z` (§5.6 note). Accepting a space instead of
  `T` is opt-in (`.allowSpaceSeparator`), because §5.6 allows it only "for the sake of
  readability".
- **Fractions.** Any number of fractional digits is accepted. Beyond nanoseconds,
  `.excessPrecision` chooses `.truncate` or `.reject`. Output uses `fractionalDigits`: `.none`,
  `.exactly(n)`, or `.upTo(n)` with trailing zeros trimmed.
- **Leap seconds.** `60` is accepted (§5.7) and reported through the existing rollover mechanism
  (`LocalTime.parseReportingRollover`). `.leapSecond` is `.rollover` (default) or `.reject`.
- **Offsets.** RFC 9557 §2 revises RFC 3339 §4.3. `Z` now carries the "local offset unknown"
  meaning that RFC 3339 gave to `-00:00`, while `+00:00` states that local time is UTC.
  - The parser keeps the distinction in a `ZoneOffset` flag, so it round-trips.
  - `-00:00` is handled as RFC 9557 §2 specifies.
- **Ranges.** Day-of-month is checked against the month and leap year (§5.7). Offsets are limited
  to `±23:59`.

### RFC 9557 (IXDTF)

- **Time zone suffix.** `[Zone/ID]` or `[+hh:mm]`. A `!` prefix marks it critical.
- **Offset vs. zone.** If both are present and disagree, the `ResolutionStrategy` decides:
  `.reject`, `.preferOffset`, or `.preferZone`. This mirrors the Temporal proposal's `offset`
  option.
- **Tagged suffixes.** `[key=value]` tags such as `u-ca=` are parsed and preserved. Unknown tags
  are kept unless marked critical (`!`), in which case they are rejected, as the RFC requires.
  Calendars other than `iso8601` are rejected until Tempo supports them.
- **Formatting** writes the offset and the bracketed zone:
  `2026-10-02T09:00:00-07:00[America/Los_Angeles]`.
  - This is the **default format for `ZonedDateTime`**, used by its `description` and by
    `format: zoned-date-time` in the coding vocabulary.
  - Keeping the offset makes the value robust against zone database changes, as RFC 9557
    recommends. Keeping the zone preserves the region for later arithmetic.
  - `.omitOffset` (zone only) and the plain RFC 3339 form (offset only) are explicit opt-outs.

### HTTP-date (RFC 9110 §5.6.7)

`.httpDate` is a codec: IMF-fixdate is primary, and RFC 850 and asctime are accepted.

- **Generation.** Only IMF-fixdate: `Sun, 06 Nov 1994 08:49:37 GMT`. Always GMT, two-digit day.
- **Parsing.** All three forms:
  - IMF-fixdate
  - obsolete RFC 850 (`Sunday, 06-Nov-94 08:49:37 GMT`)
  - asctime (`Sun Nov  6 08:49:37 1994`)
- **RFC 850 two-digit years.** A year that would be more than 50 years in the future is taken as
  the most recent past year with the same last two digits, as §5.6.7 requires, relative to a
  `Clock` the caller can inject.
- **Leniency.** Day-name and date mismatches are accepted on parse, as the spec recommends.
- **Case.** HTTP-date is case-sensitive (§5.6.7), so `.httpDate` matches literals and names
  exactly. `.httpDate(.cacheLenient)` matches case-insensitively, as the HTTP caching spec allows
  cache recipients to do.

### RFC 5322 date-time

- **Output:** `Thu, 1 Oct 2026 09:00:00 -0700`. The day-of-week is included, and the offset is
  numeric.
- **Parsing:**
  - optional day-of-week and seconds;
  - CFWS (comments and folding whitespace);
  - obsolete forms (§4.3): two- and three-digit years, and alphabetic zones (`UT`, `GMT`, US zones,
    and military zones, which are treated as `-0000` per §4.3);
  - case-insensitive literals and names, since header field text in RFC 5322 is case-insensitive.

### Durations (ISO 8601)

- **Grammar.** Full `PnYnMnDTnHnMnS` and `PnW`, with fractional seconds; the fractional part is
  only on the smallest unit. A sign prefix (`-P1D`) is accepted as an extension and is opt-in.
- **Representations.**
  - `PeriodDuration` keeps the calendar and exact parts separate.
  - `Duration` accepts only exact parts (`PT…`), unless `.allowDays(as: 24h)` is set.
- **Canonical output** omits zero components and always writes at least `PT0S`.
- **Custom duration formats** use the same interpolation style with duration fields:
  `"\(.hours):\(.twoDigitMinutes):\(.twoDigitSeconds)"`. Fields are `.days`, `.hours`, `.minutes`,
  `.seconds`, `.fraction`; the largest field present is unbounded, the rest are modular.

### Epoch units

- **Range.** Conversions use `Int128` nanoseconds (Tempo's `Duration`) and throw on overflow, never
  wrap.
- **Fractions.** A `number` (not `integer`) shape with fractional seconds is accepted when the
  schema type allows `number`. The fraction is rounded to the nearest nanosecond, half to even.
- **CBOR tags.** Tag 1 is integer or float seconds. Tag 0 is an RFC 3339 string. Tag 100 is epoch
  days. Tag 1004 is an RFC 3339 `full-date`.

## Parsing

```swift
let value = try OffsetDateTime("2026-10-02T09:15:00-07:00", format: .rfc3339)
let (value, rest) = try format.parsePrefix(of: input)          // embedding in larger grammars
let fields = try format.parseFields("…")                       // ParsedFields, unresolved
```

- **Matching.** A whole-string parse must consume all input. `parsePrefix` returns the remainder.
- **Options** (`ParseOptions`, settable on any format):
  - `literalCase`: `.sensitive` (default) or `.insensitive`
  - `textCase`: `.insensitive` (default) or `.sensitive`, for month, weekday, era, and day-period
    names
  - `whitespace`: `.exact` or `.collapse`
  - `twoDigitYearPivot`: a year, or relative to a `Clock`
  - `excessPrecision`
  - `leapSecond`
- **Errors.** `DateTimeParseError` carries:
  - the offset where matching failed;
  - the element that was expected (`"two-digit month"`);
  - the partially parsed fields;
  - for codecs, the variant that got furthest.
- **Resolution** runs after matching:

  | Step | Behaviour |
  | --- | --- |
  | Range checks | Per component kind: month 1–12, day valid for its month and year, and so on |
  | Derived fields | 12-hour clock plus AM/PM gives the hour. Week-based year, week, and weekday give the date. Ordinal day gives the date. Epoch fields give everything. |
  | Cross-checks | A parsed weekday must match the date. A parsed offset and zone must agree (`ResolutionStrategy`). |
  | Defaults | `.defaulting(.time(.midnight))`, `.defaulting(.year(2026))`, … for formats that don't carry every field the subject needs |
  | Zone resolution | Local date/time plus zone use Tempo's existing `ResolutionStrategy` for gaps and overlaps (`nextValid`, `earliest`, `reject`, …) |
  | `ResolverStyle` | `.strict`: everything checked, no defaults unless declared. `.smart` (default): `24:00` → next day, and the HTTP-date day-name leniency. `.lenient`: out-of-range values roll over (month 13 → January next year). |

- **Completeness.** Building a format for parsing checks that its fields (plus declared defaults)
  can produce the subject. `"\(.month)/\(.day)"` cannot parse a `LocalDate` without
  `.defaulting(.year(...))`. The check runs once and throws `DateTimeFormatError.incomplete`. A
  `validate(for: .parsing)` method lets tests run it early.

### Case sensitivity

Literals and names are controlled separately, with different defaults:

| Element | Default | Why |
| --- | --- | --- |
| Literals (`T`, `-`, `GMT`, `'at'`) | **Case-sensitive** | A custom format is explicit, so the text the author wrote is what's matched. |
| Names (months, weekdays, eras, AM/PM) | **Case-insensitive** | People type "oct" and "OCT"; matching names exactly rarely catches a real error. |

- **Per format:** `format.parseOptions(.literalCase(.insensitive))` or
  `.textCase(.sensitive)`.
- **Per literal:** `\(literal: "T", caseSensitive: false)`.
- **Predefined formats follow their standards:**

  | Format | Literals | Names |
  | --- | --- | --- |
  | RFC 3339, ISO 8601 family | `T`/`t` and `Z`/`z` accepted (RFC 3339 §5.6 note) | — |
  | RFC 9557 | as RFC 3339; zone IDs as written (tz database IDs are case-sensitive) | — |
  | HTTP-date | exact (RFC 9110 §5.6.7); `.cacheLenient` relaxes both | exact |
  | RFC 5322 | case-insensitive | case-insensitive |

Other libraries:
- `java.time` is case-sensitive by default with one switch for literals and names, and turns
  case-insensitivity on in its ISO and RFC 1123 formatters.
- Go matches literals exactly and names case-insensitively.
- Python `strptime` and Joda-Time ignore case throughout.

This design follows Go for custom formats and `java.time` for its predefined formats.

## Many on Decode, One on Encode

```swift
let codec = DateTimeCodec<OffsetDateTime>(
  .rfc3339(),                                        // primary: the only form ever written
  accepting: [
    .rfc3339(.allowSpaceSeparator),
    .isoBasicOffsetDateTime,
    "\(.twoDigitMonth)/\(.twoDigitDay)/\(.year) \(.twoDigitHour):\(.twoDigitMinute) \(.offset(.isoBasic))",
  ])

codec.format(value)          // always primary
try codec.parse(text)        // primary first, then each accepted format in order
```

- **Selection.** `.firstMatch` (default) uses the first variant that matches and resolves.
  `.uniqueMatch` tries them all and fails if more than one gives a different value, for inputs
  where ambiguity must be caught.
- **Errors.** When every variant fails, the error reports the variant that got furthest, plus the
  per-variant failures.
- **Two levels of variation:**
  - **Within one format:** `\(oneOf:)` and `\(optional:)` handle small differences such as a
    separator or optional seconds.
  - **Across formats:** a codec handles entirely different shapes.

  Both follow the same rule: format with the first, parse with any.
- **`DateTimeCodec` is itself a `FormatStyle` and `ParseStrategy`**, so it can be used anywhere a
  format can.

### In the coding vocabulary

The schema-driven coding layer uses the same model. Two representation keywords cascade like the
others (see [representations and tags](2026-10-01-representations-and-tags-design.md)):

| Keyword | Value | Meaning |
| --- | --- | --- |
| `dateTimeFormat` | a predefined format name (`"rfc3339"`, `"http-date"`, `"iso8601-basic"`, `"rfc5322"`, …) or `{ "pattern": "<UTS #35>" }` | The primary format for string representations. Default: the format implied by `format` (`date-time` → RFC 3339). |
| `dateTimeAccept` | array of the same | Additional formats accepted on decode, in order |

```json
"updated": {
  "type": "string", "format": "date-time",
  "dateTimeAccept": ["http-date", { "pattern": "yyyy-MM-dd HH:mm:ssXXX" }]
}
```

In Swift: `@Field(.dateTime(.rfc3339(), accepting: [.httpDate, .pattern("yyyy-MM-dd HH:mm:ssXXX")]))`.

## Swift and Apple Integration

### Tempo formats as Foundation and stdlib types

- **Foundation.** `DateTimeFormat<Subject>` and `DateTimeCodec<Subject>` conform to
  `FormatStyle`, `ParseStrategy`, and `ParseableFormatStyle` (`FormatInput == Subject`,
  `FormatOutput == String`). So these all work:
  - `value.formatted(.rfc3339())`
  - `try OffsetDateTime(text, strategy: .rfc3339())`
  - SwiftUI `Text(value, format: .isoDate)` and `TextField(value:format:)`
  - Foundation's `Codable` requirement for `FormatStyle` is met by encoding the element program.
    It is not the UTS #35 pattern, because not every format has one.
- **Regex.** Formats conform to `CustomConsumingRegexComponent`, so they can be used inside Swift
  regexes and capture typed values:

  ```swift
  let line = Regex {
    Capture { DateTimeFormat<OffsetDateTime>.rfc3339() }
    " ["
    Capture { OneOrMore(.word) }
    "] "
  }
  ```

### Foundation formatters for Tempo values

Conversions go through `Date`, `TimeZone`, and `Calendar(identifier: .gregorian)`. They have
explicit, documented limits:
- **Precision.** `Date` is a `Double` of seconds, so sub-microsecond precision is lost for
  present-day dates.
- **Zone data.** Tempo's TZif data and ICU's zone data may be different versions.
- **Range.** Years far outside the common era may not round-trip.

Local types are formatted in a GMT `TimeZone`, so their fields appear exactly as stored.

| Foundation style | Tempo entry point | Use |
| --- | --- | --- |
| `Date.FormatStyle` (`date:time:` and field builder) | `value.formatted(.foundation(.dateTime.year().month(.wide)))` | Localized display |
| `Date.VerbatimFormatStyle` / `Date.FormatString` | `.foundation(verbatim: "…", locale:)` | Localized custom strings |
| `Date.ParseStrategy` | `try OffsetDateTime(text, strategy: .foundation(...))` | Parsing localized input |
| `Date.ISO8601FormatStyle` | (bridged for comparison only) | Tempo's own ISO formats are preferred: exact precision and range |
| `Date.RelativeFormatStyle` | `instant.formatted(.relative(presentation: .named, to: now))` | "3 days ago" |
| `Date.IntervalFormatStyle` | `(start..<end).formatted(.interval...)` on Tempo ranges | "Oct 1 – 3" |
| `Duration.UnitsFormatStyle`, `Duration.TimeFormatStyle` | `duration.formatted(.units(...))`, `.time(pattern:)` | Localized durations, through `Swift.Duration` |

### Localized formats with Tempo's engine

`DateTimeFormat.localized(date:time:locale:)` and `.localized(skeleton: "yMMMd", locale:)` ask
Foundation for the locale's pattern, using `DateFormatter.dateFormat(fromTemplate:options:locale:)`.
The pattern is parsed as UTS #35 and runs on Tempo's engine with the `.localized(locale)` text
provider. The result is fully localized, with no loss of precision or range, and it parses as well
as formats. Delegating the whole operation (`.foundation(...)`) remains available for anything the
skeleton route can't express, such as flexible day periods and relative styles.

### Conversions

| Tempo | Foundation / stdlib | Notes |
| --- | --- | --- |
| `Instant` | `Date` | exists (`Instant(date:)`, `Date(instant:)`) |
| `Duration` | `TimeInterval`, `Swift.Duration` | `TimeInterval` exists; add `Swift.Duration` (exact, attoseconds) |
| `Zone` | `TimeZone` | by identifier; fixed offsets through `TimeZone(secondsFromGMT:)`; fails if the identifier is unknown to ICU |
| `LocalDate`, `LocalTime`, `LocalDateTime` | `DateComponents` | both directions; calendar fixed to Gregorian |
| `ZonedDateTime`, `OffsetDateTime` | `(Date, TimeZone)` | |

### Linux

All bridging uses swift-foundation (`FoundationEssentials`/`FoundationInternationalization`), which
ships with Swift 6 toolchains on Linux. Linux CI covers locale-dependent tests (`en_US`, `fr_FR`,
`ja_JP`) to confirm ICU parity. The Tempo engine and predefined formats don't depend on
internationalization data, so wire formats behave the same on every platform.

## Output and Performance

- **Compiled once.** Formats compile to a flat array of operations when built. Formatting and
  parsing don't allocate beyond the output `String`.
- **Output targets:**
  - `format(_:) -> String`
  - `format(_:into: inout String)`
  - `format(_:into: inout some TextOutputStream)`
  - `write(_:into: inout OutputSpan<UInt8>)`, so SolidCoding writers emit dates straight into
    their byte buffers.
- **Parse input** is `Substring` or UTF-8 bytes (`UTF8Span`). SolidCoding readers parse dates
  directly from `ScalarRef` regions.
- **Hand-written fast paths** for RFC 3339, ISO extended, and IMF-fixdate. They must produce output
  identical to the element program, which property tests enforce.
- **Benchmarks** against `ISO8601DateFormatter`, `Date.ISO8601FormatStyle`, and `DateFormatter`
  with a fixed pattern. Target: RFC 3339 format and parse at least 3× faster than
  `Date.ISO8601FormatStyle`.

## Type-Level API Changes

- **Initializers and formatting.** Every Tempo type gets `formatted(_:)` (via `FormatStyle`),
  `init(_:format:)`, and `init(_:strategy:)`. The existing `parse(string:) -> Self?` methods
  remain as thin wrappers over the predefined formats.
- **`description`** becomes the canonical ISO extended form with `T`, so `description` and parsing
  round-trip. This is a behaviour change, so record it in release notes. `Instant.description` is
  RFC 3339 in UTC. `ZonedDateTime.description` is the RFC 9557 form with offset and bracketed zone.
- **Typo fix.** `LocalTime.parseReportingRollver` → `parseReportingRollover`, with a deprecated
  alias.
- **Errors.** `DateTimeParseError`, `DateTimeFormatError` (incomplete or inconsistent format), and
  `PatternError`. All are `Sendable` and carry offsets.

## Testing

- **Standards:** every example in RFC 3339 §5.8, RFC 9557, RFC 9110 §5.6.7, and RFC 5322 §3.3 and
  Appendix A.
- **Tables:** the ISO 8601 week-date and ordinal-date edge cases (week 53, year boundaries).
- **UTS #35 patterns:** the symbol table cases, compared with Foundation's `DateFormatter` output
  for the same pattern, locale `en_US_POSIX`, across a range of values.
- **RFC 9557:** string parsing cases from [test262](https://github.com/tc39/test262) Temporal tests,
  where they apply to the supported calendars.
- **Interpolation:** compile-fail tests for field and subject mismatches, using a test target that
  expects diagnostics.
- **Round trips:** format → parse → equal for every predefined and sample custom format, over random
  values across the full range, including leap days, all offsets, and DST gaps and overlaps.
- **Codecs:** variant ordering, `.uniqueMatch` ambiguity, and furthest-failure reporting.
- **Localization:** names and skeleton patterns for several locales on macOS and Linux.

## Phasing

1. **Engine:** element model, interpolation, the POSIX text provider, parsing and resolution,
   `DateTimeCodec`.
2. **Predefined formats:** RFC 3339, ISO family, HTTP-date, RFC 5322, IXDTF, durations, epoch.
   Fast paths. `description` and typo changes.
3. **Integration:** UTS #35 patterns, `FormatStyle`/`ParseStrategy`/`Regex` conformances,
   Foundation conversions.
4. **Localization:** `FoundationTextProvider`, skeleton-based localized formats, and the
   `.foundation(...)` delegation styles (relative, interval, duration).
5. **Coding:** `dateTimeFormat`/`dateTimeAccept` keywords and the `@Field(.dateTime(...))` options.

## Open Questions

None.
