extends Node3D
var sim: DASimulation
var opponent: DAOpponent
var field: DABattlefield
var hud: DAInterface
var audio: DAAudio
var mode: String = "menu"
var selected: Array = []
var groups: Dictionary = {}
var build_kind: String = ""
var attack_mode: bool = false
var rally_mode: bool = false
var patrol_mode: bool = false
## Aiming a targeted ability (Sensor sweep, EMP shell): the next click on the ground fires it.
var ability_mode: bool = false
## "campaign" or "skirmish": what the current world is, and what Play Again restarts.
var game_kind: String = "campaign"
var fail_reason: String = ""
var last_alert_pos: Vector2 = Vector2(-1, -1)
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var speed: int = 1
var accumulator: float = 0.0
var refresh_timer: float = 0.0
var screenshot_requested: bool = false
var capture_delay: float = 3.0
var capture_frames: int = 90
var dev_overrides: Dictionary = {}
var vignette: ColorRect
var middle_drag: bool = false
var benchmark_frames: Array[float] = []
var benchmark_process: Array[float] = []
var benchmark_remaining: float = -1.0
var auto_player: DAOpponent
var mission_catalog: DAMissionCatalog = preload("res://data/missions/catalog.tres")
var mission: DAMissionController
var mission_definition: DAMissionDefinition
var campaign: DACampaignProgress = DACampaignProgress.new()
var settings: DASettingsService = DASettingsService.new()
var platform: DAPlatformService = DAPlatformService.new()
var autosave_index: int = 0
var pending_mission_id: String = "first_signal"
var saved_elapsed: float = -1.0
var unsaved_command: bool = false
var idle_cursor: int = -1
var last_click_id: int = -1
var last_click_msec: int = 0
var cursor_kind: String = ""
var cursor_timer: float = 0.0

func _ready() -> void:
	audio = DAAudio.new()
	add_child(audio)
	settings.load_settings()
	DASaveGame.load_campaign(campaign)
	if campaign.current_mission != "" and campaign.unlocked_missions.has(campaign.current_mission):
		pending_mission_id = campaign.current_mission
	platform.initialize()
	var post_layer = CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_shader = load("res://assets/shaders/vignette.gdshader") if ResourceLoader.exists("res://assets/shaders/vignette.gdshader") else null
	if vignette_shader:
		var vignette_material = ShaderMaterial.new()
		vignette_material.shader = vignette_shader
		vignette.material = vignette_material
	else:
		vignette.visible = false
	post_layer.add_child(vignette)
	new_world()
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = DAInterface.new()
	layer.add_child(hud)
	hud.setup(self)
	audio.subtitle_shown.connect(hud.show_subtitle)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(func(): ui_action("quit"))
	apply_runtime_settings()
	if settings.recovery_notice != "": hud.toast(settings.recovery_notice, "error")
	audio.set_music("menu")
	var args = OS.get_cmdline_user_args()
	if "--ui-smoke" in args: launch_smoke.call_deferred()
	if "--autoplay" in args or "--benchmark" in args:
		mode = "playing"
		auto_player = DAOpponent.new(sim, 0)
	if "--benchmark" in args:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_size = Vector2i(1920,1080)
		for side in 2:
			for i in 94:
				sim.spawn("sentinel", side, Vector2(8+(i%10)*1.3+side*35, 22+floori(i/10.0)*1.3))
		benchmark_remaining = 20.0
		# Measure what the hardware can do, not the display's refresh rate.
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		field.focus = Vector2(35,36)
		field.zoom = 68
		field.update_camera()
	if "--screenshot" in args:
		screenshot_requested = true
	# Development overrides used by tools/render_scene.sh and manual GPU checks.
	for i in args.size():
		var arg: String = args[i]
		var next: String = args[i+1] if i+1 < args.size() else ""
		if arg == "--capture-frames": capture_frames = maxi(1, int(next))
		elif arg == "--profile" and next in ["low", "normal"]: dev_overrides.profile = next
		elif arg == "--reduced": dev_overrides.reduced_effects = true
		elif arg == "--focus" and next.contains(","):
			# Development: look at a given cell, with the map revealed there.
			field.focus = Vector2(float(next.get_slice(",", 0)), float(next.get_slice(",", 1)))
			mission.reveal_area(0, field.focus, 22)
			field.update_camera()
		elif arg == "--zoom" and next != "":
			field.zoom = clampf(float(next), DABattlefield.ZOOM_MIN, DABattlefield.ZOOM_MAX)
			field.update_camera()
	if not dev_overrides.is_empty():
		var merged: Dictionary = settings.values.duplicate(true)
		merged.merge(dev_overrides, true)
		field.apply_settings(merged)
	if "--demo" in args:
		mode = "playing"
		for kind in ["fabricator", "data_center", "depot", "tower"]:
			var points = {"fabricator": Vector2(20,40), "data_center": Vector2(6,30), "depot": Vector2(21,28), "tower": Vector2(24,36)}
			sim.spawn(kind,0,points[kind])
		for i in 12:
			selected.append(sim.spawn(["sentinel","disruptor","walker","warden","mortar","phantom"][i%6],0,Vector2(19+i%6*1.5,46+floori(i/6.0)*2)))
		sim.ages[0] = 2
		if "--focus" not in args:
			field.focus = Vector2(20,36)
		field.update_camera()

