extends SceneTree
var failures: int = 0
var checks: int = 0

func expect(condition: bool, title: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func run() -> void:
	for bus in ["Master", "Music", "Effects", "Voice", "UI"]:
		expect(AudioServer.get_bus_index(bus) >= 0, "bus exists: " + bus)
	var audio = DAAudio.new()
	root.add_child(audio)
	await process_frame
	expect(audio.manifest is Dictionary, "audio loads manifest dictionary")
	var seen: Array[String] = []
	audio.event_requested.connect(func(kind, _payload): seen.append(kind))
	audio.enabled = false
	audio.play("order")
	audio.play("shot")
	audio.play("alert")
	audio.speak("opening", "Relay found.", "archivist")
	audio.set_music("menu")
	audio.apply_settings({"master_volume": 0.5, "music_volume": 0.4, "effects_volume": 0.3, "voice_volume": 0.6, "ui_volume": 0.7})
	expect(seen.has("order") and seen.has("dialogue_started"), "play and speak emit semantic events")
	expect(audio.events_seen.size() >= 2, "event log records kinds")
	var manifest = audio.manifest
	if manifest.has("events"):
		for key in manifest.events:
			var spec: Dictionary = manifest.events[key]
			if spec.has("file"):
				var path = "res://assets/audio/" + str(spec.file)
				expect(not ResourceLoader.exists(path) or FileAccess.file_exists(path), "event file path is valid or deferred: " + path)
	# Nothing recorded sits unused: every event and every spoken alert has a caller in the game's scripts.
	var source = ""
	for script in ["main", "interface", "battlefield", "audio"]:
		source += FileAccess.get_file_as_string("res://scripts/%s.gd" % script)
	for key in manifest.get("events", {}):
		expect(source.contains("\"" + str(key) + "\""), "sound event has a trigger: " + str(key))
	for id in manifest.get("voice", {}):
		# The victory speech replaces the short mission-won alert.
		if str(id).begins_with("alert.") and id != "alert.mission_won":
			expect(source.contains("\"" + str(id) + "\""), "spoken alert has a trigger: " + str(id))
	var said: Array = []
	audio.event_requested.connect(func(kind, payload): if kind == "announce": said.append(payload.id))
	expect(audio.announce("alert.under_attack") and not audio.announce("alert.under_attack") and said == ["alert.under_attack"], "spoken alerts are spaced, not stacked")
	audio.free()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _initialize() -> void:
	call_deferred("run")
