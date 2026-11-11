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
const STEEL = Color("5d6b78")
const PANEL_ALPHA = .82
const TOP_H = 48.0
const EDGE = 16.0
const DOCK_PAD = 10.0
## The command grid: five columns by three rows, one key per slot in keyboard order.
const GRID_COLS = 5
const GRID_ROWS = 3
const GRID_KEYS = [KEY_Q,KEY_W,KEY_E,KEY_R,KEY_T,KEY_A,KEY_S,KEY_D,KEY_F,KEY_G,KEY_Z,KEY_X,KEY_C,KEY_V,KEY_B]
const BUILD_ORDER = ["generator","depot","data_center","fabricator","lab","tower"]
const TRAIN = {"core":["worker"],"fabricator":["scout","sentinel","disruptor","walker"]}

## What a building trains for the player's faction: the Fabricator adds the faction's own unit.
func trains(kind: String) -> Array:
	var list: Array = TRAIN.get(kind,[]).duplicate()
	if kind == "fabricator":
		for unit in game.sim.catalog.units:
			if game.sim.catalog.units[unit].has("faction") and game.sim.allowed(0,unit): list.append(unit)
	return list.filter(func(unit): return game.sim.allowed(0,unit))
const ICONS = ["metal","energy","data","population","tech","units","build","objectives","menu","home","speed","help","settings","sound","attack","stop","rally","age","weapons","check","lock","unit","building","cargo","fortify","armor","sensors","lab","idle","hold","patrol","cancel"]
const ROLES = {"lab":"Research Structure","core":"Town Center","generator":"Power Structure","depot":"Resource Drop-off","data_center":"Compute Structure","fabricator":"Production Structure","tower":"Defensive Structure","worker":"Utility Unit","scout":"Reconnaissance Unit","sentinel":"Combat Unit","disruptor":"Combat Unit","walker":"Siege Unit","metal":"Salvage Deposit","data":"Data Deposit"}
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
var tech_open = false
## Any other full-screen panel: "saves", "skirmish", "credits".
var menu_text_y = 380.0
var panel_open = ""
var saves_mode = "load"
var slot_info: Dictionary = {}
## Minimap pings: {pos, left, level}.
var pings: Array = []
var focus_keyboard = false
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
var plate_cache: Dictionary = {}
var wrap_cache: Dictionary = {}
var clip = Rect2()
var w = 0.0
var h = 0.0
var left = 0.0
var span = 0.0
var bottom = 0.0
var dock_h = 150.0
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
	for item in pings: item.left -= dt
	pings = pings.filter(func(item): return item.left > 0)
	if message_left <= 0 and not notifications.is_empty():
		var next: Dictionary = notifications.pop_front()
		message = next.text
		severity = next.severity
		message_left = 7.0 if severity == "error" else 5.0
	layout_elapsed += dt
	prepare_layout()
	queue_redraw()

## The layout needs at least 576 units of height; a larger scale than the window
## can carry is reduced to the largest that fits (150% is for 1440p and above).
const MIN_LAYOUT_HEIGHT = 576.0
var requested_scale = 1.0

func apply_scale(value: float) -> void:
	requested_scale = clampf(value, 1.0, 1.5)
	ui_scale = requested_scale
	if size.y > 0: ui_scale = clampf(minf(requested_scale, size.y/MIN_LAYOUT_HEIGHT), 1.0, 1.5)
	scale = Vector2.ONE
	layout_signature = ""

func show_subtitle(speaker: String, text: String, duration: float = 0.0) -> void:
	subtitle_speaker = speaker
	subtitle_text = text
	subtitle_left = duration if duration > 0 else maxf(3.5, text.length()*0.065)
	layout_signature = ""

## A ring on the minimap where something happened: "danger" for losses and attacks, "info" otherwise.
func ping(pos: Vector2, level: String = "info") -> void:
	if pings.size() >= 12: pings.pop_front()
	pings.append({"pos": pos, "left": 3.0, "level": level})

func refresh_slots() -> void:
	slot_info.clear()
	for slot in DASaveGame.MANUAL_SLOTS + DASaveGame.AUTO_SLOTS:
		slot_info[slot] = DASaveGame.describe(slot)
	layout_signature = ""

func toast(value: String, level: String = "info") -> void:
	if level in ["error", "alert"] or message_left <= 0:
		message = value
		severity = level
		message_left = 7.0 if level in ["error", "alert"] else 5.0
	elif value != message:
		if notifications.size() >= 4: notifications.pop_front()
		notifications.append({"text": value, "severity": level})
	layout_signature = ""

func modal_active() -> bool:
	return overlay_open() or game.mode != "playing"

## A manual, settings, technology or confirmation screen is covering the game.
func overlay_open() -> bool:
	return manual or settings_open or tech_open or panel_open != "" or not confirmation.is_empty()

func open_overlay(kind: String) -> void:
	modal_stack.append({"manual": manual, "settings": settings_open, "tech": tech_open, "panel": panel_open, "focus": focused, "scroll": scroll_offset})
	manual = kind == "manual"
	settings_open = kind == "settings"
	tech_open = kind == "tech"
	panel_open = "" if kind in ["manual", "settings", "tech"] else kind
	if kind == "saves": refresh_slots()
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
		tech_open = previous.get("tech", false)
		panel_open = previous.get("panel", "")
		focused = previous.focus
		scroll_offset = previous.scroll
	else:
		manual = false
		settings_open = false
		tech_open = false
		panel_open = ""
	rebind_action = ""
	cancel_pointer()
	prepare_layout(true)

func clear_overlays() -> void:
	manual = false
	settings_open = false
	tech_open = false
	panel_open = ""
	confirmation.clear()
	modal_stack.clear()
	rebind_action = ""
	scroll_offset = 0
	focused = ""
	cancel_pointer()

func confirm_action(action: String, payload: Dictionary = {}) -> void:
	confirmation = {"action": action, "focus": focused, "payload": payload.duplicate()}
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

## A 9-slice plate rendered in Blender (tools/sprites/ui.py, assets/ui/frames),
## or null when the file is missing so callers fall back to the flat style.
func plate(name: String) -> StyleBox:
	if not plate_cache.has(name):
		var box: StyleBoxTexture = null
		var texture = DASprites.load_texture("res://assets/ui/frames/%s.png" % name)
		if texture:
			box = StyleBoxTexture.new()
			box.texture = texture
			box.set_texture_margin_all(12)
			box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		plate_cache[name] = box
	return plate_cache[name]

## A panel drawn with a rendered plate, falling back to the flat panel.
func plate_panel(rect: Rect2, name: String, fallback: Color = PANEL, border_color: Color = LINE) -> void:
	if plate(name) == null:
		panel(rect, fallback, true, border_color)
		return
	var actual = to_view(rect)
	if clip.has_area(): actual = actual.intersection(clip)
	if actual.has_area(): operations.append({"type":"plate", "rect":actual, "name":name})

func panel(rect: Rect2, color: Color = PANEL, border: bool = true, border_color: Color = LINE) -> void:
	var actual = to_view(rect)
	if clip.has_area(): actual = actual.intersection(clip)
	if actual.has_area(): operations.append({"type":"panel", "rect":actual, "color":color, "border":border_color if border else color})

## A heavy machined frame: graded fill, dark outer edge, steel inner edge, a
## top highlight and accent ticks in the corners. The dock and bars use it.
func frame(rect: Rect2, top: Color, base: Color, accent: Color = ACCENT) -> void:
	operations.append({"type":"frame", "rect":to_view(rect), "top":top, "bottom":base, "accent":accent})

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

## Pointer images from assets/ui/cursors, rasterised once per kind (an Image, so no texture outlives the renderer).
func cursor_image(kind: String) -> Image:
	var key = "cursor:"+kind
	if icon_cache.has(key): return icon_cache[key]
	var image: Image = null
	var path = "res://assets/ui/cursors/%s.svg" % kind
	if FileAccess.file_exists(path):
		image = Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path), 1.0) != OK: image = null
	icon_cache[key] = image
	return image

