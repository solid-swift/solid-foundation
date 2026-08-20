# SolidJPEG Development

`SolidJPEG` owns the portable baseline-sequential JPEG implementation used by
`SolidIO` DCT filters. Encoder sessions retain at most one source MCU band.
Known-height interleaved decoder sessions emit full-resolution MCU-row bands as
soon as entropy decoding completes. Separate scans emit explicit component
subsets, while DNL streams use a bounded whole-stream compatibility path until
their height is known.

## Performance comparison

Enable the conditional benchmark targets and compare the native implementation
with `swift-jpeg` on the same checkout and machine:

```shell
Scripts/benchmark-jpeg-comparison.sh
```

The script creates transient `swift-jpeg-reference` and `native-candidate`
baselines. Only wall-clock p50 is an acceptance gate; CPU, throughput, malloc,
retain, and peak-memory measurements are diagnostic. A native p50 greater than
twice the reference is a regression. Baselines are intentionally ignored and
must not be committed.

The acceptance run on 2026-08-20 used 512×512 grayscale, YCbCr 4:4:4, and YCbCr
4:2:0 encode/decode workloads. Every native p50 passed the two-times gate. For
example, native grayscale decode measured 46 ms versus 65 ms for `swift-jpeg`,
and native 4:2:0 encode measured 58 ms versus 148 ms.

## Profiling

On macOS, capture a release Time Profiler trace and attempt an Allocations trace
with:

```shell
Scripts/profile-solid-jpeg.sh
```

The profile workload runs the same native 4:2:0 encode/decode fixture without
the Benchmark host process. Override its output directory, iteration counts,
image sizes, or allocation time limit through the `SOLID_JPEG_PROFILE_*`
environment variables documented in the script. If the installed Instruments
version cannot attach Allocations to a command-line Swift process, the script
records that limitation and Benchmark's allocation metrics remain available.

The 2026-08-20 Time Profiler capture identified forward/inverse DCT, streaming
block filling and bounds checks, Huffman decoding, and entropy output as the
principal native hot paths. No optimization is accepted without rerunning the
same comparison gate.

## Deterministic mutation campaigns

Fuzz targets are excluded from ordinary dependency resolution. Build them with
`FUZZING_ENABLE=1`, then use `Scripts/fuzz-codecs.sh` for explicitly requested
sanitizer campaigns. The runner records the active input and iteration before
evaluation, supports fixed seeds and resumable iteration numbers, and leaves
generated corpus and artifact directories untracked.
