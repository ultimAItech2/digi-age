class_name DASprites
extends RefCounted

## Sprite cards: every building, unit and deposit drawn as a camera-facing
## card in the 3D battlefield. The pictures are rendered from the Blender
## models in tools/sprites into one atlas per kind (assets/sprites/rendered,
## described by DASpriteAtlasData): build stages and a wreck for buildings,
## eight facings of idle, move and attack frames for units, depletion states
## for deposits, each with a mask of the parts painted in the faction colour.
## A kind without an atlas keeps its 3D model. This file owns the lookup,
## texture loading, card geometry and the HUD portraits cut from the same images.

const PORTRAIT_SIZE = 128

static var textures: Dictionary = {}
static var portraits: Dictionary = {}

const ATLAS_DATA = preload("res://scripts/sprite_atlas_data.gd")
const RENDERED = "res://assets/sprites/rendered/%s.png"
const ELEVATION_SIN = 0.5      # sin of the camera's 30 degree elevation
const ELEVATION_COS = 0.8660254

static var atlas_cache: Dictionary = {}
static var masks: Dictionary = {}

## The atlas entry for a kind, or {} when it has no rendered atlas on disk.
static func atlas(kind: String) -> Dictionary:
	if not atlas_cache.has(kind):
		var entry: Dictionary = ATLAS_DATA.KINDS.get(kind, {})
		atlas_cache[kind] = entry if not entry.is_empty() and sprite_available(RENDERED % kind) else {}
	return atlas_cache[kind]

static func sprite_path(kind: String) -> String:
	return RENDERED % kind if not atlas(kind).is_empty() else ""

static func load_texture(path: String) -> Texture2D:
	if DABattlefield.imported(path):
		return load(path)
	if FileAccess.file_exists(path):
		var image = Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			image.generate_mipmaps()
			return ImageTexture.create_from_image(image)
	return null

## The faction-colour mask that goes with an atlas, or null.
static func mask(kind: String) -> Texture2D:
	if not masks.has(kind):
		masks[kind] = load_texture("res://assets/sprites/rendered/%s_mask.png" % kind) if not atlas(kind).is_empty() else null
	return masks[kind]

## Atlas cell of a building, deposit or scenery state ("stage0".."stage2",
## "complete", "idle1".., "wreck", "full", "half", "low", "v0"..). States run
## left to right and wrap onto further rows; an unknown state gives the main frame.
static func state_cell(kind: String, state: String) -> Vector2i:
	var entry = atlas(kind)
	var index: int = entry.get("states", []).find(state)
	if index < 0:
		var main: Array = entry.get("main", [0, 0])
		return Vector2i(main[0], main[1])
	return Vector2i(index % int(entry.cols), index / int(entry.cols))

## The frame of a finished building's idle loop at `time` seconds ("complete" is its first frame).
static func idle_cell(kind: String, time: float) -> Vector2i:
	var states: Array = atlas(kind).get("states", [])
	var count = 1
	while states.has("idle%d" % count):
		count += 1
	var frame = int(time * 8.0) % count
	return state_cell(kind, "complete" if frame == 0 else "idle%d" % frame)

## Column of a unit's one-shot death animation `age` seconds after it fell (holds the last frame).
static func death_column(kind: String, age: float) -> int:
	var spec: Array = atlas(kind).get("anims", {}).get("death", [0, 1, 1.0])
	return int(spec[0]) + mini(int(spec[1]) - 1, int(age * float(spec[2])))

## Column of a unit animation frame at `time` seconds.
static func anim_column(kind: String, anim: String, time: float) -> int:
	var spec: Array = atlas(kind).get("anims", {}).get(anim, [0, 1, 1.0])
	return int(spec[0]) + (int(time * float(spec[2])) % int(spec[1]))

## Atlas row for a unit moving along `direction` (cell x, cell y): eight facings, 0 along +x, turning toward +y.
static func facing_row(direction: Vector2) -> int:
	return posmod(roundi(atan2(direction.y, direction.x) / (PI / 4.0)), 8)

## A sprite is usable when its PNG is on disk (source runs, clean clones) or
## when Godot's imported artefact exists: exported packages ship the import,
## not the PNG, so the source file alone must never gate the feature.
static func sprite_available(path: String) -> bool:
	return path != "" and (DABattlefield.imported(path) or FileAccess.file_exists(path))

static func has_sprite(kind: String) -> bool:
	return sprite_available(sprite_path(kind))

## The sprite as a texture: the imported (mipmapped) resource when Godot has
## imported it, otherwise the PNG decoded directly so headless runs on a clean
## clone work without an import step. Null when the kind has no sprite.
static func texture(kind: String) -> Texture2D:
	if textures.has(kind):
		return textures[kind]
	var result: Texture2D = load_texture(sprite_path(kind))
	textures[kind] = result
	return result

