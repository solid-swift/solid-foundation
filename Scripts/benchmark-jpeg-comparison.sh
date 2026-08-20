#!/usr/bin/env bash
set -euo pipefail

readonly TARGET="SolidJPEGBenchmark"
readonly REFERENCE_BASELINE="swift-jpeg-reference"
readonly CANDIDATE_BASELINE="native-candidate"
readonly IMAGEIO_BASELINE="imageio-current"

SWIFT_PACKAGE=(swift package)
SWIFT_TEST=(swift test)
if [[ -n "${SOLID_JPEG_BENCHMARK_SCRATCH_PATH:-}" ]]; then
  SWIFT_PACKAGE+=(--scratch-path "$SOLID_JPEG_BENCHMARK_SCRATCH_PATH")
  SWIFT_TEST+=(--scratch-path "$SOLID_JPEG_BENCHMARK_SCRATCH_PATH")
fi

benchmark() {
  BENCHMARK_ENABLE=1 JPEG_ORACLE_ENABLE=1 "${SWIFT_PACKAGE[@]}" \
    --allow-writing-to-package-directory benchmark "$@"
}

update_baseline() {
  local backend="$1"
  local baseline="$2"
  SOLID_JPEG_BENCHMARK_BACKEND="$backend" benchmark baseline update "$baseline" \
    --target "$TARGET" \
    --no-progress \
    --quiet
}

BENCHMARK_ENABLE=1 JPEG_ORACLE_ENABLE=1 "${SWIFT_TEST[@]}" \
  --filter SolidJPEGBenchmarkSupportTests
JPEG_ORACLE_ENABLE=1 "${SWIFT_TEST[@]}" --filter SolidJPEGOracleTests

update_baseline swift-jpeg "$REFERENCE_BASELINE"
update_baseline native "$CANDIDATE_BASELINE"
if [[ "$(uname -s)" == "Darwin" ]]; then
  update_baseline imageio "$IMAGEIO_BASELINE"
fi

set +e
check_output="$(SOLID_JPEG_BENCHMARK_BACKEND=native benchmark baseline check \
  "$REFERENCE_BASELINE" "$CANDIDATE_BASELINE" \
  --target "$TARGET" \
  --no-progress 2>&1)"
check_status=$?
set -e
printf '%s\n' "$check_output"

if [[ $check_status -eq 1 && "$check_output" == *benchmarkThresholdRegression* ]]; then
  check_status=2
fi

SOLID_JPEG_BENCHMARK_BACKEND=native benchmark baseline compare \
  "$REFERENCE_BASELINE" "$CANDIDATE_BASELINE" \
  --target "$TARGET" \
  --no-progress

if [[ "$(uname -s)" == "Darwin" ]]; then
  SOLID_JPEG_BENCHMARK_BACKEND=imageio benchmark baseline compare \
    "$IMAGEIO_BASELINE" "$CANDIDATE_BASELINE" \
    --target "$TARGET" \
    --no-progress
fi

if [[ -n "${SOLID_JPEG_BENCHMARK_EXPORT_DIRECTORY:-}" ]]; then
  mkdir -p "$SOLID_JPEG_BENCHMARK_EXPORT_DIRECTORY"
  for backend in swift-jpeg native; do
    SOLID_JPEG_BENCHMARK_BACKEND="$backend" benchmark run \
      --target "$TARGET" \
      --format jmh \
      --path "$SOLID_JPEG_BENCHMARK_EXPORT_DIRECTORY/$backend" \
      --no-progress
    SOLID_JPEG_BENCHMARK_BACKEND="$backend" benchmark run \
      --target "$TARGET" \
      --format histogramSamples \
      --path "$SOLID_JPEG_BENCHMARK_EXPORT_DIRECTORY/$backend-samples" \
      --no-progress
  done
fi

case "$check_status" in
  0)
    echo "SolidJPEG gate passed: every native p50 is within 2x swift-jpeg."
    ;;
  4)
    echo "SolidJPEG gate passed: native is an improvement over swift-jpeg."
    ;;
  2)
    echo "SolidJPEG gate failed: at least one native p50 exceeds 2x swift-jpeg." >&2
    exit 2
    ;;
  *)
    echo "SolidJPEG benchmark infrastructure failed with status $check_status." >&2
    exit "$check_status"
    ;;
esac
