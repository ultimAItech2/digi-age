#!/usr/bin/env python3
"""Generate offline voice, SFX, and music through the connected Composio ElevenLabs toolkit."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOICE_SRC = ROOT / "data" / "audio" / "voice_lines.json"
PROMPT_SRC = ROOT / "data" / "audio" / "sfx_music_prompts.json"
AUDIO = ROOT / "assets" / "audio"
MANIFEST = AUDIO / "manifest.json"
COMPOSIO = shutil.which("composio") or os.path.expanduser("~/.local/bin/composio")


def run_composio(args: list[str], timeout: int = 180) -> dict:
    proc = subprocess.run(
        [COMPOSIO, *args],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    text = proc.stdout.strip() or proc.stderr.strip()
    if proc.returncode != 0:
        raise RuntimeError(f"composio {' '.join(args[:4])} failed: {text[-800:]}")
    if not text:
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        if start < 0:
            raise RuntimeError(f"non-json composio output: {text[-400:]}")
        data = json.loads(text[start:])
    if data.get("storedInFile") and data.get("outputFilePath"):
        return json.loads(Path(data["outputFilePath"]).read_text())
    return data


def execute(slug: str, payload: dict, timeout: int = 180) -> dict:
    return run_composio(["execute", slug, "-d", json.dumps(payload)], timeout=timeout)


def proxy(url: str, method: str = "GET", body: dict | None = None, timeout: int = 240) -> dict:
    args = ["proxy", url, "--toolkit", "elevenlabs", "-X", method]
    if body is not None:
        args += ["-H", "content-type: application/json", "-d", json.dumps(body)]
    return run_composio(args, timeout=timeout)


def proxy_audio(url: str, dest: Path, body: dict, timeout: int = 300) -> bool:
    """Fetch MPEG through the JS proxy client, which keeps response bytes."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    path = url
    if path.startswith("https://api.elevenlabs.io"):
        path = path[len("https://api.elevenlabs.io"):]
    snippet = f"""
const fs = await import("node:fs");
const eleven = await proxy("elevenlabs");
const response = await eleven({json.dumps(path)}, {{
  method: "POST",
  headers: {{ "content-type": "application/json", "accept": "audio/mpeg" }},
  body: {json.dumps(body)}
}});
const buf = Buffer.from(await response.arrayBuffer());
if (response.status >= 400) {{
  console.error(buf.toString("utf8").slice(0, 400));
  process.exit(2);
}}
fs.writeFileSync({json.dumps(str(dest))}, buf);
console.log("saved", {json.dumps(str(dest))}, buf.length);
"""
    proc = subprocess.run(
        [COMPOSIO, "run", "--logs-off", snippet],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if dest.exists() and dest.stat().st_size > 200:
        return True
    print(proc.stdout[-400:], proc.stderr[-400:], file=sys.stderr)
    return False


def credits() -> int:
    info = execute("ELEVENLABS_GET_USER_SUBSCRIPTION_INFO", {})
    data = info.get("data", info)
    return int(data.get("character_count", 0))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "DigitalAgeAudio/1.0"})
    with urllib.request.urlopen(req, timeout=120) as response:
        dest.write_bytes(response.read())


def extract_url(payload: dict) -> str:
    if not isinstance(payload, dict):
        return ""
    data = payload.get("data", payload)
    file_info = data.get("file", data) if isinstance(data, dict) else {}
    for key in ("s3url", "s3_url", "url", "download_url"):
        if isinstance(file_info, dict) and file_info.get(key):
            return str(file_info[key])
        if isinstance(data, dict) and data.get(key):
            return str(data[key])
    return ""


def write_audio_bytes(payload: dict, dest: Path) -> bool:
    url = extract_url(payload)
    if url:
        download(url, dest)
        return dest.stat().st_size > 200
    data = payload.get("data", payload)
    raw = None
    if isinstance(data, dict):
        raw = data.get("audio_base64") or data.get("audio") or data.get("base64")
    if isinstance(raw, str) and len(raw) > 80:
        import base64
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(base64.b64decode(raw))
        return dest.stat().st_size > 200
    return False