## Height of the health bar anchor: just above a sprite card, or the model heights.
func bar_height(e: Dictionary) -> float:
	if DASprites.has_sprite(e.kind):
		var cells = (game.sim.catalog.buildings[e.kind].radius * 2 + 1) if e.building else 1
		return DASprites.bar_height(e.kind, cells)
	return 4.4 if e.building else 2.2

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
	var fitted = clampf(minf(requested_scale, size.y/MIN_LAYOUT_HEIGHT), 1.0, 1.5)
	if not is_equal_approx(fitted, ui_scale): ui_scale = fitted
	var signature = str([game.ability_mode,game.settings.values.skirmish,game.game_kind,size,ui_scale,game.mode,manual,settings_open,tech_open,panel_open,saves_mode,confirmation,rebind_action,scroll_offset,game.selected,game.build_kind,game.attack_mode,game.rally_mode,game.patrol_mode,objectives_open,game.speed,game.campaign.selected_difficulty])
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
	dock_h = clampf(roundf(h*.24),150,196)
	bottom = h-dock_h
	world_rect = to_view(Rect2(0,TOP_H,w,h-TOP_H-(0.0 if game.mode == "menu" else dock_h)))
	if game.mode == "menu": layout_menu()
	else: layout_hud()
	if overlay_open() or game.mode in ["paused", "result"]:
		buttons.clear()
		focus_controls.clear()
		operations.clear()
		text_bounds.clear()
		if not confirmation.is_empty(): layout_confirmation()
		elif settings_open: layout_settings()
		elif manual: layout_manual()
		elif tech_open: layout_tech()
		elif panel_open == "saves": layout_saves()
		elif panel_open == "skirmish": layout_skirmish()
		elif panel_open == "credits": layout_credits()
		elif game.mode == "paused": layout_pause()
		elif game.mode == "result": layout_result()
	clip = Rect2()
	if message_left > 0: layout_notification()
	if not modal_active() or tech_open or (game.mode == "menu" and not overlay_open()): layout_tooltip()
	layout_usec = Time.get_ticks_usec()-started

func layout_menu() -> void:
	panel(Rect2(0,0,w,h),Color(BG.r,BG.g,BG.b,.88),false)
	var x = left+32
	var column = (span-96)/2
	text("D / A  ·  MACHINE CIVILIZATIONS",Rect2(x,30,column,28),16,ACCENT)
	text("THE WORLD WENT QUIET.",Rect2(x,95,column,32),16,GOLD)
	text("DIGITAL\nAGE",Rect2(x,139,column,160),58,TEXT)
	# Short windows drop the tagline so the briefing keeps its room above the buttons.
	menu_text_y = 380.0 if h >= 660 else 305.0
	if h >= 660: text("Harvest. Evolve. Command the next civilization.",Rect2(x,305,column,64),18,MUTED)
	if message_left <= 0: text(game.mission_catalog.get_definition(game.pending_mission_id).briefing,Rect2(x,menu_text_y,column,maxf(30,h-204-menu_text_y)),16,TEXT)
	var hw = (column-8)/2
	button(Rect2(x,h-194,hw,46),"DIFFICULTY · "+str(game.campaign.selected_difficulty).to_upper(),"difficulty",{"tooltip":"How quickly the rival expands and attacks. Applies to the next mission you launch."})
	button(Rect2(x+hw+8,h-194,hw,46),"LOAD GAME","saves",{"id":"load"})
	var lw = roundf(column*.6)
	button(Rect2(x,h-138,lw,52),"LAUNCH CAMPAIGN  →","start",{},"",true,true)
	button(Rect2(x+lw+8,h-138,column-lw-8,52),"SKIRMISH","skirmish",{"tooltip":"A free match on any map, against the faction and difficulty you choose."})
	var bw = (column-24)/4
	button(Rect2(x,h-74,bw,42),"MANUAL","help")
	button(Rect2(x+bw+8,h-74,bw,42),"SETTINGS","settings")
	button(Rect2(x+2*(bw+8),h-74,bw,42),"CREDITS","credits")
	button(Rect2(x+3*(bw+8),h-74,bw,42),"QUIT","quit")
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
	layout_dock()
	layout_objectives()
	layout_strips()

func layout_top_bar() -> void:
	gradient(Rect2(0,0,w,TOP_H),Color("1a2632f2"),Color("0b1016f2"))
	line(Vector2(0,TOP_H-1),Vector2(w,TOP_H-1),STEEL,1)
	line(Vector2(0,TOP_H),Vector2(w,TOP_H),Color(0,0,0,.7),1)
	blocked_regions.append(to_view(Rect2(0,0,w,TOP_H)))
	var x = left+EDGE
	var group_w = 150.0 if span >= 1500 else (124.0 if span >= 1200 else 104.0)
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
		if i > 0: line(Vector2(gx-6,10),Vector2(gx-6,TOP_H-10),LINE_SOFT,1)
	var resources_end = x+groups.size()*group_w
	var idle: int = idle_workers().size()
	var nav = [
		["idle","Idle Workers: "+str(idle)+". Select the next one.","idle_worker",str(idle) if idle > 0 else ""],
		["units","Select every combat unit","army",""],
		["tech","Technology tree","tech",""],
		["objectives","Objectives","objectives",""],
		["home","Focus Core · "+game.settings.prompt("home"),"home",""],
		["speed","Game speed · "+game.settings.prompt("speed"),"speed","×"+str(game.speed)],
		["menu","Pause menu · "+game.settings.prompt("pause"),"pause",""]]
	var s = 38.0
	var nav_w = nav.size()*s+(nav.size()-1)*6
	var nav_x = left+span-EDGE-nav_w
	for i in nav.size():
		icon_button(Rect2(nav_x+i*(s+6),(TOP_H-s)/2,s,s),nav[i][0],nav[i][1],nav[i][2],{},true,false,nav[i][3])
	# Centre: the current age as the bar's emblem, with the mission clock under it.
	var age_name: String = game.sim.catalog.ages[game.sim.ages[0]]+" AGE"
	var clock = time_text(game.sim.elapsed)
	var tw = title_width(age_name,17)
	var gap_left = resources_end+16
	var gap_right = nav_x-16
	var cx = clampf(left+span/2,gap_left+(tw+30)/2,maxf(gap_left+(tw+30)/2,gap_right-(tw+30)/2))
	if gap_right-gap_left >= tw+30:
		icon("age",Rect2(cx-(tw+30)/2,8,20,20),GOLD)
		title_text(age_name,cx-(tw+30)/2+28,7,17,GOLD)
		centered_text(clock,Rect2(cx-40,28,80,16),12,MUTED)
	elif gap_right-gap_left >= 60:
		centered_text(clock,Rect2(gap_left,15,gap_right-gap_left,18),14,MUTED)

func idle_workers() -> Array:
	return game.sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "worker" and e.order == "idle").map(func(e): return e.id)

## The bottom dock: minimap, selection and command grid in one framed band.
func layout_dock() -> void:
	var dock = Rect2(0,h-dock_h,w,dock_h)
	frame(dock,Color("1c2935f7"),Color("0b1016f7"))
	blocked_regions.append(to_view(dock))
	var inner_h = dock_h-2*DOCK_PAD
	var y = dock.position.y+DOCK_PAD
	var mw = minf(inner_h*2,span*.27)
	var mr = Rect2(left+EDGE,y+(inner_h-mw/2)/2,mw,mw/2)
	map_rect = to_view(mr)
	operations.append({"type":"map","rect":map_rect})
	var gap = 5.0
	var slot = floorf(minf(56,(inner_h-(GRID_ROWS-1)*gap)/GRID_ROWS))
	var grid_size = Vector2(GRID_COLS*slot+(GRID_COLS-1)*gap,GRID_ROWS*slot+(GRID_ROWS-1)*gap)
	var grid = Rect2(Vector2(left+span-EDGE-grid_size.x,y+(inner_h-grid_size.y)/2),grid_size)
	var free_left = mr.end.x+16
	var free_right = grid.position.x-16
	line(Vector2(free_left-8,y),Vector2(free_left-8,y+inner_h),LINE_SOFT,1)
	line(Vector2(free_right+8,y),Vector2(free_right+8,y+inner_h),LINE_SOFT,1)
	var pw = minf(900,free_right-free_left)
	panel_rect = Rect2(free_left+(free_right-free_left-pw)/2,y,pw,inner_h)
	tier = "A" if pw >= 640 else ("B" if pw >= 460 else "C")
	var selected: Array = game.selected.filter(func(id): return game.sim.entities.has(id) and game.sim.known(0,game.sim.entities[id]))
	layout_selection(panel_rect,selected)
	layout_grid(grid,slot,gap,selected)

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
	var strip_w = minf(760,span-2*EDGE)
	var strip_x = left+(span-strip_w)/2
	var notice_rect = Rect2(strip_x,bottom-54,strip_w,44)
	reserved_regions.notification = to_view(notice_rect)
	if subtitles_enabled and subtitle_left > 0 and subtitle_text != "":
		var sh = minf(150,40+text_height(subtitle_text,strip_w-28))
		var sr = Rect2(strip_x,bottom-68-sh,strip_w,sh)
		reserved_regions.subtitle = to_view(sr)
		panel(sr,Color(BG.r,BG.g,BG.b,.92))
		text(subtitle_speaker.to_upper(),Rect2(sr.position+Vector2(14,8),Vector2(strip_w-28,24)),14,GOLD)
		text(subtitle_text,Rect2(sr.position+Vector2(14,34),Vector2(strip_w-28,sh-38)),16)
	if game.build_kind != "" or game.attack_mode or game.rally_mode or game.patrol_mode or game.ability_mode:
		var value = "ATTACK-MOVE · Click a destination. Right-click or Esc to cancel."
		var color = ACCENT
		if game.ability_mode: value = "ABILITY · Click where to aim it. Right-click or Esc to cancel."
		if game.patrol_mode: value = "PATROL · Click the far end of the route. Right-click or Esc to cancel."
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

