class_name DASprites
extends RefCounted

## Photoreal sprite cards: the Age of AI sprite set drawn as camera-facing
## cards in the 3D battlefield (assets/sprites/README.md). This file owns the
## kind-to-sprite table, texture loading and the HUD portraits cut from the
## same images. Kinds without a file keep their Blender models.

const SPRITES = {
	"core": "buildings/ai_core",
	"fabricator": "buildings/mech_hangar",
	"data_center": "buildings/data_center",
	"generator": "buildings/fusion_reactor",
	"depot": "buildings/factory",
	"tower": "buildings/shield_generator",
	"worker": "units/drone",
	"scout": "units/swarm",
	"sentinel": "units/mech",
	"disruptor": "units/tank",
	"walker": "units/walker",
	"metal": "props/gold",
	"data": "props/archive",
}
## Units drawn 1.9 cells tall instead of 1.4 (Age of AI: armour, siege, mounted).
const LARGE_UNITS = ["disruptor", "walker"]
const PORTRAIT_SIZE = 128

static var textures: Dictionary = {}
static var portraits: Dictionary = {}

static func sprite_path(kind: String) -> String:
	if not SPRITES.has(kind):
		return ""
	return "res://assets/sprites/%s.png" % SPRITES[kind]

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
	var result: Texture2D = null
	var path = sprite_path(kind)
	if DABattlefield.imported(path):
		result = load(path)
	elif FileAccess.file_exists(path):
		var image = Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			result = ImageTexture.create_from_image(image)
	textures[kind] = result
	return result

## Square HUD portrait cut from the sprite's texture, so it works wherever the
## texture does (exports included). Null when the kind has no sprite.
static func portrait(kind: String) -> Texture2D:
	if portraits.has(kind):
		return portraits[kind]
	var result = portrait_from_texture(texture(kind))
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

const BUILDING_WIDTH_FACTOR = 1.05
const UNIT_HEIGHT = 1.4
const UNIT_HEIGHT_LARGE = 1.9
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
static var shadows_enabled: bool = true
static var sun_dir: Vector2 = Vector2(0.165, 0.986)
static var sun_length: float = 0.9

static func group(kind: String) -> String:
	return SPRITES[kind].get_slice("/", 0) if SPRITES.has(kind) else ""

## Card size in world units (one map cell is one unit). Buildings are as wide
## as their footprint diagonal (the sprite shows the footprint as a diamond)
## plus 5 percent; units are a fixed height; deposits span one cell diagonal.
static func card_size(kind: String, footprint_cells: int) -> Vector2:
	var tex = texture(kind)
	if tex == null:
		return Vector2.ZERO
	var aspect = float(tex.get_height()) / float(tex.get_width())
	match group(kind):
		"units":
			var h = UNIT_HEIGHT_LARGE if kind in LARGE_UNITS else UNIT_HEIGHT
			return Vector2(h / aspect, h)
		"buildings":
			var w = footprint_cells * sqrt(2.0) * BUILDING_WIDTH_FACTOR
			return Vector2(w, w * aspect)
		_:
			var w = sqrt(2.0)
			return Vector2(w, w * aspect)

## How far the card's base sits toward the camera from the node: half the
## footprint diagonal, so the diamond's near vertex is the near footprint corner.
static func anchor_offset(kind: String, footprint_cells: int) -> float:
	return 0.0 if group(kind) == "units" else footprint_cells * sqrt(2.0) * 0.5

static func bar_height(kind: String, footprint_cells: int) -> float:
	return card_size(kind, footprint_cells).y + 0.3

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
		m.set_shader_parameter("card_height", card_size(kind, footprint_cells).y)
		card_materials[kind] = m
	return card_materials[kind]

static func shadow_material(kind: String, footprint_cells: int) -> ShaderMaterial:
	if not shadow_materials.has(kind):
		if not shadow_shader:
			shadow_shader = shader("res://assets/shaders/sprite_shadow.gdshader")
		var m = ShaderMaterial.new()
		m.shader = shadow_shader
		m.set_shader_parameter("tex", texture(kind))
		m.set_shader_parameter("anchor_offset", anchor_offset(kind, footprint_cells))
		m.set_shader_parameter("card_height", card_size(kind, footprint_cells).y)
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("shadow_length", sun_length)
		m.set_shader_parameter("strength", CAST_ALPHA)
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
	body.material_override = card_material(kind, footprint_cells)
	body.custom_aabb = AABB(Vector3(-hw, 0, -hw), Vector3(hw * 2, size.y, hw * 2))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var fx = Node3D.new()
	fx.name = "Fx"
	root.add_child(fx)
	var shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = quad
	shadow.material_override = shadow_material(kind, footprint_cells)
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
	return root

## The four world-space corners of the card as drawn for `camera`: base
## centre moved anchor_offset toward the camera, width along the camera's
## right, height along the camera's up (the billboard leans to face it).
static func card_corners(node: Node3D, kind: String, footprint_cells: int, camera: Camera3D) -> PackedVector3Array:
	var size = card_size(kind, footprint_cells)
	var basis = camera.global_transform.basis
	var fwd = Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var base = node.global_position - fwd * anchor_offset(kind, footprint_cells)
	var half = basis.x * size.x * 0.5
	var up = basis.y * size.y
	return PackedVector3Array([base - half, base + half, base + half + up, base - half + up])

static func set_rise(node: Node3D, progress: float) -> void:
	for child in [node.get_node_or_null("Card"), node.get_node_or_null("Fx/Shadow")]:
		if child:
			child.set_instance_shader_parameter("rise", clampf(progress, 0.0, 1.0))

static func set_flip(node: Node3D, flipped: bool) -> void:
	for child in [node.get_node_or_null("Card"), node.get_node_or_null("Fx/Shadow")]:
		if child:
			child.set_instance_shader_parameter("flip", 1.0 if flipped else 0.0)

static func set_tint(node: Node3D, color: Color) -> void:
	for child in [node.get_node_or_null("Card"), node.get_node_or_null("Fx/Shadow")]:
		if child:
			child.set_instance_shader_parameter("tint", color)

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

static func set_shadows_enabled(on: bool) -> void:
	shadows_enabled = on
	var alive: Array = []
	for shadow in shadow_meshes:
		if is_instance_valid(shadow):
			shadow.visible = on
			alive.append(shadow)
	shadow_meshes = alive
