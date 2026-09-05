#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=4.6.3-stable
base="https://github.com/godotengine/godot-builds/releases/download/$version"
mkdir -p .tools/templates
if [[ ! -x .tools/Godot_v4.6.3-stable_linux.x86_64 ]]; then
  curl -fL --retry 3 "$base/Godot_v${version}_linux.x86_64.zip" -o .tools/godot.zip
  unzip -o .tools/godot.zip -d .tools
fi
if [[ ! -f .tools/templates/windows_release_x86_64.exe || ! -f .tools/templates/linux_release.x86_64 ]]; then
  curl -fL --retry 3 "$base/Godot_v${version}_export_templates.tpz" -o .tools/export_templates.tpz
  unzip -j -o .tools/export_templates.tpz templates/linux_release.x86_64 templates/windows_release_x86_64.exe -d .tools/templates
fi
./tools/godot.sh --headless --editor --quit