func research_name(side: int, id: String) -> String:
	if id == "age": return "Advancing to "+game.sim.catalog.ages[mini(2,game.sim.ages[side]+1)].capitalize()
	return str(game.sim.catalog.tech.get(id,{}).get("name",id.capitalize()))+" "+str(game.sim.tech_level(side,id)+1)

func selection_status(e: Dictionary, d: Dictionary) -> String:
	if e.owner < 0: return "Send Workers to harvest this deposit."
	if e.owner != 0: return "Hostile"
	if not e.complete: return "Constructing %d%%" % int(100*(1-e.build_left/d.time))
	if e.research != "": return research_name(0,e.research)+" · "+str(ceili(e.research_left))+"s"
	if not e.queue.is_empty(): return "Producing "+game.sim.catalog.units[e.queue[0].kind].name+" · "+str(ceili(e.queue[0].left))+"s · Queue "+str(e.queue.size())+"/5"
	return "Operational" if e.building else e.order.capitalize().replace("_"," ")

func active_job(e: Dictionary, d: Dictionary) -> Dictionary:
	if e.owner != 0: return {}
	if not e.complete: return {"kind":e.kind,"progress":1-e.build_left/maxf(.1,d.time),"name":"Constructing","left":e.build_left}
	if e.research != "":
		var catalog: DACatalog = game.sim.catalog
		var total = catalog.age_times[mini(1,game.sim.ages[0])] if e.research == "age" else catalog.tech_time(e.research,game.sim.tech_level(0,e.research)+1)
		total *= game.sim.faction_modifier(0,"research_speed",1.0)
		var glyph = "age" if e.research == "age" else str(catalog.tech.get(e.research,{}).get("icon","tech"))
		return {"kind":glyph,"progress":1-e.research_left/maxf(.1,total),"name":"Age upgrade" if e.research == "age" else research_name(0,e.research),"left":e.research_left}
	if not e.queue.is_empty():
		var kind: String = e.queue[0].kind
		return {"kind":kind,"progress":1-e.queue[0].left/maxf(.1,game.sim.catalog.units[kind].time),"name":game.sim.catalog.units[kind].name,"left":e.queue[0].left}
	return {}

## Combat and movement figures with the owner's research applied.
func stat_line(e: Dictionary, d: Dictionary) -> String:
	if e.owner < 0: return ""
	var parts: Array = []
	if float(d.get("damage",0.0)) > 0:
		var bonus: float = game.sim.tech_modifier(e.owner,"tower_damage" if e.building else "unit_damage")
		parts.append("ATK %d" % roundi(float(d.damage)*(1.0+bonus)))
		parts.append("RNG %.1f" % game.sim.attack_range(e))
	if not e.building and d.has("speed"): parts.append("SPD %.1f" % float(d.speed))
	if d.has("vision"): parts.append("SIGHT %d" % roundi(game.sim.vision_radius(e)))
	if d.has("armor"): parts.append(str(d.armor).to_upper())
	if game.sim.on_high_ground(e): parts.append("HIGH GROUND")
	if game.sim.stunned(e): parts.append("DISABLED")
	if float(e.get("cargo",0.0)) > 0: parts.append("CARGO %d" % int(e.cargo))
	return "  ·  ".join(parts)

func layout_selection(rect: Rect2, selected: Array) -> void:
	var x = rect.position.x
	var y = rect.position.y
	var iw = rect.size.x
	var ih = rect.size.y
	if selected.is_empty():
		text("AWAITING YOUR COMMAND",Rect2(x,y+2,iw,30),22)
		text("Select Workers to gather resources and construct your base.",Rect2(x,y+36,iw,40),15,MUTED)
		button(Rect2(x,rect.end.y-42,180,42),"SELECT WORKERS","workers",{"id":"panel"})
		button(Rect2(x+192,rect.end.y-42,160,42),"FOCUS CORE","home",{"id":"panel"})
		return
	if selected.size() > 1:
		layout_group(rect,selected)
		return
	var e: Dictionary = game.sim.entities[selected[0]]
	var d: Dictionary = game.sim.catalog.definition(e.kind)
	var title: String = d.get("name","Salvage pile" if e.kind == "metal" else "Data archive")
	var role: String = ROLES.get(e.kind,"Structure" if e.building else "Unit")
	if e.owner == 1: role = "Enemy "+role
	var portrait_w = minf(ih-34,120.0)
	var health = clampf(float(e.hp)/maxf(1,e.max_hp),0,1) if e.owner >= 0 else 1.0
	var health_text = "%s / %s" % [thousands(e.hp),thousands(e.max_hp)] if e.owner >= 0 else thousands(e.amount)+" remaining"
	var health_color = GREEN if health > .5 else (GOLD if health > .25 else ERROR)
	if e.owner < 0: health_color = GOLD if e.kind == "metal" else VIOLET
	var pr = Rect2(x,y,portrait_w,portrait_w)
	plate_panel(pr,"slot",Color(BG.r,BG.g,BG.b,.7),STEEL)
	thumb(e.kind,pr.grow(-6))
	bar(Rect2(x,y+portrait_w+6,portrait_w,7),health,health_color)
	centered_text(health_text,Rect2(x,y+portrait_w+15,portrait_w,18),12,MUTED)
	var show_job: bool = e.owner == 0 and e.building
	var job_w = 0.0
	if show_job: job_w = 170.0 if tier == "A" else (130.0 if tier == "B" else 112.0)
	var ix = x+portrait_w+14
	var info_w = iw-portrait_w-14-(job_w+14 if show_job else 0.0)
	fitted_text(title,Rect2(ix,y-3,info_w,30),22 if tier == "A" else 19)
	fitted_text(role.to_upper(),Rect2(ix,y+26,info_w,18),12,MUTED)
	fitted_text(selection_status(e,d),Rect2(ix,y+44,info_w,18),13,GOLD)
	var stats = stat_line(e,d)
	var text_y = y+64
	if stats != "":
		fitted_text(stats,Rect2(ix,text_y,info_w,18),13,ACCENT)
		text_y += 21
	var description = str(d.get("description","Select Workers and right-click this deposit to harvest it."))
	var available = rect.end.y-text_y
	for px in [14,13,12]:
		if available >= 16 and text_height(description,info_w,px) <= available:
			text(description,Rect2(ix,text_y,info_w,available),px,MUTED)
			break
	if show_job: layout_job(Rect2(rect.end.x-job_w,y,job_w,ih),e,d)

## Several units: one portrait cell each, with a health bar; a click narrows the selection.
func layout_group(rect: Rect2, selected: Array) -> void:
	var x = rect.position.x
	var y = rect.position.y
	text(str(selected.size())+" UNITS SELECTED",Rect2(x,y-2,rect.size.x,24),18)
	var cell = 42.0
	var step = cell+4
	var cols = maxi(1,floori((rect.size.x+4)/step))
	var rows = maxi(1,floori((rect.size.y-26+4)/step))
	var capacity = cols*rows
	for i in mini(selected.size(),capacity):
		var r = Rect2(x+(i%cols)*step,y+26+floori(float(i)/cols)*step,cell,cell)
		if i == capacity-1 and selected.size() > capacity:
			panel(r,Color(BG.r,BG.g,BG.b,.6),true,LINE_SOFT)
			centered_text("+"+str(selected.size()-capacity+1),Rect2(r.position+Vector2(0,12),Vector2(cell,18)),14,MUTED)
			break
		var e: Dictionary = game.sim.entities[selected[i]]
		var name: String = game.sim.catalog.definition(e.kind).get("name",e.kind.capitalize())
		var b = register(r,name,"select_one",{"id":e.id,"tooltip":name+" · "+thousands(e.hp)+" / "+thousands(e.max_hp)},true,false)
		if b.is_empty(): continue
		thumb(e.kind,r.grow(-4))
		var health = clampf(float(e.hp)/maxf(1,e.max_hp),0,1)
		bar(Rect2(r.position.x+3,r.end.y-7,cell-6,4),health,GREEN if health > .5 else (GOLD if health > .25 else ERROR))

