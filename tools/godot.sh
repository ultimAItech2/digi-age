#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_DATA_HOME="$PWD/.tools/userdata"
export XDG_CONFIG_HOME="$PWD/.tools/config"
export XDG_CACHE_HOME="$PWD/.tools/cache"
engine="${GODOT_BIN:-$PWD/.tools/Godot_v4.6.3-stable_linux.x86_64}"
if [[ ! -x "$engine" ]]; then
  echo 'Godot is missing. Run tools/setup.sh or set GODOT_BIN to Godot 4.6.3.' >&2
  exit 1
fi
exec "$engine" --path "$PWD" "$@"
