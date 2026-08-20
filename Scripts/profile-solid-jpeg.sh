#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Instruments profiling is available only on macOS." >&2
  exit 64
fi

output_directory="${SOLID_JPEG_PROFILE_OUTPUT_DIRECTORY:-.profiles/solid-jpeg}"
mkdir -p "$output_directory"

BENCHMARK_ENABLE=1 JPEG_ORACLE_ENABLE=1 swift build \
  --configuration release \
  --product SolidJPEGProfileWorkload
profile_executable="$(BENCHMARK_ENABLE=1 JPEG_ORACLE_ENABLE=1 swift build \
  --configuration release \
  --show-bin-path)/SolidJPEGProfileWorkload"

run_profile() {
  local template="$1"
  local slug="$2"
  local iterations="$3"
  local size="$4"
  local time_limit="$5"
  xcrun xctrace record \
    --template "$template" \
    --time-limit "$time_limit" \
    --output "$output_directory/$slug.trace" \
    --launch -- "$profile_executable" "$iterations" "$size"
  xcrun xctrace export --input "$output_directory/$slug.trace" --toc \
    --output "$output_directory/$slug-toc.xml"
}

run_allocation_profile() {
  local iterations="$1"
  local size="$2"
  local time_limit="$3"
  "$profile_executable" "$iterations" "$size" 10 &
  local profile_process=$!
  set +e
  xcrun xctrace record \
    --template "Allocations" \
    --time-limit "$time_limit" \
    --output "$output_directory/allocations.trace" \
    --attach "$profile_process"
  local record_status=$?
  set -e
  wait "$profile_process" || true
  if [[ $record_status -eq 0 ]]; then
    xcrun xctrace export --input "$output_directory/allocations.trace" --toc \
      --output "$output_directory/allocations-toc.xml"
    allocation_status="recorded"
  else
    allocation_status="unavailable (xctrace status $record_status)"
    echo "Allocations capture unavailable; Benchmark allocation metrics remain available." >&2
  fi
}

time_iterations="${SOLID_JPEG_PROFILE_ITERATIONS:-50}"
allocation_iterations="${SOLID_JPEG_ALLOCATION_PROFILE_ITERATIONS:-1}"
time_size="${SOLID_JPEG_PROFILE_SIZE:-512}"
allocation_size="${SOLID_JPEG_ALLOCATION_PROFILE_SIZE:-64}"
allocation_time_limit="${SOLID_JPEG_ALLOCATION_PROFILE_TIME_LIMIT:-15s}"
allocation_status="not run"
run_profile "Time Profiler" time-profiler "$time_iterations" "$time_size" 2m
run_allocation_profile "$allocation_iterations" "$allocation_size" "$allocation_time_limit"

{
  echo "# SolidJPEG Instruments Capture"
  echo
  echo "- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Host: $(scutil --get ComputerName 2>/dev/null || hostname)"
  echo "- OS: $(sw_vers -productVersion)"
  echo "- Swift: $(swift --version | head -1)"
  echo "- Workload: YCbCr 4:2:0 encode and decode"
  echo "- Time Profiler: ${time_size}x${time_size}, $time_iterations iterations"
  echo "- Allocations: ${allocation_size}x${allocation_size}, $allocation_iterations iterations"
  echo "- Allocations capture limit: $allocation_time_limit"
  echo "- Allocations capture: $allocation_status"
  echo "- Traces: time-profiler.trace and allocations.trace"
  echo
  echo "Inspect the archived traces for self-time, allocation sites, and peak resident memory."
} > "$output_directory/report.md"

echo "Profiles written to $output_directory"
