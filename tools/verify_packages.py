"""Verify the actual archives, including an isolated extracted Linux launch."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
builds = root / "builds"
# Every package must carry the licences it is obliged to ship, and no developer documents.
REQUIRED = ["README.md", "LICENSE", "CREDITS.md", "BUILD_ID.json", "licenses/GODOT-LICENSE.txt", "licenses/GODOT-COPYRIGHT.txt",
            "licenses/Rajdhani-OFL.txt", "licenses/Cinzel-OFL.txt", "licenses/POLYHAVEN-CC0.md"]
FORBIDDEN = ["VALIDATION.md", "UI_VERIFICATION.md"]


def check_contents(names: list[str], label: str) -> None:
    for name in REQUIRED:
        assert "DigitalAge/" + name in names, f"{label} package is missing {name}"
    for name in FORBIDDEN:
        assert "DigitalAge/" + name not in names, f"{label} package ships developer document {name}"


identity = json.loads((builds / "BUILD_ID.json").read_text())
assert identity["version"] == subprocess.run(["python3", str(root / "tools" / "version.py")], capture_output=True, text=True, check=True).stdout.strip(), "BUILD_ID.json is stale"
for line in (builds / "SHA256SUMS").read_text().splitlines():
    digest, name = line.split(maxsplit=1)
    assert hashlib.sha256((builds / name).read_bytes()).hexdigest() == digest, name
with zipfile.ZipFile(builds / "DigitalAge-windows-x86_64.zip") as archive:
    assert archive.testzip() is None
    assert archive.read("DigitalAge/DigitalAge.exe")[:2] == b"MZ"
    assert archive.read("DigitalAge/BUILD_ID.json") == (builds / "BUILD_ID.json").read_bytes()
    check_contents(archive.namelist(), "Windows")
with zipfile.ZipFile(builds / "DigitalAge-source.zip") as archive:
    assert archive.testzip() is None
    sources = [name for name in archive.namelist() if name.startswith("DigitalAge/art/") and name.endswith(".blend")]
    assert len(sources) >= 36, "Editable Blender sources missing"
with tempfile.TemporaryDirectory(prefix="digital-age-package-") as temporary:
    target = Path(temporary)
    with tarfile.open(builds / "DigitalAge-linux-x86_64.tar.gz") as archive:
        check_contents(archive.getnames(), "Linux")
        archive.extractall(target, filter="data")
    binary = target / "DigitalAge" / "DigitalAge.x86_64"
    assert binary.read_bytes()[:4] == b"\x7fELF"
    assert os.access(binary, os.X_OK)
    environment = os.environ.copy()
    for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        environment[key] = str(target / "userdata")
    result = subprocess.run([str(binary), "--headless", "--", "--ui-smoke"], cwd=target,
                            env=environment, capture_output=True, text=True, timeout=60)
    log = result.stdout + result.stderr
    (builds / "linux-package-smoke.log").write_text(log)
    assert result.returncode == 0 and "UI_EXPORT_SMOKE: PASS" in log, log
    assert "SCRIPT ERROR" not in log and "ERROR:" not in log, log
    # Development switches must do nothing in a release build. With --demo honoured the game
    # would start in a match with a free army and the smoke check's menu test would fail.
    cheat = subprocess.run([str(binary), "--headless", "--", "--ui-smoke", "--demo", "--autoplay"], cwd=target,
                           env=environment, capture_output=True, text=True, timeout=60)
    assert cheat.returncode == 0 and "UI_EXPORT_SMOKE: PASS" in cheat.stdout + cheat.stderr, "development switches are live in the release build:\n" + cheat.stdout + cheat.stderr
report = {"linux_extracted_launch": "PASS: menu and mission", "windows_archive": "PASS: PE executable and integrity; runtime not tested", "blender_sources": len(sources), "checksums": "PASS", "licences": "PASS", "dev_switches": "PASS: ignored in release", "version": identity["version"], "commit": identity["commit"]}
(builds / "package-verification.json").write_text(json.dumps(report, indent=2)+"\n")
print(json.dumps(report))
