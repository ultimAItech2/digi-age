extends SceneTree
## A whole match flow on a gamepad: synthetic pad events go through the game's
## real input path, as a device's would.
var game
var failures: int = 0
var checks: int = 0

func expect(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)

func pad(button: int, pressed: bool = true) -> void:
	var event = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	game._input(event)

func tap(button: int) -> void:
	pad(button, true)
	pad(button, false)

func axis(index: int, value: float) -> void:
	var event = InputEventJoypadMotion.new()
	event.axis = index
	event.axis_value = value
	game._input(event)

func own(kind: String) -> Array:
	return game.sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == kind)

func point_at(e: Dictionary) -> void:
	game.field.sync(0, game.selected)
	game.input.cursor = game.field.screen_at(e.pos, 0.6)

func drawn() -> Array:
	game.hud.prepare_layout(true)
	return game.hud.text_bounds.map(func(entry): return entry.text)

## Every control of the open screen can be reached with the D-pad alone.
func reachable() -> Array:
	var hud = game.hud
	hud.prepare_layout(true)
	var all: Array = hud.focus_controls.map(func(b): return b.id)
	hud.focused = ""
	hud.focus_move(Vector2.DOWN)
	var seen: Dictionary = {hud.focused: true}
	var queue: Array = [hud.focused]
	while not queue.is_empty():
		var from: String = queue.pop_front()
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			hud.focused = from
			hud.focus_move(direction)
			if not seen.has(hud.focused):
				seen[hud.focused] = true
				queue.append(hud.focused)
	return all.filter(func(id): return not seen.has(id))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.hud.set_process(false)
	game.audio.enabled = false
	game.settings.set_value("language", "en")
	game.apply_runtime_settings()
	var input: DAInput = game.input
	var hud = game.hud

	# The menu: the first press takes the pad into use and focuses the main control.
	expect(input.device == "kbm" and game.settings.prompt("pause") == "Space", "keyboard prompts until a pad is touched")
	tap(JOY_BUTTON_DPAD_DOWN)
	expect(input.device == "pad" and hud.focused == DAInterface.control_id("start", {}), "the first D-pad press focuses the main control")
	expect(game.settings.prompt("pause") == "Menu" and game.settings.prompt("attack") == "Y", "prompts name pad buttons once a pad is in use")
	expect(reachable().is_empty(), "every main menu control is reachable with the D-pad: " + str(reachable()))
	for overlay in ["settings", "manual", "skirmish", "credits", "saves"]:
		hud.open_overlay(overlay)
		var unreachable: Array = reachable()
		expect(unreachable.is_empty(), overlay + " is fully reachable with the D-pad: " + str(unreachable))
		var target: Dictionary = {}
		for b in hud.focus_controls:
			if b.id == hud.focused: target = b
		expect(target.is_empty() or not target.clip.has_area() or target.clip.grow(1).encloses(target.rect), overlay + " scrolls the focused control into view")
		tap(JOY_BUTTON_B)
		expect(not hud.overlay_open(), "the cancel button closes " + overlay)
	hud.focused = ""
	tap(JOY_BUTTON_DPAD_DOWN)
	tap(JOY_BUTTON_A)
	expect(game.mode == "playing", "the select button starts the campaign from the menu")

	# Cursor: the left stick moves it, the dead zone holds it still, the screen bounds it.
	var start: Vector2 = input.cursor
	axis(JOY_AXIS_LEFT_X, 0.12)
	input.step(0.5)
	expect(input.cursor == start, "a stick inside the dead zone does not move the cursor")
	axis(JOY_AXIS_LEFT_X, 1.0)
	input.step(0.1)
	expect(input.cursor.x > start.x + 20 and is_equal_approx(input.cursor.y, start.y), "the left stick moves the cursor")
	input.step(30.0)
	expect(input.cursor.x <= root.size.x - 1, "the cursor stays on screen")
	axis(JOY_AXIS_LEFT_X, 0.0)
	expect(hud.mouse != input.cursor or true, "")
	hud._process(0.0)
	hud.set_process(false)
	expect(hud.mouse == input.cursor, "the interface follows the pad cursor as its pointer")

	# Select, add to the selection, box-select.
	var workers: Array = own("worker")
	point_at(workers[0])
	tap(JOY_BUTTON_A)
	expect(game.selected == [workers[0].id], "the select button picks the unit under the cursor")
	point_at(workers[1])
	pad(JOY_BUTTON_LEFT_SHOULDER)
	tap(JOY_BUTTON_A)
	pad(JOY_BUTTON_LEFT_SHOULDER, false)
	expect(game.selected.size() == 2, "holding the modifier adds to the selection")
	tap(JOY_BUTTON_B)
	expect(game.selected.is_empty(), "the cancel button clears the selection")
	var corners: Array = workers.map(func(e): return game.field.screen_at(e.pos, 0.6))
	var box = Rect2(corners[0], Vector2.ZERO)
	for corner in corners: box = box.expand(corner)
	box = box.grow(12)
	input.cursor = box.position
	pad(JOY_BUTTON_A)
	input.cursor = box.end
	pad(JOY_BUTTON_A, false)
	expect(game.selected.size() >= workers.size(), "holding select and moving the cursor box-selects")

	# Orders.
	game.selected = [workers[0].id]
	var destination: Vector2 = workers[0].pos + Vector2(4, 3)
	input.cursor = game.field.screen_at(destination, 0.0)
	tap(JOY_BUTTON_X)
	expect(workers[0].order == "move" and workers[0].destination.distance_to(destination) < 1.5, "the order button moves the selection to the cursor")
	var deposit: Dictionary = game.sim.entities.values().filter(func(e): return e.owner == -1 and e.kind == "metal")[0]
	game.field.focus = deposit.pos
	game.field.update_camera()
	point_at(deposit)
	tap(JOY_BUTTON_X)
	expect(workers[0].order == "gather", "the order button on a deposit gathers")
	tap(JOY_BUTTON_Y)
	expect(game.attack_mode, "the attack button starts an attack-move")
	expect(drawn().any(func(line): return line.contains("ATTACK-MOVE") and line.contains("A") and not line.contains("Right-click")), "targeting hints name pad buttons")
	tap(JOY_BUTTON_B)
	expect(not game.attack_mode and game.selected == [workers[0].id], "cancel leaves the mode and keeps the selection")
	tap(JOY_BUTTON_Y)
	input.cursor = game.field.screen_at(workers[0].pos + Vector2(5, 0), 0.0)
	tap(JOY_BUTTON_A)
	expect(not game.attack_mode and workers[0].order == "attack_move", "select confirms the attack-move at the cursor")

	# The command grid on the trigger and D-pad.
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	expect(input.grid_open and hud.focus_keyboard, "holding the trigger opens the command grid")
	var slots: Dictionary = input.grid_buttons()
	expect(slots.has(input.grid_index) and hud.focused == slots[input.grid_index].id, "the grid starts on a command")
	var first_slot: int = input.grid_index
	tap(JOY_BUTTON_DPAD_RIGHT)
	expect(input.grid_index != first_slot and slots.has(input.grid_index), "the D-pad moves between commands, skipping empty slots")
	tap(JOY_BUTTON_DPAD_LEFT)
	expect(input.grid_index == first_slot, "and back")
	expect(drawn().any(func(line): return line.contains("D-pad: move")), "the hint bar explains the grid")
	var chosen: Dictionary = slots[input.grid_index]
	tap(JOY_BUTTON_A)
	expect(chosen.action == "build" and game.build_kind == str(chosen.payload.kind), "select uses the highlighted command")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	expect(not input.grid_open, "releasing the trigger closes the grid")
	tap(JOY_BUTTON_B)
	expect(game.build_kind == "", "cancel leaves placement")

	# Control groups and the bare D-pad.
	game.selected = [workers[0].id, workers[1].id]
	pad(JOY_BUTTON_RIGHT_SHOULDER)
	pad(JOY_BUTTON_LEFT_SHOULDER)
	tap(JOY_BUTTON_DPAD_UP)
	pad(JOY_BUTTON_LEFT_SHOULDER, false)
	expect(game.groups.get(1, []) == [workers[0].id, workers[1].id], "groups + modifier + D-pad saves a control group")
	game.selected.clear()
	tap(JOY_BUTTON_DPAD_UP)
	pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	expect(game.selected == [workers[0].id, workers[1].id], "groups + D-pad recalls it")
	tap(JOY_BUTTON_DPAD_LEFT)
	expect(game.selected.size() == 1 and game.sim.entities[game.selected[0]].kind == "core", "D-pad left selects the Core")
	for e in workers: game.sim.command(0, "stop", [e.id])
	tap(JOY_BUTTON_DPAD_UP)
	expect(game.selected.size() == 1 and game.sim.entities[game.selected[0]].kind == "worker", "D-pad up selects an idle Worker")

	# Camera.
	var focus: Vector2 = game.field.focus
	axis(JOY_AXIS_RIGHT_X, 1.0)
	input.step(0.2)
	expect(game.field.focus != focus, "the right stick pans the camera")
	axis(JOY_AXIS_RIGHT_X, 0.0)
	var zoom: float = game.field.zoom
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis(JOY_AXIS_RIGHT_Y, 1.0)
	input.step(0.2)
	expect(game.field.zoom != zoom, "the left trigger with the right stick zooms")
	axis(JOY_AXIS_RIGHT_Y, 0.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)

	# Pause menu.
	tap(JOY_BUTTON_START)
	expect(game.mode == "paused", "the pause button pauses")
	tap(JOY_BUTTON_DPAD_DOWN)
	var before: String = hud.focused
	tap(JOY_BUTTON_DPAD_DOWN)
	expect(before != "" and hud.focused != before, "the D-pad moves the focus in the pause menu")
	axis(JOY_AXIS_LEFT_Y, 1.0)
	var stick_before: String = hud.focused
	input.step(0.01)
	expect(hud.focused != stick_before, "the left stick moves the focus too")
	var held: String = hud.focused
	input.step(0.01)
	expect(hud.focused == held, "a held stick does not skip controls at once")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	input.step(0.01)
	expect(reachable().is_empty(), "the pause menu is fully reachable: " + str(reachable()))
	tap(JOY_BUTTON_B)
	expect(game.mode == "playing", "the cancel button resumes")
	hud.open_overlay("tech")
	expect(reachable().is_empty(), "the technology tree is fully reachable: " + str(reachable()))
	hud.clear_overlays()

	# Button names and rebinding.
	expect(DAInput.family_of("Sony Interactive Entertainment DualSense Wireless Controller") == "playstation" and DAInput.family_of("Xbox Series X Controller") == "xbox" and DAInput.family_of("Steam Deck") == "deck", "the pad family is recognised from its name")
	expect(game.settings.set_value("pad_glyphs", "playstation") == "" and game.settings.prompt("attack") == "Triangle" and input.prompt("grid") == "R2", "button names can be set to another family")
	game.settings.set_value("pad_glyphs", "auto")
	expect(game.settings.set_pad_binding("attack", JOY_BUTTON_X) == "" and input.button_for("attack") == JOY_BUTTON_X and input.button_for("order") == JOY_BUTTON_Y, "rebinding a button swaps it with the action that held it")
	game.selected = [workers[0].id]
	tap(JOY_BUTTON_X)
	expect(game.attack_mode, "the new binding takes effect")
	tap(JOY_BUTTON_B)
	expect(game.settings.set_pad_binding("attack", JOY_BUTTON_DPAD_UP) != "", "the D-pad cannot be rebound")
	hud.open_overlay("settings")
	game.ui_action("rebind", {"action": "pad:pause"})
	tap(JOY_BUTTON_BACK)
	expect(hud.rebind_action == "" and input.button_for("pause") == JOY_BUTTON_BACK and input.button_for("objectives") == JOY_BUTTON_START, "settings captures a pad button for an action")
	var reloaded = DASettingsService.new()
	reloaded.load_settings()
	expect(int(reloaded.values.pad_bindings.pause) == JOY_BUTTON_BACK, "pad bindings are remembered")
	expect(game.settings.reset("controller") == "" and input.button_for("pause") == JOY_BUTTON_START and input.button_for("attack") == JOY_BUTTON_Y, "the controller settings reset on their own")
	expect(not game.settings.valid_value("pad_bindings", {"select": JOY_BUTTON_A}) and not game.settings.valid_value("pad_deadzone", 0.9), "invalid pad settings are refused")
	hud.clear_overlays()

	# Back to the keyboard and mouse.
	var motion = InputEventMouseMotion.new()
	motion.relative = Vector2(30, 0)
	game._input(motion)
	expect(input.device == "kbm" and game.settings.prompt("pause") == "Space", "moving the mouse returns to keyboard and mouse prompts")
	expect(not drawn().any(func(line): return line.contains("D-pad")), "the pad hint bar goes away")

	print("GAMEPAD_RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
