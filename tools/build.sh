#!/usr/bin/env bash
# Linux and Windows exports, the licence texts that must travel with them, archives,
# checksums, and a verification of the finished packages.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/version.py --check >/dev/null
rm -rf builds/linux builds/windows
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
python3 tools/build_id.py >/dev/null
for target in builds/linux builds/windows; do
  # What a player gets beside the executable: the manual, the licence, the credits,
  # and every third-party licence the game is obliged to carry.
  cp README.md LICENSE assets/CREDITS.md builds/BUILD_ID.json "$target/"
  mkdir -p "$target/licenses"
  cp assets/GODOT-LICENSE.txt assets/GODOT-COPYRIGHT.txt "$target/licenses/"
  cp assets/fonts/Rajdhani-OFL.txt assets/fonts/Cinzel-OFL.txt "$target/licenses/"
  cp assets/third_party/polyhaven/LICENSE.md "$target/licenses/POLYHAVEN-CC0.md"
done
chmod +x builds/linux/DigitalAge.x86_64
python3 tools/package.py
python3 tools/verify_packages.py
