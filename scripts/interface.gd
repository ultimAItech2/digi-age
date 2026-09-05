class_name DAInterface
extends Control
## Resolution-independent immediate HUD. Input regions match rendered controls.
const BG = Color("0c1922")
const PANEL = Color("12232d")
const LINE = Color("2b414a")
const TEXT = Color("e2ebe6")
const MUTED = Color("8ba3a8")
const ACCENT = Color("6bedcf")
const GOLD = Color("e7ba7f")
var game: Node3D
var font: Font = ThemeDB.fallback_font
var buttons: Array = []
var hovered: String = ""
var map_rect: Rect2
var message: String = ""
var message_left: float = 0.0
var mouse: Vector2 = Vector2.ZERO
var manual: bool = false
var settings_open: bool = false
var rebind_action: String = ""
var subtitles_enabled: bool = true
var subtitle_speaker: String = ""
var subtitle_text: String = ""
var subtitle_left: float = 0.0
var map_image: Image
var map_texture: ImageTexture

func setup(controller: Node3D) -> void:
	game = controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/fonts/Rajdhani-SemiBold.ttf"):
		font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	map_image = Image.create(DASimulation.SIZE, DASimulation.SIZE, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_image)
	refresh_map()

func _process(dt: float) -> void:
	mouse = get_viewport().get_mouse_position()
	message_left = maxf(0, message_left - dt)
	subtitle_left = maxf(0, subtitle_left - dt)
	queue_redraw()

func apply_scale(value: float) -> void:
	scale = Vector2.ONE * clampf(value, 0.85, 1.35)
	pivot_offset = Vector2.ZERO

func show_subtitle(speaker: String, text: String) -> void:
	subtitle_speaker = speaker
	subtitle_text = text
	subtitle_left = clampf(text.length() * 0.055, 2.8, 9.0)

func toast(value: String) -> void:
	message = value
	message_left = 5.0

