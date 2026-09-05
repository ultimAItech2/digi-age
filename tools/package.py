"""Create portable desktop archives, preserving the Linux executable bit."""
from pathlib import Path
import hashlib
import tarfile
import zipfile

root = Path(__file__).resolve().parent.parent
builds = root / "builds"
with tarfile.open(builds / "DigitalAge-linux-x86_64.tar.gz", "w:gz") as archive:
    archive.add(builds / "linux", arcname="DigitalAge")
with zipfile.ZipFile(builds / "DigitalAge-windows-x86_64.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((builds / "windows").iterdir()):
        archive.write(path, "DigitalAge/" + path.name)
source_archive = builds / "DigitalAge-source.zip"
with zipfile.ZipFile(source_archive, "w", zipfile.ZIP_DEFLATED) as archive:
    for folder in ["assets", "data", "docs", "scenes", "scripts", "steam", "tests", "tools"]:
        for path in sorted((root / folder).rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                archive.write(path, "DigitalAge/" + str(path.relative_to(root)))
    for name in ["project.godot", "export_presets.cfg", "default_bus_layout.tres", "README.md", "LICENSE", "run.sh", ".gitignore"]:
        archive.write(root / name, "DigitalAge/" + name)
    archive.writestr("DigitalAge/builds/.gdignore", "")
archives = [builds / "DigitalAge-linux-x86_64.tar.gz", builds / "DigitalAge-windows-x86_64.zip", source_archive]
(builds / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in archives))
for path in archives:
    print(f"Packaged {path.name}: {path.stat().st_size / 1048576:.1f} MiB")
