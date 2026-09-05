#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -x builds/linux/DigitalAge.x86_64 ]]; then
  exec builds/linux/DigitalAge.x86_64 "$@"
fi
exec tools/godot.sh "$@"