func label_at(value: String, p: Vector2, size_px: int = 16, color: Color = TEXT) -> void:
	draw_string(font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func panel(rect: Rect2, color: Color = PANEL, border: bool = true) -> void:
	draw_style_box(style(color, LINE if border else color), rect)

func style(color: Color, border: Color, radius: int = 5) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s

func button(rect: Rect2, title: String, action: String, payload: Dictionary = {}, subtitle: String = "", enabled: bool = true, primary: bool = false) -> void:
	var over = rect.has_point(mouse)
	var bg = Color("24423f") if primary else Color("172d37")
	if over and enabled:
		bg = Color("30544f") if primary else Color("24414a")
	if not enabled:
		bg = Color("122029")
	draw_style_box(style(bg, ACCENT if primary and enabled else LINE), rect)
	var text_color = TEXT if enabled else Color("63787f")
	label_at(title, rect.position + Vector2(14, 26 if subtitle != "" else rect.size.y/2 + 6), 16, text_color)
	if subtitle != "":
		label_at(subtitle, rect.position + Vector2(14, 46), 12, MUTED if enabled else Color("53666d"))
	buttons.append({"rect": rect, "action": action, "payload": payload, "enabled": enabled})

func _draw() -> void:
	if not game or not game.sim:
		return
	buttons.clear()
	var w = size.x
	var h = size.y
	if game.mode == "menu":
		draw_menu(w, h)
		return
	draw_world_overlay()
	draw_rect(Rect2(0, 0, w, 76), BG)
	draw_line(Vector2(0, 76), Vector2(w, 76), LINE)
	label_at("D / A", Vector2(24, 35), 24, ACCENT)
	label_at("MACHINE CIVILIZATIONS", Vector2(25, 56), 10, MUTED)
	var r = game.sim.resources[0]
	resource_card(210, "METAL", str(int(r.x)), GOLD, "salvage")
	resource_card(365, "ENERGY", str(int(r.y)), ACCENT, "+" + str(int(generator_rate())) + "/s")
	resource_card(520, "DATA", str(int(r.z)), Color("c5a8f2"), "archives")
	resource_card(675, "COMPUTE", str(game.sim.population(0)) + " / " + str(game.sim.capacity(0)), TEXT, "unit capacity")
	label_at("0" + str(game.sim.ages[0]+1) + "  /  " + game.sim.catalog.ages[game.sim.ages[0]], Vector2(w-410, 31), 17, ACCENT)
	label_at(time_text(game.sim.elapsed) + "  •  " + str(game.speed) + "× SPEED", Vector2(w-410, 54), 12, MUTED)
	button(Rect2(w-156, 17, 132, 41), "II   PAUSE", "pause")
	panel(Rect2(22, 96, 390, 96), Color("11222bdd"))
	label_at((game.mission_definition.title if game.mission_definition else "SKIRMISH").to_upper(), Vector2(38, 119), 11, ACCENT)
	var directive = mission_directive()
	label_at(directive, Vector2(38, 147), 17, TEXT)
	label_at("F5 Save   F9 Load   ·   F1 Manual", Vector2(38, 174), 11, MUTED)
	label_at("ORIGIN COLLECTIVE  /  SECTOR 07", Vector2(w-355, 108), 11, MUTED)
	var bottom = h - 202
	draw_rect(Rect2(0, bottom-1, w, 203), BG)
	draw_line(Vector2(0, bottom), Vector2(w, bottom), LINE)
	draw_minimap(Rect2(22, bottom+16, 166, 166))
	label_at("SECTOR 07", Vector2(202, bottom+29), 11, MUTED)
	label_at((game.sim.active_map.display_name if game.sim.active_map else "THE SILENT GRID").to_upper(), Vector2(202, bottom+52), 17)
	label_at("LMB  Select / drag", Vector2(202, bottom+81), 12, MUTED)
	label_at("RMB  Context order", Vector2(202, bottom+103), 12, MUTED)
	label_at("A  Attack-move   S  Stop", Vector2(202, bottom+125), 12, MUTED)
	label_at("Arrows  Pan   Q/E  Rotate", Vector2(202, bottom+147), 12, MUTED)
	label_at("Scroll  Zoom   F1  Help", Vector2(202, bottom+169), 12, MUTED)
	draw_selection(Rect2(405, bottom+15, w-429, 170))
	if game.build_kind != "":
		var p = game.field.ground_at(mouse)
		var error = game.sim.placement_error(0, game.build_kind, p)
		var tip = "PLACE " + game.sim.catalog.buildings[game.build_kind].name.to_upper() + "  /  Left click to build · Right click to cancel"
		if error != "":
			tip = error + "  /  Right click to cancel"
		draw_toast(tip, h-227, ACCENT if error == "" else GOLD)
	elif game.attack_mode:
		draw_toast("ATTACK-MOVE  /  Click a destination · Right click to cancel", h-227, ACCENT)
	elif message_left > 0:
		draw_toast(message, h-227, TEXT)
	if subtitles_enabled and subtitle_left > 0 and subtitle_text != "":
		draw_subtitle(w, h)
	if game.dragging and game.drag_start.distance_to(mouse) > 5:
		var rect = Rect2(game.drag_start, mouse-game.drag_start).abs()
		draw_rect(rect, Color(0.4, 0.9, 0.8, 0.12))
		draw_rect(rect, ACCENT, false, 1.0)
	if settings_open:
		draw_settings(w, h)
	elif game.mode == "paused":
		draw_pause(w, h)
	elif game.mode == "result":
		draw_result(w, h)
	elif manual:
		draw_manual(w, h)
	else:
		draw_tooltip(w, h)

func resource_card(x: float, title: String, value: String, color: Color, suffix: String) -> void:
	draw_circle(Vector2(x+5, 31), 4, color)
	label_at(title, Vector2(x+18, 25), 10, MUTED)
	label_at(value, Vector2(x+18, 50), 22, color)
	label_at(suffix, Vector2(x+18, 65), 9, MUTED)

func generator_rate() -> float:
	var total = 0.0
	for e in game.sim.entities.values():
		if e.owner == 0 and e.kind == "generator" and e.complete:
			total += game.sim.catalog.energy_per_second
	return total

func draw_selection(rect: Rect2) -> void:
	var selected = game.selected.filter(func(id): return game.sim.entities.has(id) and game.sim.known(0, game.sim.entities[id]))
	if selected.is_empty():
		label_at("AWAITING YOUR COMMAND", rect.position+Vector2(22, 34), 20)
		label_at("Select your Workers to gather metal, retrieve data, and construct your base.", rect.position+Vector2(22, 67), 15, MUTED)
		label_at("Start with a Fabricator. Expand compute with Data Centers. Advance at your Core.", rect.position+Vector2(22, 94), 15, MUTED)
		button(Rect2(rect.position+Vector2(22, 113), Vector2(178, 43)), "SELECT WORKERS", "workers")
		button(Rect2(rect.position+Vector2(212, 113), Vector2(162, 43)), "FOCUS CORE", "home")
		return
	var e: Dictionary = game.sim.entities[selected[0]]
	var d: Dictionary = game.sim.catalog.definition(e.kind)
	var title = d.get("name", "Salvage field" if e.kind == "metal" else "Data archive")
	if selected.size() > 1:
		title = str(selected.size()) + " UNITS SELECTED"
	label_at(title.to_upper(), rect.position+Vector2(18, 25), 20)
	if e.owner < 0:
		label_at(str(int(e.amount)) + " " + e.kind + " remaining", rect.position+Vector2(18, 55), 16, GOLD)
		label_at("Select Workers, then right-click this deposit to harvest it.", rect.position+Vector2(18, 84), 14, MUTED)
		return
	var bar = Rect2(rect.position+Vector2(18, 37), Vector2(225, 5))
	draw_rect(bar, LINE)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x*clampf(e.hp/e.max_hp, 0, 1), 5)), ACCENT if e.owner == 0 else DAModels.RED)
	label_at(str(int(e.hp)) + " / " + str(int(e.max_hp)) + " INTEGRITY", rect.position+Vector2(18, 64), 12, MUTED)
	var status = "Operational"
	if not e.complete:
		status = "Constructing  " + str(int(100*(1-e.build_left/d.time))) + "%"
	elif e.research != "":
		status = ("Age advancement" if e.research == "age" else "Weapons upgrade") + "  " + str(ceili(e.research_left)) + "s"
	elif not e.queue.is_empty():
		status = "Producing " + game.sim.catalog.units[e.queue[0].kind].name + "  " + str(ceili(e.queue[0].left)) + "s"
	elif not e.building:
		status = e.order.capitalize().replace("_", " ")
		if e.kind == "worker" and e.cargo > 0:
			status += "  /  " + str(int(e.cargo)) + " " + e.cargo_kind
	label_at(status, rect.position+Vector2(18, 88), 13, GOLD)
	if e.queue.size() > 0:
		label_at("QUEUE  " + str(e.queue.size()) + " / 5", rect.position+Vector2(18, 111), 11, MUTED)
	if e.owner == 0 and not e.building:
		button(Rect2(rect.position+Vector2(18, 119), Vector2(109, 39)), "A  ATTACK", "attack_mode")
		button(Rect2(rect.position+Vector2(136, 119), Vector2(107, 39)), "S  STOP", "stop")
	var x = rect.position.x + 272
	var y = rect.position.y + 8
	var card_w = minf(166, (rect.size.x-284)/3)
	if e.owner != 0:
		label_at("RIVAL COLLECTIVE", Vector2(x, y+25), 15, DAModels.RED)
		return
	if not e.complete:
		label_at("Workers must remain at the site.", Vector2(x, y+25), 15, MUTED)
		return
	var items: Array = []
	if e.kind == "worker":
		for kind in ["generator", "depot", "data_center", "fabricator", "tower"]:
			items.append({"kind": kind, "action": "build", "d": game.sim.catalog.buildings[kind]})
	elif e.kind in ["core", "fabricator"]:
		for kind in (["worker"] if e.kind == "core" else ["scout", "sentinel", "disruptor", "walker"]):
			items.append({"kind": kind, "action": "train", "d": game.sim.catalog.units[kind]})
		if e.kind == "core":
			var age: int = game.sim.ages[0]
			if age < 2:
				items.append({"kind": "age", "action": "research", "d": {"name": game.sim.catalog.ages[age+1].capitalize() + " Age", "cost": game.sim.catalog.age_costs[age], "age": 0, "description": "Unlock the next age's units and technologies."}})
			var level: int = game.sim.upgrades[0]
			if level < 2:
				items.append({"kind": "weapons", "action": "research", "d": {"name": "Weapons " + str(level+1), "cost": game.sim.catalog.upgrade_costs[level], "age": level+1, "description": "Increase all weapon damage by 20%."}})
	for i in items.size():
		var item = items[i]
		var cost: Vector3 = item.d.cost
		var enabled = game.sim.ages[0] >= item.d.age
		if item.action == "research" and e.research != "":
			enabled = false
		var sub = cost_text(cost) if enabled else "Requires " + game.sim.catalog.ages[item.d.age].capitalize()
		button(Rect2(x+(i%3)*(card_w+8), y+floori(i/3.0)*69, card_w, 61), item.d.name, item.action, {"kind": item.kind, "tooltip": item.d.description}, sub, enabled)
	if items.is_empty():
		label_at(d.description.substr(0, 65), Vector2(x, y+25), 13, MUTED)
	if e.building and e.kind in ["core", "fabricator"]:
		label_at("Right-click terrain to set the production rally point.", Vector2(x, rect.end.y-4), 12, MUTED)