func launch_smoke() -> void:
	await get_tree().process_frame
	hud.prepare_layout(true)
	var menu_ready = mode == "menu" and hud.buttons.any(func(b): return b.action == "start")
	ui_action("start")
	await get_tree().process_frame
	hud.prepare_layout(true)
	var passed = menu_ready and mode == "playing" and not field.models.is_empty() and hud.buttons.any(func(b): return b.action == "pause")
	# The packaged build must carry the sprite look: exports ship the imported
	# textures, not the PNGs, so prove a Worker is a card and has its portrait.
	var worker_cards = field.models.values().filter(func(n): return n.name == "worker" and DASprites.is_card(n))
	var sprites_ok = DASprites.has_sprite("worker") and not worker_cards.is_empty() and hud.portrait("worker") == DASprites.portrait("worker")
	print("UI_EXPORT_SMOKE sprites: ", "PASS" if sprites_ok else "FAIL")
	passed = passed and sprites_ok
	print("UI_EXPORT_SMOKE: ", "PASS" if passed else "FAIL")
	get_tree().quit(0 if passed else 1)

func new_world(mission_id: String = "") -> void:
	if audio: audio.clear_dialogue()
	if field:
		remove_child(field)
		field.queue_free()
	sim = DASimulation.new()
	var requested = mission_id if mission_id != "" else pending_mission_id
	if requested == "skirmish":
		game_kind = "skirmish"
		mission_definition = skirmish_definition()
	else:
		game_kind = "campaign"
		mission_definition = mission_catalog.get_definition(requested)
		if mission_definition == null or not campaign.unlocked_missions.has(requested):
			mission_definition = mission_catalog.get_definition("first_signal")
		pending_mission_id = mission_definition.mission_id
	mission = DAMissionController.new()
	mission.setup(sim, mission_definition)
	opponent = DAOpponent.new(sim)
	auto_player = null
	fail_reason = ""
	last_alert_pos = Vector2(-1, -1)
	field = DABattlefield.new()
	add_child(field)
	field.vignette = vignette
	field.setup(sim)
	field.apply_settings(settings.values)
	sim.notice.connect(func(text):
		if hud:
			hud.toast(text, "success"))
	sim.alert.connect(_on_alert)
	sim.shot.connect(func(from, to, _owner, _kind):
		if sim.seen(0, from) or sim.seen(0, to):
			audio.play("shot", {"kind": _kind})
			if sim.seen(0, to):
				audio.play("impact")
			if _owner == 1:
				audio.notify_combat())
	sim.impact.connect(func(position, _kind, _radius):
		if sim.seen(0, position):
			audio.play("impact"))
	sim.destroyed.connect(func(position, kind):
		if sim.seen(0, position):
			audio.play("structure_destroyed" if sim.catalog.buildings.has(kind) else "unit_destroyed"))
	mission.objective_completed.connect(_on_objective_completed)
	mission.checkpoint_created.connect(_on_checkpoint_created)
	mission.mission_completed.connect(_on_mission_completed)
	mission.mission_failed.connect(_on_mission_failed)
	mission.dialogue_requested.connect(_on_dialogue_requested)
	sim.reset_from_mission(mission_definition)
	opponent.refresh_from_faction()
	opponent.set_difficulty(campaign.selected_difficulty)
	if auto_player:
		auto_player.refresh_from_faction()
	if field:
		field.focus = sim.bases[0]
		field.update_camera()
	selected.clear()
	groups.clear()
	build_kind = ""
	attack_mode = false
	rally_mode = false
	patrol_mode = false
	ability_mode = false
	dragging = false
	accumulator = 0
	speed = 1
	saved_elapsed = -1.0
	unsaved_command = false
	if hud:
		hud.clear_overlays()
		hud.refresh_map()

## A free match from the saved setup: equal openings, no script, one goal.
func skirmish_definition() -> DAMissionDefinition:
	var setup: Dictionary = settings.values.skirmish
	var definition = DAMissionDefinition.new()
	var map = load("res://data/maps/" + str(setup.map) + ".tres") as DAMapDefinition
	definition.mission_id = "skirmish"
	definition.title = "Skirmish · " + (map.display_name if map else str(setup.map))
	definition.briefing = "A free match. Build, scout and destroy the rival Core."
	definition.map_id = str(setup.map)
	definition.player_faction_id = str(setup.player)
	definition.enemy_faction_id = str(setup.enemy)
	definition.checkpoint_ids.clear()
	var grant: Vector3 = DASettingsService.SKIRMISH_RESOURCES[setup.resources]
	definition.starting_resources.assign([grant, grant])
	definition.symmetric_start = true
	definition.swap_sides = setup.side == "right" or (setup.side == "random" and randi() % 2 == 1)
	definition.victory_text = "The rival Core is gone. The field is yours."
	definition.defeat_text = "Your civilization has fallen."
	return definition

