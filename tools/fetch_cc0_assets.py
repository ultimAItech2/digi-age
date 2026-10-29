#!/usr/bin/env python3
"""Download the CC0 Poly Haven assets listed in tools/cc0_assets.json.

Raw downloads go to assets/third_party/polyhaven/raw/<id>/ (gitignored, never
shipped); only files processed by tools/process_cc0_models.py and
tools/build_terrain_arrays.gd are committed. Run with `python3 -I`.

  --verify   check committed processed files against their manifest, offline
  --credits  print a Markdown credits table for assets/CREDITS.md
"""
import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "tools" / "cc0_assets.json"
RAW = ROOT / "assets" / "third_party" / "polyhaven" / "raw"
MANIFEST = ROOT / "assets" / "third_party" / "polyhaven" / "manifest.json"
LICENSE = ROOT / "assets" / "third_party" / "polyhaven" / "LICENSE.md"
PROCESSED = ROOT / "assets" / "third_party" / "processed"
API = "https://api.polyhaven.com"
MAX_PROCESSED_BYTES = 25 * 1024 * 1024
USER_AGENT = "DigitalAge-fetch/1.0 (+https://github.com/ultimaitech; CC0 asset sync)"


def request(url):
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT})


def get_json(url):
    with urllib.request.urlopen(request(url), timeout=60) as response:
        return json.load(response)


def md5_of(path):
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(entry, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size == entry["size"] and md5_of(target) == entry["md5"]:
        return "cached"
    tmp = target.with_suffix(target.suffix + ".part")
    with urllib.request.urlopen(request(entry["url"]), timeout=120) as response, open(tmp, "wb") as out:
        for chunk in iter(lambda: response.read(1 << 20), b""):
            out.write(chunk)
    if md5_of(tmp) != entry["md5"]:
        tmp.unlink()
        raise RuntimeError("md5 mismatch for %s" % entry["url"])
    tmp.replace(target)
    return "downloaded"


def plan_files(kind, asset_id, spec):
    files = get_json("%s/files/%s" % (API, asset_id))
    jobs = []
    if kind == "textures":
        for map_name in spec["maps"]:
            entry = files[map_name][spec["res"]][spec["fmt"]]
            name = "%s_%s_%s.%s" % (asset_id, map_name.lower() if map_name == "Diffuse" else map_name, spec["res"], spec["fmt"])
            jobs.append((entry, RAW / asset_id / name))
    elif kind == "models":
        entry = files["gltf"][spec["res"]]["gltf"]
        jobs.append((entry, RAW / asset_id / ("%s_%s.gltf" % (asset_id, spec["res"]))))
        for rel, inc in entry["include"].items():
            jobs.append((inc, RAW / asset_id / rel))
    elif kind == "hdris":
        entry = files["hdri"][spec["res"]][spec["fmt"]]
        jobs.append((entry, RAW / asset_id / ("%s_%s.%s" % (asset_id, spec["res"], spec["fmt"]))))
    return jobs


def fetch(config, only=None):
    manifest = {"source": config["source"], "license": config["license"], "assets": {}}
    RAW.mkdir(parents=True, exist_ok=True)
    (RAW / ".gdignore").write_text("")
    with ThreadPoolExecutor(max_workers=6) as pool:
        for kind in ("textures", "models", "hdris"):
            for asset_id, spec in config[kind].items():
                if only and asset_id not in only:
                    continue
                try:
                    info = get_json("%s/info/%s" % (API, asset_id))
                    jobs = plan_files(kind, asset_id, spec)
                except urllib.error.HTTPError as error:
                    print("%-40s %-8s SKIPPED (%s)" % (asset_id, kind[:-1], error), flush=True)
                    continue
                results = list(pool.map(lambda job: download(job[0], job[1]), jobs))
                total = sum(job[0]["size"] for job in jobs)
                manifest["assets"][asset_id] = {
                    "type": kind[:-1],
                    "name": info.get("name", asset_id),
                    "authors": sorted(info.get("authors", {}).keys()),
                    "resolution": spec["res"],
                    "bytes": total,
                    "files": [{"path": str(job[1].relative_to(RAW)), "size": job[0]["size"], "md5": job[0]["md5"], "url": job[0]["url"]} for job in jobs],
                }
                print("%-40s %-8s %6.1f MB  %s" % (asset_id, kind[:-1], total / 1e6, ", ".join(sorted(set(results)))), flush=True)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    LICENSE.write_text(
        "# Poly Haven assets\n\nAll files listed in `manifest.json` were downloaded from https://polyhaven.com "
        "and are released under the CC0 1.0 Universal public domain dedication "
        "(https://creativecommons.org/publicdomain/zero/1.0/). Raw downloads live in `raw/` and are not "
        "committed or shipped; processed derivatives are in `../processed/`.\n"
    )
    return manifest


def credits(manifest):
    rows = ["| Asset | Type | Authors |", "|---|---|---|"]
    for asset_id, entry in sorted(manifest["assets"].items()):
        rows.append("| %s (`%s`) | %s | %s |" % (entry["name"], asset_id, entry["type"], ", ".join(entry["authors"]) or "Poly Haven"))
    return "\n".join(rows)


def verify():
    manifest_path = PROCESSED / "manifest.json"
    if not manifest_path.exists():
        print("processed manifest missing: %s" % manifest_path)
        return 1
    manifest = json.loads(manifest_path.read_text())
    failures = 0
    for entry in manifest.get("files", []):
        path = PROCESSED / entry["path"]
        if not path.exists():
            print("missing %s" % path)
            failures += 1
            continue
        size = path.stat().st_size
        if size > MAX_PROCESSED_BYTES:
            print("too large (%d bytes): %s" % (size, path))
            failures += 1
        if entry.get("md5") and md5_of(path) != entry["md5"]:
            print("md5 mismatch: %s" % path)
            failures += 1
    print("processed assets: %d files, %d problems" % (len(manifest.get("files", [])), failures))
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--credits", action="store_true")
    parser.add_argument("--only", nargs="*", help="asset ids to fetch")
    args = parser.parse_args()
    if args.verify:
        return verify()
    config = json.loads(CONFIG.read_text())
    if args.credits:
        manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else fetch(config)
        print(credits(manifest))
        return 0
    fetch(config, set(args.only) if args.only else None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