## What a building is doing: the active item with its progress, then the rest of the queue.
func layout_job(rect: Rect2, e: Dictionary, d: Dictionary) -> void:
	plate_panel(rect,"slot",Color(BG.r,BG.g,BG.b,.55),LINE_SOFT)
	var job = active_job(e,d)
	var x = rect.position.x
	var y = rect.position.y
	var tw = clampf(rect.size.y-70,40,64)
	if job.is_empty():
		icon("building",Rect2(x+(rect.size.x-36)/2,y+(rect.size.y-60)/2,36,36),Color(MUTED.r,MUTED.g,MUTED.b,.35))
		centered_text("IDLE",Rect2(x+4,y+(rect.size.y-60)/2+42,rect.size.x-8,18),12,Color(MUTED.r,MUTED.g,MUTED.b,.7))
		return
	thumb(job.kind,Rect2(x+(rect.size.x-tw)/2,y+5,tw,tw))
	bar(Rect2(x+8,y+tw+10,rect.size.x-16,6),job.progress,ACCENT)
	centered_text(str(job.name)+" · "+str(ceili(job.left))+"s",Rect2(x+4,y+tw+19,rect.size.x-8,18),12)
	var waiting: Array = e.get("queue",[]).slice(1)
	var q = 22.0
	var qy = y+tw+40
	if qy+q <= rect.end.y-2:
		var total = 4*q+3*4
		for i in 4:
			var cell = Rect2(x+(rect.size.x-total)/2+i*(q+4),qy,q,q)
			panel(cell,Color(BG.r,BG.g,BG.b,.6),true,LINE_SOFT)
			if i < waiting.size(): thumb(waiting[i].kind,cell.grow(-2))

## Commands for the first selected entity, by grid slot (null leaves the slot empty).
func grid_items(e: Dictionary) -> Array:
	var items: Array = []
	items.resize(GRID_COLS*GRID_ROWS)
	if e.owner != 0: return items
	var catalog: DACatalog = game.sim.catalog
	if not e.building:
		items[5] = {"icon":"attack","title":"Attack-move","action":"attack_mode","primary":game.attack_mode,"hotkey":game.settings.prompt("attack"),"bound":true}
		items[6] = {"icon":"stop","title":"Stop","action":"stop","hotkey":game.settings.prompt("stop"),"bound":true}
		items[7] = {"icon":"hold","title":"Hold position\nStand ground and fire only at what comes into range.","action":"hold","primary":e.order == "hold"}
		items[8] = {"icon":"patrol","title":"Patrol\nWalk back and forth to a point, engaging enemies on the way.","action":"patrol_mode","primary":game.patrol_mode or e.order == "patrol"}
		if e.kind != "worker":
			var aggressive: bool = e.get("stance","defensive") == "aggressive"
			items[9] = {"icon":"attack" if aggressive else "fortify","title":("Stance: aggressive" if aggressive else "Stance: defensive")+"\nDefensive units fire from where they stand. Aggressive units chase what they see, up to 12 cells, then return.","action":"stance","primary":aggressive}
		var ability: Dictionary = catalog.abilities.get(e.kind,{})
		if not ability.is_empty():
			var wait: float = float(e.get("ability_ready",0.0))-game.sim.elapsed
			var active: bool = e.get("braced",false) or float(e.get("overdrive_until",0.0)) > game.sim.elapsed
			items[0] = {"icon":str(ability.get("icon","tech")),"kind":e.kind,"title":str(ability.name)+"\n"+str(ability.description)+"\nRecharge: "+str(int(ability.cooldown))+" s","action":"ability","primary":active or game.ability_mode,"reason":"Recharging · "+str(ceili(wait))+" s" if wait > 0 else "","count":str(ceili(wait)) if wait > 0 else ""}
		if e.kind == "worker":
			for i in BUILD_ORDER.size():
				items[i if i < GRID_COLS else 2*GRID_COLS+i-GRID_COLS] = {"kind":BUILD_ORDER[i],"action":"build","d":catalog.buildings[BUILD_ORDER[i]]}
			if not game.sim.has_core(0,false):
				items[2*GRID_COLS+1] = {"kind":"core","action":"build","d":catalog.buildings.core}
		return items
	if not e.complete: return items
	if not e.queue.is_empty() or e.research != "":
		items[GRID_COLS*GRID_ROWS-1] = {"icon":"cancel","title":"Cancel\nRemove the last queued item, or stop the research, and refund it.","action":"cancel_job"}
	var trains: Array = trains(e.kind)
	for i in trains.size():
		items[i] = {"kind":trains[i],"action":"train","d":catalog.units[trains[i]]}
	if not trains.is_empty():
		items[2*GRID_COLS] = {"icon":"rally","title":"Set rally point","action":"rally","primary":game.rally_mode}
	if e.kind == "core":
		var age: int = game.sim.ages[0]
		if age < 2: items[1] = {"icon":"age","kind":"age","action":"research","d":{"name":"Advance to "+catalog.ages[age+1].capitalize(),"cost":catalog.age_costs[age],"age":0,"description":"Advance to the next technological age."}}
		else: items[1] = {"icon":"age","kind":"age","action":"research","title":"Final age reached","reason":"The Singularity is the final age."}
	if e.kind == "lab":
		for row in mini(GRID_ROWS,catalog.tech_branches.size()):
			var ids: Array = catalog.tech_ids(catalog.tech_branches[row])
			for i in mini(GRID_COLS,ids.size()):
				items[row*GRID_COLS+i] = tech_item(ids[i])
	return items

func tech_item(id: String) -> Dictionary:
	var catalog: DACatalog = game.sim.catalog
	var entry: Dictionary = catalog.tech[id]
	var level: int = game.sim.tech_level(0,id)
	var next = mini(level+1,DACatalog.TECH_MAX_LEVEL)
	return {"icon":str(entry.get("icon","tech")),"kind":id,"action":"research","tech":true,"level":level,
		"d":{"name":str(entry.name)+" "+str(next),"cost":catalog.tech_cost(id,next),"age":DACatalog.tech_age_for_level(next),"description":str(entry.description)}}

func layout_grid(rect: Rect2, slot: float, gap: float, selected: Array) -> void:
	var items: Array = []
	items.resize(GRID_COLS*GRID_ROWS)
	var e: Dictionary = {}
	if not selected.is_empty():
		e = game.sim.entities[selected[0]]
		items = grid_items(e)
	var queued: Dictionary = {}
	for entry in e.get("queue",[]): queued[entry.kind] = queued.get(entry.kind,0)+1
	for i in items.size():
		var cell = Rect2(rect.position.x+(i%GRID_COLS)*(slot+gap),rect.position.y+floori(float(i)/GRID_COLS)*(slot+gap),slot,slot)
		if items[i] == null:
			plate_panel(cell,"slot",Color(0,0,0,.18),Color(1,1,1,.08))
			continue
		var item: Dictionary = items[i]
		var reason: String = str(item.get("reason",""))
		var title: String = str(item.get("title",""))
		var tooltip = title
		if item.has("d"):
			title = item.d.name
			if item.get("tech",false): reason = game.sim.tech_error(0,item.kind)
			if reason == "" or reason == "Insufficient resources.": reason = availability(item,e)
			tooltip = title+" · "+cost_text(item.d.cost)+"\n"+item.d.description
			if item.action == "train":
				var strong: String = game.sim.catalog.counter_text(item.kind)
				tooltip += "\nArmour: "+str(item.d.get("armor","light"))+(" · Strong: "+strong if strong != "" else "")
		var hotkey: String = str(item.get("hotkey",OS.get_keycode_string(GRID_KEYS[i])))
		var payload = {"tooltip":tooltip+"\nHotkey: "+hotkey,"reason":reason}
		if item.has("kind"): payload.kind = item.kind
		if not item.get("bound",false): payload.grid = GRID_KEYS[i]
		var b = register(cell,title,item.action,payload,reason == "",item.get("primary",false))
		if b.is_empty(): continue
		var enabled: bool = reason == ""
		var inset = 4.0 if item.has("d") and not item.has("icon") else slot*.22
		if item.has("icon"): icon(item.icon,cell.grow(-inset),TEXT if enabled else Color(MUTED.r,MUTED.g,MUTED.b,.6))
		else: thumb(item.kind,cell.grow(-inset),Color.WHITE if enabled else Color(1,1,1,.4))
		text_control = b.id
		text(hotkey.left(3),Rect2(cell.position+Vector2(4,0),Vector2(slot-8,15)),11,GOLD if enabled else MUTED)
		var badge = ""
		if queued.has(item.get("kind","")) and item.action == "train": badge = "×"+str(queued[item.kind])
		elif item.get("count","") != "": badge = str(item.count)
		elif item.get("tech",false): badge = str(item.level)+"/"+str(DACatalog.TECH_MAX_LEVEL)
		if badge != "":
			var bw = font.get_string_size(badge,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(11*ui_scale)).x/ui_scale
			text(badge,Rect2(cell.end.x-bw-4,cell.end.y-16,bw+2,15),11,ACCENT)
		text_control = ""
		if not enabled and not item.get("tech",false): icon("lock",Rect2(cell.end.x-16,cell.position.y+3,12,12),GOLD)

