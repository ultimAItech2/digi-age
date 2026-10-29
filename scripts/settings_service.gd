class_name DASettingsService
extends RefCounted
## Validated preferences, independent from campaign data. Commit before applying.
const PATH = "user://settings.cfg"
const DEFAULTS = {"profile": "normal", "ui_scale": 1.0, "reduced_effects": false, "subtitles": true, "master_volume": 1.0, "ui_volume": 1.0, "voice_volume": 1.0, "effects_volume": 1.0, "music_volume": 0.7, "bindings": {"fullscreen": KEY_F11, "manual": KEY_F1, "cancel": KEY_ESCAPE, "pause": KEY_SPACE, "speed": KEY_F2, "events": KEY_M, "save": KEY_F5, "load": KEY_F9, "attack": KEY_A, "stop": KEY_S, "home": KEY_HOME}}
const CATEGORIES = {"audio": ["master_volume", "music_volume", "effects_volume", "voice_volume", "ui_volume"], "display": ["profile", "ui_scale", "reduced_effects", "subtitles"], "bindings": ["bindings"]}
const SCALES = [1.0, 1.15, 1.25]
var path = PATH
var values: Dictionary = DEFAULTS.duplicate(true)
var committed: Dictionary = DEFAULTS.duplicate(true)
var recovery_notice = ""

func valid_value(key: String, value: Variant) -> bool:
	if key == "bindings": return value is Dictionary and binding_error(value) == ""
	if key == "profile": return value is String and value in ["normal", "low"]
	if key == "ui_scale": return (value is float or value is int) and value in SCALES
	if key in ["reduced_effects", "subtitles"]: return value is bool
	if key.ends_with("_volume"):
		return (value is float or value is int) and is_finite(float(value)) and value >= 0 and value <= 1
	return false

func binding_error(bindings: Dictionary) -> String:
	var used: Dictionary = {}
	for action in DEFAULTS.bindings:
		if not bindings.has(action) or not bindings[action] is int: return "Invalid key binding."
		var code: int = bindings[action]
		if action == "cancel":
			if code != KEY_ESCAPE: return "Escape is reserved for cancel."
		elif code in [KEY_NONE, KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_Q, KEY_E] or (code >= KEY_0 and code <= KEY_9):
			return "That key is reserved for navigation, camera controls, or control groups."
		if OS.get_keycode_string(code) == "": return "Choose a supported keyboard key."
		if used.has(code): return "Already assigned to %s. Choose another key." % str(used[code]).capitalize()
		used[code] = action
	return ""

func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	recovery_notice = ""
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var loaded: Variant = file.get_var(false) if file else null
		if file: file.close()
		if loaded is Dictionary:
			for key in DEFAULTS:
				if not loaded.has(key): continue
				var candidate: Variant = loaded[key]
				if key == "bindings" and candidate is Dictionary:
					var merged: Dictionary = DEFAULTS.bindings.duplicate(true)
					for action in merged:
						if candidate.has(action): merged[action] = candidate[action]
					candidate = merged
				if valid_value(key, candidate): values[key] = candidate
				else: recovery_notice = "Some preferences were invalid and have been reset to defaults."
		else: recovery_notice = "Preferences could not be read. Defaults have been restored."
	committed = values.duplicate(true)

func save_settings() -> String:
	for key in DEFAULTS:
		if not values.has(key) or not valid_value(key, values[key]):
			values = committed.duplicate(true)
			return "Invalid preference. Your previous settings are unchanged."
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		values = committed.duplicate(true)
		return "Unable to save preferences. Your previous settings are unchanged."
	file.store_var(values)
	file.flush()
	var error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		values = committed.duplicate(true)
		return "Unable to commit preferences. Your previous settings are unchanged."
	committed = values.duplicate(true)
	return ""

func set_value(key: String, value: Variant) -> String:
	if not DEFAULTS.has(key) or not valid_value(key, value): return "Invalid preference."
	values[key] = value
	return save_settings()

func set_binding(action: String, keycode: int) -> String:
	if not DEFAULTS.bindings.has(action) or action == "cancel": return "This binding cannot be changed."
	var candidate: Dictionary = values.bindings.duplicate(true)
	candidate[action] = keycode
	var error = binding_error(candidate)
	if error != "": return error
	return set_value("bindings", candidate)

func reset(category: String = "all") -> String:
	if category == "all": values = DEFAULTS.duplicate(true)
	elif CATEGORIES.has(category):
		for key in CATEGORIES[category]:
			values[key] = DEFAULTS[key].duplicate(true) if DEFAULTS[key] is Dictionary else DEFAULTS[key]
	else: return "Unknown preference category."
	return save_settings()

func binding(action: String, fallback: int) -> int:
	return int(values.bindings.get(action, fallback))

func prompt(action: String) -> String:
	return OS.get_keycode_string(binding(action, KEY_NONE))
