extends SceneTree
## The language files: complete, consistent with the English text, drawable with the
## shipped fonts, and actually applied by the game.
var failures: int = 0
var checks: int = 0

func expect(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)

func placeholders(value: String) -> Array:
	var pattern = RegEx.new()
	pattern.compile("\\{[a-z_]+\\}")
	var found: Array = pattern.search_all(value).map(func(m): return m.get_string())
	found.sort()
	return found

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DAText.load_tables()
	var template: Dictionary = DAText.parse(DAText.DIR + "/digi-age.pot")
	expect(template.size() > 500, "the template lists the game's text (%d strings)" % template.size())
	var body: Font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	var title = FontFile.new()
	expect(title.load_dynamic_font("res://assets/fonts/Cinzel.ttf") == OK, "the title font loads")
	# The top bar's age emblem is the only text set in the title font.
	var title_ids: Array = ["{age} AGE", "Awakening", "Network", "Singularity"]
	for code in DAText.LANGUAGES:
		if code == "en":
			continue
		var table: Dictionary = DAText.parse(DAText.DIR + "/" + code + ".po")
		var missing: Array = template.keys().filter(func(id): return str(table.get(id, "")) == "")
		expect(missing.is_empty(), "%s translates every string (missing %d: %s)" % [code, missing.size(), str(missing.slice(0, 3))])
		var stale: Array = table.keys().filter(func(id): return not template.has(id))
		expect(stale.is_empty(), "%s has no strings the game no longer uses (%s)" % [code, str(stale.slice(0, 3))])
		var wrong: Array = []
		var edges: Array = []
		var glyphs: Dictionary = {}
		for id in table:
			var value: String = table[id]
			if value == "":
				continue
			if placeholders(id) != placeholders(value): wrong.append(id)
			if id.ends_with(" ") != value.ends_with(" ") or id.count("\n") != value.count("\n"): edges.append(id)
			for character in value:
				# Arrows and the like already in the English text come from the fallback font.
				if character != "\n" and not id.contains(character) and not body.has_char(character.unicode_at(0)): glyphs[character] = id
		expect(wrong.is_empty(), "%s keeps every {placeholder} (%s)" % [code, str(wrong.slice(0, 3))])
		expect(edges.is_empty(), "%s keeps line breaks and trailing spaces (%s)" % [code, str(edges.slice(0, 3))])
		expect(glyphs.is_empty(), "%s uses only characters the interface font has (%s)" % [code, str(glyphs)])
		for id in title_ids:
			for character in str(table.get(id, "")).to_upper():
				if not character in "{}" and not title.has_char(character.unicode_at(0)):
					expect(false, "%s title text '%s' needs a character the title font lacks: %s" % [code, id, character])
	# The translation function.
	DAText.set_language("de")
	expect(DAText.t("SETTINGS") == "EINSTELLUNGEN", "a plain string is translated")
	expect(DAText.t("{subject} ready.", {"subject": DAText.t("Worker")}) == "Arbeiter bereit.", "placeholders are filled after translation")
	expect(DAText.t("Requires the Network age.") == "Erfordert das Zeitalter Netzwerk.", "messages composed by the simulation are translated")
	expect(DAText.t("Hold position\nStand ground and fire only at what comes into range.").begins_with("Stellung halten\n"), "lines are translated one by one")
	expect(DAText.t("not a known string") == "not a known string", "unknown text passes through")
	expect(DAInterface.thousands(1234567) == "1.234.567" and DAInterface.compact("1.234.567") == "1.2M", "numbers are grouped for the language")
	DAText.set_language("en")
	expect(DAText.t("SETTINGS") == "SETTINGS" and DAInterface.thousands(1234567) == "1,234,567", "English is the text itself")
	expect(DAText.resolve("fr") == "fr" and DAText.resolve("auto") in DAText.LANGUAGES and DAText.resolve("xx") in DAText.LANGUAGES, "the language setting resolves to a shipped language")
	# The game applies the setting: the menu is drawn in the chosen language and it is remembered.
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.hud.set_process(false)
	var drawn = func() -> Array:
		game.hud.prepare_layout(true)
		return game.hud.text_bounds.map(func(entry): return entry.text)
	expect(game.settings.set_value("language", "en") == "", "the language can be set")
	game.apply_runtime_settings()
	expect(drawn.call().has("SETTINGS"), "the menu is English when English is chosen")
	game.ui_action("language", {})
	expect(game.settings.values.language == "fr" and drawn.call().has("RÉGLAGES"), "the next language is applied at once")
	expect(game.settings.set_value("language", "es") == "", "another language can be set")
	game.apply_runtime_settings()
	expect(drawn.call().has("AJUSTES"), "the menu follows the setting")
	var reloaded = DASettingsService.new()
	reloaded.load_settings()
	expect(reloaded.values.language == "es", "the language is remembered")
	expect(not reloaded.valid_value("language", "klingon"), "an unknown language is refused")
	game.ui_action("start")
	game._on_dialogue_requested("opening")
	expect(game.audio.voice_queue.any(func(line): return str(line.get("text", "")).begins_with("Repetidor localizado")) or game.hud.subtitle_text.begins_with("Repetidor localizado"), "subtitles are translated")
	game.settings.set_value("language", "auto")
	DAText.set_language("en")
	print("LOCALISATION_RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
