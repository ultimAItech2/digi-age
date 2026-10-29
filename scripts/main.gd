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
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var speed: int = 1
var accumulator: float = 0.0
var refresh_timer: float = 0.0
var screenshot_requested: bool = false
var capture_delay: float = 3.0
var capture_frames: int = 90
var dev_overrides: Dictionary = {}
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

func _ready() -> void:
	audio = DAAudio.new()
	add_child(audio)
	settings.load_settings()
	DASaveGame.load_campaign(campaign)
	if campaign.current_mission != "" and campaign.unlocked_missions.has(campaign.current_mission):
		pending_mission_id = campaign.current_mission
	platform.initialize()
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
		elif arg == "--zoom" and next != "":
			field.zoom = clampf(float(next), 18.0, 70.0)
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
		for i in 10:
			selected.append(sim.spawn(["sentinel","disruptor","walker"][i%3],0,Vector2(20+i%5*1.5,46+floori(i/5.0)*2)))
		sim.ages[0] = 2
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
	print("UI_EXPORT_SMOKE: ", "PASS" if passed else "FAIL")
	get_tree().quit(0 if passed else 1)

func new_world(mission_id: String = "") -> void:
	if audio: audio.clear_dialogue()
	if field:
		remove_child(field)
		field.queue_free()
	sim = DASimulation.new()
	var requested = mission_id if mission_id != "" else pending_mission_id
	mission_definition = mission_catalog.get_definition(requested)
	if mission_definition == null or not campaign.unlocked_missions.has(requested):
		mission_definition = mission_catalog.get_definition("first_signal")
	pending_mission_id = mission_definition.mission_id
	mission = DAMissionController.new()
	mission.setup(sim, mission_definition)
	opponent = DAOpponent.new(sim)
	auto_player = null
	field = DABattlefield.new()
	add_child(field)
	field.setup(sim)
	field.apply_settings(settings.values)
	sim.notice.connect(func(text):
		if hud:
			hud.toast(text)
		audio.play("alert"))
	sim.shot.connect(func(from, to, _owner, _kind):
		if sim.seen(0, from) or sim.seen(0, to):
			audio.play("shot", {"kind": _kind})
			if _owner == 1:
				audio.notify_combat())
	mission.objective_completed.connect(_on_objective_completed)
	mission.checkpoint_created.connect(_on_checkpoint_created)
	mission.mission_completed.connect(_on_mission_completed)
	mission.mission_failed.connect(_on_mission_failed)
	mission.dialogue_requested.connect(_on_dialogue_requested)
	sim.reset_from_mission(mission_definition)
	opponent.refresh_from_faction()
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
	dragging = false
	accumulator = 0
	speed = 1
	saved_elapsed = -1.0
	unsaved_command = false
	if hud:
		hud.clear_overlays()
		hud.refresh_map()

func _on_objective_completed(objective_id: String) -> void:
	audio.play("objective_updated", {"id": objective_id})
	if hud:
		hud.toast(objective_id.replace("_", " ").capitalize(), "success")

func _on_dialogue_requested(entry_id: String) -> void:
	var entry = mission_definition.dialogue_entry(entry_id) if mission_definition else {}
	var text = str(entry.get("text", ""))
	var speaker = str(entry.get("speaker", "archivist"))
	audio.speak(mission_definition.mission_id + "." + entry_id, text, speaker)

func apply_runtime_settings() -> void:
	audio.apply_settings(settings.values)
	if field: field.apply_settings(settings.values)
	if hud:
		hud.apply_scale(float(settings.values.get("ui_scale", 1.0)))
		hud.subtitles_enabled = bool(settings.values.get("subtitles", true))

func _on_checkpoint_created(slot_id: String) -> void:
	campaign.current_mission = mission_definition.mission_id
	campaign.last_checkpoint = slot_id
	DASaveGame.save_campaign(campaign)
	var error = DASaveGame.save_slot("autosave_" + str(autosave_index), sim, mission, campaign, {"checkpoint": slot_id})
	autosave_index = (autosave_index + 1) % DASaveGame.SLOT_COUNT
	if error != "" and hud:
		hud.toast(error)

