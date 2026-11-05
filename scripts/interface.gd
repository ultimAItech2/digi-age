class_name DAInterface
extends Control
## Immediate-mode rendering from a shared, viewport-coordinate layout model.
const BG = Color("0b1016")
const PANEL = Color("101820")
const BUTTON = Color("16222e")
const BUTTON_DISABLED = Color("0e151c")
const BUTTON_PRIMARY = Color("164055")
const BUTTON_HOVER = Color("1f3446")
const BUTTON_PRESSED = Color("12222f")
const LINE = Color("8b98a5")
const LINE_SOFT = Color(1, 1, 1, .22)
const TEXT = Color("f2f6fa")
const MUTED = Color("a9b7c6")
const ACCENT = Color("4fc3ff")
const GOLD = Color("f0c060")
const ERROR = Color("ff8a80")
const GREEN = Color("4ade80")
const VIOLET = Color("c9a8ff")
const PANEL_ALPHA = .82
const TOP_H = 48.0
const EDGE = 16.0
const MAP_PAD = 12.0
const PANEL_H = 150.0
const TITLE = "AGE OF AI"
const ICONS = ["metal","energy","data","population","tech","units","build","objectives","menu","home","speed","help","settings","sound","attack","stop","rally","age","weapons","check","lock","unit","building"]
const ROLES = {"core":"Town Center","generator":"Power Structure","depot":"Resource Drop-off","data_center":"Compute Structure","fabricator":"Production Structure","tower":"Defensive Structure","worker":"Utility Unit","scout":"Reconnaissance Unit","sentinel":"Combat Unit","disruptor":"Combat Unit","walker":"Siege Unit","metal":"Salvage Deposit","data":"Data Deposit"}
var game: Node3D
var font: Font = ThemeDB.fallback_font
var title_font: Font = ThemeDB.fallback_font
var buttons: Array = []
var focus_controls: Array = []
var operations: Array = []
var text_bounds: Array = []
var blocked_regions: Array[Rect2] = []
var reserved_regions: Dictionary = {}
var map_rect = Rect2()
var world_rect = Rect2()
var panel_rect = Rect2()
var message = ""
var message_left = 0.0
var severity = "info"
var notifications: Array = []
var manual = false
var settings_open = false
var objectives_open = false
var rebind_action = ""
var confirmation: Dictionary = {}
var subtitles_enabled = true
var subtitle_speaker = ""
var subtitle_text = ""
var subtitle_left = 0.0
var mouse = Vector2.ZERO
var hovered = ""
var focused = ""
var pressed = ""
var modal_stack: Array = []
var scroll_offset = 0.0
var scroll_max = 0.0
var scroll_rect = Rect2()
var map_image: Image
var map_scaled: Image
var map_texture: ImageTexture
var icon_cache: Dictionary = {}
var portrait_cache: Dictionary = {}
var ui_scale = 1.0
var layout_elapsed = 0.0
var layout_signature = ""
var layout_usec = 0
var style_cache: Dictionary = {}
var wrap_cache: Dictionary = {}
var clip = Rect2()
var w = 0.0
var h = 0.0
var left = 0.0
var span = 0.0
var bottom = 0.0
var block_right = 0.0
var tier = "A"
var text_control = ""

func setup(controller: Node3D) -> void:
	game = controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/fonts/Rajdhani-SemiBold.ttf"):
		font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	title_font = load_title_font()
	map_image = Image.create(DASimulation.SIZE, DASimulation.SIZE, false, Image.FORMAT_RGBA8)
	map_scaled = Image.create(DASimulation.SIZE*3, DASimulation.SIZE*3, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_scaled)
	refresh_map()
	prepare_layout(true)

func load_title_font() -> Font:
	# Cinzel ships as a raw TTF (importer="keep") so it loads without the editor import step.
	var path = "res://assets/fonts/Cinzel.ttf"
	if not FileAccess.file_exists(path): return font
	var file = FontFile.new()
	if file.load_dynamic_font(path) != OK: return font
	var variation = FontVariation.new()
	variation.base_font = file
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 600}
	variation.set_spacing(TextServer.SPACING_GLYPH, 4)
	return variation

func _process(dt: float) -> void:
	mouse = get_viewport().get_mouse_position()
	message_left = maxf(0, message_left-dt)
	subtitle_left = maxf(0, subtitle_left-dt)
	if message_left <= 0 and not notifications.is_empty():
		var next: Dictionary = notifications.pop_front()
		message = next.text
		severity = next.severity
		message_left = 7.0 if severity == "error" else 5.0
	layout_elapsed += dt
	prepare_layout()
	queue_redraw()

func apply_scale(value: float) -> void:
	ui_scale = clampf(value, 1.0, 1.25)
	scale = Vector2.ONE
	layout_signature = ""

func show_subtitle(speaker: String, text: String, duration: float = 0.0) -> void:
	subtitle_speaker = speaker
	subtitle_text = text
	subtitle_left = duration if duration > 0 else maxf(3.5, text.length()*0.065)
	layout_signature = ""

func toast(value: String, level: String = "info") -> void:
	if level == "error" or message_left <= 0:
		message = value
		severity = level
		message_left = 7.0 if level == "error" else 5.0
	elif value != message:
		if notifications.size() >= 4: notifications.pop_front()
		notifications.append({"text": value, "severity": level})
	layout_signature = ""

func modal_active() -> bool:
	return manual or settings_open or not confirmation.is_empty() or game.mode != "playing"

func open_overlay(kind: String) -> void:
	modal_stack.append({"manual": manual, "settings": settings_open, "focus": focused, "scroll": scroll_offset})
	manual = kind == "manual"
	settings_open = kind == "settings"
	focused = ""
	scroll_offset = 0
	cancel_pointer()
	prepare_layout(true)

func close_overlay() -> void:
	if not confirmation.is_empty():
		focused = confirmation.get("focus", "")
		confirmation.clear()
	elif not modal_stack.is_empty():
		var previous: Dictionary = modal_stack.pop_back()
		manual = previous.manual
		settings_open = previous.settings
		focused = previous.focus
		scroll_offset = previous.scroll
	else:
		manual = false
		settings_open = false
	rebind_action = ""
	cancel_pointer()
	prepare_layout(true)

func clear_overlays() -> void:
	manual = false
	settings_open = false
	confirmation.clear()
	modal_stack.clear()
	rebind_action = ""
	scroll_offset = 0
	focused = ""
	cancel_pointer()

func confirm_action(action: String) -> void:
	confirmation = {"action": action, "focus": focused}
	focused = ""
	cancel_pointer()
	prepare_layout(true)

func cancel_pointer() -> void:
	pressed = ""
	game.dragging = false
	game.middle_drag = false

func to_view(rect: Rect2) -> Rect2:
	return Rect2(rect.position*ui_scale, rect.size*ui_scale)

func style(color: Color, border: Color, radius: int = 5) -> StyleBoxFlat:
	var key = str(color)+str(border)+str(radius)
	if not style_cache.has(key):
		var value = StyleBoxFlat.new()
		value.bg_color = color
		value.border_color = border
		value.set_border_width_all(1)
		value.set_corner_radius_all(radius)
		style_cache[key] = value
	return style_cache[key]

func panel(rect: Rect2, color: Color = PANEL, border: bool = true, border_color: Color = LINE) -> void:
	var actual = to_view(rect)
	if clip.has_area(): actual = actual.intersection(clip)
	if actual.has_area(): operations.append({"type":"panel", "rect":actual, "color":color, "border":border_color if border else color})

func gradient(rect: Rect2, top: Color, base: Color) -> void:
	operations.append({"type":"gradient", "rect":to_view(rect), "top":top, "bottom":base})

