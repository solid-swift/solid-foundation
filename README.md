# Solid Foundation

**All the boring parts, no dependency roulette!**

Solid Foundation is a comprehensive Swift library that provides production-grade implementations of foundational data structures, utilities, and domain-specific systems. It's the bedrock you build on when you're tired of wondering whether that random GitHub package from 2019 still works with Swift 6.

## Overview

We've all been there: you need arbitrary-precision math, proper timezone handling, or JSON Schema validation, and suddenly you're juggling five different packages from five different maintainers with five different release schedules (and one of them hasn't been updated since the Obama administration). Solid Foundation consolidates these essential building blocks into a single, well-maintained package that we actually care about keeping up to date.

This isn't a framework that tries to do everything. It's the foundation that lets you build the things that do everything. Think of it as the concrete slab your house sits on: not glamorous, but you'd notice pretty quickly if it wasn't there.

## Modules

| Module | Description |
|--------|-------------|
| [SolidCore](#solidcore) | Collections, encodings, logging, synchronization, and parsing utilities |
| [SolidNumeric](#solidnumeric) | Arbitrary-precision integers and decimals, heavily optimized |
| [SolidTempo](#solidtempo) | Date, time, and timezone handling inspired by Java Time and JS Temporal |
| [SolidIO](#solidio) | Async I/O streams with compression, hashing, and network support |
| [SolidData](#soliddata) | Universal value representation powering formats and schema validation |
| [SolidJSON](#solidjson) | JSON serialization and deserialization |
| [SolidCBOR](#solidcbor) | CBOR binary format, the IETF standard behind CWT and COSE |
| [SolidSchema](#solidschema) | JSON Schema validation for any format, not just JSON |
| [SolidURI](#soliduri) | RFC 3986 URI and IRI parsing, resolution, and manipulation |
| [SolidNet](#solidnet) | Email, hostname, and IP address parsing with IDN support |
| [SolidID](#solidid) | Unique identifiers from local counters to global UUIDs |

## Getting Started

### Swift Package Manager

Add Solid Foundation to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/solid-swift/solid-foundation.git", from: "1.0.0")
]
```

Then add the modules you need to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Solid", package: "solid-foundation"),      // Everything
        // Or pick what you need:
        .product(name: "SolidNumeric", package: "solid-foundation"),
        .product(name: "SolidTempo", package: "solid-foundation"),
        .product(name: "SolidSchema", package: "solid-foundation"),
    ]
)
```

The `Solid` module re-exports all other modules, so you can import everything at once if you're feeling adventurous.

## Requirements

- Swift 6.2+
- macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, or Linux

## Module Overviews

### SolidCore

The foundation of the foundation. SolidCore provides the building blocks that other modules depend on: collections, base encodings, logging, synchronization primitives, and parsing utilities.

```swift
import SolidCore

// Base encodings for all your encoding needs
let data = "Hello, World!".data(using: .utf8)!
let base64 = BaseEncoding.base64.encode(data: data)
let base32 = BaseEncoding.base32.encode(data: data)

// Thread-safe logging with privacy controls
let log = LogFactory.for(category: "MyApp")
log.info("Application started")
log.debug("User ID: \(userId, privacy: .sensitive)")
```

**Standout Features:**

The logging system integrates with both OSLog (on Apple platforms) and swift-log (on Linux), with built-in privacy controls that can redact or obscure sensitive data based on environment configuration.

---

### SolidNumeric

Arbitrary-precision arithmetic that doesn't care how big your numbers get. `BigInt`, `BigUInt`, and `BigDecimal` implement all the standard Swift numeric protocols, so they work exactly like you'd expect.

```swift
import SolidNumeric

// Arbitrary-precision integers
let bigNumber: BigInt = 123456789012345678901234567890
let doubled = bigNumber * 2
let factorial = (1...100).reduce(BigInt.one) { $0 * BigInt($1) }

// Arbitrary-precision decimals for when Float64 isn't precise enough
let price = BigDecimal("19.99")!
let taxRate = BigDecimal("0.0825")!
let total = price * (BigDecimal.one + taxRate)
print(total.rounded(.toNearestOrAwayFromZero, places: 2)) // 21.64
```

**Standout Features:**

`BigDecimal` handles all the edge cases that make financial calculations terrifying: proper rounding modes, scale management, and no floating-point surprises. The entire module is heavily optimized and benchmarked for performance, so you're not trading correctness for speed.

---

### SolidTempo

Date and time handling that doesn't make you want to flip a table. Built in the style of Java Time and JS Temporal (why reinvent good API design?), with full IANA timezone database support, proper DST handling, and a type system that prevents you from accidentally comparing a `LocalDateTime` to a `ZonedDateTime`.

```swift
import SolidTempo

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
```

**Standout Features:**

Like its progenitors, SolidTempo provides dedicated types for every temporal scenario: `Instant` for absolute moments, `ZonedDateTime` for wall-clock time in a timezone, `LocalDateTime` for timezone-agnostic timestamps, `LocalDate` and `LocalTime` for date-only or time-only values, plus `Duration` and `Period` for time-based and calendar-based intervals. This makes it ideal for client/server API contracts where precise semantics matter.

The `ResolutionStrategy` system even handles DST transition edge cases, letting you choose how to resolve ambiguous or non-existent local times.

---

### SolidIO

Async I/O streams built on Swift concurrency. Read from files, write to networks, pipe data through compression filters, and never think about buffer management again.

```swift
import SolidIO

// Read a file asynchronously
let source = try FileSource(path: "/path/to/file.txt")
for try await chunk in source.buffers() {
    // Process each chunk
}

// Pipe data with compression
let input = try FileSource(path: "/path/to/input.txt")
let output = try FileSink(path: "/path/to/output.gz")
try await input.compressing(algorithm: .zlib).pipe(to: output)
```

**Standout Features:**

The filter system lets you chain transformations: compress, hash, encrypt, all in a single pipeline without intermediate buffers eating your memory.

---

### SolidData

The building block for SolidSchema and format modules like SolidJSON and SolidCBOR. The universal `Value` type can represent any structured data and serves as the interchange format between serialization and validation.

```swift
import SolidData

// Values work like you'd expect
let user: Value = [
    "name": "Alice",
    "age": 30,
    "active": true,
    "tags": ["admin", "verified"]
]

// Access nested data
if let name = user["name"]?.string {
    print("Hello, \(name)")
}

// Numbers preserve precision
let precise: Value = .number(BigDecimal("123.456789012345678901234567890")!)
```

**Standout Features:**

`Value` natively handles binary data for efficient support of binary formats like CBOR, and it preserves the original representation of data (e.g., JSON numbers stay as strings until you need them as numbers). This means no precision loss and no surprises when round-tripping data.

---

### SolidJSON

JSON serialization that plays nicely with the `Value` type. Nothing fancy, just JSON that works.

```swift
import SolidJSON
import SolidData

// Parse JSON to Value
let json = """
{"name": "Bob", "scores": [95, 87, 92]}
"""
let reader = JSONValueReader(data: json.data(using: .utf8)!)
let value = try reader.read()

// Write Value to JSON
var output = Data()
let writer = JSONValueWriter(output: &output)
try writer.write(value)
```

---

### SolidCBOR

CBOR (Concise Binary Object Representation) is an IETF standard that can losslessly represent both JSON and YAML in a compact binary format. It's the foundation for other IETF standards like CWT (CBOR Web Tokens) and COSE (CBOR Object Signing and Encryption).

```swift
import SolidCBOR
import SolidData

// Encode to CBOR
let value: Value = ["temperature": 23.5, "humidity": 65]
var output = Data()
let writer = CBORWriter(output: &output)
try writer.write(value)

// Decode from CBOR
let reader = CBORReader(data: output)
let decoded = try reader.read()
```

---

### SolidSchema

JSON Schema validation that works with any format, not just JSON. Built on SolidData, it can validate data from JSON, CBOR, or any other source that produces `Value` instances.

```swift
import SolidSchema
import SolidData

// Build a schema
let schema = Schema.Builder.build(constant: [
    "type": "object",
    "properties": [
        "name": ["type": "string", "minLength": 1],
        "age": ["type": "integer", "minimum": 0],
        "email": ["type": "string", "format": "email"]
    ],
    "required": ["name", "email"]
])

// Validate data
let userData: Value = [
    "name": "Alice",
    "age": 30,
    "email": "alice@example.com"
]

let result = try schema.validate(instance: userData)
if result.isValid {
    print("Data is valid!")
} else {
    print("Validation errors: \(result.errors)")
}
```

**Standout Features:**

Because it validates `Value` instances rather than raw JSON, you can validate CBOR, YAML, or any other format. It also includes a custom 2020-12 vocabulary extension for validating binary `bytes` data. Full vocabulary support including format validation (email, hostname, URI, date-time, etc.), content encoding validation, and proper `$ref` / `$dynamicRef` resolution.

---

### SolidURI

RFC 3986 URI and IRI parsing, resolution, and manipulation. Handle absolute URIs, relative references, internationalized identifiers, and all the edge cases the specs throw at you.

```swift
import SolidURI

// Parse URIs
let uri = URI(encoded: "https://example.com/path?query=value#fragment")!

// Access components
print(uri.scheme)           // "https"
print(uri.authority?.host)  // "example.com"
print(uri.encodedPath)      // "/path"

// Resolve relative references
let base = URI(valid: "https://example.com/a/b/c")
let relative = URI(encoded: "../d")!
let resolved = relative.resolved(relativeTo: base)
print(resolved.encoded)  // "https://example.com/a/d"

// Build URIs programmatically
let newUri = URI.absolute(
    scheme: "https",
    authority: URI.Authority(host: "api.example.com", port: 8080),
    path: [.segment("v1"), .segment("users")],
    query: [URI.QueryItem(name: "limit", value: "10")]
)
```

**Standout Features:**

The component system makes URI manipulation a breeze. Update or remove individual parts without rebuilding the entire URI:

```swift
// Update components individually
let uri = URI(encoded: "http://example.com/path?query=value#fragment")!

let secured = uri.updating(.scheme("https"))
let newHost = uri.updating(.host("api.example.com"), .port(8080))
let cleaned = uri.removing(.query, .fragment)
```

---

### SolidNet

Network identifier parsing and validation: email addresses, hostnames, IPv4, IPv6, with full internationalized domain name (IDN) support.

```swift
import SolidNet

// Parse and validate email addresses
if let email = EmailAddress.parse(string: "user@example.com") {
    print("Local: \(email.local)")   // "user"
    print("Domain: \(email.domain)") // "example.com"
}

// Hostnames with IDN support
let hostname = IDNHostname.parse(string: "münchen.example.com")

// IP addresses
let ipv4 = IPv4Address.parse(string: "192.168.1.1")
let ipv6 = IPv6Address.parse(string: "2001:db8::1")
```

---

### SolidID

Unique identifier generation from simple local counters to globally unique UUIDs. Supports UUID versions 1, 3, 4, 5, 6, and 7, with multiple encoding options.

```swift
import SolidID

// Local counter IDs for simple sequential identifiers
let counter = AtomicCounterIDSource<CounterID<UInt64>>()
let localId = counter.next()  // 1, 2, 3, ...

// Generate UUIDs
let v4 = UUID.V4Source().next()  // Random UUID
let v7 = UUID.V7Source().next()  // Time-ordered UUID (great for databases)

// Version 5: Name-based with SHA-1
let v5Source = UUID.V5Source(namespace: .dns)
let domainId = v5Source.next(name: "example.com")
```

**Standout Features:**

UUID v7 generates time-ordered UUIDs that sort chronologically, making them ideal for database primary keys where you want both uniqueness and temporal ordering. For simpler use cases, `CounterID` provides lightweight sequential identifiers without the overhead of full UUIDs.

## Contributing

We welcome contributions! Here's how to get involved:

- **Questions?** Start a discussion in [GitHub Discussions](https://github.com/solid-swift/solid-foundation/discussions)
- **Found a bug?** Open an [issue](https://github.com/solid-swift/solid-foundation/issues)
- **Have a feature idea?** Open an issue first so we can discuss it
- **Want to submit code?** PRs are welcome! For new features, please tie your PR to an existing issue

## License

Solid Foundation is available under the MIT License. See the [LICENSE](LICENSE) file for details.

---

Built with care by people who got tired of dependency roulette.
