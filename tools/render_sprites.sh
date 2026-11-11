#!/usr/bin/env bash
# Rebuild every rendered sprite: Blender models -> frames -> atlases (see tools/sprites/).
# Pass --kinds a,b to redo only some kinds; the atlas table is rewritten from whatever frames exist.
set -euo pipefail
cd "$(dirname "$0")/.."
blender="${BLENDER:-$PWD/.tools/blender-4.5.3-linux-x64/blender}"
mkdir -p builds/sprites
"$blender" -b -noaudio --factory-startup --python-exit-code 1 --python tools/sprites/render.py -- "$@" 2>&1 | grep -E 'SPRITE|RENDER|Traceback|Error|File ' || true
python3 tools/sprites/pack.py