## What the simulation tells the player: a sound, a spoken line, a toast and a minimap ping.
func _on_alert(kind: String, pos: Vector2, side: int, detail: String) -> void:
	if side != 0:
		return
	var subject: String = str(sim.catalog.definition(detail).get("name", detail.capitalize()))
	match kind:
		"under_attack":
			last_alert_pos = pos
			audio.play("alert")
			audio.announce("alert.under_attack", true)
			if hud:
				hud.ping(pos, "danger")
				hud.toast("Under attack. Press " + settings.prompt("alert") + " to look.", "alert")
		"unit_lost":
			audio.announce("alert.unit_lost")
			if hud: hud.ping(pos, "danger")
		"structure_lost":
			last_alert_pos = pos
			audio.announce("alert.structure_lost")
			if hud:
				hud.ping(pos, "danger")
				hud.toast(subject + " destroyed.", "alert")
		"core_lost":
			last_alert_pos = pos
			audio.play("alert")
			if hud: hud.toast("Core destroyed. Raise a new Core within two minutes or the match is lost.", "alert")
		"construction_started":
			audio.play("construction")
		"construction_complete":
			audio.announce("alert.construction_complete")
			if hud:
				hud.ping(pos, "info")
				hud.toast(subject + " complete.", "success")
		"unit_ready":
			if hud and hud.message_left <= 0: hud.toast(subject + " ready.")
		"research_started":
			audio.play("research")
		"research_complete", "age_advanced":
			audio.play("research")
			audio.announce("alert.research_complete")
		"population_cap":
			audio.announce("alert.population")
			if hud: hud.toast("Compute limit reached. Build a Data Center.", "alert")
		"deposit_exhausted":
			if hud:
				hud.ping(pos, "info")
				hud.toast(("Salvage" if detail == "metal" else "Data") + " deposit exhausted.")

func _on_objective_completed(objective_id: String) -> void:
	audio.play("objective_updated", {"id": objective_id})
	audio.announce("alert.objective")
	if hud:
		hud.toast(objective_id.replace("_", " ").capitalize(), "success")

func _on_dialogue_requested(entry_id: String) -> void:
	var entry = mission_definition.dialogue_entry(entry_id) if mission_definition else {}
	var text = str(entry.get("text", ""))
	var speaker = str(entry.get("speaker", "archivist"))
	audio.speak(mission_definition.mission_id + "." + entry_id, text, speaker)

## Blue against orange stays apart under the common forms of colour blindness.
const COLORBLIND_COLORS: Array[Color] = [Color("4a90ff"), Color("ff9d2e")]

func apply_runtime_settings() -> void:
	audio.enabled = not bool(settings.values.get("muted", false))
	audio.apply_settings(settings.values)
	apply_window_settings()
	if sim:
		var wanted: Array[Color] = COLORBLIND_COLORS if bool(settings.values.get("colorblind", false)) else ([] as Array[Color])
		if sim.color_override != wanted:
			sim.color_override = wanted
			# Models carry their side colour from creation; rebuild them in the new one.
			if field:
				for model in field.models.values(): model.queue_free()
				field.models.clear()
				field.selections.clear()
	if field: field.apply_settings(settings.values)
	if hud:
		hud.apply_scale(float(settings.values.get("ui_scale", 1.0)))
		hud.subtitles_enabled = bool(settings.values.get("subtitles", true))

## Window mode, size, vsync and frame cap. A headless run has no window to change.
func apply_window_settings() -> void:
	Engine.max_fps = int(settings.values.get("frame_cap", 0))
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings.values.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	var wanted = {"windowed": DisplayServer.WINDOW_MODE_WINDOWED, "borderless": DisplayServer.WINDOW_MODE_WINDOWED, "fullscreen": DisplayServer.WINDOW_MODE_FULLSCREEN}[str(settings.values.get("window_mode", "windowed"))]
	var borderless: bool = settings.values.get("window_mode", "windowed") == "borderless"
	if DisplayServer.window_get_mode() != wanted:
		DisplayServer.window_set_mode(wanted)
	if wanted == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, borderless)
		var parts: PackedStringArray = str(settings.values.get("resolution", "1600x900")).split("x")
		var size = Vector2i(int(parts[0]), int(parts[1]))
		var screen = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		if borderless:
			DisplayServer.window_set_position(screen.position)
			DisplayServer.window_set_size(screen.size)
		elif DisplayServer.window_get_size() != size:
			size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)

func _on_checkpoint_created(slot_id: String) -> void:
	campaign.current_mission = mission_definition.mission_id
	campaign.last_checkpoint = slot_id
	DASaveGame.save_campaign(campaign)
	var error = DASaveGame.save_slot("autosave_" + str(autosave_index), sim, mission, campaign, {"checkpoint": slot_id, "difficulty": campaign.selected_difficulty, "title": mission_definition.title, "session": session_state()})
	autosave_index = (autosave_index + 1) % DASaveGame.SLOT_COUNT
	if error != "" and hud:
		hud.toast(error)

func _on_mission_completed() -> void:
	mode = "result"
	build_kind = ""
	attack_mode = false
	rally_mode = false
	patrol_mode = false
	ability_mode = false
	audio.set_music("result")
	audio.play("mission_won")
	if game_kind == "skirmish":
		platform.unlock("skirmish_won")
		return
	campaign.mark_complete(mission_definition.mission_id)
	var definitions = mission_catalog.all_definitions()
	var index = 0
	for i in definitions.size():
		if definitions[i].mission_id == mission_definition.mission_id:
			index = i
	if index + 1 < definitions.size():
		campaign.unlock(definitions[index + 1].mission_id)
	DASaveGame.save_slot("campaign_complete", sim, mission, campaign, {"mission": mission_definition.mission_id})
	DASaveGame.save_campaign(campaign)
	platform.unlock("mission_" + mission_definition.mission_id)
	if mission_definition:
		audio.speak("victory", mission_definition.victory_text, "archivist")

func _on_mission_failed(reason: String) -> void:
	mode = "result"
	fail_reason = reason
	build_kind = ""
	attack_mode = false
	rally_mode = false
	patrol_mode = false
	ability_mode = false
	audio.set_music("result")
	audio.play("mission_failed", {"reason": reason})
	audio.announce("alert.mission_failed")
	if hud:
		hud.toast(reason)

