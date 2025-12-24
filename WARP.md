# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common Development Commands

### Building and Testing
- **Build all targets**: `swift build`
- **Run all tests**: `swift test`
- **Run specific test target**: `swift test --filter <TargetName>`
- **Run single test**: `swift test --filter <TestClassName>.<testMethodName>`

### Code Quality
- **Format code**: The project uses SwiftFormat via the Lint plugin (automatically applied during build)
- **Swift format configuration**: Defined in `.swift-format` with 120-char line length and 2-space tabs

### Benchmarks (Optional)
- **Enable benchmarks**: `export BENCHMARK_ENABLE=1` or `BENCHMARK_ENABLE=true`
- **Run benchmarks**: `swift run SolidBench` or `swift run SolidNumericBenchmark`

## Architecture Overview

SolidFoundation is a modular Swift foundation library designed as a comprehensive replacement/extension to Swift's Foundation with additional functionality. It follows a layered, dependency-based architecture.

### Core Module Architecture

**SolidCore** - Foundation layer providing:
- Core utilities, extensions, and data structures
- Custom collections (`RingBuffer`, `UnsafeOutputBuffer`)
- Logging infrastructure (cross-platform compatible)
- Base protocols and type-safe utilities

**Specialized Modules** (all depend on SolidCore):
- **SolidNumeric** - Numeric types and operations with 128-bit integer support
- **SolidTempo** - Java Time/JS Temporal-style date/time library with comprehensive timezone support
- **SolidURI** - RFC 3986 URI handling with template support
- **SolidNet** - Network-related utilities (email addresses, etc.)
- **SolidIO** - I/O streams, filters, and async buffer operations
- **SolidData** - Generic data structures with Path/Pointer navigation

**Format Support Modules** (depend on SolidData):
- **SolidJSON** - JSON processing
- **SolidYAML** - YAML processing  
- **SolidCBOR** - CBOR (Concise Binary Object Representation) processing

**High-Level Modules**:
- **SolidSchema** - Schema validation system (depends on multiple modules)
- **Solid** - Umbrella module re-exporting all functionality via namespace enums

### Key Architectural Patterns

**Namespace Organization**: The root `Solid` module uses namespace enums (e.g., `Tempo`, `Data`) to organize functionality from sub-modules while maintaining clean API boundaries.

**Component System**: The Tempo module implements a sophisticated component-based system for date/time manipulation, allowing flexible construction and modification of temporal objects.

**Protocol-Oriented Design**: Heavy use of protocols for extensibility, particularly in areas like:
- `ComponentContainer`/`ComponentBuildable` for temporal components
- `DateTime` protocol for various date/time representations
- Stream/filter protocols for I/O operations

**Platform Abstraction**: Conditional platform dependencies (e.g., swift-log only on Linux) with custom logging on other platforms.

## Development Patterns

### Module Dependencies
When adding functionality, respect the dependency hierarchy:
- Core utilities go in SolidCore
- Domain-specific functionality goes in appropriate specialized modules
- Cross-cutting concerns that need multiple modules go in SolidSchema or higher

### Testing
- Test files are organized by module in `Tests/` directory
- Prefer the swift-testing package for new tests with parameterized test cases
- Use `@Suite`, `@Test(arguments:)`, and data-driven tables for coverage and clarity
- Use `SolidTesting` for shared test utilities (legacy XCTest-based suites may remain until migrated)
- JSON test suites are available for schema validation testing

### Swift Language Mode
The project uses Swift 6.0 language mode with modern concurrency support (Sendable, async/await patterns).

### Platform Targets
Supports modern Apple platforms:
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+

## Schema Validation
The SolidSchema module provides comprehensive JSON Schema validation with support for multiple draft versions (draft-04 through draft-next). Test suites in `Tests/SolidSchemaTests/Resources/JSONTestSuite/` contain extensive validation test cases.

## Tempo Date/Time Library
SolidTempo provides a Java Time-inspired API with:
- `Instant` - Points in time with nanosecond precision
- `Duration` - Time spans with nanosecond precision using 128-bit integers
- Various `DateTime` implementations (`LocalDateTime`, `ZonedDateTime`, `OffsetDateTime`)
- Comprehensive timezone support with transition handling
- Component-based temporal arithmetic and manipulation