func line(from: Vector2, to: Vector2, color: Color = LINE_SOFT, width: float = 1.0) -> void:
	operations.append({"type":"line", "from":from*ui_scale, "to":to*ui_scale, "color":color, "width":width*ui_scale})

func outline(rect: Rect2, color: Color = ACCENT, width: float = 2.0) -> void:
	operations.append({"type":"outline", "rect":to_view(rect), "color":color, "width":width*ui_scale})

func bar(rect: Rect2, fraction: float, color: Color) -> void:
	operations.append({"type":"bar", "rect":to_view(rect), "fraction":clampf(fraction,0,1), "color":color})

func icon(name: String, rect: Rect2, color: Color = TEXT) -> void:
	var actual = to_view(rect)
	if clip.has_area() and not clip.encloses(actual): return
	operations.append({"type":"icon", "rect":actual, "name":name, "color":color})

func thumb(kind: String, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	# Rendered portrait when available, otherwise an icon glyph for the category.
	var texture = portrait(kind)
	if texture:
		operations.append({"type":"texture", "rect":to_view(rect), "texture":texture, "modulate":modulate})
		return
	var glyph = kind if ICONS.has(kind) else ("building" if game.sim.catalog.buildings.has(kind) else "unit")
	var inset = rect.size.x*.2
	icon(glyph, Rect2(rect.position+Vector2(inset,inset), rect.size-Vector2(2*inset,2*inset)), Color(MUTED.r,MUTED.g,MUTED.b,modulate.a*.9))

func icon_texture(name: String, px: int) -> Texture2D:
	var key = name+":"+str(px)
	if icon_cache.has(key): return icon_cache[key]
	var texture = null
	var path = "res://assets/ui/icons/%s.svg" % name
	if FileAccess.file_exists(path):
		var image = Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path), maxf(1,px)/24.0) == OK:
			texture = ImageTexture.create_from_image(image)
	icon_cache[key] = texture
	return texture

func portrait(kind: String) -> Texture2D:
	if portrait_cache.has(kind): return portrait_cache[kind]
	# Kinds drawn as sprite cards use the sprite itself, so the panel matches the field.
	var texture = DASprites.portrait(kind)
	if texture:
		portrait_cache[kind] = texture
		return texture
	var path = "res://assets/ui/portraits/%s.png" % DAModels.BLENDER_ASSETS.get(kind, kind)
	if FileAccess.file_exists(path):
		var image = Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			if image.get_width() > 128: image.resize(128,128,Image.INTERPOLATE_LANCZOS)
			texture = ImageTexture.create_from_image(image)
	portrait_cache[kind] = texture
	return texture

static func thousands(value: float) -> String:
	var digits = str(absi(int(value)))
	var out = ""
	for i in digits.length():
		if i > 0 and (digits.length()-i) % 3 == 0: out += ","
		out += digits[i]
	return ("-" if value < 0 else "")+out

static func rate_text(value: float) -> String:
	return ("+" if value >= 0 else "")+thousands(value)+"/min"