## Session state that is not the simulation's: the opponent's timers, control groups, speed.
func session_state() -> Dictionary:
	return {"opponent": opponent.serialize_state(), "groups": groups.duplicate(true), "speed": speed}

func save_game(slot: String = "manual_1") -> String:
	if game_kind == "campaign": campaign.current_mission = mission_definition.mission_id
	var metadata = {"difficulty": campaign.selected_difficulty, "title": mission_definition.title, "session": session_state()}
	if game_kind == "skirmish":
		# Enough to rebuild the same match definition before loading into it.
		metadata["skirmish"] = settings.values.skirmish.duplicate()
		metadata.skirmish.side = "right" if mission_definition.swap_sides else "left"
	var error = DASaveGame.save_slot(slot, sim, mission, campaign, metadata)
	if error == "":
		saved_elapsed = sim.elapsed
		unsaved_command = false
	if hud: hud.refresh_slots()
	return error

func load_game(slot: String = "manual_1") -> String:
	# A save from another mission switches to that mission first.
	var info: Dictionary = DASaveGame.describe(slot)
	var saved_mission: String = str(info.get("mission_id", ""))
	if saved_mission == "skirmish":
		# Rebuild the match the save was made in, then load into it.
		var setup = info.get("metadata", {}).get("skirmish", {})
		if not settings.valid_value("skirmish", setup):
			return "This skirmish save has no usable match setup."
		var setup_error = settings.set_value("skirmish", setup)
		if setup_error != "":
			return setup_error
		new_world("skirmish")
	elif saved_mission != "" and saved_mission != mission_definition.mission_id:
		if mission_catalog.get_definition(saved_mission) == null:
			return "This save belongs to a mission that is no longer available."
		campaign.unlock(saved_mission)
		new_world(saved_mission)
	var metadata: Dictionary = {}
	var error = DASaveGame.load_slot(slot, sim, mission, campaign, metadata)
	if error == "":
		var session: Dictionary = metadata.get("session", {}) if metadata.get("session", {}) is Dictionary else {}
		if session.get("opponent", {}) is Dictionary and not session.get("opponent", {}).is_empty():
			opponent.restore_state(session.get("opponent", {}))
		else:
			opponent.set_difficulty(campaign.selected_difficulty)
		groups.clear()
		if session.get("groups", {}) is Dictionary:
			for key in session.groups:
				if key is int and session.groups[key] is Array:
					groups[key] = session.groups[key].filter(func(id): return id is int)
		speed = int(session.get("speed", 1)) if int(session.get("speed", 1)) in [1, 2, 4] else 1
		mode = "playing" if sim.winner < 0 and mission.active else "result"
		audio.set_music("ambient" if mode == "playing" else "result")
		if game_kind == "campaign": pending_mission_id = mission_definition.mission_id
		hud.clear_overlays()
		selected.clear()
		for model in field.models.values(): model.queue_free()
		field.models.clear()
		field.selections.clear()
		field.refresh_fog()
		hud.refresh_map()
		saved_elapsed = sim.elapsed
		unsaved_command = false
	return error

func _process(dt: float) -> void:
	if mode == "playing" and not hud.modal_active():
		accumulator += minf(dt, 0.2) * speed
		while accumulator >= sim.catalog.tick_seconds:
			opponent.step(sim.catalog.tick_seconds)
			if auto_player:
				auto_player.step(sim.catalog.tick_seconds)
			sim.tick(sim.catalog.tick_seconds)
			mission.tick(sim.catalog.tick_seconds)
			accumulator -= sim.catalog.tick_seconds
		if sim.winner >= 0:
			if sim.winner == 1 and fail_reason == "": fail_reason = "core"
			mode = "result"
			build_kind = ""
			attack_mode = false
			rally_mode = false
			patrol_mode = false
			ability_mode = false
			audio.play("alert")
		camera_controls(dt)
	if "--benchmark" in OS.get_cmdline_user_args():
		for x in DASimulation.SIZE:
			for y in DASimulation.SIZE:
				sim.visible[0][Vector2i(x,y)] = true
				sim.explored[0][Vector2i(x,y)] = true
	refresh_timer -= dt
	if refresh_timer <= 0:
		refresh_timer = 0.4
		field.refresh_fog()
		hud.refresh_map()
	selected = selected.filter(func(id): return sim.entities.has(id) and sim.known(0, sim.entities[id]))
	field.sync(dt if mode not in ["paused", "result"] else 0, selected)
	if build_kind != "" and mode == "playing" and not hud.modal_active():
		var p = field.ground_at(get_viewport().get_mouse_position())
		field.preview(build_kind, p, sim.placement_error(0, build_kind, p) == "")
	else:
		field.preview("", Vector2.ZERO, false)
	update_cursor(dt)
	capture_delay -= dt
	if screenshot_requested: capture_frames -= 1
	if screenshot_requested and capture_frames <= 0:
		screenshot_requested = false
		capture.call_deferred()
	if benchmark_remaining >= 0:
		benchmark_remaining -= dt
		if benchmark_remaining < 17:
			benchmark_frames.append(dt)
			benchmark_process.append(Performance.get_monitor(Performance.TIME_PROCESS))
		if benchmark_remaining < 0:
			var total = 0.0
			for value in benchmark_frames:
				total += value
			var process_total = 0.0
			for value in benchmark_process:
				process_total += value
			print("BENCHMARK CPU average_ms=%.3f draw_calls=%d primitives=%d viewport=%s" % [process_total/benchmark_process.size()*1000,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),get_viewport().get_texture().get_size()])
			print("BENCHMARK frames=%d seconds=%.3f fps=%.2f adapter=%s renderer=%s" % [benchmark_frames.size(),total,benchmark_frames.size()/total,RenderingServer.get_video_adapter_name(),RenderingServer.get_current_rendering_method()])
			get_tree().quit()

