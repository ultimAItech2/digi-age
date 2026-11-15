class_name DAText
extends RefCounted
## Every string a player reads goes through here. The English text is the key;
## `locale/<language>.po` holds the translations. Text is translated where it is
## drawn (interface.gd `text()`), so plain literals need nothing; a sentence built
## from parts uses `DAText.t("{unit} ready.", {"unit": name})` so the whole
## sentence can be reordered by a translator.
const LANGUAGES: Array[String] = ["en", "fr", "it", "de", "es"]
const NAMES: Dictionary = {"en": "English", "fr": "Français", "it": "Italiano", "de": "Deutsch", "es": "Español"}
## Digit grouping: 12,500 / 12 500 / 12.500.
const GROUPING: Dictionary = {"en": ",", "fr": " ", "it": ".", "de": ".", "es": "."}
const DIR: String = "res://locale"
## Marks around text that went through translation while `pseudo` is on. The
## localisation test strips them: letters left outside are untranslated text.
const OPEN: String = "[~"
const CLOSE: String = "~]"

static var language: String = "en"
## Test mode: every known string is wrapped in markers and padded by a third,
## the length German tends to add.
static var pseudo: bool = false
static var tables: Dictionary = {}
static var known: Dictionary = {}
static var loaded: bool = false
## While `pseudo` is on, every string handed to the interface for drawing.
static var seen: Array[String] = []
## Messages the simulation composes around a name: [prefix, suffix, key].
const PATTERNS: Array = [
	["Requires the ", " age.", "Requires the {value} age."],
	["This operation is limited to the ", " age.", "This operation is limited to the {value} age."],
]

## The language to use for a setting value: a language code, or "auto" for the system's.
static func resolve(setting: String) -> String:
	if setting in LANGUAGES:
		return setting
	var system: String = OS.get_locale_language()
	return system if system in LANGUAGES else "en"

static func set_language(code: String) -> void:
	load_tables()
	language = code if code in LANGUAGES else "en"

static func load_tables() -> void:
	if loaded:
		return
	loaded = true
	for id in parse(DIR + "/digi-age.pot"):
		known[id] = true
	for code in LANGUAGES:
		if code == "en":
			continue
		var table: Dictionary = parse(DIR + "/" + code + ".po")
		for id in table.keys():
			if table[id] == "":
				table.erase(id)
		tables[code] = table

## msgid → msgstr from a gettext file. Plural forms and contexts are not used.
static func parse(path: String) -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(path):
		return result
	var id: String = ""
	var value: String = ""
	var target: String = ""
	for raw in (FileAccess.get_file_as_string(path) + "\n").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("msgid "):
			if target == "msgstr" and id != "":
				result[id] = value
			id = unquote(line.substr(6))
			value = ""
			target = "msgid"
		elif line.begins_with("msgstr "):
			value = unquote(line.substr(7))
			target = "msgstr"
		elif line.begins_with("\""):
			if target == "msgid": id += unquote(line)
			elif target == "msgstr": value += unquote(line)
		elif line == "" and target == "msgstr":
			if id != "":
				result[id] = value
			id = ""
			value = ""
			target = ""
	return result

static func unquote(quoted: String) -> String:
	var body: String = quoted.strip_edges()
	if body.length() >= 2 and body.begins_with("\"") and body.ends_with("\""):
		body = body.substr(1, body.length() - 2)
	return body.c_unescape()

## The text in the current language, with `{name}` placeholders filled from `args`.
## Unknown text comes back unchanged, so already-translated text passes through.
static func t(msgid: String, args: Dictionary = {}) -> String:
	var out: String = msgid
	if msgid != "":
		if pseudo:
			if (known.has(msgid) or not args.is_empty()) and not msgid.contains(OPEN):
				out = OPEN + msgid + "~".repeat(ceili(letters(msgid) * 0.35)) + CLOSE
		elif language != "en":
			out = str(tables.get(language, {}).get(msgid, msgid))
		if out == msgid and args.is_empty() and (pseudo or language != "en"):
			for pattern in PATTERNS:
				if msgid.begins_with(pattern[0]) and msgid.ends_with(pattern[1]) and msgid.length() > pattern[0].length() + pattern[1].length():
					return t(pattern[2], {"value": t(msgid.substr(pattern[0].length(), msgid.length() - pattern[0].length() - pattern[1].length()))})
			# Several lines are translated one by one.
			if msgid.contains("\n"):
				return lines(msgid)
	return out.format(args) if not args.is_empty() else out

## Letters and spaces outside {placeholders}: the part of a string a translation lengthens.
static func letters(value: String) -> int:
	var count: int = 0
	var inside: bool = false
	for character in value:
		if character == "{": inside = true
		elif character == "}": inside = false
		elif not inside and (character == " " or character.to_upper() != character.to_lower()): count += 1
	return count

## Several lines, each translated on its own.
static func lines(value: String) -> String:
	var parts: PackedStringArray = value.split("\n")
	for i in parts.size():
		parts[i] = t(parts[i])
	return "\n".join(parts)

## A name that is data, not prose (a unit, an age, a faction): translated when known.
static func name(value: String) -> String:
	return t(value)

## Upper case in the current language's rules, for headings.
static func upper(msgid: String, args: Dictionary = {}) -> String:
	return t(msgid, args).to_upper()

static func grouping() -> String:
	return str(GROUPING.get(language, ","))

## What `pseudo` text looks like with the marked (translated) parts removed.
static func unmarked(value: String) -> String:
	var out: String = ""
	var depth: int = 0
	var i: int = 0
	while i < value.length():
		if value.substr(i, 2) == OPEN:
			depth += 1
			i += 2
		elif value.substr(i, 2) == CLOSE and depth > 0:
			depth -= 1
			i += 2
		else:
			if depth == 0:
				out += value[i]
			i += 1
	return out