func cost_text(cost: Vector3) -> String:
	return str(int(cost.x)) + " M  /  " + str(int(cost.y)) + " E" + ("  /  " + str(int(cost.z)) + " D" if cost.z > 0 else "")

func refresh_map() -> void:
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var p = Vector2i(x, y)
			var color = Color("0b151e")
			if game.sim.explored[0].has(p):
				color = Color("47594e") if game.sim.visible[0].has(p) else Color("283931")
				if game.sim.obstacles.has(p):
					color = Color("727663")
			map_image.set_pixel(x, y, color)
	map_texture.update(map_image)

func draw_minimap(rect: Rect2) -> void:
	map_rect = rect
	draw_texture_rect(map_texture, rect, false)
	draw_rect(rect, LINE, false, 1)
	for e in game.sim.entities.values():
		if not game.sim.known(0, e) or e.get("amount", 1) <= 0:
			continue
		var p: Vector2 = rect.position + e.pos / DASimulation.SIZE * rect.size
		var color = ACCENT if e.owner == 0 else (DAModels.RED if e.owner == 1 else (GOLD if e.kind == "metal" else Color("c5a8f2")))
		draw_circle(p, 2.7 if e.building else 1.5, color)
	var points = PackedVector2Array()
	var h = size.y - 202
	for screen in [Vector2(0, 76), Vector2(size.x, 76), Vector2(size.x, h), Vector2(0, h), Vector2(0, 76)]:
		points.append(rect.position + game.field.ground_at(screen).clamp(Vector2.ZERO, Vector2.ONE*72)/72*rect.size)
	draw_polyline(points, Color("dee4c5"), 1.0)

