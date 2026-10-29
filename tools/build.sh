#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p builds/linux builds/windows
run_export_check() {
  local name="$1"
  shift
  ./tools/godot.sh "$@" 2>&1 | tee "builds/$name.log"
  if grep -Eq 'SCRIPT ERROR|^ERROR:' "builds/$name.log"; then return 1; fi
}
run_export_check import --headless --editor --import --quit
run_export_check linux-export --headless --export-release 'Linux Desktop'
run_export_check windows-export --headless --export-release 'Windows Desktop'
cp README.md LICENSE assets/CREDITS.md assets/GODOT-LICENSE.txt assets/GODOT-COPYRIGHT.txt docs/VALIDATION.md builds/linux/
cp README.md LICENSE assets/CREDITS.md assets/GODOT-LICENSE.txt assets/GODOT-COPYRIGHT.txt docs/VALIDATION.md builds/windows/
cp docs/UI_VERIFICATION.md builds/linux/
cp docs/UI_VERIFICATION.md builds/windows/
if [[ -f builds/BUILD_ID.json ]]; then
  cp builds/BUILD_ID.json builds/linux/
  cp builds/BUILD_ID.json builds/windows/
fi
chmod +x builds/linux/DigitalAge.x86_64
python3 tools/package.py
