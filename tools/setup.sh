#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=4.6.3-stable
base="https://github.com/godotengine/godot-builds/releases/download/$version"
mkdir -p .tools/templates
# The engine and the export templates are pinned by SHA-256: a different download is refused.
verify() {
  echo "$2  $1" | sha256sum --check --status || { echo "Checksum mismatch for $1; delete it and run again." >&2; exit 1; }
}
if [[ ! -x .tools/Godot_v4.6.3-stable_linux.x86_64 ]]; then
  curl -fL --retry 3 "$base/Godot_v${version}_linux.x86_64.zip" -o .tools/godot.zip
  verify .tools/godot.zip d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3
  unzip -o .tools/godot.zip -d .tools
fi
if [[ ! -f .tools/templates/windows_release_x86_64.exe || ! -f .tools/templates/linux_release.x86_64 ]]; then
  curl -fL --retry 3 "$base/Godot_v${version}_export_templates.tpz" -o .tools/export_templates.tpz
  verify .tools/export_templates.tpz 3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8
  unzip -j -o .tools/export_templates.tpz templates/linux_release.x86_64 templates/windows_release_x86_64.exe -d .tools/templates
fi
./tools/godot.sh --headless --editor --quit