func draw_world_overlay() -> void:
	for e in game.sim.entities.values():
		if e.owner < 0 or not game.sim.known(0, e):
			continue
		if not game.selected.has(e.id) and e.hp >= e.max_hp and e.complete:
			continue
		var p = game.field.screen_at(e.pos, 4.4 if e.building else 2.2)
		if p.y < 80 or p.y > size.y-209 or p.x < 0 or p.x > size.x:
			continue
		var width = 54 if e.building else 32
		draw_rect(Rect2(p.x-width/2.0-1, p.y-1, width+2, 6), BG)
		draw_rect(Rect2(p.x-width/2.0, p.y, width*clampf(e.hp/e.max_hp, 0, 1), 4), ACCENT if e.owner == 0 else DAModels.RED)
		if e.building and not e.complete:
			label_at(str(int(100*(1-e.build_left/game.sim.catalog.buildings[e.kind].time))) + "%", p+Vector2(-12, -6), 11, GOLD)
	if game.selected.size() == 1 and game.sim.entities.has(game.selected[0]):
		var e = game.sim.entities[game.selected[0]]
		if e.owner == 0 and e.building and e.kind in ["core", "fabricator"]:
			var p = game.field.screen_at(e.rally)
			draw_line(p, p-Vector2(0, 28), ACCENT, 2)
			draw_colored_polygon(PackedVector2Array([p-Vector2(0,28), p+Vector2(16,-22), p-Vector2(0,16)]), ACCENT)

func draw_toast(value: String, y: float, color: Color) -> void:
	var width = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 34
	var x = (size.x-width)/2
	panel(Rect2(x, y-28, width, 40), Color("10202bf2"))
	label_at(value, Vector2(x+17, y-2), 15, color)