## Activates the command-grid slot bound to `key`; false when no slot uses it.
func grid_key(key: int) -> bool:
	if modal_active(): return false
	prepare_layout(true)
	for b in buttons:
		if b.payload.get("grid",-1) == key:
			activate(b)
			return true
	return false

## The technology tree: every upgrade by branch, its level and what the next one costs.
func layout_tech() -> void:
	var rect = modal_shell("TECHNOLOGY",1100)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var catalog: DACatalog = game.sim.catalog
	var labs: Array = game.sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "lab" and e.complete)
	var idle: int = labs.filter(func(e): return e.research == "").size()
	var summary = "No Research Lab yet. Workers can build one." if labs.is_empty() else "Research Labs: %d · idle: %d" % [labs.size(),idle]
	text(catalog.ages[game.sim.ages[0]].capitalize()+" age · "+summary,Rect2(x,rect.position.y+58,cw,22),14,MUTED)
	var top = rect.position.y+90
	var branches: Array = catalog.tech_branches
	var col_gap = 14.0
	var col_w = (cw-(branches.size()-1)*col_gap)/maxi(1,branches.size())
	var avail = rect.end.y-66-top-28
	for column in branches.size():
		var bx = x+column*(col_w+col_gap)
		text(str(branches[column]).to_upper(),Rect2(bx,top,col_w,22),16,GOLD)
		var ids: Array = catalog.tech_ids(branches[column])
		var row_h = minf(96,avail/maxi(1,ids.size()))
		for i in ids.size():
			var id: String = ids[i]
			var entry: Dictionary = catalog.tech[id]
			var level: int = game.sim.tech_level(0,id)
			var busy: bool = game.sim.researching(0,id)
			var reason: String = game.sim.tech_error(0,id)
			if reason == "" and labs.is_empty(): reason = "Build a Research Lab first."
			elif reason == "" and idle == 0: reason = "Every Research Lab is busy."
			var r = Rect2(bx,top+28+i*row_h,col_w,row_h-6)
			var b = register(r,str(entry.name),"research_tech",{"kind":id,"tooltip":str(entry.description),"reason":reason},reason == "",busy)
			if b.is_empty(): continue
			icon(str(entry.get("icon","tech")),Rect2(r.position+Vector2(10,(r.size.y-26)/2),Vector2(26,26)),ACCENT if reason == "" or busy else MUTED)
			text_control = b.id
			var tx = r.position.x+46
			var tw = r.size.x-56
			fitted_text(str(entry.name),Rect2(tx,r.position.y+3,tw-74,20),15,TEXT)
			var status = "Researching…" if busy else ("Complete" if level >= DACatalog.TECH_MAX_LEVEL else "Level %d · %s" % [level+1,cost_text(catalog.tech_cost(id,level+1))])
			if not busy and level < DACatalog.TECH_MAX_LEVEL and reason != "" and reason != "Insufficient resources.": status = reason
			fitted_text(status,Rect2(tx,r.position.y+r.size.y-22,tw,18),12,GOLD if busy else (MUTED if reason != "" else ACCENT))
			text_control = ""
			for pip in DACatalog.TECH_MAX_LEVEL:
				panel(Rect2(r.end.x-78+pip*14,r.position.y+8,10,10),ACCENT if pip < level else Color(BG.r,BG.g,BG.b,.8),true,ACCENT if pip < level else STEEL)
	button(Rect2(x,rect.end.y-58,cw,44),"RETURN","tech",{"id":"close"},"",true,true)

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
	plate_panel(rect,"panel")
	text(title,Rect2(rect.position+Vector2(24,16),Vector2(rect.size.x-48,44)),26,ACCENT)
	return rect

func layout_pause() -> void:
	var rect = modal_shell("SIMULATION PAUSED",620)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var y = rect.position.y+82
	var entries = [["RESUME","resume",{}],["SPEED "+str(game.speed)+"×","speed",{}],["SAVE GAME","saves",{"id":"save"}],["LOAD GAME","saves",{"id":"load"}],["FIELD MANUAL","help",{}],["SETTINGS","settings",{}],["RESTART MISSION","restart",{}],["MAIN MENU","menu",{}]]
	for i in entries.size():
		button(Rect2(x+(i%2)*(cw/2+4),y+floori(i/2.0)*70,cw/2-4,52),entries[i][0],entries[i][1],entries[i][2],"",true,i==0)
	text("Quick save "+game.settings.prompt("save")+" · quick load "+game.settings.prompt("load")+" use the first manual slot.",Rect2(x,y+4*70+4,cw,24),14,MUTED)
	text("Esc resumes · Tab changes focus · Enter selects",Rect2(x,rect.end.y-78,cw,50),14,MUTED)

func layout_result() -> void:
	var won: bool = game.sim.winner == 0 or game.mission.mission_won
	var rect = modal_shell("TRANSMISSION COMPLETE" if won else "TRANSMISSION LOST",720)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	# Say why the match ended: the Core fell, the clock ran out, or an objective failed.
	var headline = "VICTORY"
	var detail: String = game.mission_definition.victory_text
	if not won:
		var reason: String = game.fail_reason
		headline = "CORE LOST" if game.sim.winner == 1 or reason == "core" else ("TIME EXPIRED" if reason.begins_with("Time limit") else "MISSION FAILED")
		detail = game.mission_definition.defeat_text
		if reason not in ["", "core", detail]: detail = reason+" "+detail
	text(headline,Rect2(x,rect.position.y+86,cw,72),48,ACCENT if won else ERROR)
	text(detail,Rect2(x,rect.position.y+166,cw,84),18)
	text("Time "+time_text(game.sim.elapsed)+" · Enemies destroyed "+str(game.sim.stats[0].kills)+"\nResources harvested "+str(int(game.sim.stats[0].gathered)),Rect2(x,rect.position.y+256,cw,52),16,MUTED)
	var next_id: String = game.next_mission_id() if won else ""
	if next_id != "":
		button(Rect2(x,rect.end.y-146,cw,52),"NEXT MISSION · "+str(game.mission_catalog.get_definition(next_id).title).to_upper()+"  →","next_mission",{},"",true,true)
	if game.game_kind == "skirmish":
		var third = (cw-16)/3
		button(Rect2(x,rect.end.y-84,third,52),"PLAY AGAIN","restart",{},"",true,true)
		button(Rect2(x+third+8,rect.end.y-84,third,52),"CHANGE SETUP","skirmish")
		button(Rect2(x+2*(third+8),rect.end.y-84,third,52),"MAIN MENU","menu")
	else:
		button(Rect2(x,rect.end.y-84,cw/2-6,52),"PLAY AGAIN","restart",{},"",true,next_id == "")
		button(Rect2(x+cw/2+6,rect.end.y-84,cw/2-6,52),"MAIN MENU","menu")