## Square HUD portrait cut from the sprite's texture, so it works wherever the
## texture does (exports included). Null when the kind has no sprite.
static func portrait(kind: String) -> Texture2D:
	if portraits.has(kind):
		return portraits[kind]
	var result: Texture2D = null
	var entry = atlas(kind)
	var tex = texture(kind)
	if entry.is_empty() or tex == null:
		result = portrait_from_texture(tex)
	else:
		# The opaque box of the kind's main frame, cut out of the atlas.
		var image: Image = tex.get_image()
		if image and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			var box: Array = entry.box
			var region = Rect2i(int(entry.main[0]) * int(entry.frame[0]) + int(box[0]), int(entry.main[1]) * int(entry.frame[1]) + int(box[1]), int(box[2]) - int(box[0]), int(box[3]) - int(box[1]))
			result = portrait_from_texture(ImageTexture.create_from_image(image.get_region(region)))
	portraits[kind] = result
	return result

## Pads a texture's image to a square on its longer side and scales it to PORTRAIT_SIZE.
static func portrait_from_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var image: Image = tex.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var side = maxi(image.get_width(), image.get_height())
	var square = Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.fill(Color(0, 0, 0, 0))
	var offset = Vector2i((side - image.get_width()) / 2, (side - image.get_height()) / 2)
	square.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), offset)
	square.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(square)

# --- Cards ------------------------------------------------------------------

const CONTACT_SCALE = 1.3
## Age of AI draws its cast shadows at 38% black on a 2D canvas (sRGB); Godot
## blends in linear space, where 0.65 darkens bright ground by the same amount.
const CAST_ALPHA = 0.65
const CONTACT_ALPHA = 0.5

static var card_shader: Shader
static var shadow_shader: Shader
static var ground_shader: Shader
static var card_materials: Dictionary = {}
static var shadow_materials: Dictionary = {}
static var ground_materials: Dictionary = {}
static var shadow_meshes: Array = []
## The Compatibility renderer can address only about 256 instances with per-instance
## shader parameters (a uniform block of 4,096 items, 16 reserved per instance, and a
## card plus its shadow are two). A large battle exceeds that and the cards past the
## limit lose their frame and colour. There each card gets its own material, from a
## variant of the shader that reads the same three values as ordinary uniforms.
static var own_materials: bool = false
static var plain_shaders: Dictionary = {}

## `shader` with its per-instance uniforms turned into ordinary ones.
static func plain(source: Shader) -> Shader:
	if not plain_shaders.has(source):
		var variant = Shader.new()
		variant.code = source.code.replace("instance uniform", "uniform")
		plain_shaders[source] = variant
	return plain_shaders[source]

## The material a card or shadow draws with: the shared one, or its own copy when
## per-instance parameters are not available in quantity.
static func instance_material(shared: ShaderMaterial) -> ShaderMaterial:
	if not own_materials:
		return shared
	var own: ShaderMaterial = shared.duplicate()
	own.shader = plain(shared.shader)
	return own

static func set_param(child: GeometryInstance3D, name: String, value: Variant) -> void:
	if own_materials and child.material_override is ShaderMaterial and plain_shaders.values().has(child.material_override.shader):
		child.material_override.set_shader_parameter(name, value)
	else:
		child.set_instance_shader_parameter(name, value)

## A card's per-instance value ("cell", "team" or "tint"), whichever way it is stored.
static func param(child: GeometryInstance3D, name: String) -> Variant:
	if child.material_override is ShaderMaterial and plain_shaders.values().has(child.material_override.shader):
		return child.material_override.get_shader_parameter(name)
	return child.get_instance_shader_parameter(name)
static var shadows_enabled: bool = true
static var sun_dir: Vector2 = Vector2(0.165, 0.986)
static var sun_length: float = 0.9

static func group(kind: String) -> String:
	return atlas(kind).get("group", "")

## Card size in world units (one map cell is one unit). The atlas is rendered
## at a fixed scale, so the frame is exactly this many cells on screen.
static func card_size(kind: String, _footprint_cells: int) -> Vector2:
	var entry = atlas(kind)
	if entry.is_empty():
		return Vector2.ZERO
	return Vector2(entry.frame[0], entry.frame[1]) / float(entry.ppu)

## How far the card's base sits toward the camera from the node. The origin is
## `anchor` pixels above the frame's bottom edge; a ground point that far down
## the screen lies this far toward the camera.
static func anchor_offset(kind: String, _footprint_cells: int) -> float:
	var entry = atlas(kind)
	if entry.is_empty():
		return 0.0
	return float(entry.anchor) / float(entry.ppu) / ELEVATION_SIN

