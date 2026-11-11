class_name DAAudio
extends Node
## Offline audio mixer. Assets are generated ahead of time; missing files stay silent.
signal event_requested(event_id: String, payload: Dictionary)
signal subtitle_shown(speaker: String, text: String, duration: float)

const MANIFEST_PATH := "res://assets/audio/manifest.json"
const MAX_SHOTS_PER_WINDOW := 4
var enabled: bool = true
var events_seen: Array[String] = []
var manifest: Dictionary = {}
var streams: Dictionary = {}
var pools: Dictionary = {}
var last_played: Dictionary = {}
var shot_window: float = 0.0
var shots_in_window: int = 0
var music_player: AudioStreamPlayer
var current_music: String = ""
var combat_left: float = 0.0
var voice_player: AudioStreamPlayer
var voice_queue: Array[Dictionary] = []
var warned_missing: Dictionary = {}
var caption_left: float = 0.0
var caption_pages: Array[Dictionary] = []
## Short spoken alerts ("under attack"): their own player, spaced so they never pile up.
const ANNOUNCE_GAP := 3.0
const ANNOUNCE_REPEAT := 14.0
var announce_player: AudioStreamPlayer
var announce_last: Dictionary = {}
var announce_time: float = -100.0
var ambient_player: AudioStreamPlayer

func _ready() -> void:
	_load_manifest()
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = "Voice"
	voice_player.finished.connect(_on_voice_finished)
	add_child(voice_player)
	announce_player = AudioStreamPlayer.new()
	announce_player.bus = "Voice"
	add_child(announce_player)
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Effects"
	add_child(ambient_player)
	for bus in ["Music", "Effects", "Voice", "UI"]:
		pools[bus] = []

func _process(dt: float) -> void:
	if caption_left > 0:
		caption_left = maxf(0, caption_left-dt)
		if caption_left <= 0:
			if not caption_pages.is_empty(): _next_caption()
			elif not voice_player.playing: _play_next_voice()
	shot_window = maxf(0.0, shot_window - dt)
	if shot_window <= 0.0:
		shots_in_window = 0
	if combat_left > 0.0:
		combat_left = maxf(0.0, combat_left - dt)
		if current_music == "ambient" and combat_left > 0.0:
			set_music("combat")
		elif current_music == "combat" and combat_left <= 0.0:
			set_music("ambient")

func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		manifest = parsed

func play(kind: String, payload: Dictionary = {}) -> void:
	if not events_seen.has(kind):
		events_seen.append(kind)
	event_requested.emit(kind, payload)
	var resolved = _alias(kind)
	if not enabled or DisplayServer.get_name() == "headless":
		return
	if resolved == "shot":
		if shots_in_window >= MAX_SHOTS_PER_WINDOW:
			return
		if shot_window <= 0.0:
			shot_window = 0.12
		shots_in_window += 1
	var spec = (manifest.get("events", {}) as Dictionary).get(resolved, {})
	if spec is Dictionary and not spec.is_empty():
		var cooldown = float(spec.get("cooldown", 0.0))
		if cooldown > 0.0 and Time.get_ticks_msec() * 0.001 - float(last_played.get(resolved, -999.0)) < cooldown:
			return
		last_played[resolved] = Time.get_ticks_msec() * 0.001
		var path = _event_path(spec, payload)
		_play_path(path, str(spec.get("bus", "Effects")), float(spec.get("volume", 0.0)))

func speak(dialogue_id: String, text: String = "", speaker: String = "archivist") -> void:
	play("dialogue_started", {"id": dialogue_id, "text": text, "speaker": speaker})
	var voices: Dictionary = manifest.get("voice", {})
	var path = str(voices.get(dialogue_id, ""))
	if path == "" and dialogue_id.contains("."):
		path = str(voices.get(dialogue_id.get_slice(".", 1), ""))
	if path == "":
		path = str(voices.get(speaker + "." + dialogue_id, ""))
	if path == "" and text == "":
		return
	voice_queue.append({"path": path, "text": text, "speaker": speaker})
	if not voice_player.playing and caption_left <= 0:
		_play_next_voice()

## A spoken alert from the manifest's voice table. Dialogue keeps priority, and
## the same line is not repeated within ANNOUNCE_REPEAT seconds.
## An urgent line (the base is under attack) is not held back by a line that just played.
func announce(id: String, urgent: bool = false) -> bool:
	var now = Time.get_ticks_msec() * 0.001
	if (not urgent and now - announce_time < ANNOUNCE_GAP) or now - float(announce_last.get(id, -100.0)) < ANNOUNCE_REPEAT:
		return false
	announce_time = now
	announce_last[id] = now
	play("announce", {"id": id})
	if not enabled or DisplayServer.get_name() == "headless" or voice_player.playing:
		return true
	var stream = _stream(str((manifest.get("voice", {}) as Dictionary).get(id, "")))
	if stream:
		announce_player.stream = stream
		announce_player.play()
	return true

