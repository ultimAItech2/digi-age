#!/usr/bin/env python3
"""Write builds/BUILD_ID.json: the version, the commit and a hash of everything the game ships from.

The file travels inside each package, so a build can be traced to its exact source. Rendered
UI results (from tools/render_ui.sh) are kept only while they describe the same source.
"""
import hashlib
import json
import subprocess
from pathlib import Path

from version import version

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "builds" / "BUILD_ID.json"


def source_hash() -> str:
    digest = hashlib.sha256()
    for folder in ("scripts", "assets", "data", "scenes", "locale"):
        for path in sorted((ROOT / folder).rglob("*")):
            if path.is_file() and not path.name.endswith(".import"):
                digest.update(str(path.relative_to(ROOT)).encode())
                digest.update(hashlib.sha256(path.read_bytes()).digest())
    digest.update((ROOT / "project.godot").read_bytes())
    return digest.hexdigest()


def commit() -> str:
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def identity(rendered: dict | None = None) -> dict:
    result = {"version": version(), "commit": commit(), "runtime_source_sha256": source_hash()}
    previous = {}
    if TARGET.exists():
        try:
            previous = json.loads(TARGET.read_text())
        except json.JSONDecodeError:
            previous = {}
    if rendered is None and previous.get("runtime_source_sha256") == result["runtime_source_sha256"]:
        rendered = {key: previous[key] for key in ("renderer", "rendered_checks", "rendered_failures", "screenshots") if key in previous}
    result.update(rendered or {})
    return result


def write(rendered: dict | None = None) -> dict:
    result = identity(rendered)
    TARGET.parent.mkdir(exist_ok=True)
    TARGET.write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    print(json.dumps(write()))
