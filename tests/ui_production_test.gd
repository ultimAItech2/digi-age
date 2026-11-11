extends SceneTree
const RESOLUTIONS = [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(3440,1440),Vector2i(3840,2160)]
var game
var failures = 0
var checks = 0
var captures = false
var label = ""
var layouts: Array = []

func luminance(color: Color) -> float:
	var linear = color.srgb_to_linear()
	return .2126*linear.r+.7152*linear.g+.0722*linear.b

func contrast(a: Color, b: Color) -> float:
	return (maxf(luminance(a),luminance(b))+.05)/(minf(luminance(a),luminance(b))+.05)

func _initialize():
	captures = "--capture-ui" in OS.get_cmdline_user_args()
	call_deferred("run")

func expect(ok: bool, title: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label+" "+title)

func key(code: int, shift = false):
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	game._input(event)

func mouse_at(p: Vector2, code: int, down: bool):
	var event = InputEventMouseButton.new()
	event.position = p
	event.button_index = code
	event.pressed = down
	game._input(event)

func click(p: Vector2, code: int = MOUSE_BUTTON_LEFT):
	mouse_at(p,code,true)
	mouse_at(p,code,false)

func control(action: String, kind: String = "") -> Dictionary:
	game.hud.prepare_layout(true)
	for b in game.hud.buttons:
		if b.action == action and (kind == "" or b.payload.get("kind","") == kind): return b
	return {}

func activate(action: String, kind: String = ""):
	var b = control(action,kind)
	expect(not b.is_empty(),"control exists: "+action)
	if not b.is_empty(): click(b.rect.get_center())

func check_layout():
	game.hud.prepare_layout(true)
	var viewport = Rect2(Vector2.ZERO,game.hud.size)
	var ids: Dictionary = {}
	for b in game.hud.buttons:
		expect(viewport.encloses(b.rect),"button within viewport: "+b.id)
		expect(b.rect.size.y >= 36*game.hud.ui_scale,"minimum control height")
		expect(not ids.has(b.id),"stable unique ID: "+b.id)
		ids[b.id] = true
	for i in game.hud.buttons.size():
		for j in range(i+1,game.hud.buttons.size()):
			expect(not game.hud.buttons[i].rect.intersects(game.hud.buttons[j].rect),"interactive controls do not overlap")
	for entry in game.hud.text_bounds:
		expect(viewport.grow(1).encloses(entry.rect),"text within viewport: "+entry.text)
		if label.ends_with("manual") or label.ends_with("subtitle"):
			expect(entry.source == "","manual and captions are never abbreviated: "+entry.text)
		if entry.clip.has_area(): expect(entry.clip.grow(1).encloses(entry.rect),"text obeys scroll clipping")
		for b in game.hud.buttons:
			if entry.control != b.id:
				expect(not entry.rect.intersects(b.rect),"text does not cover another control: "+entry.text+" / "+b.id)
	var regions: Dictionary = game.hud.reserved_regions
	for a in regions:
		for b in regions:
			if a < b and a != "notification" and b != "notification":
				expect(not regions[a].intersects(regions[b]),"reserved regions separated: "+a+" / "+b)
	layouts.append({"state":label,"controls":game.hud.buttons.size(),"text_lines":game.hud.text_bounds.size(),"layout_usec":game.hud.layout_usec})