## The low machine hum under a match; silent in the menu and on the result screen.
func update_ambient() -> void:
	if not ambient_player:
		return
	var wanted = enabled and current_music in ["ambient", "combat"] and DisplayServer.get_name() != "headless"
	if wanted and not ambient_player.playing:
		var spec: Dictionary = (manifest.get("events", {}) as Dictionary).get("ambient", {})
		var stream = _stream(str(spec.get("file", "")))
		if stream:
			if stream is AudioStreamMP3:
				stream.loop = true
			ambient_player.stream = stream
			ambient_player.volume_db = float(spec.get("volume", -16.0))
			ambient_player.play()
	elif not wanted and ambient_player.playing:
		ambient_player.stop()

func set_music(state: String) -> void:
	if state == current_music:
		return
	if state == "combat" and current_music in ["menu", "result"]:
		return
	current_music = state
	update_ambient()
	if not enabled or DisplayServer.get_name() == "headless":
		return
	var tracks: Dictionary = manifest.get("music", {})
	var path = str(tracks.get(state, ""))
	var stream = _stream(path)
	if stream == null:
		return
	if music_player.stream != stream:
		music_player.stream = stream
		music_player.play()

func notify_combat() -> void:
	combat_left = 8.0

func set_bus_volume(bus: String, linear: float) -> void:
	var index = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(bus == "Master" and linear <= 0.001, false)

func apply_settings(values: Dictionary) -> void:
	var master = float(values.get("master_volume", 1.0)) if enabled else 0.0
	_set_linear("Master", master)
	_set_linear("Music", float(values.get("music_volume", values.get("ui_volume", 0.8))))
	_set_linear("Effects", float(values.get("effects_volume", 1.0)))
	_set_linear("Voice", float(values.get("voice_volume", 1.0)))
	_set_linear("UI", float(values.get("ui_volume", 1.0)))
	if music_player and enabled and current_music != "" and not music_player.playing:
		set_music(current_music)
	if not enabled and music_player:
		music_player.stop()
		voice_player.stop()
		announce_player.stop()
	update_ambient()

func _set_linear(bus: String, linear: float) -> void:
	var index = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))
	if bus == "Master":
		AudioServer.set_bus_mute(index, linear <= 0.001)

func _alias(kind: String) -> String:
	if kind == "order_issued":
		return "order"
	if kind == "weapon_fired":
		return "shot"
	if kind == "mission_won":
		return "mission_won"
	return kind

func _event_path(spec: Dictionary, payload: Dictionary) -> String:
	if spec.has("files"):
		var files: Array = spec.files
		if payload.has("kind"):
			for path in files:
				if str(path).contains(str(payload.kind)):
					return str(path)
		if not files.is_empty():
			return str(files[randi() % files.size()])
	return str(spec.get("file", ""))

func _play_path(path: String, bus: String, volume_db: float) -> void:
	var stream = _stream(path)
	if stream == null:
		return
	var player = _borrow(bus)
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func _borrow(bus: String) -> AudioStreamPlayer:
	if not pools.has(bus):
		pools[bus] = []
	for player in pools[bus]:
		if not player.playing:
			return player
	var player = AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	pools[bus].append(player)
	return player

func _stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not path.begins_with("res://"):
		path = "res://assets/audio/" + path
	if streams.has(path):
		return streams[path]
	if not ResourceLoader.exists(path):
		if not warned_missing.has(path):
			warned_missing[path] = true
		return null
	var stream = load(path)
	if stream is AudioStream:
		if stream is AudioStreamMP3:
			stream.loop = path.contains("/music/")
		streams[path] = stream
		return stream
	return null

func _play_next_voice() -> void:
	if voice_queue.is_empty():
		return
	var next: Dictionary = voice_queue.pop_front()
	var stream = _stream(str(next.get("path", "")))
	var words = str(next.get("text", "")).split(" ")
	var pages: Array[String] = []
	var page = ""
	for word in words:
		if (page+" "+word).length() > 145 and page != "":
			pages.append(page)
			page = ""
		page += (" " if page != "" else "") + word
	if page != "": pages.append(page)
	var duration = maxf(stream.get_length() if stream else 0.0, maxf(3.5,str(next.text).length()*.065))
	for caption in pages:
		caption_pages.append({"text":caption,"speaker":next.speaker,"duration":duration*caption.length()/maxi(1,str(next.text).length())})
	if not caption_pages.is_empty(): _next_caption()
	if stream and enabled and DisplayServer.get_name() != "headless":
		voice_player.stream = stream
		voice_player.play()
	elif caption_left <= 0: _play_next_voice()

func _next_caption() -> void:
	var caption: Dictionary = caption_pages.pop_front()
	caption_left = caption.duration
	subtitle_shown.emit(caption.speaker, caption.text, caption.duration)

func clear_dialogue() -> void:
	voice_queue.clear()
	caption_pages.clear()
	caption_left = 0
	if voice_player: voice_player.stop()

func _on_voice_finished() -> void:
	if caption_left <= 0 and caption_pages.is_empty(): _play_next_voice()

func _exit_tree() -> void:
	voice_queue.clear()
	if music_player:
		music_player.stop()
		music_player.stream = null
	if voice_player:
		voice_player.stop()
		voice_player.stream = null
	for player in [announce_player, ambient_player]:
		if player:
			player.stop()
			player.stream = null
	for bus in pools:
		for player in pools[bus]:
			if is_instance_valid(player):
				player.stop()
				player.stream = null
	streams.clear()