func wrapped(value: String, width: float, px: int) -> Array:
	var key = value + "|" + str(width) + "|" + str(px)
	if wrap_cache.has(key): return wrap_cache[key]
	var lines: Array = []
	for paragraph in value.split("\n"):
		var line_text = ""
		for word in paragraph.split(" "):
			var trial = word if line_text == "" else line_text + " " + word
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT,-1,px).x <= width:
				line_text = trial
			else:
				if line_text != "": lines.append(line_text)
				line_text = ""
				for character in word:
					if font.get_string_size(line_text+character,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x > width and line_text != "":
						lines.append(line_text)
						line_text = ""
					line_text += character
		lines.append(line_text)
	if wrap_cache.size() > 2048: wrap_cache.clear()
	wrap_cache[key] = lines
	return lines

func text_height(value: String, width: float, px: int = 16) -> float:
	var font_size = roundi(px*ui_scale)
	var step = ceilf(font.get_height(font_size)+2*ui_scale)
	return wrapped(value,width*ui_scale,font_size).size()*step/ui_scale+.1

func text(value: String, rect: Rect2, px: int = 16, color: Color = TEXT) -> void:
	var actual = to_view(rect)
	var font_size = roundi(px*ui_scale)
	var step = ceilf(font.get_height(font_size)+2*ui_scale)
	var lines = wrapped(value, actual.size.x, font_size).duplicate()
	var capacity = maxi(1, floori(actual.size.y/step))
	var truncated = lines.size() > capacity
	if truncated:
		lines.resize(capacity)
		var last: String = lines[-1]
		while last.length() > 0 and font.get_string_size(last+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > actual.size.x:
			last = last.left(-1)
		lines[-1] = last + "…"
	for i in lines.size():
		var bounds = Rect2(actual.position+Vector2(0,i*step),Vector2(font.get_string_size(lines[i],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x,step))
		if clip.has_area() and not clip.encloses(bounds): continue
		var entry = {"type":"text", "rect":bounds, "text":lines[i], "size":font_size, "color":color, "clip":clip, "source":value if truncated else "", "control":text_control}
		operations.append(entry)
		text_bounds.append(entry)

func fitted_text(value: String, rect: Rect2, px: int, color: Color = TEXT) -> void:
	# Single line that shrinks, then compacts large numbers, rather than abbreviating with an ellipsis.
	var line_text = value
	var size = px
	while size > 11 and font.get_string_size(line_text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(size*ui_scale)).x > rect.size.x*ui_scale:
		size -= 1
	if font.get_string_size(line_text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(size*ui_scale)).x > rect.size.x*ui_scale:
		line_text = compact(value)
		size = px
		while size > 11 and font.get_string_size(line_text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(size*ui_scale)).x > rect.size.x*ui_scale:
			size -= 1
	text(line_text,Rect2(rect.position+Vector2(0,(px-size)*.5),rect.size),size,color)

static func compact(value: String) -> String:
	# "99,999,999" -> "100.0M"; keeps any prefix/suffix such as "+" or "/min".
	var digits = ""
	var prefix = ""
	var suffix = ""
	for i in value.length():
		var c = value[i]
		if c in "0123456789,":
			if suffix == "": digits += c
			else: suffix += c
		elif digits == "": prefix += c
		else: suffix += c
	var number = float(digits.replace(",",""))
	var short = digits
	if number >= 1000000: short = "%.1fM" % (number/1000000.0)
	elif number >= 10000: short = "%.1fK" % (number/1000.0)
	return prefix+short+suffix

func centered_text(value: String, rect: Rect2, px: int = 14, color: Color = TEXT) -> void:
	# Single line, horizontally centred and truncated to the rect.
	var font_size = roundi(px*ui_scale)
	var line_text = value
	while line_text.length() > 1 and font.get_string_size(line_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > rect.size.x*ui_scale:
		line_text = line_text.left(-1)
	var width = font.get_string_size(line_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/ui_scale
	text(line_text,Rect2(rect.position+Vector2(maxf(0,(rect.size.x-width)/2),0),Vector2(rect.size.x,rect.size.y)),px,color)

func title_text(value: String, x: float, y: float, px: int, color: Color = TEXT) -> float:
	var font_size = roundi(px*ui_scale)
	var size = title_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var bounds = Rect2(Vector2(x,y)*ui_scale,Vector2(size.x,ceilf(title_font.get_height(font_size))))
	var entry = {"type":"text", "rect":bounds, "text":value, "size":font_size, "color":color, "clip":clip, "source":"", "control":text_control, "font":title_font}
	operations.append(entry)
	text_bounds.append(entry)
	return size.x/ui_scale

func title_width(value: String, px: int) -> float:
	return title_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(px*ui_scale)).x/ui_scale

static func control_id(action: String, payload: Dictionary) -> String:
	return action + ":" + str(payload.get("kind",payload.get("action",payload.get("key",payload.get("id",payload.get("category","")))))) + ":" + str(payload.get("delta",""))

func register(rect: Rect2, title: String, action: String, payload: Dictionary, enabled: bool, primary: bool) -> Dictionary:
	var actual = to_view(rect)
	var b = {"id":control_id(action,payload),"rect":actual,"action":action,"payload":payload,"enabled":enabled,"primary":primary,"title":title,"clip":clip}
	focus_controls.append(b)
	if clip.has_area() and not clip.encloses(actual): return {}
	buttons.append(b)
	operations.append({"type":"button","button":b})
	return b

func button(rect: Rect2, title: String, action: String, payload: Dictionary = {}, subtitle: String = "", enabled: bool = true, primary: bool = false) -> void:
	var b = register(rect,title,action,payload,enabled,primary)
	if b.is_empty(): return
	text_control = b.id
	text(title,Rect2(rect.position+Vector2(10,7),Vector2(rect.size.x-20,rect.size.y-14 if subtitle == "" else 27)),16,TEXT if enabled else MUTED)
	if subtitle != "":
		text(subtitle,Rect2(rect.position+Vector2(10,35),Vector2(rect.size.x-20,rect.size.y-40)),14,MUTED)
	text_control = ""

func icon_button(rect: Rect2, glyph: String, title: String, action: String, payload: Dictionary = {}, enabled: bool = true, primary: bool = false, badge: String = "") -> void:
	var p = payload.duplicate()
	if not p.has("tooltip"): p.tooltip = title
	var b = register(rect,title,action,p,enabled,primary)
	if b.is_empty(): return
	var inset = rect.size.x*.24
	icon(glyph,Rect2(rect.position+Vector2(inset,inset),rect.size-Vector2(2*inset,2*inset)),TEXT if enabled else MUTED)
	if badge != "":
		text_control = b.id
		centered_text(badge,Rect2(rect.position.x+rect.size.x*.4,rect.end.y-15,rect.size.x*.6-2,14),11,ACCENT)
		text_control = ""

func nav_button(rect: Rect2, glyph: String, title: String, action: String, payload: Dictionary = {}) -> void:
	var b = register(rect,title,action,payload,true,false)
	if b.is_empty(): return
	icon(glyph,Rect2(rect.position+Vector2(10,(rect.size.y-18)/2),Vector2(18,18)),ACCENT)
	text_control = b.id
	text(title,Rect2(rect.position+Vector2(34,(rect.size.y-22)/2),Vector2(rect.size.x-40,22)),14)
	text_control = ""

func slot_button(rect: Rect2, kind: String, title: String, action: String, payload: Dictionary, caption: String, enabled: bool = true) -> void:
	var p = payload.duplicate()
	if not p.has("tooltip"): p.tooltip = title
	var b = register(rect,title,action,p,enabled,false)
	if b.is_empty(): return
	thumb(kind,Rect2(rect.position+Vector2(4,4),Vector2(rect.size.x-8,rect.size.x-8)),Color.WHITE if enabled else Color(1,1,1,.4))
	if not enabled: icon("lock",Rect2(rect.end.x-18,rect.position.y+4,14,14),GOLD)
	text_control = b.id
	centered_text(caption,Rect2(rect.position.x,rect.end.y-17,rect.size.x,15),12,ACCENT if caption.begins_with("×") else (MUTED if enabled else Color(MUTED.r,MUTED.g,MUTED.b,.6)))
	text_control = ""

func prepare_layout(force: bool = false) -> void:
	if not game or not game.sim: return
	if size.x < 1 or size.y < 1: return
	var signature = str([size,ui_scale,game.mode,manual,settings_open,confirmation,rebind_action,scroll_offset,game.selected,game.build_kind,game.attack_mode,game.rally_mode,objectives_open,game.speed])
	if not force and signature == layout_signature and layout_elapsed < .1: return
	var started = Time.get_ticks_usec()
	layout_signature = signature
	layout_elapsed = 0
	buttons.clear()
	focus_controls.clear()
	operations.clear()
	text_bounds.clear()
	blocked_regions.clear()
	reserved_regions.clear()
	clip = Rect2()
	scroll_rect = Rect2()
	scroll_max = 0
	w = size.x/ui_scale
	h = size.y/ui_scale
	span = minf(w,1920)
	left = (w-span)/2
	bottom = h-EDGE-PANEL_H
	block_right = left+EDGE
	world_rect = to_view(Rect2(0,TOP_H,w,h-TOP_H))
	if game.mode == "menu": layout_menu()
	else: layout_hud()
	if manual or settings_open or not confirmation.is_empty() or game.mode in ["paused", "result"]:
		buttons.clear()
		focus_controls.clear()
		operations.clear()
		text_bounds.clear()
		if not confirmation.is_empty(): layout_confirmation()
		elif settings_open: layout_settings()
		elif manual: layout_manual()
		elif game.mode == "paused": layout_pause()
		elif game.mode == "result": layout_result()
	clip = Rect2()
	if message_left > 0: layout_notification()
	if not modal_active() or (game.mode == "menu" and not manual and not settings_open and confirmation.is_empty()): layout_tooltip()
	layout_usec = Time.get_ticks_usec()-started

func layout_menu() -> void:
	panel(Rect2(0,0,w,h),Color(BG.r,BG.g,BG.b,.88),false)
	var x = left+32
	var column = (span-96)/2
	text("D / A  ·  MACHINE CIVILIZATIONS",Rect2(x,30,column,28),16,ACCENT)
	text("THE WORLD WENT QUIET.",Rect2(x,95,column,32),16,GOLD)
	text("DIGITAL\nAGE",Rect2(x,139,column,160),58,TEXT)
	text("Harvest. Evolve. Command the next civilization.",Rect2(x,305,column,64),18,MUTED)
	if message_left <= 0: text(game.mission_catalog.get_definition(game.pending_mission_id).briefing,Rect2(x,380,column, maxf(30,h-530)),16,TEXT)
	button(Rect2(x,h-138,column,52),"LAUNCH CAMPAIGN  →","start",{},"",true,true)
	var bw = (column-16)/3
	button(Rect2(x,h-74,bw,42),"MANUAL","help")
	button(Rect2(x+bw+8,h-74,bw,42),"SETTINGS","settings")
	button(Rect2(x+2*(bw+8),h-74,bw,42),"QUIT","quit")
	var rx = x+column+32
	panel(Rect2(rx,28,column,h-60),Color(PANEL.r,PANEL.g,PANEL.b,PANEL_ALPHA))
	text("CAMPAIGN OPERATIONS",Rect2(rx+20,46,column-40,30),20,ACCENT)
	var definitions = game.mission_catalog.all_definitions()
	var y = 96.0
	for definition in definitions:
		var unlocked: bool = game.campaign.unlocked_missions.has(definition.mission_id)
		var complete: bool = game.campaign.completed_missions.has(definition.mission_id)
		var marker = "DONE" if complete else ("OPEN" if unlocked else "LOCKED")
		button(Rect2(rx+16,y,column-32,44),marker+" · "+definition.title,"select_mission",{"id":definition.mission_id,"title":definition.title,"tooltip":definition.briefing,"reason":"Complete the preceding operation to unlock this mission."},"",unlocked,definition.mission_id == game.pending_mission_id)
		y += 52

func layout_hud() -> void:
	layout_top_bar()
	layout_minimap_block()
	layout_bottom_panel()
	layout_objectives()
	layout_strips()

func layout_top_bar() -> void:
	gradient(Rect2(0,0,w,TOP_H),Color(BG.r,BG.g,BG.b,.92),Color(BG.r,BG.g,BG.b,.55))
	line(Vector2(0,TOP_H),Vector2(w,TOP_H),LINE_SOFT,1)
	blocked_regions.append(to_view(Rect2(0,0,w,TOP_H)))
	var x = left+EDGE
	var group_w = 150.0 if span >= 1500 else 118.0
	var resources: Vector3 = game.sim.resources[0]
	var income: Vector3 = game.sim.income_per_minute(0)
	var groups = [
		["metal",thousands(resources.x),rate_text(income.x),GOLD],
		["energy",thousands(resources.y),rate_text(income.y),ACCENT],
		["data",thousands(resources.z),rate_text(income.z),VIOLET],
		["population","%d / %d" % [game.sim.population(0),game.sim.capacity(0)],"",TEXT]]
	for i in groups.size():
		var gx = x+i*group_w
		icon(groups[i][0],Rect2(gx,13,22,22),groups[i][3])
		fitted_text(groups[i][1],Rect2(gx+30,2,group_w-34,27),20,TEXT)
		if groups[i][2] != "": fitted_text(groups[i][2],Rect2(gx+30,27,group_w-34,18),13,MUTED)
	var resources_end = x+groups.size()*group_w
	var nav_w = 4*112+3*6+6+38
	var nav_x = left+span-EDGE-nav_w
	var ny = (TOP_H-38)/2
	var entries = [["tech","TECH","tech"],["units","UNITS","army"],["build","BUILD","workers"],["objectives","OBJECTIVES","objectives"]]
	for i in entries.size():
		nav_button(Rect2(nav_x+i*118,ny,112,38),entries[i][0],entries[i][1],entries[i][2])
	icon_button(Rect2(nav_x+4*118,ny,38,38),"menu","Pause menu","pause")
	var tw = title_width(TITLE,20)
	var tx = left+(span-tw)/2
	if tx >= resources_end+16 and tx+tw <= nav_x-16:
		title_text(TITLE,tx,(TOP_H-24)/2,20,TEXT)
	elif span-resources_end-nav_w > 0 and false: pass
	text(game.sim.catalog.ages[game.sim.ages[0]].capitalize()+" · "+time_text(game.sim.elapsed)+(" · "+str(game.speed)+"×" if game.speed != 1 else ""),Rect2(nav_x-170,ny+9,160,20),12,MUTED) if nav_x-170 >= resources_end+8 and (tx < resources_end+16 or tx+tw > nav_x-16) else null

func layout_minimap_block() -> void:
	var m = clampf(minf(270,h*.25),150,270)
	var frame = Rect2(left+EDGE,h-EDGE-m-2*MAP_PAD,m+2*MAP_PAD,m+2*MAP_PAD)
	panel(frame,Color(PANEL.r,PANEL.g,PANEL.b,PANEL_ALPHA))
	blocked_regions.append(to_view(frame))
	map_rect = to_view(Rect2(frame.position+Vector2(MAP_PAD,MAP_PAD),Vector2(m,m)))
	operations.append({"type":"map","rect":map_rect})
	var s = 44.0 if m >= 240 else 38.0
	var cx = frame.end.x+8
	var entries = [["home","Focus Core","home",""],["speed","Game speed","speed","×"+str(game.speed)],["help","Field manual","help",""],["settings","Settings","settings",""],["sound","Sound on" if game.audio.enabled else "Sound off","sound",""]]
	for i in entries.size():
		var cy = h-EDGE-(entries.size()-i)*s-(entries.size()-1-i)*6
		icon_button(Rect2(cx,cy,s,s),entries[i][0],entries[i][1],entries[i][2],{},true,false,entries[i][3])
	blocked_regions.append(to_view(Rect2(cx,h-EDGE-entries.size()*s-(entries.size()-1)*6,s,entries.size()*s+(entries.size()-1)*6)))
	block_right = cx+s

func layout_bottom_panel() -> void:
	var right_edge = left+span-EDGE
	var pw = minf(1120,right_edge-(block_right+12))
	var px = maxf(left+(span-pw)/2,block_right+12)
	panel_rect = Rect2(px,bottom,pw,PANEL_H)
	tier = "A" if pw >= 960 else ("B" if pw >= 800 else "C")
	panel(panel_rect,Color(PANEL.r,PANEL.g,PANEL.b,PANEL_ALPHA))
	blocked_regions.append(to_view(panel_rect))
	layout_selection(panel_rect)

func layout_objectives() -> void:
	if not objectives_open: return
	var items: Array = game.mission_definition.objectives if game.mission_definition else []
	var ow = minf(360,span*.4)
	var oh = 44+26*maxi(1,items.size())
	var r = Rect2(left+EDGE,TOP_H+12,ow,oh)
	panel(r,Color(PANEL.r,PANEL.g,PANEL.b,PANEL_ALPHA))
	blocked_regions.append(to_view(r))
	reserved_regions.objectives = to_view(r)
	text((game.mission_definition.title if game.mission_definition else "Skirmish").to_upper(),Rect2(r.position+Vector2(14,9),Vector2(ow-28,24)),15,ACCENT)
	if items.is_empty():
		text("Destroy the rival Core",Rect2(r.position+Vector2(36,40),Vector2(ow-50,24)),14)
		icon("objectives",Rect2(r.position+Vector2(14,43),Vector2(16,16)),MUTED)
	for i in items.size():
		var item: Dictionary = items[i]
		var complete: bool = game.mission.completed.get(item.get("id",""),false) if game.mission else false
		var suffix = ""
		if not complete and item.get("kind","") in ["survive","gather"] and game.mission:
			suffix = " · %s / %s" % [thousands(game.mission.progress_for(item)),thousands(item.get("required",1))]
		if item.get("optional",false): suffix += " (optional)"
		icon("check" if complete else "objectives",Rect2(r.position+Vector2(14,43+i*26),Vector2(16,16)),GREEN if complete else MUTED)
		text(str(item.get("title","Await orders"))+suffix,Rect2(r.position+Vector2(36,40+i*26),Vector2(ow-50,24)),14,MUTED if complete else TEXT)

func layout_strips() -> void:
	var strip_left = block_right+12
	var strip_w = minf(760,left+span-EDGE-strip_left)
	var strip_x = strip_left+(left+span-EDGE-strip_left-strip_w)/2
	var notice_rect = Rect2(strip_x,bottom-56,strip_w,44)
	reserved_regions.notification = to_view(notice_rect)
	if subtitles_enabled and subtitle_left > 0 and subtitle_text != "":
		var sh = minf(150,40+text_height(subtitle_text,strip_w-28))
		var sr = Rect2(strip_x,bottom-70-sh,strip_w,sh)
		reserved_regions.subtitle = to_view(sr)
		panel(sr,Color(BG.r,BG.g,BG.b,.92))
		text(subtitle_speaker.to_upper(),Rect2(sr.position+Vector2(14,8),Vector2(strip_w-28,24)),14,GOLD)
		text(subtitle_text,Rect2(sr.position+Vector2(14,34),Vector2(strip_w-28,sh-38)),16)
	if game.build_kind != "" or game.attack_mode or game.rally_mode:
		var value = "ATTACK-MOVE · Click a destination. Right-click or Esc to cancel."
		var color = ACCENT
		if game.rally_mode: value = "RALLY POINT · Click where new units should gather. Right-click or Esc to cancel."
		if game.build_kind != "":
			var error: String = game.sim.placement_error(0,game.build_kind,game.field.ground_at(mouse))
			value = "PLACE "+game.sim.catalog.buildings[game.build_kind].name+" · Click to build. Esc to cancel."
			if error != "":
				value = "CANNOT BUILD · "+error
				color = GOLD
		panel(notice_rect,Color(BG.r,BG.g,BG.b,.92))
		text(value,Rect2(notice_rect.position+Vector2(12,4),notice_rect.size-Vector2(24,8)),14,color)
		blocked_regions.append(to_view(notice_rect))

func selection_status(e: Dictionary, d: Dictionary) -> String:
	if e.owner < 0: return "Send Workers to harvest this deposit."
	if e.owner != 0: return "Hostile"
	if not e.complete: return "Constructing %d%%" % int(100*(1-e.build_left/d.time))
	if e.research != "":
		var label = "Advancing to "+game.sim.catalog.ages[mini(2,game.sim.ages[0]+1)].capitalize() if e.research == "age" else "Weapons research"
		return label+" · "+str(ceili(e.research_left))+"s"
	if not e.queue.is_empty(): return "Producing "+game.sim.catalog.units[e.queue[0].kind].name+" · "+str(ceili(e.queue[0].left))+"s · Queue "+str(e.queue.size())+"/5"
	return "Operational" if e.building else e.order.capitalize().replace("_"," ")

func active_job(e: Dictionary, d: Dictionary) -> Dictionary:
	if e.owner != 0: return {}
	if not e.complete: return {"kind":e.kind,"progress":1-e.build_left/maxf(.1,d.time),"name":"Constructing","left":e.build_left}
	if e.research != "":
		var total = (game.sim.catalog.age_times[mini(1,game.sim.ages[0])] if e.research == "age" else 30.0)*game.sim.faction_modifier(0,"research_speed",1.0)
		return {"kind":e.research,"progress":1-e.research_left/maxf(.1,total),"name":("Age upgrade" if e.research == "age" else "Weapons "+str(game.sim.upgrades[0]+1)),"left":e.research_left}
	if not e.queue.is_empty():
		var kind: String = e.queue[0].kind
		return {"kind":kind,"progress":1-e.queue[0].left/maxf(.1,game.sim.catalog.units[kind].time),"name":game.sim.catalog.units[kind].name,"left":e.queue[0].left}
	return {}

func layout_selection(rect: Rect2) -> void:
	var pad = 14.0
	var x = rect.position.x+pad
	var y = rect.position.y+pad
	var inner_w = rect.size.x-2*pad
	var inner_h = rect.size.y-2*pad
	var selected: Array = game.selected.filter(func(id): return game.sim.entities.has(id) and game.sim.known(0,game.sim.entities[id]))
	if selected.is_empty():
		text("AWAITING YOUR COMMAND",Rect2(x,y,inner_w,30),22)
		text("Select Workers to gather resources and construct your base.",Rect2(x,y+34,inner_w,40),15,MUTED)
		button(Rect2(x,rect.end.y-pad-42,180,42),"SELECT WORKERS","workers",{"id":"panel"})
		button(Rect2(x+192,rect.end.y-pad-42,160,42),"FOCUS CORE","home",{"id":"panel"})
		return
	var e: Dictionary = game.sim.entities[selected[0]]
	var d: Dictionary = game.sim.catalog.definition(e.kind)
	var title: String = d.get("name","Salvage pile" if e.kind == "metal" else "Data archive")
	if selected.size() > 1: title = str(selected.size())+" units selected"
	var role: String = ROLES.get(e.kind,"Structure" if e.building else "Unit")
	if e.owner == 1: role = "Enemy "+role
	var portrait_w = 0.0 if tier == "C" else 92.0
	var info_w = 220.0 if tier == "A" else (120.0 if tier == "B" else 150.0)
	var ix = x+(portrait_w+14 if portrait_w > 0 else 0.0)
	var health = clampf(float(e.hp)/maxf(1,e.max_hp),0,1) if e.owner >= 0 else 1.0
	var health_text = "%s / %s" % [thousands(e.hp),thousands(e.max_hp)] if e.owner >= 0 else thousands(e.amount)+" remaining"
	var health_color = GREEN if health > .5 else (GOLD if health > .25 else ERROR)
	if e.owner < 0: health_color = GOLD if e.kind == "metal" else VIOLET
	if portrait_w > 0:
		var pr = Rect2(x,y,portrait_w,portrait_w)
		panel(pr,Color(BG.r,BG.g,BG.b,.55),true,LINE_SOFT)
		thumb(e.kind,pr.grow(-5))
		bar(Rect2(x,y+portrait_w+6,portrait_w,6),health,health_color)
		centered_text(health_text,Rect2(x,y+portrait_w+14,portrait_w,18),12,MUTED)
	fitted_text(title,Rect2(ix,y-3,info_w,30),22 if tier == "A" else 19)
	fitted_text(role,Rect2(ix,y+27,info_w,18),13,MUTED)
	var status = selection_status(e,d)
	if tier == "C":
		bar(Rect2(ix,y+50,info_w,6),health,health_color)
		text(health_text,Rect2(ix,y+58,info_w,16),12,MUTED)
		fitted_text(status,Rect2(ix,y+78,info_w,18),13,GOLD)
	elif tier == "B":
		fitted_text(status,Rect2(ix,y+50,info_w,18),13,GOLD)
	else:
		fitted_text(status,Rect2(ix,y+46,info_w,18),13,GOLD)
		var description = str(d.get("description","Select Workers and right-click this deposit to harvest it."))
		var available = inner_h-68
		for px in [14,13,12]:
			if text_height(description,info_w,px) <= available:
				text(description,Rect2(ix,y+68,info_w,available),px,MUTED)
				break
	var items: Array = []
	if e.owner == 0 and e.complete:
		if e.kind == "worker":
			for kind in ["generator","depot","data_center","fabricator","tower"]: items.append({"kind":kind,"action":"build","d":game.sim.catalog.buildings[kind]})
		elif e.kind == "core": items.append({"kind":"worker","action":"train","d":game.sim.catalog.units.worker})
		elif e.kind == "fabricator":
			for kind in ["scout","sentinel","disruptor","walker"]: items.append({"kind":kind,"action":"train","d":game.sim.catalog.units[kind]})
	var job_w = 80.0 if tier == "C" else 100.0
	var cmd_w = 86.0
	var slot = 72.0 if tier == "A" else 56.0
	var job_x = rect.end.x-pad-job_w
	var cmd_x = job_x-12-cmd_w
	var sx = ix+info_w+12
	var cols = maxi(0,floori((cmd_x-12-sx+8)/(slot+8)))
	var queued: Dictionary = {}
	for entry in e.get("queue",[]): queued[entry.kind] = queued.get(entry.kind,0)+1
	for i in mini(items.size(),cols):
		var item: Dictionary = items[i]
		var reason = availability(item,e)
		var payload = {"kind":item.kind,"tooltip":item.d.name+" · "+cost_text(item.d.cost)+"\n"+item.d.description,"reason":reason}
		var caption = ("×"+str(queued[item.kind])) if queued.has(item.kind) else thousands(item.d.cost.x)+" M"
		slot_button(Rect2(sx+i*(slot+8),y+(inner_h-slot-16)/2,slot,slot+16),item.kind,item.d.name,item.action,payload,caption,reason == "")
	var commands: Array = []
	if e.owner == 0 and not e.building:
		commands.append({"icon":"attack","title":game.settings.prompt("attack")+" · Attack-move","action":"attack_mode","primary":game.attack_mode})
		commands.append({"icon":"stop","title":game.settings.prompt("stop")+" · Stop","action":"stop"})
	elif e.owner == 0 and e.complete and e.kind in ["core","fabricator"]:
		if e.kind == "core":
			var age: int = game.sim.ages[0]
			var upgrade: int = game.sim.upgrades[0]
			if age < 2:
				var item = {"kind":"age","action":"research","d":{"name":game.sim.catalog.ages[age+1].capitalize(),"cost":game.sim.catalog.age_costs[age],"age":0,"description":"Advance to the next technological age."}}
				var reason = availability(item,e)
				commands.append({"icon":"age","title":"Advance to "+item.d.name,"action":"research","payload":{"kind":"age","tooltip":"Advance to "+item.d.name+" · "+cost_text(item.d.cost)+"\n"+item.d.description,"reason":reason},"enabled":reason == ""})
			else: commands.append({"icon":"age","title":"Final age reached","action":"research","payload":{"kind":"age","reason":"The Singularity is the final age."},"enabled":false})
			if upgrade < 2:
				var item = {"kind":"weapons","action":"research","d":{"name":"Weapons "+str(upgrade+1),"cost":game.sim.catalog.upgrade_costs[upgrade],"age":upgrade+1,"description":"Increase weapon damage by 20%."}}
				var reason = availability(item,e)
				commands.append({"icon":"weapons","title":item.d.name,"action":"research","payload":{"kind":"weapons","tooltip":item.d.name+" · "+cost_text(item.d.cost)+"\n"+item.d.description,"reason":reason},"enabled":reason == ""})
			else: commands.append({"icon":"weapons","title":"Weapons fully upgraded","action":"research","payload":{"kind":"weapons","reason":"Weapons are fully upgraded."},"enabled":false})
		commands.append({"icon":"rally","title":"Set rally point","action":"rally","primary":game.rally_mode})
	var cy = y+(inner_h-86)/2
	for i in 4:
		var cell = Rect2(cmd_x+(i%2)*46,cy+floori(i/2.0)*46,40,40)
		if i < commands.size():
			var c: Dictionary = commands[i]
			icon_button(cell,c.icon,c.title,c.action,c.get("payload",{}),c.get("enabled",true),c.get("primary",false))
		else: panel(cell,Color(0,0,0,0),true,LINE_SOFT)
	var jr = Rect2(job_x,y,job_w,inner_h)
	panel(jr,Color(BG.r,BG.g,BG.b,.5),true,LINE_SOFT)
	var job = active_job(e,d)
	var tw = 56.0 if tier == "C" else 64.0
	if not job.is_empty():
		thumb(job.kind,Rect2(job_x+(job_w-tw)/2,y+6,tw,tw))
		bar(Rect2(job_x+8,y+tw+14,job_w-16,6),job.progress,ACCENT)
		centered_text(job.name,Rect2(job_x+4,y+tw+24,job_w-8,18),12)
		centered_text(str(ceili(job.left))+"s",Rect2(job_x+4,y+tw+42,job_w-8,16),12,MUTED)
	else:
		icon("building" if e.building else "unit",Rect2(job_x+(job_w-36)/2,y+30,36,36),Color(MUTED.r,MUTED.g,MUTED.b,.35))
		centered_text("IDLE",Rect2(job_x+4,y+76,job_w-8,18),12,Color(MUTED.r,MUTED.g,MUTED.b,.7))

func availability(item: Dictionary, e: Dictionary) -> String:
	if game.sim.ages[0] < item.d.age: return "Requires "+game.sim.catalog.ages[item.d.age].capitalize()+" age."
	if item.action == "research" and e.research != "": return "Research is already underway."
	if item.action == "train":
		if e.queue.size() >= 5: return "Production queue is full."
		if game.sim.population(0,true) >= game.sim.capacity(0): return "Compute limit reached. Build a Data Center."
	if not game.sim.can_pay(0,item.d.cost): return "Insufficient resources. Cost: "+cost_text(item.d.cost)
	return ""

func cost_text(cost: Vector3) -> String:
	return "%d M · %d E" % [cost.x,cost.y]+(" · %d D" % cost.z if cost.z > 0 else "")

func modal_shell(title: String, width: float = 720) -> Rect2:
	panel(Rect2(0,0,w,h),Color("07121bf5"),false)
	var rect = Rect2((w-minf(width,w-48))/2,24,minf(width,w-48),h-112)
	panel(rect)
	text(title,Rect2(rect.position+Vector2(24,16),Vector2(rect.size.x-48,44)),26,ACCENT)
	return rect

func layout_pause() -> void:
	var rect = modal_shell("SIMULATION PAUSED",620)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var y = rect.position.y+82
	for entry in [["RESUME","resume"],["SPEED "+str(game.speed)+"×","speed"],["SAVE · "+game.settings.prompt("save"),"save"],["LOAD · "+game.settings.prompt("load"),"load"],["FIELD MANUAL","help"],["SETTINGS","settings"],["RESTART MISSION","restart"],["MAIN MENU","menu"]]:
		var i: int = ["resume","speed","save","load","help","settings","restart","menu"].find(entry[1])
		button(Rect2(x+(i%2)*(cw/2+4),y+floori(i/2.0)*70,cw/2-4,52),entry[0],entry[1],{},"",true,i==0)
	text("Esc resumes · Tab changes focus · Enter selects",Rect2(x,rect.end.y-78,cw,50),14,MUTED)

func layout_result() -> void:
	var rect = modal_shell("TRANSMISSION COMPLETE",720)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var won: bool = game.sim.winner == 0 or game.mission.mission_won
	text("VICTORY" if won else "CORE LOST",Rect2(x,rect.position.y+86,cw,72),48,ACCENT if won else ERROR)
	text(game.mission_definition.victory_text if won else game.mission_definition.defeat_text,Rect2(x,rect.position.y+176,cw,110),18)
	text("Time "+time_text(game.sim.elapsed)+" · Enemies destroyed "+str(game.sim.stats[0].kills)+"\nResources harvested "+str(int(game.sim.stats[0].gathered)),Rect2(x,rect.position.y+300,cw,72),16,MUTED)
	button(Rect2(x,rect.end.y-84,cw/2-6,52),"PLAY AGAIN","restart",{},"",true,true)
	button(Rect2(x+cw/2+6,rect.end.y-84,cw/2-6,52),"MAIN MENU","menu")

func begin_scroll(rect: Rect2, content_height: float) -> void:
	# Keep the scrollbar in a gutter, away from text and button borders.
	scroll_rect = to_view(Rect2(rect.position,rect.size+Vector2(12,0)))
	scroll_max = maxf(0,content_height-rect.size.y)
	scroll_offset = clampf(scroll_offset,0,scroll_max)
	clip = scroll_rect

func end_scroll() -> void:
	clip = Rect2()
	if scroll_max > 0:
		var r = Rect2(scroll_rect.position/ui_scale,scroll_rect.size/ui_scale)
		panel(Rect2(r.end.x-4,r.position.y,4,r.size.y),BG,false)
		var thumb = maxf(24,r.size.y*r.size.y/(r.size.y+scroll_max))
		panel(Rect2(r.end.x-4,r.position.y+(r.size.y-thumb)*scroll_offset/scroll_max,4,thumb),ACCENT,false)

func layout_settings() -> void:
	var rect = modal_shell("SETTINGS",760)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	text("Auto-save enabled. Scroll or ↑↓ for more. Esc cancels key capture.",Rect2(x,rect.position.y+62,cw,42),14,MUTED)
	begin_scroll(Rect2(x,rect.position.y+110,cw,rect.size.y-206),980)
	var y = rect.position.y+110-scroll_offset
	text("AUDIO",Rect2(x,y,cw,28),18,ACCENT)
	y += 36
	for entry in [["Master","master_volume"],["Music","music_volume"],["Effects","effects_volume"],["Voice","voice_volume"],["Interface","ui_volume"]]:
		text(entry[0]+" · "+str(roundi(game.settings.values[entry[1]]*100))+"%",Rect2(x,y+8,cw-160,30),16)
		button(Rect2(x+cw-150,y,66,40),"−","volume",{"key":entry[1],"delta":-.1})
		button(Rect2(x+cw-76,y,66,40),"+","volume",{"key":entry[1],"delta":.1})
		y += 50
	button(Rect2(x,y,200,42),"RESET AUDIO","reset_category",{"category":"audio"})
	y += 62
	text("DISPLAY & CAPTIONS",Rect2(x,y,cw,28),18,ACCENT)
	y += 38
	var options = [["Profile · "+str(game.settings.values.profile),"profile"],["UI scale · "+str(roundi(ui_scale*100))+"%","ui_scale"],["Subtitles · "+("On" if subtitles_enabled else "Off"),"subtitles"],["Reduced effects · "+("On" if game.settings.values.reduced_effects else "Off"),"effects"]]
	for i in options.size():
		button(Rect2(x+(i%2)*(cw/2+4),y+floori(i/2.0)*54,cw/2-4,44),options[i][0],options[i][1])
	y += 112
	button(Rect2(x,y,220,42),"RESET DISPLAY","reset_category",{"category":"display"})
	y += 62
	text("KEYBOARD · Select a binding, then press a key",Rect2(x,y,cw,28),16,ACCENT)
	y += 38
	var actions = ["pause","manual","save","load","attack","stop","speed","events","home","fullscreen"]
	for i in actions.size():
		var action: String = actions[i]
		button(Rect2(x+(i%2)*(cw/2+4),y+floori(i/2.0)*52,cw/2-4,44),action.capitalize()+" · "+("Press key… (Esc cancels)" if rebind_action == action else game.settings.prompt(action)),"rebind",{"action":action},"",true,rebind_action==action)
	y += 270
	button(Rect2(x,y,220,42),"RESET BINDINGS","reset_category",{"category":"bindings"})
	end_scroll()
	button(Rect2(x,rect.end.y-68,cw/2-6,44),"CLOSE","settings",{},"",true,true)
	button(Rect2(x+cw/2+6,rect.end.y-68,cw/2-6,44),"RESET ALL","reset_all")

func layout_manual() -> void:
	var rect = modal_shell("FIELD MANUAL",850)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var sections = [
		["01 / ESTABLISH","Select Workers and right-click golden salvage for metal or violet archives for data. Workers carry 24 resources home. Build a Salvage Depot near distant deposits."],
		["02 / EXPAND","Generators supply energy. Data Centers add 20 compute, up to 100. Select a Worker and a building, then choose a clear explored site. Right-click or Esc cancels placement."],
		["03 / EVOLVE","Train Workers and research ages at your Core. Network unlocks Disruptors and Towers; Singularity unlocks Siege Walkers. Fabricators manufacture your army."],
		["04 / CONQUER","Sentinels counter Disruptors. Disruptors counter Walkers. Walkers destroy buildings. Scout first: enemies outside your vision cannot be targeted."],
		["05 / COMMAND","Click or drag to select; Shift adds units. Right-click moves, gathers, attacks, repairs, or sets a rally point. "+game.settings.prompt("attack")+": attack-move. "+game.settings.prompt("stop")+": stop. Ctrl+1–9 saves groups; 1–9 recalls them."],
		["06 / NAVIGATE","Arrows, screen edges, or middle drag pan. Q/E rotate; wheel zooms. Minimap left-click moves the camera; right-click issues orders. "+game.settings.prompt("pause")+": pause. "+game.settings.prompt("manual")+": manual. "+game.settings.prompt("fullscreen")+": fullscreen."]
	]
	var total = 0.0
	for section in sections:
		total += 54+text_height(section[1],cw)
	begin_scroll(Rect2(x,rect.position.y+78,cw,rect.size.y-166),total)
	var y = rect.position.y+78-scroll_offset
	for section in sections:
		text(section[0],Rect2(x,y,cw,28),18,GOLD)
		var th = text_height(section[1],cw)
		text(section[1],Rect2(x,y+34,cw,th),16)
		y += th+54
	end_scroll()
	button(Rect2(x,rect.end.y-66,cw,44),"RETURN","help_close",{},"",true,true)

func layout_confirmation() -> void:
	var rect = modal_shell("CONFIRM ACTION",660)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var action: String = confirmation.action
	text("Reset all preferences?" if action == "reset_all" else "Leave this mission state?",Rect2(x,rect.position.y+100,cw,70),24)
	var explanation = "Unsaved progress will be lost. You can save before continuing."
	if action == "reset_all": explanation = "Audio, display and keyboard settings will return to their defaults."
	elif action == "load": explanation = "Loading replaces unsaved progress. Your existing saved game will be kept."
	text(explanation,Rect2(x,rect.position.y+170,cw,62),18,MUTED)
	button(Rect2(x,rect.end.y-204,cw,48),"CANCEL","confirm_cancel",{},"",true,true)
	if action not in ["reset_all", "load"]:
		button(Rect2(x,rect.end.y-146,cw,48),"SAVE AND CONTINUE","confirm_save")
	button(Rect2(x,rect.end.y-88,cw,48),"RESET PREFERENCES" if action == "reset_all" else ("LOAD SAVED GAME" if action == "load" else "CONTINUE WITHOUT SAVING"),"confirm_proceed")

func layout_notification() -> void:
	# Above modals and below their headers; world notifications use a reserved strip.
	var r = Rect2((w-minf(800,w-64))/2,h-76,minf(800,w-64),66) if modal_active() else Rect2(reserved_regions.notification.position/ui_scale,reserved_regions.notification.size/ui_scale)
	if game.mode == "menu" and not manual and not settings_open and confirmation.is_empty():
		r = Rect2(left+32,380,(span-96)/2,maxf(40,minf(90,h-534)))
	if not modal_active() and (game.build_kind != "" or game.attack_mode or game.rally_mode):
		r.position.y -= 64
	if not modal_active() and reserved_regions.has("subtitle") and to_view(r).intersects(reserved_regions.subtitle):
		r.position.y = reserved_regions.subtitle.position.y/ui_scale-r.size.y-8
	panel(r,BG)
	text(("ERROR · " if severity=="error" else ("COMPLETE · " if severity=="success" else "NOTICE · "))+message,Rect2(r.position+Vector2(12,6),r.size-Vector2(24,12)),14,ERROR if severity=="error" else (ACCENT if severity=="success" else TEXT))
	reserved_regions.message = to_view(r)
	blocked_regions.append(to_view(r))

func layout_tooltip() -> void:
	var value = ""
	for b in buttons:
		if b.rect.has_point(mouse) or b.id == focused:
			value = str(b.payload.get("reason","")) if not b.enabled else ""
			var details = str(b.payload.get("tooltip",""))
			if details != "": value += ("\n" if value != "" else "")+details
			break
	if value == "":
		for entry in text_bounds:
			if entry.source != "" and entry.rect.has_point(mouse):
				value = entry.source
				break
	if value == "": return
	var tw = minf(380,span-48)
	var th = minf(230,text_height(value,tw-24,14)+20)
	var r = Rect2(left+span-EDGE-tw,TOP_H+12,tw,th)
	if game.mode == "menu":
		r = Rect2(left+32,140,(span-96)/2,minf(220,th+40))
	panel(r,Color(BG.r,BG.g,BG.b,.96))
	text(value,Rect2(r.position+Vector2(12,8),r.size-Vector2(24,16)),14)
	reserved_regions.tooltip = to_view(r)
	blocked_regions.append(to_view(r))

func _draw() -> void:
	if not game: return
	for op in operations:
		match op.type:
			"panel": draw_style_box(style(op.color,op.border),op.rect)
			"gradient":
				var r: Rect2 = op.rect
				draw_polygon(PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]),PackedColorArray([op.top,op.top,op.bottom,op.bottom]))
			"line": draw_line(op.from,op.to,op.color,op.width)
			"outline": draw_rect(op.rect,op.color,false,op.width)
			"bar":
				var r: Rect2 = op.rect
				draw_rect(r,Color(BG.r,BG.g,BG.b,.85))
				if op.fraction > 0: draw_rect(Rect2(r.position,Vector2(r.size.x*op.fraction,r.size.y)),op.color)
				draw_rect(r,LINE_SOFT,false,1)
			"texture": draw_texture_rect(op.texture,op.rect,false,op.modulate)
			"icon":
				var texture = icon_texture(op.name,roundi(op.rect.size.x))
				if texture: draw_texture_rect(texture,op.rect,false,op.color)
			"text": draw_string(op.get("font",font),op.rect.position+Vector2(0,op.get("font",font).get_ascent(op.size)),op.text,HORIZONTAL_ALIGNMENT_LEFT,-1,op.size,op.color)
			"button":
				var b: Dictionary = op.button
				var over: bool = b.rect.has_point(mouse)
				var color = BUTTON if b.enabled else BUTTON_DISABLED
				if b.primary: color = BUTTON_PRIMARY
				if over and b.enabled: color = BUTTON_HOVER
				if pressed == b.id and over: color = BUTTON_PRESSED
				draw_style_box(style(color,ACCENT if focused==b.id or b.primary else (LINE if b.enabled else LINE_SOFT)),b.rect)
				if focused==b.id: draw_rect(b.rect.grow(-3),ACCENT,false,2)
			"map": draw_minimap(op.rect)
	if not modal_active(): draw_world_overlay()

func refresh_map() -> void:
	if not game or not map_image: return
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var p = Vector2i(x,y)
			var color = Color("0a0e13")
			if game.sim.explored[0].has(p):
				color = Color("41563f") if game.sim.visible[0].has(p) else Color("26332c")
				if game.sim.obstacles.has(p): color = Color("6a6d5c")
			map_image.set_pixel(x,y,color)
	map_scaled.copy_from(map_image)
	map_scaled.resize(DASimulation.SIZE*3,DASimulation.SIZE*3,Image.INTERPOLATE_NEAREST)
	map_texture.update(map_scaled)

func draw_minimap(rect: Rect2) -> void:
	draw_texture_rect(map_texture,rect,false)
	for e in game.sim.entities.values():
		if not game.sim.known(0,e) or e.get("amount",1) <= 0: continue
		var p: Vector2 = rect.position+e.pos/DASimulation.SIZE*rect.size
		var color = game.sim.faction_color(e.owner) if e.owner >= 0 else (GOLD if e.kind=="metal" else VIOLET)
		if e.building: draw_rect(Rect2(p-Vector2(2,2)*ui_scale,Vector2(4,4)*ui_scale),color)
		else: draw_circle(p,1.6*ui_scale,color)
	var points = PackedVector2Array()
	for screen in [world_rect.position,Vector2(world_rect.end.x,world_rect.position.y),world_rect.end,Vector2(world_rect.position.x,world_rect.end.y),world_rect.position]:
		points.append(rect.position+game.field.ground_at(screen).clamp(Vector2.ZERO,Vector2.ONE*72)/72*rect.size)
	draw_polyline(points,Color(BG.r,BG.g,BG.b,.7),3*ui_scale,true)
	draw_polyline(points,Color.WHITE,1.5*ui_scale,true)
	draw_rect(rect,LINE_SOFT,false,1)

func draw_world_overlay() -> void:
	for e in game.sim.entities.values():
		if e.owner < 0 or not game.sim.known(0,e): continue
		if not game.selected.has(e.id) and e.hp>=e.max_hp and e.complete: continue
		var p: Vector2 = game.field.screen_at(e.pos,4.4 if e.building else 2.2)
		if not is_world(p): continue
		var width = 54 if e.building else 32
		draw_rect(Rect2(p.x-width/2.0,p.y,width,6),BG)
		draw_rect(Rect2(p.x-width/2.0,p.y,width*clampf(e.hp/e.max_hp,0,1),4),ACCENT if e.owner==0 else ERROR)
	if game.selected.size() == 1 and game.sim.entities.has(game.selected[0]):
		var e: Dictionary = game.sim.entities[game.selected[0]]
		if e.owner == 0 and e.kind in ["core", "fabricator"]:
			var rally: Vector2 = game.field.screen_at(e.rally)
			if is_world(rally):
				draw_line(rally,rally-Vector2(0,28),ACCENT,2)
				draw_colored_polygon(PackedVector2Array([rally-Vector2(0,28),rally+Vector2(16,-22),rally-Vector2(0,16)]),ACCENT)
	if game.dragging and game.drag_start.distance_to(mouse)>5:
		var r = Rect2(game.drag_start,mouse-game.drag_start).abs().intersection(world_rect)
		draw_rect(r,Color(.4,.9,.8,.12))
		draw_rect(r,ACCENT,false,1)

func is_world(p: Vector2) -> bool:
	if modal_active() or not world_rect.has_point(p): return false
	for region in blocked_regions:
		if region.has_point(p): return false
	return true

func handle_click(p: Vector2, right: bool = false) -> bool:
	# World/minimap routing only; buttons are managed by press/release below.
	if modal_active(): return true
	if map_rect.has_point(p):
		var target = (p-map_rect.position)/map_rect.size*DASimulation.SIZE
		if right:
			game.issue("attack_move" if game.attack_mode else "move",{"pos":target})
			game.attack_mode = false
		else:
			game.field.focus = target
			game.field.update_camera()
		return true
	return not is_world(p)

func pointer_event(event: InputEventMouseButton) -> bool:
	prepare_layout(true)
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and modal_active():
		if event.pressed and scroll_rect.has_point(event.position):
			scroll_offset = clampf(scroll_offset+(-60 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 60),0,scroll_max)
			prepare_layout(true)
		return true
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for b in buttons:
				if b.rect.has_point(event.position):
					pressed = b.id
					focused = b.id
					return true
		elif pressed != "":
			var id = pressed
			pressed = ""
			for b in buttons:
				if b.id == id and b.rect.has_point(event.position):
					activate(b)
					break
			return true
	if modal_active(): return true
	return false

func activate(b: Dictionary) -> void:
	if not b.enabled: toast(str(b.payload.get("reason","This action is unavailable.")),"error")
	else: game.ui_action(b.action,b.payload)
	prepare_layout(true)

func keyboard(event: InputEventKey) -> bool:
	prepare_layout(true)
	if event.physical_keycode == KEY_TAB:
		var ids = focus_controls.map(func(b): return b.id)
		if ids.is_empty(): return true
		var next = ids.find(focused)+( -1 if event.shift_pressed else 1)
		if next<0: next = ids.size()-1
		if next>=ids.size(): next=0
		focused = ids[next]
		var target: Dictionary = focus_controls[next]
		if target.clip.has_area() and not target.clip.encloses(target.rect):
			if target.rect.position.y < target.clip.position.y:
				scroll_offset += (target.rect.position.y-target.clip.position.y)/ui_scale
			else: scroll_offset += (target.rect.end.y-target.clip.end.y)/ui_scale
			prepare_layout(true)
		return true
	if event.physical_keycode in [KEY_ENTER,KEY_KP_ENTER]:
		for b in buttons:
			if b.id==focused:
				activate(b)
				return true
		return modal_active()
	if modal_active() and event.physical_keycode in [KEY_PAGEDOWN,KEY_PAGEUP,KEY_DOWN,KEY_UP]:
		scroll_offset = clampf(scroll_offset+(100 if event.physical_keycode in [KEY_PAGEDOWN,KEY_DOWN] else -100),0,scroll_max)
		prepare_layout(true)
		return true
	return false

func mission_directive() -> String:
	if not game.mission or not game.mission_definition: return "Destroy the rival Core"
	for item in game.mission_definition.objectives:
		if not game.mission.completed.get(item.get("id",""),false):
			var suffix = ""
			if item.get("kind","") in ["survive","gather"]:
				suffix = " · %d / %d" % [game.mission.progress_for(item),item.get("required",1)]
			return str(item.get("title","Await orders"))+suffix
	return "All objectives complete"

static func time_text(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds)/60,int(seconds)%60]