func _on_mission_completed() -> void:
	mode = "result"
	build_kind = ""
	attack_mode = false
	rally_mode = false
	audio.set_music("result")
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
	audio.play("mission_won")
	if mission_definition:
		audio.speak("victory", mission_definition.victory_text, "archivist")

func _on_mission_failed(reason: String) -> void:
	mode = "result"
	build_kind = ""
	attack_mode = false
	rally_mode = false
	audio.set_music("result")
	audio.play("mission_failed", {"reason": reason})
	if hud:
		hud.toast(reason)

func save_game(slot: String = "manual_1") -> String:
	campaign.current_mission = mission_definition.mission_id
	var error = DASaveGame.save_slot(slot, sim, mission, campaign, {"difficulty": mission_definition.difficulty})
	if error == "":
		saved_elapsed = sim.elapsed
		unsaved_command = false
	return error

func load_game(slot: String = "manual_1") -> String:
	var error = DASaveGame.load_slot(slot, sim, mission, campaign)
	if error == "":
		mode = "playing" if sim.winner < 0 and mission.active else "result"
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
			mode = "result"
			build_kind = ""
			attack_mode = false
			rally_mode = false
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

func capture() -> void:
	await RenderingServer.frame_post_draw
	var path = "res://builds/screenshot.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot saved: ", path)

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
	if hud.is_world(mouse) and mouse.x >= 0 and mouse.x < 7:
		direction.x -= 1
	if hud.is_world(mouse) and mouse.x > size.x-7 and mouse.x < size.x:
		direction.x += 1
	if hud.is_world(mouse) and mouse.y < hud.world_rect.position.y+7:
		direction.y -= 1
	if hud.is_world(mouse) and mouse.y > hud.world_rect.end.y-7:
		direction.y += 1
	if direction != Vector2.ZERO:
		field.pan(direction.normalized(), dt)
	if Input.is_physical_key_pressed(KEY_Q):
		field.yaw -= dt
		field.update_camera()
	if Input.is_physical_key_pressed(KEY_E):
		field.yaw += dt
		field.update_camera()

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
				field.zoom = clampf(field.zoom + (-2.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2.5), 18,  70.0)
				field.update_camera()
				return
			if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				return
			if event.button_index == MOUSE_BUTTON_RIGHT and (build_kind != "" or ((attack_mode or rally_mode) and not hud.map_rect.has_point(p))):
				build_kind = ""
				attack_mode = false
				rally_mode = false
				return
			if hud.handle_click(p, event.button_index == MOUSE_BUTTON_RIGHT):
				return
			var ground = field.ground_at(p)
			if event.button_index == MOUSE_BUTTON_RIGHT:
				if build_kind != "" or attack_mode or rally_mode:
					build_kind = ""
					attack_mode = false
					rally_mode = false
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
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if key == settings.binding("manual", KEY_F1):
		if hud.manual: hud.close_overlay()
		elif not hud.settings_open and hud.confirmation.is_empty(): hud.open_overlay("manual")
		return
	if key == settings.binding("cancel", KEY_ESCAPE):
		if hud.settings_open or hud.manual or not hud.confirmation.is_empty():
			hud.close_overlay()
		elif build_kind != "" or attack_mode or rally_mode:
			build_kind = ""
			attack_mode = false
			rally_mode = false
		elif mode == "playing":
			mode = "paused"
			hud.cancel_pointer()
		elif mode == "paused":
			mode = "playing"
		return
	if hud.settings_open or hud.manual or not hud.confirmation.is_empty(): return
	if key == settings.binding("pause", KEY_SPACE) and mode in ["playing", "paused"]:
		mode = "paused" if mode == "playing" else "playing"
		hud.cancel_pointer()
		return
	if mode != "playing" or hud.manual:
		return
	if key == settings.binding("speed", KEY_F2):
		speed = {1:2, 2:4, 4:1}[speed]
	if key == settings.binding("events", KEY_M):
		audio.enabled = not audio.enabled
		audio.apply_settings(settings.values)
	if key == settings.binding("save", KEY_F5):
		ui_action("save")
	if key == settings.binding("load", KEY_F9):
		ui_action("load")
	if key == settings.binding("attack", KEY_A) and not selected.is_empty():
		attack_mode = true
		build_kind = ""
	if key == settings.binding("stop", KEY_S) and not selected.is_empty():
		issue("stop")
	if key == settings.binding("home", KEY_HOME):
		ui_action("home")
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
		for child in model.get_children():
			if not child is MeshInstance3D:
				continue
			var aabb = child.get_aabb()
			for i in 8:
				var point = field.camera.unproject_position(child.global_transform*aabb.get_endpoint(i))
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
		if id >= 0:
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
	else:
		unsaved_command = true
		audio.play("order")
		if payload.has("pos"):
			field.show_marker(payload.pos)
	return error

