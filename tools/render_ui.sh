#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
render_dir="$(mktemp -d /tmp/digital-age-render.XXXXXX)"
export DA_TEST_HOME="$render_dir/userdata"
export LIBGL_ALWAYS_SOFTWARE=1
display_binary="${XVFB_BIN:-$PWD/.tools/virtual-display/runtime/usr/bin/Xvfb}"
if [[ ! -x "$display_binary" ]]; then
  display_binary="$(command -v Xvfb || true)"
fi
if [[ ! -x "$display_binary" ]]; then
  echo 'Xvfb is required for real renderer captures. Install xvfb or set XVFB_BIN.' >&2
  exit 1
fi
"$display_binary" -displayfd 3 -screen 0 3440x1440x24 -nolisten tcp 3>"$render_dir/display" >"$render_dir/xvfb.log" 2>&1 &
display_pid=$!
trap 'kill "$display_pid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do
  [[ -s "$render_dir/display" ]] && break
  sleep 0.1
done
if [[ ! -s "$render_dir/display" ]]; then
  cat "$render_dir/xvfb.log" >&2
  exit 1
fi
export DISPLAY=":$(<"$render_dir/display")"
mkdir -p builds/ui
./tools/godot.sh --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script tests/ui_production_test.gd -- --capture-ui 2>&1 | tee builds/ui/render.log
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:' builds/ui/render.log; then exit 1; fi
python3 tools/ui_report.py