def generate_voice(line: dict, voices: dict, model: str, fmt: str) -> Path:
    speaker = line["speaker"]
    dest = AUDIO / "voice" / f"{line['id'].replace('.', '_')}.mp3"
    if dest.exists() and dest.stat().st_size > 200:
        return dest
    voice_id = voices[speaker]["voice_id"]
    result = execute(
        "ELEVENLABS_TEXT_TO_SPEECH",
        {"voice_id": voice_id, "text": line["text"], "model_id": model, "output_format": fmt},
        timeout=180,
    )
    if not write_audio_bytes(result, dest):
        raise RuntimeError(f"TTS produced no file for {line['id']}: {json.dumps(result)[:400]}")
    print(f"voice {line['id']} -> {dest.name} ({dest.stat().st_size} bytes)")
    return dest


def generate_sfx(item: dict) -> Path:
    dest = AUDIO / item["file"]
    if dest.exists() and dest.stat().st_size > 200:
        return dest
    body = {
        "text": item["prompt"],
        "loop": bool(item.get("loop", False)),
        "duration_seconds": max(0.5, float(item.get("duration", 1.0))),
        "prompt_influence": 0.3,
        "model_id": "eleven_text_to_sound_v2",
    }
    if not proxy_audio("https://api.elevenlabs.io/v1/sound-generation", dest, body, timeout=180):
        raise RuntimeError(f"SFX produced no file for {item['id']}")
    print(f"sfx {item['id']} -> {dest.name} ({dest.stat().st_size} bytes)")
    return dest


def generate_music(item: dict) -> Path:
    dest = AUDIO / item["file"]
    if dest.exists() and dest.stat().st_size > 200:
        return dest
    body = {
        "prompt": item["prompt"],
        "music_length_ms": int(item.get("duration_ms", 90000)),
        "force_instrumental": True,
    }
    if not proxy_audio("https://api.elevenlabs.io/v1/music", dest, body, timeout=300):
        if not proxy_audio("https://api.elevenlabs.io/v1/music/compose", dest, body, timeout=300):
            raise RuntimeError(f"Music produced no file for {item['id']}")
    print(f"music {item['id']} -> {dest.name} ({dest.stat().st_size} bytes)")
    return dest


def build_manifest(voice_src: dict, prompts: dict, records: list[dict]) -> dict:
    voice_map = {}
    for line in voice_src["lines"]:
        voice_map[line["id"]] = f"voice/{line['id'].replace('.', '_')}.mp3"
    events = {
        "order": {"bus": "UI", "file": "sfx/order.mp3", "cooldown": 0.12},
        "alert": {"bus": "UI", "file": "sfx/alert.mp3", "cooldown": 0.4},
        "shot": {
            "bus": "Effects",
            "files": ["sfx/shot_sentinel.mp3", "sfx/shot_disruptor.mp3", "sfx/shot_walker.mp3", "sfx/shot_tower.mp3"],
            "cooldown": 0.05,
        },
        "objective_updated": {"bus": "UI", "file": "sfx/objective.mp3", "cooldown": 0.3},
        "dialogue_started": {"bus": "Voice"},
        "mission_failed": {"bus": "UI", "file": "sfx/mission_failed.mp3"},
        "mission_won": {"bus": "UI", "file": "sfx/mission_won.mp3"},
        "ui_click": {"bus": "UI", "file": "sfx/ui_click.mp3", "cooldown": 0.04},
        "construction": {"bus": "Effects", "file": "sfx/construction.mp3"},
        "research": {"bus": "UI", "file": "sfx/research.mp3"},
        "ui_confirm": {"bus": "UI", "file": "sfx/ui_confirm.mp3", "cooldown": 0.08},
        "ui_error": {"bus": "UI", "file": "sfx/ui_error.mp3", "cooldown": 0.25},
        "impact": {"bus": "Effects", "file": "sfx/impact.mp3", "cooldown": 0.12, "volume": -6.0},
        "unit_destroyed": {"bus": "Effects", "file": "sfx/unit_destroyed.mp3", "cooldown": 0.2},
        "structure_destroyed": {"bus": "Effects", "file": "sfx/structure_destroyed.mp3", "cooldown": 0.3},
        "ambient": {"bus": "Effects", "file": "sfx/ambient_hum.mp3", "volume": -16.0},
    }
    return {
        "version": 1,
        "provider": "ElevenLabs via Composio",
        "model_id": voice_src.get("model_id", ""),
        "events": events,
        "voice": voice_map,
        "music": {item["id"]: item["file"] for item in prompts["music"]},
        "records": records,
    }