## The pointer says what a click will do: build, rally, attack or gather.
func update_cursor(dt: float) -> void:
	cursor_timer -= dt
	if cursor_timer > 0 or DisplayServer.get_name() == "headless":
		return
	cursor_timer = 0.1
	var kind = "default"
	if mode == "playing" and not hud.modal_active():
		var mouse = get_viewport().get_mouse_position()
		if build_kind != "":
			kind = "build"
		elif rally_mode:
			kind = "rally"
		elif attack_mode or patrol_mode or ability_mode:
			kind = "attack"
		elif hud.is_world(mouse) and not selected.is_empty() and sim.entities.has(selected[0]):
			var first: Dictionary = sim.entities[selected[0]]
			var id = pick_screen(mouse) if first.owner == 0 and not first.building else -1
			if id >= 0 and sim.entities[id].owner == 1:
				kind = "attack"
			elif id >= 0 and sim.entities[id].owner == -1 and first.kind == "worker":
				kind = "gather"
	if kind != cursor_kind:
		cursor_kind = kind
		var image = hud.cursor_image(kind)
		if image:
			Input.set_custom_mouse_cursor(image, Input.CURSOR_ARROW, Vector2(16, 16) if kind == "attack" else Vector2(4, 3))

func capture() -> void:
	await RenderingServer.frame_post_draw
	var path = "res://builds/screenshot.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot saved: ", path)
	# tools/render_scene.sh waits for the process to end; a benchmark quits on its own.
	if benchmark_remaining < 0:
		get_tree().quit()

func camera_controls(dt: float) -> void:
	if hud.modal_active(): return
	var direction = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1
	var mouse = get_viewport().get_mouse_position()
	var size = get_viewport().get_visible_rect().size
	# Screen edges pan whether or not the HUD covers them, as long as the pointer is in the window.
	if Rect2(Vector2.ZERO, size).has_point(mouse) and DisplayServer.window_is_focused():
		if mouse.x < 4:
			direction.x -= 1
		if mouse.x > size.x-5:
			direction.x += 1
		if mouse.y < 4:
			direction.y -= 1
		if mouse.y > size.y-5:
			direction.y += 1
	if direction != Vector2.ZERO:
		field.pan(direction.normalized(), dt)

func _input(event: InputEvent) -> void:
	if not hud:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		key_input(event)
		return
	if event is InputEventMouseButton and hud.pointer_event(event): return
	if hud.modal_active(): return
	if event is InputEventMouseMotion and middle_drag and mode == "playing":
		field.pan(-event.relative, 0.0012)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		middle_drag = event.pressed and hud.is_world(event.position)
		return
	if event is InputEventMouseButton:
		var p: Vector2 = event.position
		if event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and hud.is_world(p):
				field.zoom = clampf(field.zoom + (-2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2.0), DABattlefield.ZOOM_MIN, DABattlefield.ZOOM_MAX)
				field.update_camera()
				return
			if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				return
			if event.button_index == MOUSE_BUTTON_RIGHT and (build_kind != "" or ((attack_mode or rally_mode or patrol_mode or ability_mode) and not hud.map_rect.has_point(p))):
				build_kind = ""
				attack_mode = false
				rally_mode = false
				patrol_mode = false
				ability_mode = false
				return
			if hud.handle_click(p, event.button_index == MOUSE_BUTTON_RIGHT):
				return
			var ground = field.ground_at(p)
			if event.button_index == MOUSE_BUTTON_RIGHT:
				if build_kind != "" or attack_mode or rally_mode or patrol_mode or ability_mode:
					build_kind = ""
					attack_mode = false
					rally_mode = false
					patrol_mode = false
					ability_mode = false
				else:
					context_order(ground, p)
			elif build_kind != "":
				if issue("build", {"kind": build_kind, "pos": ground}) == "" and not event.shift_pressed:
					build_kind = ""
			elif attack_mode:
				issue("attack_move", {"pos": ground})
				attack_mode = false
			elif rally_mode:
				issue("rally", {"pos": ground})
				rally_mode = false
			elif ability_mode:
				issue("ability", {"pos": ground})
				ability_mode = false
			elif patrol_mode:
				issue("patrol", {"pos": ground})
				patrol_mode = false
				ability_mode = false
			else:
				dragging = true
				drag_start = p
		elif event.button_index == MOUSE_BUTTON_LEFT and dragging:
			dragging = false
			if hud.is_world(p): select_at(p, event.shift_pressed)