## Screen-space box of the drawn picture relative to the node's ground point,
## in cells: x from the centre line, y up from the origin.
static func drawn_box(kind: String, footprint_cells: int) -> Rect2:
	var entry = atlas(kind)
	var size = card_size(kind, footprint_cells)
	if entry.is_empty():
		return Rect2()
	var ppu = float(entry.ppu)
	var box: Array = entry.box
	var x0 = float(box[0]) / ppu - size.x * 0.5
	var y0 = (float(entry.frame[1]) - float(box[3]) - float(entry.anchor)) / ppu
	return Rect2(x0, y0, float(box[2] - box[0]) / ppu, float(box[3] - box[1]) / ppu)

## World height whose screen position is just above the drawn picture.
static func bar_height(kind: String, footprint_cells: int) -> float:
	return drawn_box(kind, footprint_cells).end.y / ELEVATION_COS + 0.25

static func is_card(node: Node3D) -> bool:
	return node.get_child_count() > 0 and node.get_child(0) is MeshInstance3D and node.get_child(0).name == "Card"

static func shader(path: String) -> Shader:
	return load(path)

static func card_material(kind: String, footprint_cells: int) -> ShaderMaterial:
	if not card_materials.has(kind):
		if not card_shader:
			card_shader = shader("res://assets/shaders/sprite_card.gdshader")
		var m = ShaderMaterial.new()
		m.shader = card_shader
		m.set_shader_parameter("tex", texture(kind))
		m.set_shader_parameter("anchor_offset", anchor_offset(kind, footprint_cells))
		var entry = atlas(kind)
		m.set_shader_parameter("grid", Vector2(entry.cols, entry.rows))
		if mask(kind):
			m.set_shader_parameter("mask_tex", mask(kind))
			m.set_shader_parameter("mask_on", 1.0)
		card_materials[kind] = m
	return card_materials[kind]

static func shadow_material(kind: String, _footprint_cells: int) -> ShaderMaterial:
	if not shadow_materials.has(kind):
		if not shadow_shader:
			shadow_shader = shader("res://assets/shaders/sprite_shadow.gdshader")
		var m = ShaderMaterial.new()
		m.shader = shadow_shader
		m.set_shader_parameter("tex", texture(kind))
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("shadow_length", sun_length)
		m.set_shader_parameter("strength", CAST_ALPHA)
		var entry = atlas(kind)
		m.set_shader_parameter("grid", Vector2(entry.cols, entry.rows))
		# The silhouette stands on the picture's origin row, not on the frame's bottom edge.
		m.set_shader_parameter("base_height", float(entry.anchor) / float(entry.ppu))
		shadow_materials[kind] = m
	return shadow_materials[kind]

static func ground_material(disc: Color, ring_frac: float) -> ShaderMaterial:
	var key = disc.to_html() + "/" + str(snappedf(ring_frac, 0.01))
	if not ground_materials.has(key):
		if not ground_shader:
			ground_shader = shader("res://assets/shaders/sprite_ground.gdshader")
		var m = ShaderMaterial.new()
		m.shader = ground_shader
		m.set_shader_parameter("disc", disc)
		m.set_shader_parameter("contact_alpha", CONTACT_ALPHA)
		m.set_shader_parameter("ring_frac", ring_frac)
		ground_materials[key] = m
	return ground_materials[key]

## Contact shadow plus owner disc under `parent` (a card's Fx node, or a 3D
## model entity so mixed kinds share the depth cues). `disc.a == 0` hides the ring.
static func ground_only(parent: Node3D, disc: Color, diameter: float, ring_radius: float = -1.0) -> MeshInstance3D:
	var ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane = PlaneMesh.new()
	plane.size = Vector2(diameter, diameter)
	ground.mesh = plane
	ground.position.y = 0.03
	var radius = ring_radius if ring_radius >= 0.0 else diameter * 0.33
	ground.material_override = ground_material(disc, clampf(radius / (diameter * 0.5), 0.1, 0.95))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ground)
	return ground

