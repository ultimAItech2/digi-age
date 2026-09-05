#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p builds/linux builds/windows
./tools/godot.sh --headless --editor --quit
./tools/godot.sh --headless --export-release 'Linux Desktop'
./tools/godot.sh --headless --export-release 'Windows Desktop'
cp README.md LICENSE assets/CREDITS.md assets/GODOT-LICENSE.txt assets/GODOT-COPYRIGHT.txt docs/VALIDATION.md builds/linux/
cp README.md LICENSE assets/CREDITS.md assets/GODOT-LICENSE.txt assets/GODOT-COPYRIGHT.txt docs/VALIDATION.md builds/windows/
chmod +x builds/linux/DigitalAge.x86_64
python3 tools/package.py