func draw_menu(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w*0.53, h), Color("0a1722eb"))
	draw_rect(Rect2(0, 0, w, 5), ACCENT)
	label_at("D / A     ORIGINAL REAL-TIME STRATEGY", Vector2(65, 70), 14, ACCENT)
	label_at("THE WORLD WENT QUIET.", Vector2(65, h*0.28), 14, GOLD)
	label_at("DIGITAL", Vector2(60, h*0.28+95), 88)
	label_at("AGE", Vector2(60, h*0.28+183), 88, ACCENT)
	label_at("M A C H I N E   C I V I L I Z A T I O N S", Vector2(66, h*0.28+222), 15, MUTED)
	label_at("From the ruins, a new intelligence awakens.", Vector2(65, h*0.28+270), 18)
	label_at("Harvest. Evolve. Command the next civilization.", Vector2(65, h*0.28+298), 18, MUTED)
	var launch_sub = (game.mission_definition.title if game.mission_definition else "FIRST SIGNAL") + "  /  ORIGIN COLLECTIVE"
	button(Rect2(65, h-205, 330,  60.0), "LAUNCH CAMPAIGN   →", "start", {}, launch_sub, true, true)
	button(Rect2(65, h-130, 158, 44), "FIELD MANUAL", "help")
	button(Rect2(237, h-130, 104, 44), "SETTINGS", "settings")
	button(Rect2(351, h-130, 104, 44), "QUIT", "quit")
	label_at("OFFLINE  •  SINGLE PLAYER  •  VOICE, MUSIC, AND EFFECTS", Vector2(65, h-40), 11, MUTED)
	panel(Rect2(w-390, 72, 340, h-260), Color("0d2029e8"))
	label_at("CAMPAIGN MISSIONS", Vector2(w-365, 108), 13, ACCENT)
	label_at("Select an unlocked operation", Vector2(w-365, 130), 12, MUTED)
	var definitions = game.mission_catalog.all_definitions()
	for i in definitions.size():
		var definition: DAMissionDefinition = definitions[i]
		var unlocked = game.campaign.unlocked_missions.has(definition.mission_id)
		var marker = "✓" if game.campaign.completed_missions.has(definition.mission_id) else ("▶" if unlocked else "·")
		button(Rect2(w-365, 145+i*36, 290, 30), marker + "  " + definition.title, "select_mission", {"id": definition.mission_id, "title": definition.title}, "", unlocked, definition.mission_id == game.pending_mission_id)
	label_at("ORIGIN COLLECTIVE  /  EIGHT MISSION CAMPAIGN", Vector2(w-365, h-116), 11, MUTED)
	label_at("Eight maps. Three factions. One machine war.", Vector2(w-365, h-94), 13, TEXT)
	if settings_open:
		draw_settings(w, h)
	elif manual:
		draw_manual(w, h)


func draw_pause(w: float, h: float) -> void:
	buttons.clear()
	draw_rect(Rect2(0,0,w,h), Color(0.02,0.04,0.07,0.8))
	var x = w/2-210
	panel(Rect2(x-30, h/2-300, 480, 600))
	label_at("SIMULATION PAUSED", Vector2(x, h/2-170), 27)
	label_at("Your civilization awaits.", Vector2(x, h/2-138), 16, MUTED)
	button(Rect2(x, h/2-104, 420, 46), "RESUME", "resume", {}, "", true, true)
	button(Rect2(x, h/2-44, 132, 46), "SPEED  " + str(game.speed) + "×", "speed")
	button(Rect2(x+144, h/2-44, 132, 46), "SOUND  " + ("ON" if game.audio.enabled else "OFF"), "sound")
	button(Rect2(x+288, h/2-44, 132, 46), "SHADOWS " + ("ON" if game.field.sun.shadow_enabled else "OFF"), "shadows")
	button(Rect2(x, h/2+16, 204, 46), "PROFILE  " + str(game.settings.values.profile).to_upper(), "profile")
	button(Rect2(x+216, h/2+16, 204, 46), "REDUCED FX  " + ("ON" if game.settings.values.reduced_effects else "OFF"), "effects")
	button(Rect2(x, h/2+76, 204, 46), "SAVE GAME  F5", "save")
	button(Rect2(x+216, h/2+76, 204, 46), "LOAD GAME  F9", "load")
	button(Rect2(x, h/2+136, 204, 46), "FIELD MANUAL", "help")
	button(Rect2(x+216, h/2+136, 204, 46), "SETTINGS", "settings")
	button(Rect2(x, h/2+196, 420, 46), "RESTART MISSION", "restart")
	button(Rect2(x, h/2+256, 420, 46), "MAIN MENU", "menu")
	if settings_open:
		draw_settings(w, h)
	elif manual:
		draw_manual(w, h)