## A sprite card entity: child(0) "Card" (the MeshInstance3D main.gd picks
## against), then "Fx" with the cast "Shadow" and the "Ground" disc.
static func card(kind: String, side: int, footprint_cells: int, accent: Color, with_ground: bool = true) -> Node3D:
	var root = Node3D.new()
	root.name = kind
	var size = card_size(kind, footprint_cells)
	var quad = QuadMesh.new()
	quad.size = size
	quad.center_offset = Vector3(0, size.y * 0.5, 0)
	# The drawn base sits anchor_offset toward the camera in any yaw, so the
	# box (used for culling and by main.gd's pick_screen) grows by it all round.
	var hw = maxf(size.x * 0.5, footprint_cells * 0.5) + anchor_offset(kind, footprint_cells)
	var body = MeshInstance3D.new()
	body.name = "Card"
	body.mesh = quad
	body.material_override = instance_material(card_material(kind, footprint_cells))
	body.custom_aabb = AABB(Vector3(-hw, 0, -hw), Vector3(hw * 2, size.y, hw * 2))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var fx = Node3D.new()
	fx.name = "Fx"
	root.add_child(fx)
	var shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = quad
	shadow.material_override = instance_material(shadow_material(kind, footprint_cells))
	var reach = hw + size.y * 1.6
	shadow.custom_aabb = AABB(Vector3(-reach, 0, -reach), Vector3(reach * 2, size.y, reach * 2))
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.visible = shadows_enabled
	fx.add_child(shadow)
	shadow_meshes.append(shadow)
	var is_unit = group(kind) == "units"
	var diameter = CONTACT_SCALE * (1.0 if is_unit else footprint_cells * sqrt(2.0))
	var ring_radius = 0.65 if is_unit else (footprint_cells - 1) * 0.5 + 0.4
	var disc = accent if side >= 0 else Color(accent.r, accent.g, accent.b, 0.0)
	if with_ground:
		ground_only(fx, disc, diameter, ring_radius)
	var entry = atlas(kind)
	set_frame(root, int(entry.main[0]), int(entry.main[1]))
	set_team(root, accent if side >= 0 else Color(0.62, 0.64, 0.66))
	return root

## The four world-space corners of the picture as drawn for `camera`: only its
## opaque part, so the empty frame around it is not clickable. Width runs along
## the camera's right, height along its up (the billboard leans to face it).
static func card_corners(node: Node3D, kind: String, footprint_cells: int, camera: Camera3D) -> PackedVector3Array:
	var basis = camera.global_transform.basis
	var fwd = Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var box = drawn_box(kind, footprint_cells)
	var origin = node.global_position
	var low = origin + basis.y * box.position.y if box.position.y >= 0.0 else origin - fwd * (-box.position.y / ELEVATION_SIN)
	var left = basis.x * box.position.x
	var right = basis.x * box.end.x
	var up = basis.y * box.size.y
	return PackedVector3Array([low + left, low + right, low + right + up, low + left + up])

## Which atlas cell a card shows: the column (state or animation frame) and row (facing).
static func set_frame(node: Node3D, column: int, row: int) -> void:
	for child in [node.get_node_or_null("Card"), node.get_node_or_null("Fx/Shadow")]:
		if child:
			set_param(child, "cell", Vector2(column, row))

## The colour the masked parts of the picture are painted in.
static func set_team(node: Node3D, color: Color) -> void:
	var child = node.get_node_or_null("Card")
	if child:
		set_param(child, "team", color)

static func set_tint(node: Node3D, color: Color) -> void:
	for child in [node.get_node_or_null("Card"), node.get_node_or_null("Fx/Shadow")]:
		if child:
			set_param(child, "tint", color)

# --- Sun ----------------------------------------------------------------------

## Horizontal direction light travels for a DirectionalLight3D with these
## rotation degrees (pitch, yaw, 0): shadows fall this way on the ground.
static func sun_ground_direction(sun_rotation_degrees: Vector3) -> Vector2:
	var p = deg_to_rad(sun_rotation_degrees.x)
	var y = deg_to_rad(sun_rotation_degrees.y)
	return Vector2(-cos(p) * sin(y), -cos(p) * cos(y)).normalized()

## Ground distance a point one unit up casts its shadow, from the sun's elevation.
static func shadow_length(sun_rotation_degrees: Vector3) -> float:
	return clampf(1.0 / tan(deg_to_rad(-sun_rotation_degrees.x)), 0.5, 1.6)

static func set_sun(dir: Vector2, length: float) -> void:
	sun_dir = dir
	sun_length = length
	for m in shadow_materials.values():
		m.set_shader_parameter("sun_dir", dir)
		m.set_shader_parameter("shadow_length", length)
	# Shadows that carry their own material follow the sun too.
	for shadow in shadow_meshes:
		if is_instance_valid(shadow) and shadow.material_override is ShaderMaterial and not shadow_materials.values().has(shadow.material_override):
			shadow.material_override.set_shader_parameter("sun_dir", dir)
			shadow.material_override.set_shader_parameter("shadow_length", length)

static func set_shadows_enabled(on: bool) -> void:
	shadows_enabled = on
	var alive: Array = []
	for shadow in shadow_meshes:
		if is_instance_valid(shadow):
			shadow.visible = on
			alive.append(shadow)
	shadow_meshes = alive
