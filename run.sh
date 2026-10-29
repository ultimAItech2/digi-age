#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "${1:-}" == "--packaged" ]]; then
  shift
  if [[ ! -x builds/linux/DigitalAge.x86_64 ]]; then
    echo 'Packaged build is missing. Run tools/build.sh first.' >&2
    exit 1
  fi
  exec builds/linux/DigitalAge.x86_64 "$@"
fi
exec tools/godot.sh "$@"