func key_input(event: InputEventKey) -> void:
	var key = event.physical_keycode
	if hud.settings_open and hud.rebind_action != "":
		if key == KEY_ESCAPE:
			hud.rebind_action = ""
			return
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
			hud.toast("Choose a single key without modifiers.", "error")
			return
		var binding_error = settings.set_binding(hud.rebind_action, key)
		if binding_error == "":
			hud.rebind_action = ""
			hud.toast("Binding updated", "success")
		else: hud.toast(binding_error, "error")
		return
	if hud.keyboard(event): return
	if key == settings.binding("fullscreen", KEY_F11):
		commit_preferences(settings.set_value("window_mode", "windowed" if settings.values.window_mode == "fullscreen" else "fullscreen"))
		return
	if key == settings.binding("manual", KEY_F1):
		if hud.manual: hud.close_overlay()
		elif not hud.overlay_open(): hud.open_overlay("manual")
		return
	if key == settings.binding("cancel", KEY_ESCAPE):
		if hud.overlay_open():
			hud.close_overlay()
		elif build_kind != "" or attack_mode or rally_mode or patrol_mode or ability_mode:
			build_kind = ""
			attack_mode = false
			rally_mode = false
			patrol_mode = false
			ability_mode = false
		elif mode == "playing":
			mode = "paused"
			hud.cancel_pointer()
		elif mode == "paused":
			mode = "playing"
		return
	if hud.overlay_open(): return
	if key == settings.binding("pause", KEY_SPACE) and mode in ["playing", "paused"]:
		mode = "paused" if mode == "playing" else "playing"
		hud.cancel_pointer()
		return
	if mode != "playing" or hud.manual:
		return
	# The command grid's slot keys come first; attack-move and stop keep their own bindings.
	if not event.ctrl_pressed and hud.grid_key(key):
		return
	if key == KEY_PERIOD:
		ui_action("idle_worker")
	if key == settings.binding("speed", KEY_F2):
		speed = {1:2, 2:4, 4:1}[speed]
	if key == settings.binding("events", KEY_M):
		ui_action("sound")
	if key == settings.binding("save", KEY_F5):
		ui_action("save")
	if key == settings.binding("load", KEY_F9):
		ui_action("load")
	if key == settings.binding("attack", KEY_A) and not selected.is_empty():
		attack_mode = true
		patrol_mode = false
		ability_mode = false
		build_kind = ""
	if key == settings.binding("stop", KEY_S) and not selected.is_empty():
		issue("stop")
	if key == settings.binding("home", KEY_HOME):
		ui_action("home")
	if key == settings.binding("alert", KEY_N):
		ui_action("jump_alert")
	if key >= KEY_1 and key <= KEY_9:
		var group = key-KEY_0
		if event.ctrl_pressed:
			groups[group] = selected.duplicate()
			hud.toast("Control group " + str(group) + " saved.")
		elif groups.has(group):
			selected = groups[group].filter(func(id): return sim.entities.has(id) and sim.entities[id].owner == 0)

func pick(p: Vector2) -> int:
	var best = -1
	var distance = INF
	for e in sim.entities.values():
		if not sim.known(0, e) or e.get("amount", 1) <= 0:
			continue
		var d = p.distance_to(e.pos)
		var radius = sim.catalog.buildings[e.kind].radius + 0.8 if e.building else (1.8 if e.owner == -1 else 1.0)
		if d < radius and d < distance:
			distance = d
			best = e.id
	return best

