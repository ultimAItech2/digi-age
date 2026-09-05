#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p builds
# Godot may return zero after a script error; fail on error output as well.
run_check() {
  local test_script="$1"
  local log_file="builds/$(basename "$test_script" .gd).log"
  timeout 600 ./tools/godot.sh --headless --script "$test_script" 2>&1 | tee "$log_file"
  if rg -q 'SCRIPT ERROR|^ERROR:|FAIL:' "$log_file"; then return 1; fi
}
run_check tests/simulation_test.gd
run_check tests/production_foundation_test.gd
run_check tests/campaign_test.gd
run_check tests/audio_test.gd
run_check tests/interface_test.gd
if [[ "${1:-}" == "--soak" ]]; then
  run_check tests/soak_test.gd
fi