func draw_result(w: float, h: float) -> void:
	buttons.clear()
	draw_rect(Rect2(0,0,w,h), Color(0.02,0.04,0.07,0.86))
	var x = w/2-270
	panel(Rect2(x-40, h/2-210, 620, 420))
	label_at("TRANSMISSION COMPLETE", Vector2(x,h/2-155), 14, MUTED)
	var won = game.sim.winner == 0 or (game.mission != null and game.mission.mission_won)
	label_at("VICTORY" if won else "CORE LOST", Vector2(x,h/2-86), 60, ACCENT if won else DAModels.RED)
	label_at((game.mission_definition.victory_text if won and game.mission_definition else "The next age belongs to you.") if won else (game.mission_definition.defeat_text if game.mission_definition else "A civilization ends. Another can awaken."), Vector2(x,h/2-43), 19)
	label_at("TIME  " + time_text(game.sim.elapsed) + "     ENEMIES DESTROYED  " + str(game.sim.stats[0].kills), Vector2(x,h/2+4), 15, MUTED)
	label_at("RESOURCES HARVESTED  " + str(int(game.sim.stats[0].gathered)), Vector2(x,h/2+32), 15, MUTED)
	button(Rect2(x,h/2+75,260,56),"PLAY AGAIN", "restart", {}, "", true, true)
	button(Rect2(x+280,h/2+75,260,56),"MAIN MENU", "menu")

func draw_manual(w: float, h: float) -> void:
	buttons.clear()
	draw_rect(Rect2(0,0,w,h), Color(0.02,0.04,0.07,0.94))
	var x = w/2-500
	label_at("FIELD MANUAL", Vector2(x, 95), 36, ACCENT)
	label_at("Build the economy. Protect your Core. Out-evolve the rival collective.", Vector2(x, 132), 18)
	var lines = [
		["01 / ESTABLISH", "Select Workers and right-click golden salvage piles for metal. Violet archives provide data.", "Workers carry 24 resources home. Build a Salvage Depot near distant deposits."],
		["02 / EXPAND", "Generators supply energy. Data Centers add 20 compute. The maximum army capacity is 100.", "Select a Worker, choose a building, then click a clear explored site. Right-click cancels placement."],
		["03 / EVOLVE", "Select your Core to train Workers, advance ages, and upgrade weapons.", "Network unlocks Disruptors and Towers. Singularity unlocks Siege Walkers."],
		["04 / CONQUER", "Fabricators manufacture your army. Sentinels counter Disruptors; Disruptors counter Walkers.", "Walkers demolish buildings. Scout first: enemies outside your vision cannot be targeted."],
		["05 / COMMAND", "Click / drag: select. Shift: add. Right-click: move, gather, attack, repair, or set a rally point.", "A then click: attack-move. S: stop. Ctrl+1–9: save group. 1–9: recall. Home: focus Core."],
		["06 / NAVIGATE", "Arrows / screen edges / middle drag: pan. Mouse wheel: zoom. Q/E: rotate. Click minimap: move camera.", "Space / Escape: pause. F1: help. F2: cycle 1× / 2× / 4× speed. M: sound. F11: fullscreen."]
	]
	for i in lines.size():
		var y = 195+i*83
		label_at(lines[i][0],Vector2(x,y),14,GOLD)
		label_at(lines[i][1],Vector2(x,y+25),16)
		label_at(lines[i][2],Vector2(x,y+48),14,MUTED)
	button(Rect2(x,h-100,220,48),"RETURN", "help_close", {}, "", true, true)

func draw_subtitle(w: float, h: float) -> void:
	var width = minf(w - 80, 820)
	var x = (w - width) / 2
	var y = h - 268
	panel(Rect2(x, y, width, 58), Color("0d1c24f0"))
	label_at(subtitle_speaker.to_upper(), Vector2(x + 16, y + 18), 11, GOLD)
	label_at(subtitle_text, Vector2(x + 16, y + 40), 14, TEXT)

