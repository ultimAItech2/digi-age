class_name DASettingsService
extends RefCounted
## Hardware-independent settings stay separate from campaign saves and cloud data.
const PATH: String = "user://settings.cfg"
var values: Dictionary = {"profile": "normal", "ui_scale": 1.0, "reduced_effects": false, "subtitles": true, "master_volume": 1.0, "ui_volume": 1.0, "voice_volume": 1.0, "effects_volume": 1.0, "music_volume": 0.7, "bindings": {"fullscreen": KEY_F11, "manual": KEY_F1, "cancel": KEY_ESCAPE, "pause": KEY_SPACE, "speed": KEY_F2, "events": KEY_M, "save": KEY_F5, "load": KEY_F9, "attack": KEY_A, "stop": KEY_S, "home": KEY_HOME}}

func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var file = FileAccess.open(PATH, FileAccess.READ)
	var loaded = file.get_var()
	file.close()
	if loaded is Dictionary:
		for key in values:
			if loaded.has(key):
				values[key] = loaded[key].duplicate(true) if loaded[key] is Dictionary else loaded[key]

func save_settings() -> String:
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return "Unable to save settings."
	file.store_var(values)
	file.close()
	return ""

func set_value(key: String, value: Variant) -> String:
	if not values.has(key):
		return "Unknown setting."
	values[key] = value
	return save_settings()

func set_binding(action: String, keycode: int) -> String:
	if not values.bindings.has(action):
		return "Unknown binding."
	values.bindings[action] = keycode
	return save_settings()

func binding(action: String, fallback: int) -> int:
	return int(values.bindings.get(action, fallback))