func scenario(name: String):
	game.hud.clear_overlays()
	game.hud.message_left = 0
	game.hud.notifications.clear()
	game.hud.subtitle_left = 0
	game.hud.mouse = Vector2(-100,-100)
	game.hud.focused = ""
	game.hud.objectives_open = false
	game.build_kind = ""
	game.attack_mode = false
	game.rally_mode = false
	game.patrol_mode = false
	game.ability_mode = false
	game.mode = "playing"
	game.sim.winner = -1
	game.mission.mission_won = false
	game.selected.clear()
	game.sim.resources[0] = Vector3(99999999,99999999,99999999)
	for e in game.sim.entities.values():
		if e.owner>=0: e.queue.clear()
	if name == "menu" or name == "menu_error":
		game.mode = "menu"
		if name=="menu_error": game.hud.toast("Complete the preceding operation to unlock this mission.","error")
	elif name == "pause": game.mode = "paused"
	elif name == "settings": game.hud.open_overlay("settings")
	elif name == "bindings":
		game.hud.open_overlay("settings")
		game.hud.prepare_layout(true)
		game.hud.scroll_offset = game.hud.scroll_max
	elif name == "manual": game.hud.open_overlay("manual")
	elif name == "credits":
		game.mode = "menu"
		game.hud.open_overlay("credits")
	elif name == "skirmish":
		game.mode = "menu"
		game.hud.open_overlay("skirmish")
	elif name == "saves_load" or name == "saves_save":
		game.mode = "paused"
		game.hud.saves_mode = name.get_slice("_",1)
		game.hud.open_overlay("saves")
	elif name == "patrol":
		for e in game.sim.entities.values():
			if e.kind == "scout" and e.owner == 0:
				game.selected = [e.id]
				break
		game.patrol_mode = true
	elif name == "ability":
		for e in game.sim.entities.values():
			if e.kind == "scout" and e.owner == 0:
				game.selected = [e.id]
				e["ability_ready"] = game.sim.elapsed+30.0
				e["stance"] = "aggressive"
				break
		game.ability_mode = true
	elif name == "alert":
		game.hud.toast("Under attack. Press N to look.","alert")
		game.hud.ping(Vector2(20,30),"danger")
	elif name == "tech": game.hud.open_overlay("tech")
	elif name == "group":
		game.selected = game.sim.entities.values().filter(func(e): return e.owner == 0 and not e.building).map(func(e): return e.id)
	elif name == "victory" or name == "defeat":
		game.mode = "result"
		game.sim.winner = 0 if name == "victory" else 1
	elif name == "confirmation": game.hud.confirm_action("restart")
	elif name == "empty": pass
	elif name == "objectives":
		game.hud.objectives_open = true
		for e in game.sim.entities.values():
			if e.kind == "core" and e.owner == 0:
				game.selected = [e.id]
				break
	else:
		var kind = "worker" if name in ["placement","subtitle","error","disabled"] else ("core" if name=="queue" else name)
		for e in game.sim.entities.values():
			if e.kind == kind and e.owner <= 0:
				game.selected = [e.id]
				break
		if name == "placement": game.build_kind = "generator"
		if name == "subtitle": game.hud.show_subtitle("Origin archivist","Restore the industrial network. Our Workers can gather metal from salvage piles and retrieve data from archives to power the next age.",10)
		if name == "error": game.hud.toast("Insufficient resources. Gather additional metal and energy before constructing a Fabricator.","error")
		if name == "disabled": game.sim.resources[0] = Vector3.ZERO
		if name == "queue":
			for i in 5: game.sim.entities[game.selected[0]].queue.append({"kind":"worker","left":12.0})
	game.field.sync(0,game.selected)

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = RESOLUTIONS[0]
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.audio.enabled = false
	game.hud.set_process(false)
	label = "behavior"
	for background in [DAInterface.BG,DAInterface.PANEL,DAInterface.BUTTON,DAInterface.BUTTON_DISABLED,DAInterface.BUTTON_PRIMARY,DAInterface.BUTTON_HOVER,DAInterface.BUTTON_PRESSED]:
		for foreground in [DAInterface.TEXT,DAInterface.MUTED,DAInterface.ACCENT,DAInterface.GOLD,DAInterface.ERROR,DAInterface.GREEN,DAInterface.VIOLET]:
			expect(contrast(background.blend(foreground),background)>=4.5,"informative text contrast")
		expect(contrast(background.blend(DAInterface.LINE),background)>=3,"control boundary contrast")
	# The rendered plates sit under text too: their mean colour must hold the same contrast.
	for plate_name in ["panel","dock","button","button_hover","button_pressed","button_disabled","slot"]:
		var plate_image = Image.new()
		expect(plate_image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/frames/%s.png" % plate_name)) == OK and game.hud.plate(plate_name) != null,"rendered plate loads: "+plate_name)
		plate_image.resize(1,1,Image.INTERPOLATE_LANCZOS)
		var mean: Color = plate_image.get_pixel(0,0)
		for foreground in [DAInterface.TEXT,DAInterface.MUTED,DAInterface.ACCENT,DAInterface.GOLD]:
			expect(contrast(foreground,mean)>=4.5,"text contrast on rendered plate: "+plate_name)
	game.hud.prepare_layout(true)
	var start = control("start")
	expect(not start.is_empty(),"menu launch exists before drawing")
	mouse_at(start.rect.get_center(),MOUSE_BUTTON_LEFT,true)
	expect(game.mode == "menu","press does not activate")
	mouse_at(Vector2.ZERO,MOUSE_BUTTON_LEFT,false)
	expect(game.mode == "menu","release outside cancels")
	activate("start")
	game.hud.set_process(false)
	expect(game.mode == "playing","release inside starts mission")
	game.hud.open_overlay("settings")
	var elapsed = game.sim.elapsed
	var camera = game.field.focus
	var zoom = game.field.zoom
	game._process(.2)
	click(Vector2(600,350),MOUSE_BUTTON_RIGHT)
	click(game.hud.map_rect.get_center(),MOUSE_BUTTON_RIGHT)
	click(Vector2(600,350),MOUSE_BUTTON_WHEEL_UP)
	key(KEY_SPACE)
	key(KEY_A)
	expect(game.sim.elapsed==elapsed and game.field.focus==camera and game.field.zoom==zoom and not game.attack_mode,"settings block simulation and world input")
	game.hud.rebind_action = "save"
	key(KEY_ESCAPE)
	expect(game.hud.settings_open and game.hud.rebind_action=="","Escape cancels capture first")
	key(KEY_ESCAPE)
	expect(not game.hud.modal_active(),"Escape restores gameplay")
	game.dragging = true
	game.middle_drag = true
	game.hud.open_overlay("manual")
	expect(not game.dragging and not game.middle_drag,"modal cancels drags")
	key(KEY_TAB)
	expect(game.hud.focused != "","Tab sets visible focus")
	key(KEY_ENTER)
	expect(not game.hud.manual,"Enter activates focused Return")
	game.ui_action("restart")
	expect(not game.hud.confirmation.is_empty(),"restart protects unsaved progress")
	activate("confirm_cancel")
	expect(game.hud.confirmation.is_empty() and game.sim.elapsed==elapsed,"cancel preserves session")
	game.ui_action("settings")
	for i in 18: key(KEY_TAB)
	expect(game.hud.scroll_offset > 0,"Tab brings offscreen settings controls into view")
	var prior: Dictionary = game.settings.values.duplicate(true)
	expect(game.settings.set_binding("save",KEY_A)!="","duplicate binding rejected")
	expect(game.settings.set_binding("save",KEY_Q)!="","camera binding rejected")
	expect(game.settings.set_binding("save",KEY_TAB)!="","navigation binding rejected")
	expect(game.settings.set_binding("save",KEY_SHIFT)!="","modifier-only binding rejected")
	expect(game.settings.set_binding("save",KEY_F6)=="","valid rebind saved")
	expect(game.settings.prompt("save")=="F6","displayed prompt follows binding")
	game.settings.path = "user://absent-directory/settings.cfg"
	var previous_volume: float = game.settings.values.master_volume
	game.ui_action("volume",{"key":"master_volume","delta":-.1})
	expect(game.settings.values.master_volume==previous_volume and game.hud.severity=="error","failed preference write rolls back and shows error")
	game.settings.path = DASettingsService.PATH
	game.settings.reset()
	game.ui_action("reset_all")
	expect(not game.hud.confirmation.is_empty(),"reset-all requires confirmation")
	activate("confirm_cancel")
	var pref_file = FileAccess.open(DASettingsService.PATH,FileAccess.WRITE)
	pref_file.store_var({"master_volume":2.0,"profile":"invalid","bindings":{"save":KEY_F6}})
	pref_file.close()
	game.settings.load_settings()
	expect(game.settings.values.master_volume==1.0 and game.settings.values.profile=="normal" and game.settings.binding("save",0)==KEY_F6,"legacy settings merge and invalid values recover")
	game.settings.reset()
	game.hud.clear_overlays()
	expect(game.save_game("production_ui")=="","save succeeds")
	var file = FileAccess.open(DASaveGame.path_for("production_ui"),FileAccess.READ)
	var saved: Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	saved.mission.mission_id = "wrong_mission"
	file = FileAccess.open(DASaveGame.path_for("production_ui_invalid"),FileAccess.WRITE)
	file.store_buffer(var_to_bytes(saved))
	file.close()
	var before = game.sim.serialize_state()
	expect(game.load_game("production_ui_invalid")!="" and game.sim.serialize_state()==before,"wrong mission load leaves live state intact")
	expect(game.load_game("missing_ui_slot")!="" and game.sim.serialize_state()==before,"missing save leaves live state intact")
	expect(game.load_game("production_ui")=="","valid saved game loads after staging")
	game.unsaved_command = true
	game.ui_action("load")
	expect(not game.hud.confirmation.is_empty(),"load asks before replacing active state")
	expect(control("confirm_save").is_empty(),"load cannot overwrite its target with a pre-load save")
	activate("confirm_cancel")
	game.hud.clear_overlays()
	# Voice captions are queued and paged even with muted/missing audio.
	game.audio.clear_dialogue()
	game.audio.speak("missing-a","First message.","Speaker A")
	game.audio.speak("missing-b","Second message.","Speaker B")
	expect(game.hud.subtitle_speaker=="Speaker A","queued dialogue does not replace current caption")
	game.audio._process(10)
	expect(game.hud.subtitle_speaker=="Speaker B","next caption appears when previous duration ends")
	game.audio.clear_dialogue()
	# Add every selection category for layout and rendered review.
	game.hud.clear_overlays()
	game.mode = "playing"
	game.unsaved_command = true
	game.ui_action("restart")
	DirAccess.make_dir_recursive_absolute("user://saves/manual_1.save.tmp")
	game.ui_action("confirm_save")
	expect(not game.hud.confirmation.is_empty() and game.mode=="playing" and game.hud.severity=="error","save failure prevents leaving the session")
	DirAccess.remove_absolute("user://saves/manual_1.save.tmp")
	game.ui_action("confirm_save")
	expect(game.hud.confirmation.is_empty() and game.mode=="playing" and FileAccess.file_exists(DASaveGame.path_for("manual_1")),"save-and-continue commits before restart")
	for kind in ["fabricator","generator","data_center","tower","depot","lab","scout","sentinel","disruptor","walker","warden","mortar","phantom"]:
		game.sim.spawn(kind,0,Vector2(22,35))
	game.sim.resources[0] = Vector3(99999999,99999999,99999999)
	game.sim.ages[0] = 2
	var states = ["menu","worker","core","fabricator","generator","data_center","tower","depot","lab","scout","sentinel","disruptor","walker","metal","data","group","tech","placement","subtitle","error","pause","settings","bindings","manual","victory","defeat","confirmation","menu_error","disabled","queue","objectives","empty","credits","skirmish","saves_load","saves_save","patrol","alert","ability","warden","mortar","phantom"]
	DirAccess.make_dir_recursive_absolute("res://builds/ui")
	for resolution in RESOLUTIONS:
		root.size = resolution
		await process_frame
		for scale_value in DASettingsService.SCALES:
			game.hud.apply_scale(scale_value)
			for state in states:
				label = "%dx%d-%d-%s" % [resolution.x,resolution.y,roundi(scale_value*100),state]
				scenario(state)
				check_layout()
				if captures and (scale_value == 1.0 or resolution==RESOLUTIONS[0]):
					game.hud.queue_redraw()
					await process_frame
					await RenderingServer.frame_post_draw
					var image = root.get_texture().get_image()
					expect(image.get_size()==resolution,"real rendered image dimensions")
					image.save_png("res://builds/ui/"+label+".png")
			# Exercise real controller routing at every viewport and UI scale.
			label = "%dx%d-%d-input" % [resolution.x,resolution.y,roundi(scale_value*100)]
			scenario("worker")
			activate("build","generator")
			expect(game.build_kind=="generator","scaled build control activates its displayed action")
			click(Vector2(10,10),MOUSE_BUTTON_RIGHT)
			expect(game.build_kind=="","right-click over HUD cancels placement")
			activate("pause")
			expect(game.mode=="paused","scaled pause control activates")
			activate("resume")
			expect(game.mode=="playing","scaled resume control restores play")
			game.hud.prepare_layout(true)
			var previous_focus: Vector2 = game.field.focus
			var map_point: Vector2 = game.hud.map_point(Vector2.ONE*54)
			click(map_point)
			expect(game.field.focus.distance_to(Vector2.ONE*54)<.01,"scaled minimap points to correct world coordinates")
			click(map_point,MOUSE_BUTTON_RIGHT)
			var worker: Dictionary = game.sim.entities[game.selected[0]]
			expect(worker.order=="move" and worker.destination.distance_to(Vector2.ONE*54)<.01,"scaled minimap order reaches the intended destination")
			game.sim.command(0,"stop",game.selected)
			game.field.focus = previous_focus
			game.field.update_camera()
	if captures:
		label = "fullscreen-transition"
		root.mode = Window.MODE_FULLSCREEN
		for i in 4: await process_frame
		check_layout()
		root.mode = Window.MODE_WINDOWED
		root.size = RESOLUTIONS[0]
		for i in 4: await process_frame
		check_layout()
	var report = FileAccess.open("res://builds/ui/layout-report.json" if captures else "res://builds/ui/layout-report-headless.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"layouts":layouts},"  "))
	report.close()
	print("PRODUCTION_UI: %d checks, %d failures, %d layouts" % [checks,failures,layouts.size()])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
