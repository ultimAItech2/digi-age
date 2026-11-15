class_name DASettingsService
extends RefCounted
## Validated preferences, independent from campaign data. Commit before applying.
const PATH = "user://settings.cfg"
const DEFAULTS = {"profile": "normal", "ui_scale": 1.0, "reduced_effects": false, "subtitles": true, "window_mode": "windowed", "resolution": "1600x900", "vsync": true, "frame_cap": 0, "shadows": true, "colorblind": false, "pause_unfocused": true, "language": "auto", "tutorial_seen": false, "pad_deadzone": 0.2, "pad_cursor_speed": "normal", "pad_glyphs": "auto", "pad_bindings": {"select": JOY_BUTTON_A, "order": JOY_BUTTON_X, "cancel": JOY_BUTTON_B, "attack": JOY_BUTTON_Y, "modifier": JOY_BUTTON_LEFT_SHOULDER, "groups": JOY_BUTTON_RIGHT_SHOULDER, "pause": JOY_BUTTON_START, "objectives": JOY_BUTTON_BACK, "speed": JOY_BUTTON_LEFT_STICK, "tech": JOY_BUTTON_RIGHT_STICK}, "muted": false, "master_volume": 1.0, "ui_volume": 1.0, "voice_volume": 1.0, "effects_volume": 1.0, "music_volume": 0.7, "skirmish": {"map": "silent_grid", "player": "origin", "enemy": "foundry", "resources": "standard", "side": "left"}, "bindings": {"fullscreen": KEY_F11, "manual": KEY_F1, "cancel": KEY_ESCAPE, "pause": KEY_SPACE, "speed": KEY_F2, "events": KEY_M, "save": KEY_F5, "load": KEY_F9, "attack": KEY_A, "stop": KEY_S, "home": KEY_HOME, "alert": KEY_N}}
const CATEGORIES = {"audio": ["master_volume", "music_volume", "effects_volume", "voice_volume", "ui_volume"], "display": ["profile", "ui_scale", "reduced_effects", "subtitles", "window_mode", "resolution", "vsync", "frame_cap", "shadows", "colorblind", "pause_unfocused", "language"], "bindings": ["bindings"], "controller": ["pad_bindings", "pad_deadzone", "pad_cursor_speed", "pad_glyphs"]}
const SCALES = [1.0, 1.15, 1.25, 1.5]
const WINDOW_MODES = ["windowed", "borderless", "fullscreen"]
const RESOLUTIONS = ["1280x720", "1280x800", "1600x900", "1920x1080", "2560x1440"]
const FRAME_CAPS = [0, 30, 60, 120, 144]
const SKIRMISH_MAPS = ["silent_grid", "relay_road", "salvage_basin", "transfer_corridor", "blackout_grid", "foundry_fortress", "lattice_web", "inheritance_core"]
const SKIRMISH_FACTIONS = ["origin", "foundry", "lattice"]
const SKIRMISH_RESOURCES = {"low": Vector3(300, 150, 0), "standard": Vector3(600, 350, 0), "high": Vector3(1500, 1000, 300)}
const SKIRMISH_SIDES = ["left", "right", "random"]
## Buttons a pad action may be bound to. Sticks, triggers and the D-pad keep their jobs.
const PAD_BUTTONS = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
const PAD_DEADZONES = [0.1, 0.2, 0.3]
const PAD_SPEEDS = ["slow", "normal", "fast"]
const PAD_GLYPHS = ["auto", "xbox", "playstation", "deck"]
## Keyboard actions that have a pad button of their own, and the two on the D-pad.
const PAD_EQUIVALENT = {"attack": "attack", "pause": "pause", "speed": "speed", "cancel": "cancel"}
const PAD_DIRECTIONS = {"home": "←", "alert": "↓"}
var path = PATH
## Set by the game: prompts name pad buttons while a pad is in use.
var input: DAInput
var values: Dictionary = DEFAULTS.duplicate(true)
var committed: Dictionary = DEFAULTS.duplicate(true)
var recovery_notice = ""

