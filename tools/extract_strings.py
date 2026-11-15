#!/usr/bin/env python3
"""Collect every player-facing string into locale/digi-age.pot and refresh the .po files.

English text is the key. Strings come from the scripts (literals that read as prose),
the catalogue, the missions, the factions and the maps. Translations already present in
locale/<language>.po are kept; new strings are added empty, strings no longer used are
dropped.

  extract_strings.py           rewrite the template and merge the language files
  extract_strings.py --check   fail if the template on disk is out of date
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locale"
LANGUAGES = {"fr": "French", "it": "Italian", "de": "German", "es": "Spanish"}
SCRIPTS = ["text.gd", "interface.gd", "main.gd", "simulation.gd", "save_game.gd", "settings_service.gd", "catalog.gd", "mission_controller.gd"]
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
# Data fields that hold text a player reads.
FIELDS = re.compile(r'"(?:name|description|title|text)": "((?:[^"\\]|\\.)*)"')
PROPERTIES = re.compile(r'^(?:title|briefing|victory_text|defeat_text|display_name|description) = "((?:[^"\\]|\\.)*)"', re.M)
# Literals that look like prose but are not shown: asserts, log lines, paths, identifiers.
IGNORE = re.compile(
    r"^(res://|user://|/|#|--|\.|BENCHMARK|UI_EXPORT_SMOKE|Screenshot saved|Audio clip missing|DASV|Rajdhani|Cinzel|"
    r"Digital Age: Machine Civilizations|PRODUCTION_UI|[A-Z]+_[A-Z_]+$|[a-z0-9_.:/%{}\-\s]*$|%[0-9.]*[dfs]|x$)"
)
NOT_TEXT = {"Menu", "View", "Cross", "Circle", "Square", "Triangle", "Options", "Create", "English", "Français", "Italiano", "Deutsch", "Español", "Requires the ", " age.", "This operation is limited to the ", "AGE ADVANCED  /  ", "RESEARCH COMPLETE  /  ", "A", "B", "C", "T", "DIGITAL", "AGE", "Insufficient", "Time limit", "Skirmish · ", "Requires the ", "Steam", "Master", "Music", "Effects", "Voice", "UI", "Dummy", "Forward Plus", "X11", "AWAKENING", "NETWORK", "SINGULARITY", "DAInterface"}
# Bus names are shown in settings; keep those that double as labels.
KEEP = {"Master", "Music", "Effects", "Voice"}


def unescape(value: str) -> str:
    return value.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def prose(value: str) -> bool:
    if not value or not re.search(r"[A-Za-z]", value):
        return False
    if value in KEEP:
        return True
    if value in NOT_TEXT or "%d" in value or "%s" in value:
        return False
    # A sentence with a {placeholder} is always text.
    if re.search(r"\{[a-z_]+\}", value) and re.search(r"[A-Za-z]", re.sub(r"\{[a-z_]+\}", "", value)):
        return True
    if IGNORE.match(value):
        return False
    # A lower-case word with no space is an identifier ("metal", "load_slot").
    return bool(re.search(r"[A-Z]", value) or " " in value.strip())


def collect() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}

    def add(value: str, where: str) -> None:
        value = unescape(value)
        if value.strip():
            found.setdefault(value, [])
            if where not in found[value]:
                found[value].append(where)

    for name in SCRIPTS:
        path = ROOT / "scripts" / name
        if not path.exists():
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("#", 1)[0] if line.lstrip().startswith("#") else line
            if re.match(r"\s*(##|#)", line) or re.match(r"\s*(print|push_error|push_warning|assert)\(", line):
                continue
            for match in STRING.finditer(code):
                # A literal is split at "\n" when its lines are translated one by one.
                for part in unescape(match.group(1)).split("\n") if "\\n" in match.group(1) and not re.search(r"\{[a-z_]+\}", match.group(1)) else [unescape(match.group(1))]:
                    if prose(part):
                        add(part, f"scripts/{name}:{number}")
    for path in sorted((ROOT / "data").rglob("*.tres")):
        text = path.read_text()
        where = str(path.relative_to(ROOT))
        for match in FIELDS.finditer(text):
            add(match.group(1), where)
        for match in PROPERTIES.finditer(text):
            add(match.group(1), where)
    for match in FIELDS.finditer((ROOT / "scripts" / "catalog.gd").read_text()):
        add(match.group(1), "scripts/catalog.gd")
    return found


def quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
    lines = escaped.split("\n")
    if len(lines) == 1:
        return f'"{escaped}"'
    return '""\n' + "\n".join(f'"{part}\\n"' if index < len(lines) - 1 else f'"{part}"' for index, part in enumerate(lines))


def parse(path: Path) -> tuple[dict[str, str], dict[str, list[str]]]:
    """msgid -> msgstr, and msgid -> translator comment lines."""
    entries: dict[str, str] = {}
    comments: dict[str, list[str]] = {}
    if not path.exists():
        return entries, comments
    msgid, msgstr, target, pending = "", "", "", []

    def text(fragment: str) -> str:
        fragment = fragment.strip()
        return unescape(fragment[1:-1]) if len(fragment) >= 2 else ""

    def flush() -> None:
        nonlocal msgid, msgstr, target, pending
        if target == "msgstr" and msgid:
            entries[msgid] = msgstr
            comments[msgid] = pending
        msgid, msgstr, target, pending = "", "", "", []

    for raw in path.read_text().splitlines() + [""]:
        line = raw.strip()
        if line.startswith("msgid "):
            if target == "msgstr":
                flush()
            msgid, target = text(line[6:]), "msgid"
        elif line.startswith("msgstr "):
            msgstr, target = text(line[7:]), "msgstr"
        elif line.startswith('"'):
            if target == "msgid":
                msgid += text(line)
            elif target == "msgstr":
                msgstr += text(line)
        elif line.startswith("# ") and target in ("", "msgstr"):
            if target == "msgstr":
                flush()
            pending.append(line)
        elif not line:
            flush()
    return entries, comments


def render(found: dict[str, list[str]], translations: dict[str, str] | None, comments: dict[str, list[str]], language: str = "") -> str:
    header = ['msgid ""', 'msgstr ""', '"Project-Id-Version: Digital Age\\n"', '"Content-Type: text/plain; charset=UTF-8\\n"']
    if language:
        header.append(f'"Language: {language}\\n"')
    out = ["\n".join(header), ""]
    for msgid in sorted(found):
        block = list(comments.get(msgid, []))
        block.append("#: " + " ".join(found[msgid][:3]))
        block.append("msgid " + quote(msgid))
        block.append("msgstr " + quote(translations.get(msgid, "") if translations is not None else ""))
        out.append("\n".join(block))
        out.append("")
    return "\n".join(out)


def main() -> None:
    found = collect()
    LOCALE.mkdir(exist_ok=True)
    template = render(found, None, {})
    target = LOCALE / "digi-age.pot"
    if "--check" in sys.argv:
        if not target.exists() or target.read_text() != template:
            raise SystemExit("locale/digi-age.pot is out of date. Run tools/extract_strings.py.")
        print(f"{len(found)} strings, template up to date")
        return
    target.write_text(template)
    for code in LANGUAGES:
        path = LOCALE / f"{code}.po"
        translations, comments = parse(path)
        path.write_text(render(found, translations, comments, code))
        missing = sum(1 for msgid in found if not translations.get(msgid))
        print(f"{code}: {len(found) - missing} of {len(found)} translated")
    print(f"{len(found)} strings")


if __name__ == "__main__":
    main()
