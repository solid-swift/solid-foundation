#!/usr/bin/env bash
set -euo pipefail

iterations="${FUZZ_ITERATIONS:-1000}"
seed="${FUZZ_SEED:-6003092301531665754}"
timeout="${FUZZ_TIMEOUT:-60}"

run_harness() {
  local sanitizer="$1"
  local target="$2"
  FUZZING_ENABLE=1 swift run --sanitize "$sanitizer" "$target" \
    --seed "$seed" \
    --iterations "$iterations" \
    --timeout "$timeout" \
    --artifacts ".fuzz-artifacts/$sanitizer/$target"
}

for sanitizer in address undefined; do
  run_harness "$sanitizer" SolidJPEGFuzz
  run_harness "$sanitizer" SolidCCITTFaxFuzz
done