func pick_screen(screen: Vector2) -> int:
	var best = -1
	var best_distance = INF
	for e in sim.entities.values():
		if not sim.known(0, e) or e.get("amount",1) <= 0 or not field.models.has(e.id):
			continue
		var model: Node3D = field.models[e.id]
		var first = true
		var bounds = Rect2()
		var points: PackedVector3Array = []
		if DASprites.is_card(model):
			# A sprite card is drawn leaning toward the camera from a base that sits
			# ahead of the node, so its real corners replace the mesh box.
			var cells = (sim.catalog.buildings[e.kind].radius * 2 + 1) if e.building else 1
			points = DASprites.card_corners(model, e.kind, cells, field.camera)
		else:
			for child in model.get_children():
				if not child is MeshInstance3D:
					continue
				var aabb = child.get_aabb()
				for i in 8:
					points.append(child.global_transform*aabb.get_endpoint(i))
		for p3 in points:
			var point = field.camera.unproject_position(p3)
			if first:
				bounds = Rect2(point,Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
		if not first and bounds.grow(4).has_point(screen):
			var distance = screen.distance_to(bounds.get_center())
			if distance < best_distance:
				best_distance = distance
				best = e.id
	return best

func select_at(screen: Vector2, additive: bool) -> void:
	if not additive:
		selected.clear()
	if drag_start.distance_to(screen) > 6:
		var rect = Rect2(drag_start, screen-drag_start).abs()
		for e in sim.entities.values():
			if e.owner == 0 and not e.building and rect.has_point(field.screen_at(e.pos, 0.6)) and not selected.has(e.id):
				selected.append(e.id)
	else:
		var id = pick_screen(screen)
		var now = Time.get_ticks_msec()
		var double: bool = id >= 0 and id == last_click_id and now - last_click_msec < 350
		last_click_id = id
		last_click_msec = now
		if double and sim.entities[id].owner == 0 and not sim.entities[id].building:
			# Double-click: every unit of that type on screen.
			var kind: String = sim.entities[id].kind
			for e in sim.entities.values():
				if e.owner == 0 and e.kind == kind and hud.is_world(field.screen_at(e.pos, 0.6)) and not selected.has(e.id):
					selected.append(e.id)
		elif id >= 0:
			if additive and selected.has(id):
				selected.erase(id)
			elif not selected.has(id):
				selected.append(id)
	if not selected.is_empty():
		audio.play("order")

func context_order(p: Vector2, screen: Vector2 = Vector2(-1,-1)) -> void:
	if selected.is_empty():
		return
	var owned = selected.filter(func(id): return sim.entities.has(id) and sim.entities[id].owner == 0)
	if owned.is_empty():
		return
	var first = sim.entities[owned[0]]
	if first.building:
		issue("rally", {"pos": p})
		return
	var target = pick_screen(screen) if screen.x >= 0 else pick(p)
	if target >= 0:
		var e = sim.entities[target]
		if e.owner == 1:
			issue("attack", {"target": target})
			return
		if e.owner == -1:
			issue("gather", {"target": target})
			return
		if e.owner == 0 and e.building and (not e.complete or e.hp < e.max_hp):
			issue("repair", {"target": target})
			return
	issue("move", {"pos": p})

func issue(action: String, payload: Dictionary = {}) -> String:
	var error = sim.command(0, action, selected, payload)
	if error != "":
		hud.toast(error, "error")
		audio.play("ui_error")
		if error.begins_with("Insufficient"): audio.announce("alert.insufficient")
	else:
		unsaved_command = true
		audio.play("order")
		if payload.has("pos"):
			field.show_marker(payload.pos)
	return error

## The mission after the current one, when it exists and is unlocked.
func next_mission_id() -> String:
	var definitions = mission_catalog.all_definitions()
	for i in definitions.size() - 1:
		if definitions[i].mission_id == mission_definition.mission_id and campaign.unlocked_missions.has(definitions[i + 1].mission_id):
			return definitions[i + 1].mission_id
	return ""

func commit_preferences(error: String, success: String = "") -> void:
	apply_runtime_settings()
	if error != "": hud.toast(error, "error")
	elif success != "": hud.toast(success, "success")
	hud.prepare_layout(true)

func ui_action(action: String, payload: Dictionary = {}) -> void:
	if action in ["restart", "load", "load_slot", "menu", "quit"] and not payload.get("confirmed", false) and mode in ["playing", "paused"] and (sim.elapsed > saved_elapsed or unsaved_command):
		hud.confirm_action(action, payload)
		return
	match action:
		"confirm_cancel":
			var previous_focus: String = hud.confirmation.get("focus", "")
			hud.close_overlay()
			hud.focused = previous_focus
		"confirm_save", "confirm_proceed":
			var next_action: String = hud.confirmation.get("action", "")
			var next_payload: Dictionary = hud.confirmation.get("payload", {}).duplicate()
			next_payload.confirmed = true
			if action == "confirm_save":
				if next_action in ["load", "load_slot"]:
					hud.toast("Choose Load Saved Game or Cancel to preserve the saved game.")
					return
				var error = save_game()
				if error != "":
					hud.toast(error, "error")
					return
			hud.confirmation.clear()
			if next_action == "reset_all": commit_preferences(settings.reset(), "Preferences reset")
			elif next_action != "": ui_action(next_action, next_payload)
		"reset_all": hud.confirm_action("reset_all")
		"reset_category": commit_preferences(settings.reset(str(payload.get("category", ""))), "Preferences reset")
		"start", "restart", "start_skirmish":
			var skirmish: bool = action == "start_skirmish" or (action == "restart" and game_kind == "skirmish")
			new_world("skirmish" if skirmish else pending_mission_id)
			mode = "playing"
			hud.objectives_open = true
			audio.set_music("ambient")
			hud.toast(mission_definition.title + " initiated.")
			if not skirmish:
				audio.speak(mission_definition.mission_id + ".briefing", mission_definition.briefing, "archivist")
		"skirmish":
			if hud.panel_open == "skirmish": hud.close_overlay()
			else:
				if mode != "menu":
					new_world(pending_mission_id)
					mode = "menu"
					audio.set_music("menu")
				hud.open_overlay("skirmish")
		"skirmish_option":
			# Step one setting of the saved setup forward or back through its choices.
			var setup: Dictionary = settings.values.skirmish.duplicate()
			var field_name: String = str(payload.get("key", "map"))
			var choices: Array = {"map": DASettingsService.SKIRMISH_MAPS, "player": DASettingsService.SKIRMISH_FACTIONS, "enemy": DASettingsService.SKIRMISH_FACTIONS, "resources": DASettingsService.SKIRMISH_RESOURCES.keys(), "side": DASettingsService.SKIRMISH_SIDES}.get(field_name, [])
			if not choices.is_empty():
				setup[field_name] = choices[posmod(choices.find(setup[field_name]) + int(payload.get("delta", 1)), choices.size())]
				commit_preferences(settings.set_value("skirmish", setup))
		"select_mission":
			pending_mission_id = str(payload.get("id", "first_signal"))
			hud.toast("Selected mission: " + str(payload.get("title", pending_mission_id)))
		"pause":
			mode = "paused"
			hud.cancel_pointer()
		"resume":
			mode = "playing"
		"menu":
			new_world(pending_mission_id)
			mode = "menu"
			audio.set_music("menu")
		"help":
			hud.open_overlay("manual")
		"help_close":
			hud.close_overlay()
		"quit":
			get_tree().quit()
		"speed":
			speed = {1:2, 2:4, 4:1}[speed]
		"sound":
			commit_preferences(settings.toggle("muted"), "Sound off" if not settings.values.muted else "Sound on")
		"window_mode":
			commit_preferences(settings.cycle("window_mode", DASettingsService.WINDOW_MODES))
		"resolution":
			commit_preferences(settings.cycle("resolution", DASettingsService.RESOLUTIONS))
		"frame_cap":
			commit_preferences(settings.cycle("frame_cap", DASettingsService.FRAME_CAPS))
		"vsync":
			commit_preferences(settings.toggle("vsync"))
		"colorblind":
			commit_preferences(settings.toggle("colorblind"))
		"credits":
			if hud.panel_open == "credits": hud.close_overlay()
			else: hud.open_overlay("credits")
		"settings":
			if hud.settings_open: hud.close_overlay()
			else: hud.open_overlay("settings")
		"volume":
			var key = str(payload.get("key", "master_volume"))
			var delta = float(payload.get("delta", 0.0))
			commit_preferences(settings.set_value(key, clampf(float(settings.values.get(key, 1.0)) + delta, 0.0, 1.0)))
		"subtitles":
			commit_preferences(settings.set_value("subtitles", not settings.values.subtitles))
		"ui_scale":
			var next = (DASettingsService.SCALES.find(settings.values.ui_scale)+1)%DASettingsService.SCALES.size()
			commit_preferences(settings.set_value("ui_scale", DASettingsService.SCALES[next]))
		"rebind":
			hud.rebind_action = str(payload.get("action", ""))
		"shadows":
			commit_preferences(settings.toggle("shadows"))
		"profile":
			commit_preferences(settings.set_value("profile", "low" if settings.values.profile == "normal" else "normal"))
		"effects":
			commit_preferences(settings.set_value("reduced_effects", not settings.values.reduced_effects))
		"save", "save_slot":
			var save_error = save_game(str(payload.get("slot", "manual_1")))
			if action == "save_slot" and save_error == "": hud.close_overlay()
			if save_error == "": audio.play("ui_confirm")
			hud.toast("Game saved" if save_error == "" else save_error, "success" if save_error == "" else "error")
		"load", "load_slot":
			var load_error = load_game(str(payload.get("slot", "manual_1")))
			hud.toast("Game loaded" if load_error == "" else load_error, "success" if load_error == "" else "error")
		"saves":
			if hud.panel_open == "saves": hud.close_overlay()
			else:
				hud.saves_mode = str(payload.get("id", "load"))
				hud.open_overlay("saves")
		"difficulty":
			var levels: Array = DAOpponent.DIFFICULTIES
			campaign.selected_difficulty = levels[(levels.find(campaign.selected_difficulty) + 1) % levels.size()]
			DASaveGame.save_campaign(campaign)
			opponent.set_difficulty(campaign.selected_difficulty)
		"next_mission":
			var next_id = next_mission_id()
			if next_id != "":
				pending_mission_id = next_id
				ui_action("start")
		"jump_alert":
			if last_alert_pos.x < 0: hud.toast("No alert to show.")
			else:
				field.focus = last_alert_pos
				field.update_camera()
		"patrol_mode":
			patrol_mode = true
			attack_mode = false
			rally_mode = false
			build_kind = ""
		"hold":
			issue("hold")
		"stance":
			# Switch the selection between holding its ground and chasing what it sees.
			var units = selected.filter(func(id): return sim.entities.has(id) and not sim.entities[id].building)
			var aggressive: bool = not units.is_empty() and sim.entities[units[0]].get("stance", "defensive") == "aggressive"
			if issue("stance", {"stance": "defensive" if aggressive else "aggressive"}) == "":
				hud.toast("Stance: " + ("defensive. Units fire from where they stand." if aggressive else "aggressive. Units chase what they see, then return."))
		"ability":
			var spec: Dictionary = sim.catalog.abilities.get(str(payload.get("kind", "")), {})
			if spec.get("targeted", false):
				ability_mode = true
				attack_mode = false
				rally_mode = false
				patrol_mode = false
				build_kind = ""
			else:
				issue("ability")
		"cancel_job":
			if issue("cancel", payload) == "": hud.toast("Cancelled and refunded.")
		"workers":
			selected = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "worker").map(func(e): return e.id)
		"home":
			field.focus = sim.bases[0]
			field.update_camera()
			selected = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "core").map(func(e): return e.id)
		"attack_mode":
			attack_mode = true
			rally_mode = false
			patrol_mode = false
			ability_mode = false
			build_kind = ""
		"rally":
			rally_mode = true
			attack_mode = false
			patrol_mode = false
			ability_mode = false
			build_kind = ""
		"tech":
			if hud.tech_open: hud.close_overlay()
			else: hud.open_overlay("tech")
		"research_tech":
			var labs = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "lab" and e.complete and e.research == "")
			if labs.is_empty():
				hud.toast("Build a Research Lab, or wait for one to finish its project.", "error")
			else:
				var research_error = sim.command(0, "research", [labs[0].id], payload)
				if research_error != "": hud.toast(research_error, "error")
				else:
					unsaved_command = true
					audio.play("order")
		"select_one":
			selected = [payload.id]
		"idle_worker":
			var idle: Array = hud.idle_workers()
			if idle.is_empty(): hud.toast("Every Worker is busy.")
			else:
				idle_cursor = (idle_cursor + 1) % idle.size()
				selected = [idle[idle_cursor]]
				field.focus = sim.entities[selected[0]].pos
				field.update_camera()
		"army":
			selected = sim.entities.values().filter(func(e): return e.owner == 0 and not e.building and e.kind != "worker").map(func(e): return e.id)
			if selected.is_empty(): hud.toast("No combat units. Train units at a Fabricator.")
		"objectives":
			hud.objectives_open = not hud.objectives_open
			hud.prepare_layout(true)
		"build":
			build_kind = payload.kind
			attack_mode = false
			rally_mode = false
			patrol_mode = false
			ability_mode = false
		"train", "research", "stop":
			issue(action, payload)