## Skirmish setup: the map with a preview, both factions, difficulty, resources and start.
func layout_skirmish() -> void:
	var rect = modal_shell("SKIRMISH",920)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var setup: Dictionary = game.settings.values.skirmish
	var map = map_definition(str(setup.map))
	var side = minf(minf(300,cw*.36),rect.size.y-190)
	var pr = Rect2(x,rect.position.y+74,side,side)
	operations.append({"type":"preview","rect":to_view(pr),"map":map,"side":str(setup.side),"player":str(setup.player),"enemy":str(setup.enemy)})
	if map:
		text("%d deposits · %d blocked cells" % [map.resource_nodes.size(),map.obstacle_cells.size()],Rect2(x,pr.end.y+8,side,20),13,MUTED)
	var ox = x+side+20
	var ow = cw-side-20
	var rows = [
		["MAP",map.display_name if map else str(setup.map),"map",""],
		["YOUR FACTION",faction_name(str(setup.player)),"player",faction_note(str(setup.player))],
		["RIVAL FACTION",faction_name(str(setup.enemy)),"enemy",faction_note(str(setup.enemy))],
		["RESOURCES",str(setup.resources).capitalize(),"resources","What both sides start with."],
		["START POSITION",str(setup.side).capitalize(),"side","Which of the map's two starts is yours."]]
	var row_h = clampf((rect.end.y-78-pr.position.y)/(rows.size()+1),40,54)
	for i in rows.size():
		var y = pr.position.y+i*row_h
		text(rows[i][0],Rect2(ox,y,ow-104,16),12,MUTED)
		fitted_text(str(rows[i][1]),Rect2(ox,y+15,ow-104,24),18,TEXT)
		button(Rect2(ox+ow-96,y,44,row_h-6),"‹","skirmish_option",{"key":rows[i][2],"delta":-1,"tooltip":rows[i][3]})
		button(Rect2(ox+ow-48,y,44,row_h-6),"›","skirmish_option",{"key":rows[i][2],"delta":1,"tooltip":rows[i][3]})
	var dy = pr.position.y+rows.size()*row_h
	text("DIFFICULTY",Rect2(ox,dy,ow-164,16),12,MUTED)
	fitted_text(str(game.campaign.selected_difficulty).capitalize(),Rect2(ox,dy+15,ow-164,24),18,TEXT)
	button(Rect2(ox+ow-156,dy,152,row_h-6),"CHANGE","difficulty",{"id":"skirmish","tooltip":"How quickly the rival expands and attacks."})
	button(Rect2(x,rect.end.y-66,cw*.62,44),"START SKIRMISH  →","start_skirmish",{},"",true,true)
	button(Rect2(x+cw*.62+8,rect.end.y-66,cw*.38-8,44),"RETURN","skirmish",{"id":"close"})

## The shipped credits file, shown as plain text.
func layout_credits() -> void:
	var rect = modal_shell("CREDITS",850)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	var sections = credit_sections()
	var total = 0.0
	for section in sections:
		total += (40 if section[0] != "" else 0)+text_height(section[1],cw)+18
	begin_scroll(Rect2(x,rect.position.y+78,cw,rect.size.y-166),total)
	var y = rect.position.y+78-scroll_offset
	for section in sections:
		if section[0] != "":
			text(section[0],Rect2(x,y,cw,28),18,GOLD)
			y += 40
		var th = text_height(section[1],cw)
		text(section[1],Rect2(x,y,cw,th),16)
		y += th+18
	end_scroll()
	button(Rect2(x,rect.end.y-66,cw,44),"RETURN","credits",{"id":"close"},"",true,true)

var credit_cache: Array = []

## assets/CREDITS.md as [heading, paragraph] pairs: headings from "#" lines, paragraphs
## joined from wrapped lines, markdown marks removed.
func credit_sections() -> Array:
	if not credit_cache.is_empty(): return credit_cache
	var source = FileAccess.get_file_as_string("res://assets/CREDITS.md") if FileAccess.file_exists("res://assets/CREDITS.md") else ""
	if source == "": source = "# Digital Age\n\nAll models, terrain, interface and campaign data were made for Digital Age. The full credits ship beside the game as CREDITS.md."
	var heading = ""
	var paragraph = ""
	for raw in (source+"\n\n").split("\n"):
		var line_text = raw.strip_edges()
		if line_text.begins_with("#") or line_text == "":
			if paragraph != "":
				credit_cache.append([heading,paragraph])
				heading = ""
				paragraph = ""
			if line_text.begins_with("#"): heading = line_text.lstrip("# ").to_upper()
			continue
		line_text = line_text.replace("`","").replace("**","").replace("*","")
		if line_text.begins_with("- "): line_text = "· "+line_text.substr(2)
		paragraph += (" " if paragraph != "" and not line_text.begins_with("· ") else ("\n" if paragraph != "" else ""))+line_text
	if credit_cache.is_empty(): credit_cache.append(["DIGITAL AGE","Credits are unavailable."])
	return credit_cache

var map_cache: Dictionary = {}
var faction_cache: Dictionary = {}

func map_definition(id: String) -> DAMapDefinition:
	if not map_cache.has(id): map_cache[id] = load("res://data/maps/"+id+".tres") as DAMapDefinition
	return map_cache[id]

func faction(id: String) -> DAFactionDefinition:
	if not faction_cache.has(id): faction_cache[id] = load("res://data/factions/"+id+".tres") as DAFactionDefinition
	return faction_cache[id]

func faction_name(id: String) -> String:
	return faction(id).display_name if faction(id) else id.capitalize()

func faction_note(id: String) -> String:
	return faction(id).description if faction(id) else ""

## A top-down sketch of a map: blocked cells, deposits and the two starts.
func draw_preview(op: Dictionary) -> void:
	var r: Rect2 = op.rect
	draw_rect(r,Color("1b2620"))
	var map: DAMapDefinition = op.map
	if map:
		var cell = r.size/float(DASimulation.SIZE)
		for c in map.obstacle_cells:
			draw_rect(Rect2(r.position+Vector2(c)*cell,cell+Vector2.ONE),Color("6a6d5c"))
		for node in map.resource_nodes:
			draw_circle(r.position+(node.get("pos",Vector2.ZERO)+Vector2(.5,.5))*cell,2.4*ui_scale,GOLD if str(node.get("kind","metal")) == "metal" else VIOLET)
		for i in mini(2,map.starts.size()):
			# Start 0 is the player's unless the sides are swapped; unknown when random.
			var mine: bool = (i == 0) != (op.side == "right")
			var tone = MUTED
			if op.side != "random":
				var owner_faction = faction(op.player if mine else op.enemy)
				tone = owner_faction.primary_color if owner_faction else (ACCENT if mine else ERROR)
				if not mine and op.player == op.enemy: tone = Color.from_hsv(fposmod(tone.h+.5,1.0),tone.s,tone.v)
			var p = r.position+(map.starts[i]+Vector2(.5,.5))*cell
			draw_rect(Rect2(p-Vector2(5,5)*ui_scale,Vector2(10,10)*ui_scale),tone)
			draw_rect(Rect2(p-Vector2(5,5)*ui_scale,Vector2(10,10)*ui_scale),Color.WHITE,false,1.0)
	draw_rect(r,STEEL,false,1.5*ui_scale)

