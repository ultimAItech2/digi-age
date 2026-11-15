class_name DAInput
extends RefCounted
## Gamepad play. The pad drives the same paths as the mouse and keyboard: a virtual
## cursor stands in for the pointer, and buttons are turned into the clicks and
## commands the game already understands. Stick and trigger state is built from the
## events themselves, so a test can drive it without a device.
##
## In a match: left stick moves the cursor, right stick pans, LT + right stick zooms.
## The bound buttons select, order, cancel and attack-move. Holding RT opens the
## command grid on the D-pad; holding the groups button recalls control groups.
## In menus the D-pad or left stick moves the focus.
const FAMILIES: Array[String] = ["xbox", "playstation", "deck"]
## What each button is called on each family of pad.
const LABELS: Dictionary = {
	"xbox": {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS", "lt": "LT", "rt": "RT"},
	"playstation": {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Create", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", "lt": "L2", "rt": "R2"},
	"deck": {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", "lt": "L2", "rt": "R2"},
}
## The D-pad's four directions, in the order control groups 1 to 4 use them.
const DPAD: Array = [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]
const DPAD_VECTOR: Dictionary = {JOY_BUTTON_DPAD_UP: Vector2(0, -1), JOY_BUTTON_DPAD_RIGHT: Vector2(1, 0), JOY_BUTTON_DPAD_DOWN: Vector2(0, 1), JOY_BUTTON_DPAD_LEFT: Vector2(-1, 0)}
## What the bare D-pad does in a match.
const DPAD_ACTIONS: Dictionary = {JOY_BUTTON_DPAD_UP: "idle_worker", JOY_BUTTON_DPAD_RIGHT: "army", JOY_BUTTON_DPAD_DOWN: "jump_alert", JOY_BUTTON_DPAD_LEFT: "home"}
const TRIGGER_ON: float = 0.5
const CURSOR_SPEEDS: Dictionary = {"slow": 0.55, "normal": 0.85, "fast": 1.25}
const REPEAT_DELAY: float = 0.35
const REPEAT_RATE: float = 0.12

var game: Node3D
## "kbm" or "pad": whichever the player touched last. Prompts follow it.
var device: String = "kbm"
var family: String = "xbox"
var cursor: Vector2 = Vector2.ZERO
var left: Vector2 = Vector2.ZERO
var right: Vector2 = Vector2.ZERO
var triggers: Dictionary = {"lt": 0.0, "rt": 0.0}
var held: Dictionary = {}
## The command-grid slot under the D-pad while the grid trigger is held.
var grid_index: int = 0
var grid_open: bool = false
var repeat_left: float = 0.0
var stick_direction: Vector2 = Vector2.ZERO
## True while a click made from a pad button is being delivered.
var injecting: bool = false

func setup(controller: Node3D) -> void:
	game = controller
	cursor = controller.get_viewport().get_visible_rect().size * 0.5

func settings() -> DASettingsService:
	return game.settings

func deadzone() -> float:
	return float(settings().values.get("pad_deadzone", 0.2))

func button_for(action: String) -> int:
	return int(settings().values.pad_bindings.get(action, DASettingsService.DEFAULTS.pad_bindings[action]))

func is_held(action: String) -> bool:
	return held.get(button_for(action), false)

## Where the pointer is: the virtual cursor on a pad, the mouse otherwise.
func pointer() -> Vector2:
	return cursor if device == "pad" else game.get_viewport().get_mouse_position()

## The name of a pad button, or of the trigger "lt"/"rt", on the player's pad.
func label(button: Variant) -> String:
	var chosen: String = str(settings().values.get("pad_glyphs", "auto"))
	var names: Dictionary = LABELS[chosen if chosen in FAMILIES else family]
	return str(names.get(button, "?"))

## The pad button bound to an action, by name; "" when the action has no pad button.
func prompt(action: String) -> String:
	if action in ["grid"]: return label("rt")
	if action in ["zoom"]: return label("lt")
	if settings().values.pad_bindings.has(action): return label(button_for(action))
	return ""

static func family_of(name: String) -> String:
	var lower: String = name.to_lower()
	if lower.contains("sony") or lower.contains("dualsense") or lower.contains("dualshock") or lower.contains("ps4") or lower.contains("ps5") or lower.contains("playstation"):
		return "playstation"
	if lower.contains("steam deck") or lower.contains("valve") or lower.contains("steam virtual"):
		return "deck"
	return "xbox"

func use(kind: String, pad_id: int = -1) -> void:
	if kind == "pad" and pad_id >= 0:
		var detected: String = family_of(Input.get_joy_name(pad_id))
		if DASettingsService.on_deck(): detected = "deck"
		if detected != family:
			family = detected
			game.hud.layout_signature = ""
	if kind == device:
		return
	device = kind
	if kind == "pad":
		cursor = game.get_viewport().get_mouse_position() if DisplayServer.get_name() != "headless" else cursor
		clamp_cursor()
	else:
		release_all()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if kind == "pad" else Input.MOUSE_MODE_VISIBLE
	game.hud.layout_signature = ""

func clamp_cursor() -> void:
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	cursor = cursor.clamp(Vector2.ZERO, size - Vector2.ONE)

func release_all() -> void:
	if is_held("select") and game.dragging:
		click(MOUSE_BUTTON_LEFT, false)
	held.clear()
	left = Vector2.ZERO
	right = Vector2.ZERO
	triggers = {"lt": 0.0, "rt": 0.0}
	grid_open = false

## Deliver a mouse button at the cursor through the game's own input path.
func click(button: int, pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.position = cursor
	event.global_position = cursor
	event.button_index = button
	event.pressed = pressed
	event.shift_pressed = is_held("modifier")
	injecting = true
	game._input(event)
	injecting = false

func key(code: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	injecting = true
	game._input(event)
	injecting = false

## True when the event was a pad event and has been dealt with.
func handle(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		motion(event)
		return true
	if event is InputEventJoypadButton:
		use("pad", event.device)
		if event.pressed: press(event.button_index)
		else: release(event.button_index)
		return true
	if not injecting and (event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2)):
		use("kbm")
	return false

func motion(event: InputEventJoypadMotion) -> void:
	var value: float = event.axis_value
	match event.axis:
		JOY_AXIS_LEFT_X: left.x = value
		JOY_AXIS_LEFT_Y: left.y = value
		JOY_AXIS_RIGHT_X: right.x = value
		JOY_AXIS_RIGHT_Y: right.y = value
		JOY_AXIS_TRIGGER_LEFT: triggers.lt = value
		JOY_AXIS_TRIGGER_RIGHT:
			triggers.rt = value
			set_grid(value >= TRIGGER_ON)
	if absf(value) > maxf(deadzone(), 0.35):
		use("pad", event.device)

## Stick position with the dead zone removed and the rest rescaled to 0..1.
func shaped(stick: Vector2) -> Vector2:
	var length: float = stick.length()
	var dead: float = deadzone()
	if length <= dead:
		return Vector2.ZERO
	return stick / length * minf(1.0, (length - dead) / (1.0 - dead))

func set_grid(open: bool) -> void:
	if open == grid_open:
		return
	grid_open = open and not game.hud.modal_active() and game.mode == "playing"
	if grid_open:
		grid_index = first_grid_slot()
	else:
		game.hud.focus_keyboard = false
	game.hud.layout_signature = ""
	focus_grid()

func grid_buttons() -> Dictionary:
	game.hud.prepare_layout(true)
	var slots: Dictionary = {}
	for b in game.hud.buttons:
		if b.payload.has("slot"): slots[int(b.payload.slot)] = b
	return slots

func first_grid_slot() -> int:
	var slots: Dictionary = grid_buttons()
	var keys: Array = slots.keys()
	keys.sort()
	return int(keys[0]) if not keys.is_empty() else 0

func focus_grid() -> void:
	if not grid_open:
		return
	var slots: Dictionary = grid_buttons()
	if slots.has(grid_index):
		game.hud.focused = slots[grid_index].id
		game.hud.focus_keyboard = true
	game.hud.layout_signature = ""

## Move across the command grid, skipping empty slots in that direction.
func move_grid(direction: Vector2) -> void:
	var slots: Dictionary = grid_buttons()
	if slots.is_empty():
		return
	var columns: int = DAInterface.GRID_COLS
	var rows: int = DAInterface.GRID_ROWS
	var column: int = grid_index % columns
	var row: int = grid_index / columns
	for step in maxi(columns, rows):
		column = posmod(column + int(direction.x), columns)
		row = posmod(row + int(direction.y), rows)
		if slots.has(row * columns + column):
			grid_index = row * columns + column
			break
	focus_grid()

func press(button: int) -> void:
	held[button] = true
	var hud = game.hud
	# Settings is waiting for a pad button to bind.
	if hud.settings_open and hud.rebind_action.begins_with("pad:"):
		var error: String = settings().set_pad_binding(hud.rebind_action.substr(4), button)
		hud.rebind_action = ""
		hud.toast("Binding updated" if error == "" else error, "success" if error == "" else "error")
		hud.prepare_layout(true)
		return
	if hud.modal_active():
		press_in_menu(button)
		return
	if grid_open:
		if button in DPAD:
			move_grid(DPAD_VECTOR[button])
		elif button == button_for("select"):
			var slots: Dictionary = grid_buttons()
			if slots.has(grid_index): hud.activate(slots[grid_index])
			focus_grid()
		elif button == button_for("cancel"):
			set_grid(false)
		return
	if button in DPAD:
		if is_held("groups"):
			group(DPAD.find(button) + 1)
		else:
			game.ui_action(DPAD_ACTIONS[button])
		return
	if button == button_for("select"):
		click(MOUSE_BUTTON_LEFT, true)
	elif button == button_for("order"):
		click(MOUSE_BUTTON_RIGHT, true)
	elif button == button_for("cancel"):
		if game.build_kind != "" or game.attack_mode or game.rally_mode or game.patrol_mode or game.ability_mode:
			game.cancel_modes()
		else:
			game.selected.clear()
	elif button == button_for("attack"):
		game.begin_attack_move()
	elif button == button_for("pause"):
		game.toggle_pause()
	elif button == button_for("objectives"):
		game.ui_action("objectives")
	elif button == button_for("speed"):
		game.ui_action("speed")
	elif button == button_for("tech"):
		game.ui_action("tech")

func press_in_menu(button: int) -> void:
	var hud = game.hud
	if button in DPAD:
		hud.focus_move(DPAD_VECTOR[button])
	elif button == button_for("select"):
		hud.focus_activate()
	elif button == button_for("cancel"):
		key(KEY_ESCAPE)
	elif button == button_for("pause") and game.mode == "paused" and not hud.overlay_open():
		game.toggle_pause()
	elif button == JOY_BUTTON_LEFT_SHOULDER:
		hud.scroll_by(-240)
	elif button == JOY_BUTTON_RIGHT_SHOULDER:
		hud.scroll_by(240)

func release(button: int) -> void:
	var was: bool = held.get(button, false)
	held.erase(button)
	if not was or game.hud.modal_active():
		return
	if button == button_for("select") and not grid_open:
		click(MOUSE_BUTTON_LEFT, false)

## Control groups: with the modifier held the selection is saved, otherwise recalled.
func group(number: int) -> void:
	if is_held("modifier"):
		game.save_group(number)
	else:
		game.recall_group(number)

func step(dt: float) -> void:
	if device != "pad":
		return
	var hud = game.hud
	var move: Vector2 = shaped(left)
	var look: Vector2 = shaped(right)
	if hud.modal_active():
		# The left stick steps the focus, with a repeat while it is held over.
		var direction: Vector2 = Vector2.ZERO
		if move.length() > 0.5:
			direction = Vector2(signf(move.x), 0) if absf(move.x) > absf(move.y) else Vector2(0, signf(move.y))
		if direction != stick_direction:
			stick_direction = direction
			repeat_left = REPEAT_DELAY
			if direction != Vector2.ZERO: hud.focus_move(direction)
		elif direction != Vector2.ZERO:
			repeat_left -= dt
			if repeat_left <= 0:
				repeat_left = REPEAT_RATE
				hud.focus_move(direction)
		if absf(look.y) > 0:
			hud.scroll_by(look.y * 900.0 * dt)
		return
	stick_direction = Vector2.ZERO
	if move != Vector2.ZERO:
		var size: Vector2 = game.get_viewport().get_visible_rect().size
		# Squared response: small deflections give fine control.
		cursor += move * move.length() * size.y * float(CURSOR_SPEEDS.get(str(settings().values.get("pad_cursor_speed", "normal")), 0.85)) * dt
		clamp_cursor()
	if look != Vector2.ZERO and game.mode == "playing":
		if float(triggers.lt) >= TRIGGER_ON:
			game.zoom_by(look.y * 40.0 * dt)
		else:
			game.field.pan(look, dt)
			game.mission.note("camera")