func volume_label(key: String) -> String:
	return str(int(round(float(game.settings.values.get(key, 1.0)) * 100))) + "%"

func draw_settings(w: float, h: float) -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.07, 0.9))
	var x = w / 2 - 260
	panel(Rect2(x - 24, 48, 568, h - 96))
	label_at("SETTINGS", Vector2(x, 92), 28, ACCENT)
	label_at("Volumes, captions, scale, and key bindings persist separately from saves.", Vector2(x, 122), 13, MUTED)
	var rows = [["MASTER", "master_volume"], ["MUSIC", "music_volume"], ["EFFECTS", "effects_volume"], ["VOICE", "voice_volume"], ["UI", "ui_volume"]]
	for i in rows.size():
		var y = 150 + i * 46
		label_at(rows[i][0], Vector2(x, y + 22), 14)
		label_at(volume_label(rows[i][1]), Vector2(x + 150, y + 22), 14, GOLD)
		button(Rect2(x + 230, y, 54, 34), "-", "volume", {"key": rows[i][1], "delta": -0.1})
		button(Rect2(x + 292, y, 54, 34), "+", "volume", {"key": rows[i][1], "delta": 0.1})
	button(Rect2(x, 390, 200, 40), "SUBTITLES  " + ("ON" if game.settings.values.subtitles else "OFF"), "subtitles")
	button(Rect2(x + 220, 390, 200, 40), "UI SCALE  " + str(game.settings.values.ui_scale), "ui_scale")
	label_at("CLICK A BINDING, THEN PRESS A KEY", Vector2(x, 450), 12, MUTED)
	var binds = ["pause", "manual", "save", "load", "attack", "stop"]
	for i in binds.size():
		var action = binds[i]
		var label = action.capitalize() + "  " + OS.get_keycode_string(game.settings.binding(action, KEY_NONE))
		if rebind_action == action:
			label = action.capitalize() + "  …"
		button(Rect2(x + (i % 3) * 168, 470 + floori(i / 3.0) * 44, 160, 38), label, "rebind", {"action": action})
	button(Rect2(x, h - 120, 240, 46), "CLOSE", "settings", {}, "", true, true)

func draw_tooltip(w: float, h: float) -> void:
	for b in buttons:
		if b.rect.has_point(mouse) and b.payload.has("tooltip"):
			var text: String = b.payload.tooltip
			var width = minf(w-40, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x+30)
			var x = clampf(mouse.x-width/2, 20, w-width-20)
			panel(Rect2(x, h-256, width, 42), Color("132c34"))
			label_at(text, Vector2(x+15, h-229), 14)

func mission_directive() -> String:
	if not game.mission or not game.mission_definition:
		return "Destroy the rival Core"
	for item in game.mission_definition.objectives:
		if not game.mission.completed.get(item.get("id", ""), false):
			var progress = game.mission.progress_for(item)
			var target = float(item.get("required", 1.0))
			var suffix = ""
			if item.get("kind", "") in ["survive", "gather"]:
				suffix = "  " + str(int(progress)) + " / " + str(int(target))
			return str(item.get("title", "Await orders")) + suffix
	return "All objectives complete"

func is_world(p: Vector2) -> bool:
	return game.mode == "playing" and not manual and p.y > 76 and p.y < size.y-202

func handle_click(p: Vector2, right: bool = false) -> bool:
	if settings_open and not right:
		for b in buttons:
			if b.rect.has_point(p) and b.enabled:
				game.ui_action(b.action, b.payload)
				return true
		return true
	if not manual and game.mode == "playing" and map_rect.has_point(p):
		var target = (p-map_rect.position)/map_rect.size*DASimulation.SIZE
		if right:
			game.issue("attack_move" if game.attack_mode else "move", {"pos": target})
			game.attack_mode = false
		else:
			game.field.focus = target
			game.field.update_camera()
		return true
	if not right:
		for b in buttons:
			if b.rect.has_point(p):
				if b.enabled:
					game.ui_action(b.action, b.payload)
				else:
					toast("This action is not yet available.")
				return true
	return not is_world(p)

static func time_text(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds)/60, int(seconds)%60]