## Save and load slots: three manual, three written automatically at checkpoints.
func layout_saves() -> void:
	var saving: bool = saves_mode == "save"
	var rect = modal_shell("SAVE GAME" if saving else "LOAD GAME",720)
	var x = rect.position.x+24
	var cw = rect.size.x-48
	text("Choose a slot to overwrite." if saving else "Manual saves, then the checkpoints saved automatically.",Rect2(x,rect.position.y+62,cw,24),14,MUTED)
	var slots: Array = DASaveGame.MANUAL_SLOTS.duplicate() if saving else DASaveGame.MANUAL_SLOTS + DASaveGame.AUTO_SLOTS
	var row = minf(62,(rect.size.y-176)/maxi(1,slots.size()))
	for i in slots.size():
		var slot: String = slots[i]
		var info: Dictionary = slot_info.get(slot,{})
		var label = ("MANUAL " if slot.begins_with("manual") else "CHECKPOINT ")+str(int(slot.get_slice("_",1))+(0 if slot.begins_with("manual") else 1))
		var subtitle = "Empty"
		if not info.is_empty():
			var definition = game.mission_catalog.get_definition(str(info.mission_id))
			var title: String = definition.title if definition else str(info.get("metadata",{}).get("title","Skirmish"))
			subtitle = title+" · "+time_text(float(info.elapsed))+" · "+str(info.saved_at).replace("T"," ")
		button(Rect2(x,rect.position.y+96+i*row,cw,row-6),label+" · "+subtitle,"save_slot" if saving else "load_slot",{"id":slot,"slot":slot,"reason":"This slot is empty."},"",saving or not info.is_empty(),i == 0 and (saving or not info.is_empty()))
	button(Rect2(x,rect.end.y-66,cw,44),"RETURN","saves",{"id":"close"},"",true,false)

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
	begin_scroll(Rect2(x,rect.position.y+110,cw,rect.size.y-206),1248)
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
	var v: Dictionary = game.settings.values
	var on = func(value: bool) -> String: return "On" if value else "Off"
	var scale_note = "" if is_equal_approx(ui_scale,float(v.ui_scale)) else " (window fits %d%%)" % roundi(ui_scale*100)
	var options = [
		["Window · "+str(v.window_mode).capitalize(),"window_mode","Windowed, borderless across the screen, or exclusive fullscreen. "+game.settings.prompt("fullscreen")+" switches fullscreen."],
		["Resolution · "+str(v.resolution).replace("x"," × "),"resolution","The window's size in Windowed mode."],
		["VSync · "+on.call(v.vsync),"vsync","Match frames to the display to stop tearing."],
		["Frame cap · "+("Off" if v.frame_cap == 0 else str(v.frame_cap)+" fps"),"frame_cap","Limit the frame rate to save power and heat."],
		["Profile · "+str(v.profile),"profile","Low reduces shadows, effects and draw distance for slower graphics cards."],
		["Shadows · "+on.call(v.shadows),"shadows","Cast shadows from the sun on terrain, buildings and units."],
		["UI scale · "+str(roundi(float(v.ui_scale)*100))+"%"+scale_note,"ui_scale","Size of the interface. 150% needs a window at least 864 pixels high."],
		["Reduced effects · "+on.call(v.reduced_effects),"effects","Fewer particles and flashes."],
		["Subtitles · "+on.call(subtitles_enabled),"subtitles","Show spoken lines as text."],
		["Colour-blind sides · "+on.call(v.colorblind),"colorblind","Draw your side in blue and the rival in orange."],
		["Sound · "+on.call(not v.muted),"sound","Turn all sound on or off. "+game.settings.prompt("events")+" does the same in a match."]]
	for i in options.size():
		button(Rect2(x+(i%2)*(cw/2+4),y+floori(i/2.0)*54,cw/2-4,44),options[i][0],options[i][1],{"tooltip":options[i][2]})
	y += ceili(options.size()/2.0)*54+4
	button(Rect2(x,y,220,42),"RESET DISPLAY","reset_category",{"category":"display"})
	y += 62
	text("KEYBOARD · Select a binding, then press a key",Rect2(x,y,cw,28),16,ACCENT)
	y += 38
	var actions = ["pause","manual","save","load","attack","stop","speed","events","home","fullscreen","alert"]
	for i in actions.size():
		var action: String = actions[i]
		button(Rect2(x+(i%2)*(cw/2+4),y+floori(i/2.0)*52,cw/2-4,44),action.capitalize()+" · "+("Press key… (Esc cancels)" if rebind_action == action else game.settings.prompt(action)),"rebind",{"action":action},"",true,rebind_action==action)
	y += 322
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
		["03 / EVOLVE","Train Workers and advance ages at your Core. Network unlocks Disruptors and Towers; Singularity unlocks Siege Walkers. Fabricators manufacture your army. Research Labs improve resources, buildings and the military, five levels each; every Lab runs one project at a time."],
		["04 / CONQUER","Sentinels counter armoured units such as Disruptors. Disruptors counter heavy units such as Walkers. Walkers destroy buildings. Disruptor and Walker shells travel and splash. Every combat unit has one ability on the first grid slot: the Scout's sweep reveals an area, the Sentinel fires faster, the Disruptor's EMP stuns, the Walker braces for range. Scout first: enemies outside your vision cannot be targeted, though buildings you have seen stay marked."],
["04 / GROUND AND FACTIONS","Roads carry units a quarter faster. Rough ground around ruins slows everything that does not hover. Units on high ground see two cells farther and shoot one cell farther. Each faction fields one unit of its own from the Network age: Origin's Warden shields nearby units, the Foundry's Mortar shells from long range, the Lattice's Phantom stays unseen until an enemy comes close."],
		["05 / COMMAND","Click or drag to select; Shift adds units; double-click selects every unit of that type in view. The command grid uses the keys Q to T, A to G and Z to B in the order shown on each slot. Right-click moves, gathers, attacks, repairs, or sets a rally point. "+game.settings.prompt("attack")+": attack-move. "+game.settings.prompt("stop")+": stop. Hold position keeps units where they stand; Patrol walks them back and forth, engaging on the way. Cancel on a building's command grid removes its last queued item, or stops its research, and refunds the cost. Ctrl+1–9 saves groups; 1–9 recalls them."],
		["06 / NAVIGATE","Arrows, screen edges, or middle drag pan; the wheel zooms. Minimap left-click moves the camera; right-click issues orders. "+game.settings.prompt("pause")+": pause. "+game.settings.prompt("manual")+": manual. "+game.settings.prompt("fullscreen")+": fullscreen. "+game.settings.prompt("alert")+": jump to the last alert, which also pings the minimap."]
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
	elif action in ["load", "load_slot"]: explanation = "Loading replaces unsaved progress. Your existing saved game will be kept."
	text(explanation,Rect2(x,rect.position.y+170,cw,62),18,MUTED)
	button(Rect2(x,rect.end.y-204,cw,48),"CANCEL","confirm_cancel",{},"",true,true)
	if action not in ["reset_all", "load", "load_slot"]:
		button(Rect2(x,rect.end.y-146,cw,48),"SAVE AND CONTINUE","confirm_save")
	button(Rect2(x,rect.end.y-88,cw,48),"RESET PREFERENCES" if action == "reset_all" else ("LOAD SAVED GAME" if action in ["load", "load_slot"] else "CONTINUE WITHOUT SAVING"),"confirm_proceed")

func layout_notification() -> void:
	# Above modals and below their headers; world notifications use a reserved strip.
	var r = Rect2((w-minf(800,w-64))/2,h-76,minf(800,w-64),66) if modal_active() else Rect2(reserved_regions.notification.position/ui_scale,reserved_regions.notification.size/ui_scale)
	if game.mode == "menu" and not manual and not settings_open and confirmation.is_empty():
		r = Rect2(left+32,menu_text_y,(span-96)/2,maxf(40,minf(90,h-204-menu_text_y)))
	if not modal_active() and (game.build_kind != "" or game.attack_mode or game.rally_mode or game.patrol_mode or game.ability_mode):
		r.position.y -= 64
	if not modal_active() and reserved_regions.has("subtitle") and to_view(r).intersects(reserved_regions.subtitle):
		r.position.y = reserved_regions.subtitle.position.y/ui_scale-r.size.y-8
	panel(r,BG)
	var prefix = {"error":"ERROR · ","success":"COMPLETE · ","alert":"ALERT · "}.get(severity,"NOTICE · ")
	text(prefix+message,Rect2(r.position+Vector2(12,6),r.size-Vector2(24,12)),14,{"error":ERROR,"success":ACCENT,"alert":GOLD}.get(severity,TEXT))
	reserved_regions.message = to_view(r)
	blocked_regions.append(to_view(r))

func layout_tooltip() -> void:
	var value = ""
	var anchor = Rect2()
	for b in buttons:
		if b.rect.has_point(mouse) or (b.id == focused and focus_keyboard):
			value = str(b.payload.get("reason","")) if not b.enabled else ""
			var details = str(b.payload.get("tooltip",""))
			if details != "": value += ("\n" if value != "" else "")+details
			anchor = b.rect
			break
	if value == "":
		for entry in text_bounds:
			if entry.source != "" and entry.rect.has_point(mouse):
				value = entry.source
				anchor = entry.rect
				break
	if value == "": return
	var tw = minf(340,span-48)
	var th = minf(230,text_height(value,tw-24,14)+18)
	# Beside the control it describes: above it, or below when there is no room.
	var a = Rect2(anchor.position/ui_scale,anchor.size/ui_scale)
	var r = Rect2(a.get_center().x-tw/2,a.position.y-th-8,tw,th)
	if r.position.y < 4: r.position.y = a.end.y+8
	r.position.x = clampf(r.position.x,left+8,maxf(left+8,left+span-tw-8))
	r.position.y = clampf(r.position.y,4,maxf(4,h-th-4))
	if game.mode == "menu" and not overlay_open():
		r = Rect2(left+32,140,(span-96)/2,minf(220,th+40))
	plate_panel(r,"panel",Color(BG.r,BG.g,BG.b,.97),STEEL)
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
			"frame":
				var r: Rect2 = op.rect
				if plate("dock"):
					draw_style_box(plate("dock"),r)
				else:
					draw_polygon(PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]),PackedColorArray([op.top,op.top,op.bottom,op.bottom]))
					draw_rect(r,Color(0,0,0,.75),false,1)
					draw_rect(r.grow(-1),STEEL,false,1)
					draw_line(r.position+Vector2(2,2.5),Vector2(r.end.x-2,r.position.y+2.5),Color(1,1,1,.12),1)
				var tick = 14.0*ui_scale
				for corner in [r.position+Vector2(3,3),Vector2(r.end.x-3,r.position.y+3)]:
					var dir = 1.0 if corner.x < r.get_center().x else -1.0
					draw_line(corner,corner+Vector2(tick*dir,0),op.accent,2*ui_scale)
					draw_line(corner,corner+Vector2(0,tick),op.accent,2*ui_scale)
			"plate": draw_style_box(plate(op.name),op.rect)
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
				var skin = "button"
				if not b.enabled: skin = "button_disabled"
				elif pressed == b.id and over: skin = "button_pressed"
				elif over: skin = "button_hover"
				if plate(skin):
					# Rendered plate per state; the active command and keyboard focus are lit in the accent colour.
					draw_style_box(plate(skin),b.rect)
					if b.primary: draw_rect(b.rect.grow(-3),Color(ACCENT.r,ACCENT.g,ACCENT.b,.16))
					if b.primary or focused==b.id: draw_rect(b.rect.grow(-1),ACCENT,false,1.5)
				else:
					draw_style_box(style(color,ACCENT if focused==b.id or b.primary else (LINE if b.enabled else LINE_SOFT)),b.rect)
				# A machined bevel: light along the top edge, shade along the bottom.
				if not plate(skin) and b.enabled and not (pressed == b.id and over):
					draw_line(b.rect.position+Vector2(3,1.5),Vector2(b.rect.end.x-3,b.rect.position.y+1.5),Color(1,1,1,.10),1)
					draw_line(Vector2(b.rect.position.x+3,b.rect.end.y-1.5),b.rect.end-Vector2(3,1.5),Color(0,0,0,.35),1)
				if focused==b.id and focus_keyboard: draw_rect(b.rect.grow(-3),ACCENT,false,2)
			"map": draw_minimap(op.rect)
			"preview": draw_preview(op)
	if not modal_active(): draw_world_overlay()

