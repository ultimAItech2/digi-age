#!/usr/bin/env python3
"""The game version, read from project.godot (the only place it is set).

  version.py           print the version, e.g. 1.0.0-rc3
  version.py --check   fail unless the Windows file version in export_presets.cfg matches
  version.py --sync    rewrite the Windows file version from project.godot
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def version() -> str:
    match = re.search(r'^config/version="([^"]+)"', (ROOT / "project.godot").read_text(), re.M)
    if not match:
        raise SystemExit("project.godot has no config/version")
    return match.group(1)


def windows_version(value: str) -> str:
    """Windows wants four numbers: 1.0.0-rc3 becomes 1.0.0.3, a final 1.0.0 becomes 1.0.0.0."""
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-rc(\d+))?", value)
    if not match:
        raise SystemExit(f"version {value!r} is not MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-rcN")
    return ".".join([match.group(1), match.group(2), match.group(3), match.group(4) or "0"])


def main() -> None:
    value = version()
    presets = ROOT / "export_presets.cfg"
    text = presets.read_text()
    wanted = windows_version(value)
    if "--sync" in sys.argv:
        text = re.sub(r'^(application/(?:file|product)_version)="[^"]*"', rf'\1="{wanted}"', text, flags=re.M)
        presets.write_text(text)
    elif "--check" in sys.argv:
        found = re.findall(r'^application/(?:file|product)_version="([^"]*)"', text, re.M)
        if not found or any(entry != wanted for entry in found):
            raise SystemExit(f"export_presets.cfg has Windows versions {found}, project.godot needs {wanted}. Run tools/version.py --sync.")
    print(value)


if __name__ == "__main__":
    main()
