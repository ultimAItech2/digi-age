#!/usr/bin/env bash
# Capture the demo scene under Xvfb: --gl (llvmpipe OpenGL, the CI gate) or --vulkan (lavapipe Forward+).
set -euo pipefail
cd "$(dirname "$0")/.."
mode="gl"
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gl) mode="gl" ;;
    --vulkan) mode="vulkan" ;;
    --zoom) extra+=(--zoom "$2"); shift ;;
    --profile) extra+=(--profile "$2"); shift ;;
    --reduced) extra+=(--reduced) ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
render_dir="$(mktemp -d /tmp/digital-age-scene.XXXXXX)"
export DA_TEST_HOME="$render_dir/userdata"
export LIBGL_ALWAYS_SOFTWARE=1
display_binary="${XVFB_BIN:-$PWD/.tools/virtual-display/runtime/usr/bin/Xvfb}"
[[ -x "$display_binary" ]] || display_binary="$(command -v Xvfb || true)"
if [[ ! -x "$display_binary" ]]; then
  echo 'Xvfb is required. Install xvfb or set XVFB_BIN.' >&2
  exit 1
fi
"$display_binary" -displayfd 3 -screen 0 1280x720x24 -nolisten tcp 3>"$render_dir/display" >"$render_dir/xvfb.log" 2>&1 &
display_pid=$!
trap 'kill "$display_pid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do [[ -s "$render_dir/display" ]] && break; sleep 0.1; done
export DISPLAY=":$(<"$render_dir/display")"
mkdir -p builds
if [[ "$mode" == "vulkan" ]]; then
  export VK_DRIVER_FILES="${VK_DRIVER_FILES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
  renderer=(--rendering-method forward_plus --rendering-driver vulkan)
  frames=24
else
  renderer=(--rendering-method gl_compatibility --rendering-driver opengl3)
  frames=12
fi
timeout 900 ./tools/godot.sh --audio-driver Dummy --resolution 1280x720 "${renderer[@]}" -- --demo --screenshot --capture-frames "$frames" "${extra[@]}" 2>&1 | tee "builds/scene-$mode.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:' "builds/scene-$mode.log"; then exit 1; fi
mv builds/screenshot.png "builds/scene-$mode.png"
echo "wrote builds/scene-$mode.png"