func valid_value(key: String, value: Variant) -> bool:
	if key == "bindings": return value is Dictionary and binding_error(value) == ""
	if key == "pad_bindings":
		if not value is Dictionary: return false
		var seen: Dictionary = {}
		for action in DEFAULTS.pad_bindings:
			if not value.has(action) or not value[action] is int or value[action] not in PAD_BUTTONS or seen.has(value[action]): return false
			seen[value[action]] = true
		return true
	if key == "pad_deadzone": return (value is float or value is int) and PAD_DEADZONES.any(func(entry): return is_equal_approx(entry, float(value)))
	if key == "pad_cursor_speed": return value is String and value in PAD_SPEEDS
	if key == "pad_glyphs": return value is String and value in PAD_GLYPHS
	if key == "skirmish":
		return value is Dictionary and value.get("map") in SKIRMISH_MAPS and value.get("player") in SKIRMISH_FACTIONS and value.get("enemy") in SKIRMISH_FACTIONS and SKIRMISH_RESOURCES.has(value.get("resources")) and value.get("side") in SKIRMISH_SIDES
	if key == "profile": return value is String and value in ["normal", "low"]
	if key == "ui_scale": return (value is float or value is int) and value in SCALES
	if key in ["reduced_effects", "subtitles", "vsync", "shadows", "colorblind", "pause_unfocused", "tutorial_seen", "muted"]: return value is bool
	if key == "window_mode": return value is String and value in WINDOW_MODES
	if key == "language": return value is String and (value == "auto" or value in DAText.LANGUAGES)
	if key == "resolution": return value is String and value in RESOLUTIONS
	if key == "frame_cap": return value is int and value in FRAME_CAPS
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
		elif code in [KEY_NONE, KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_D, KEY_F, KEY_G, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_PERIOD] or (code >= KEY_0 and code <= KEY_9):
			return "That key is reserved for navigation, the command grid, or control groups."
		elif (code == KEY_A and action != "attack") or (code == KEY_S and action != "stop"):
			# A and S are command-grid slots; only the orders that sit there may keep them.
			return "That key is reserved for navigation, the command grid, or control groups."
		if OS.get_keycode_string(code) == "": return "Choose a supported keyboard key."
		if used.has(code): return DAText.t("Already assigned to {action}. Choose another key.", {"action": DAText.t(str(DAInterface.BINDING_NAMES.get(used[code], str(used[code]).capitalize())))})
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
				if key in ["bindings", "pad_bindings"] and candidate is Dictionary:
					var merged: Dictionary = DEFAULTS[key].duplicate(true)
					for action in merged:
						if candidate.has(action): merged[action] = candidate[action]
					candidate = merged
				if valid_value(key, candidate): values[key] = candidate
				else: recovery_notice = "Some preferences were invalid and have been reset to defaults."
		else: recovery_notice = "Preferences could not be read. Defaults have been restored."
	elif on_deck():
		# First launch on a Steam Deck: its 1280 x 800 screen wants larger text, and no window.
		values.ui_scale = 1.25
		values.window_mode = "fullscreen"
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

## Binding a pad button that another action holds swaps the two.
func set_pad_binding(action: String, button: int) -> String:
	if not DEFAULTS.pad_bindings.has(action): return "This binding cannot be changed."
	if button not in PAD_BUTTONS: return "That button cannot be assigned. Sticks, triggers and the D-pad keep their jobs."
	var candidate: Dictionary = values.pad_bindings.duplicate(true)
	for other in candidate:
		if candidate[other] == button: candidate[other] = candidate[action]
	candidate[action] = button
	return set_value("pad_bindings", candidate)

## Valve sets SteamDeck=1 for everything it launches on a Steam Deck.
static func on_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1"

func reset(category: String = "all") -> String:
	if category == "all": values = DEFAULTS.duplicate(true)
	elif CATEGORIES.has(category):
		for key in CATEGORIES[category]:
			values[key] = DEFAULTS[key].duplicate(true) if DEFAULTS[key] is Dictionary else DEFAULTS[key]
	else: return "Unknown preference category."
	return save_settings()

## The next choice in a list setting, wrapping around.
func cycle(key: String, choices: Array) -> String:
	return set_value(key, choices[(choices.find(values[key]) + 1) % choices.size()])

func toggle(key: String) -> String:
	return set_value(key, not values[key])

func binding(action: String, fallback: int) -> int:
	return int(values.bindings.get(action, fallback))

func prompt(action: String) -> String:
	if input and input.device == "pad":
		if PAD_EQUIVALENT.has(action): return input.prompt(PAD_EQUIVALENT[action])
		if PAD_DIRECTIONS.has(action): return DAText.t("D-pad {direction}", {"direction": PAD_DIRECTIONS[action]})
	return DAText.t(key_label(binding(action, KEY_NONE)))

## Key names that are words, so they can be translated.
const KEY_WORDS = ["Space", "Escape", "Home", "End", "Enter", "Tab", "Shift", "Ctrl", "Alt", "Insert", "Delete", "Backspace", "Page Up", "Page Down", "Left", "Right", "Up", "Down"]

## The name printed on the key at this physical position in the player's keyboard layout.
static func key_label(physical: int) -> String:
	# A headless run has no keyboard layout to ask.
	var label: int = DisplayServer.keyboard_get_label_from_physical(physical as Key) if DisplayServer.get_name() != "headless" else KEY_NONE
	return OS.get_keycode_string(label if label != KEY_NONE else physical)

## Development switches (--demo, --benchmark, --autoplay, --focus, ...) given after "--".
## A release export ignores them unless it was built with the "dev" feature.
static func dev_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if OS.is_debug_build() or OS.has_feature("dev") else PackedStringArray()