func commit_preferences(error: String, success: String = "") -> void:
	apply_runtime_settings()
	if error != "": hud.toast(error, "error")
	elif success != "": hud.toast(success, "success")
	hud.prepare_layout(true)

func ui_action(action: String, payload: Dictionary = {}) -> void:
	if action in ["restart", "load", "menu", "quit"] and not payload.get("confirmed", false) and mode in ["playing", "paused"] and (sim.elapsed > saved_elapsed or unsaved_command):
		hud.confirm_action(action)
		return
	match action:
		"confirm_cancel":
			var previous_focus: String = hud.confirmation.get("focus", "")
			hud.close_overlay()
			hud.focused = previous_focus
		"confirm_save", "confirm_proceed":
			var next_action: String = hud.confirmation.get("action", "")
			if action == "confirm_save":
				if next_action == "load":
					hud.toast("Choose Load Saved Game or Cancel to preserve the saved game.")
					return
				var error = save_game()
				if error != "":
					hud.toast(error, "error")
					return
			hud.confirmation.clear()
			if next_action == "reset_all": commit_preferences(settings.reset(), "Preferences reset")
			elif next_action != "": ui_action(next_action, {"confirmed": true})
		"reset_all": hud.confirm_action("reset_all")
		"reset_category": commit_preferences(settings.reset(str(payload.get("category", ""))), "Preferences reset")
		"start", "restart":
			new_world(pending_mission_id)
			mode = "playing"
			hud.objectives_open = true
			audio.set_music("ambient")
			hud.toast(mission_definition.title + " initiated.")
			audio.speak(mission_definition.mission_id + ".briefing", mission_definition.briefing, "archivist")
		"select_mission":
			pending_mission_id = str(payload.get("id", "first_signal"))
			hud.toast("Selected mission: " + str(payload.get("title", pending_mission_id)))
		"pause":
			mode = "paused"
			hud.cancel_pointer()
		"resume":
			mode = "playing"
		"menu":
			new_world()
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
			audio.enabled = not audio.enabled
			audio.apply_settings(settings.values)
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
			field.sun.shadow_enabled = not field.sun.shadow_enabled
		"profile":
			commit_preferences(settings.set_value("profile", "low" if settings.values.profile == "normal" else "normal"))
		"effects":
			commit_preferences(settings.set_value("reduced_effects", not settings.values.reduced_effects))
		"save":
			var save_error = save_game()
			hud.toast("Game saved" if save_error == "" else save_error, "success" if save_error == "" else "error")
		"load":
			var load_error = load_game()
			hud.toast("Game loaded" if load_error == "" else load_error, "success" if load_error == "" else "error")
		"workers":
			selected = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "worker").map(func(e): return e.id)
		"home":
			field.focus = sim.bases[0]
			field.update_camera()
			selected = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "core").map(func(e): return e.id)
		"attack_mode":
			attack_mode = true
			rally_mode = false
			build_kind = ""
		"rally":
			rally_mode = true
			attack_mode = false
			build_kind = ""
		"tech":
			selected = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "core").map(func(e): return e.id)
			if selected.is_empty(): hud.toast("No Core remains to research at.", "error")
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
		"train", "research", "stop":
			issue(action, payload)