func refresh_map() -> void:
	if not game or not map_image: return
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var p = Vector2i(x,y)
			var color = Color("0a0e13")
			if game.sim.explored[0].has(p):
				var lit: bool = game.sim.visible[0].has(p)
				color = Color("41563f") if lit else Color("26332c")
				if game.sim.roads.has(p): color = Color("505650") if lit else Color("2f3431")
				if game.sim.rough.has(p): color = Color("5b4d37") if lit else Color("362f24")
				if game.sim.high.has(p): color = Color("7d8a78") if lit else Color("454c44")
				if game.sim.obstacles.has(p): color = Color("6a6d5c")
			map_image.set_pixel(x,y,color)
	map_scaled.copy_from(map_image)
	map_scaled.resize(DASimulation.SIZE*3,DASimulation.SIZE*3,Image.INTERPOLATE_NEAREST)
	map_texture.update(map_scaled)

## The minimap is the map seen from the fixed camera: a 2:1 diamond whose
## screen axes match the battlefield's, so the view outline is a plain rectangle.
func map_point(p: Vector2) -> Vector2:
	var yaw = DABattlefield.CAMERA_YAW
	var q = p-Vector2.ONE*DASimulation.SIZE*.5
	var half = DASimulation.SIZE*.5*sqrt(2.0)
	return map_rect.get_center()+Vector2(q.dot(Vector2(cos(yaw),-sin(yaw))),q.dot(Vector2(sin(yaw),cos(yaw))))/half*map_rect.size*.5

func map_world(view: Vector2) -> Vector2:
	var yaw = DABattlefield.CAMERA_YAW
	var n = (view-map_rect.get_center())/(map_rect.size*.5)*DASimulation.SIZE*.5*sqrt(2.0)
	var p = Vector2.ONE*DASimulation.SIZE*.5+Vector2(cos(yaw),-sin(yaw))*n.x+Vector2(sin(yaw),cos(yaw))*n.y
	return p.clamp(Vector2.ZERO,Vector2.ONE*DASimulation.SIZE)

func draw_minimap(rect: Rect2) -> void:
	draw_rect(rect.grow(3*ui_scale),Color(BG.r,BG.g,BG.b,.75))
	var origin = map_point(Vector2.ZERO)
	var size_cells = float(DASimulation.SIZE)
	draw_set_transform_matrix(Transform2D((map_point(Vector2(size_cells,0))-origin)/size_cells,(map_point(Vector2(0,size_cells))-origin)/size_cells,origin))
	draw_texture_rect(map_texture,Rect2(0,0,size_cells,size_cells),false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for e in game.sim.entities.values():
		if not game.sim.known(0,e) or e.get("amount",1) <= 0: continue
		var p: Vector2 = map_point(e.pos)
		var color = game.sim.faction_color(e.owner) if e.owner >= 0 else (GOLD if e.kind=="metal" else VIOLET)
		if e.building: draw_rect(Rect2(p-Vector2(2.5,2.5)*ui_scale,Vector2(5,5)*ui_scale),color)
		else: draw_circle(p,1.7*ui_scale,color)
	for item in pings:
		# Two rings expanding from the spot, fading as they grow.
		var centre: Vector2 = map_point(item.pos)
		var tone: Color = ERROR if item.level == "danger" else ACCENT
		for phase in [0.0, 0.5]:
			var t = fmod((3.0-item.left)*1.2+phase,1.0)
			draw_arc(centre,(3+t*13)*ui_scale,0,TAU,24,Color(tone.r,tone.g,tone.b,(1.0-t)*minf(1.0,item.left)),1.5*ui_scale,true)
	var view = Rect2()
	var first = true
	for screen in [world_rect.position,Vector2(world_rect.end.x,world_rect.position.y),world_rect.end,Vector2(world_rect.position.x,world_rect.end.y)]:
		var corner = map_point(game.field.ground_at(screen)).clamp(rect.position,rect.end)
		view = Rect2(corner,Vector2.ZERO) if first else view.expand(corner)
		first = false
	draw_rect(view,Color(BG.r,BG.g,BG.b,.7),false,3*ui_scale)
	draw_rect(view,Color.WHITE,false,1.5*ui_scale)
	var outline = PackedVector2Array()
	for corner in [Vector2.ZERO,Vector2(size_cells,0),Vector2(size_cells,size_cells),Vector2(0,size_cells),Vector2.ZERO]: outline.append(map_point(corner))
	draw_polyline(outline,STEEL,1.5*ui_scale,true)

func draw_world_overlay() -> void:
	for e in game.sim.entities.values():
		if e.owner < 0 or not game.sim.known(0,e): continue
		# A building remembered in the fog shows no health: its state is not known any more.
		if e.owner != 0 and not game.sim.seen(0,e.pos): continue
		if not game.selected.has(e.id) and e.hp>=e.max_hp and e.complete: continue
		var p: Vector2 = game.field.screen_at(e.pos, bar_height(e))
		if not is_world(p): continue
		var width = 54 if e.building else 32
		draw_rect(Rect2(p.x-width/2.0,p.y,width,6),BG)
		draw_rect(Rect2(p.x-width/2.0,p.y,width*clampf(e.hp/e.max_hp,0,1),4),ACCENT if e.owner==0 else ERROR)
	if game.build_kind != "" and is_world(mouse):
		# The footprint the building will stand on, cell by cell: green where it fits, red where it does not.
		var radius: int = game.sim.catalog.buildings[game.build_kind].radius
		var centre: Vector2 = game.field.ground_at(mouse).round()
		var fits: bool = game.sim.placement_error(0,game.build_kind,centre) == ""
		var tone = GREEN if fits else ERROR
		for dx in range(-radius,radius+1):
			for dy in range(-radius,radius+1):
				var cell = PackedVector2Array()
				for corner in [Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)]:
					cell.append(game.field.screen_at(centre+Vector2(dx,dy)+corner*.92))
				draw_colored_polygon(cell,Color(tone.r,tone.g,tone.b,.2))
				cell.append(cell[0])
				draw_polyline(cell,Color(tone.r,tone.g,tone.b,.75),1.0,true)
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
		var target = map_world(p)
		if right:
			game.issue("patrol" if game.patrol_mode else ("attack_move" if game.attack_mode else "move"),{"pos":target})
			game.attack_mode = false
			game.patrol_mode = false
		elif game.ability_mode:
			# A Sensor sweep can be aimed straight on the minimap.
			game.issue("ability",{"pos":target})
			game.ability_mode = false
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
					focus_keyboard = false
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
	if not b.enabled:
		toast(str(b.payload.get("reason","This action is unavailable.")),"error")
		game.audio.play("ui_error")
	else:
		game.audio.play("ui_click")
		game.ui_action(b.action,b.payload)
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
		focus_keyboard = true
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