def main() -> int:
    if not Path(COMPOSIO).exists():
        print("composio CLI not found", file=sys.stderr)
        return 1
    voice_src = json.loads(VOICE_SRC.read_text())
    prompts = json.loads(PROMPT_SRC.read_text())
    AUDIO.mkdir(parents=True, exist_ok=True)
    (AUDIO / "voice").mkdir(exist_ok=True)
    (AUDIO / "sfx").mkdir(exist_ok=True)
    (AUDIO / "music").mkdir(exist_ok=True)

    start_credits = credits()
    print(f"credits used at start: {start_credits}")
    print("smoke TTS...")
    smoke = execute(
        "ELEVENLABS_TEXT_TO_SPEECH",
        {
            "voice_id": voice_src["voices"]["system"]["voice_id"],
            "text": "Diagnostic channel open.",
            "model_id": voice_src["model_id"],
            "output_format": voice_src["output_format"],
        },
    )
    smoke_path = Path(tempfile.gettempdir()) / "da_smoke_tts.mp3"
    if not write_audio_bytes(smoke, smoke_path):
        print("TTS smoke failed", file=sys.stderr)
        return 1
    after_tts = credits()
    print(f"TTS smoke ok, credits now {after_tts}")

    skip_music = os.environ.get("DA_SKIP_MUSIC") == "1"
    if not skip_music:
        try:
            print("smoke SFX...")
            generate_sfx(prompts["sfx"][0])
            print("smoke music...")
            generate_music(prompts["music"][3])  # shortest result cue first
        except Exception as exc:
            print(f"SFX/music smoke failed: {exc}", file=sys.stderr)
            skip_music = True
            print("continuing with voice and any existing SFX; music may be incomplete")

    records = []
    for line in voice_src["lines"]:
        dest = generate_voice(line, voice_src["voices"], voice_src["model_id"], voice_src["output_format"])
        records.append(
            {
                "id": line["id"],
                "kind": "voice",
                "speaker": line["speaker"],
                "voice_id": voice_src["voices"][line["speaker"]]["voice_id"],
                "text": line["text"],
                "file": str(dest.relative_to(AUDIO)),
                "sha256": sha256(dest),
            }
        )
        time.sleep(0.15)

    for item in prompts["sfx"]:
        try:
            dest = generate_sfx(item)
        except Exception as exc:
            print(f"skip sfx {item['id']}: {exc}", file=sys.stderr)
            continue
        records.append({"id": item["id"], "kind": "sfx", "prompt": item["prompt"], "file": item["file"], "sha256": sha256(dest)})
        time.sleep(0.2)

    if not skip_music:
        for item in prompts["music"]:
            try:
                dest = generate_music(item)
            except Exception as exc:
                print(f"skip music {item['id']}: {exc}", file=sys.stderr)
                continue
            records.append({"id": item["id"], "kind": "music", "prompt": item["prompt"], "file": item["file"], "sha256": sha256(dest)})

    manifest = build_manifest(voice_src, prompts, records)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    end_credits = credits()
    print(f"wrote {MANIFEST}")
    print(f"credits used this run: {end_credits - start_credits} (now {end_credits})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
