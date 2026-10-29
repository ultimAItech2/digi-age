class_name DAModels
extends RefCounted
## Blender-authored assets combined into shared meshes for RTS instancing.
const BLENDER_ASSETS = {
	"core": "core", "worker": "worker", "scout": "scout", "sentinel": "sentinel",
	"disruptor": "disruptor", "walker": "walker", "generator": "generator",
	"depot": "depot", "data_center": "data_center", "fabricator": "fabricator",
	"tower": "tower", "metal": "metal", "data": "archive", "ruin": "ruin",
	"barrier": "barrier", "tree": "tree", "bush": "bush", "rubble": "rubble",
	"highrise_a": "highrise_a", "highrise_b": "highrise_b", "highrise_c": "highrise_c",
}
## Scenery kinds that never carry a faction colour (baked once with side -1).
const SCENERY_KINDS = ["ruin", "barrier", "tree", "bush", "rubble", "highrise_a", "highrise_b", "highrise_c"]
## Ruined towers, 7-14 units tall, for the skyline outside the map and clustered obstacle cells.
const HIGHRISE_KINDS = ["highrise_a", "highrise_b", "highrise_c"]
## Emission strength of team/amber/violet parts so the environment glow picks them up.
const GLOW_ENERGY = 2.0
const CYAN = Color("57ebd5")
const RED = Color("ff795c")
const DARK = Color("1b2c35")
const STEEL = Color("536872")
static var materials: Dictionary = {}
static var baked_meshes: Dictionary = {}
static var baked_material: ShaderMaterial
static var source_scenes: Dictionary = {}

static func blender_entity(kind: String, side: int, accent: Color) -> Node3D:
	var root = Node3D.new()
	var cache_key = kind + str(side) + accent.to_html()
	if not baked_meshes.has(cache_key):
		var asset_name: String = BLENDER_ASSETS[kind]
		if not source_scenes.has(asset_name):
			source_scenes[asset_name] = load("res://assets/models/%s.glb" % asset_name)
		var scene: PackedScene = source_scenes[asset_name]
		if not scene:
			root.free()
			return null
		var source = scene.instantiate()
		append_blender_parts(source, Transform3D.IDENTITY, root, accent)
		source.free()
	return bake(root, kind, side, accent)

static func append_blender_parts(node: Node, parent_transform: Transform3D, root: Node3D, accent: Color) -> void:
	var transform = parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var source_material = node.get_active_material(surface) as StandardMaterial3D
			var color = STEEL
			var glow = false
			if source_material:
				color = accent if source_material.resource_name == "team" else source_material.albedo_color
				glow = source_material.emission_enabled
			var part = MeshInstance3D.new()
			var mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, node.mesh.surface_get_arrays(surface))
			part.mesh = mesh
			part.transform = transform
			part.material_override = material(color, glow)
			root.add_child(part)
	for child in node.get_children():
		append_blender_parts(child, transform, root, accent)

static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key = str(color) + str(glow)
	if materials.has(key):
		return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if color.a < 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		# Lit base plus strong emission: readable under shadow and bright enough
		# for the environment glow threshold. bake() reads `emission` back.
		m.albedo_color = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, color.a)
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b, 1.0)
		m.emission_energy_multiplier = GLOW_ENERGY
	materials[key] = m
	return m

## Shared scenery mesh (trees, rubble, ...) for MultiMesh scatter; cached by kind.
## `low` bakes the kit's _low export instead, for the dense scatter outside the map.
static func scenery_mesh(kind: String, low: bool = false) -> ArrayMesh:
	var name = kind + ("_low" if low else "")
	var key = name + "-1"
	if not baked_meshes.has(key):
		if low:
			var root = Node3D.new()
			var scene: PackedScene = load("res://assets/models/%s_low.glb" % BLENDER_ASSETS[kind])
			var source = scene.instantiate()
			append_blender_parts(source, Transform3D.IDENTITY, root, RED)
			source.free()
			bake(root, name, -1).free()
		else:
			entity(kind, -1).free()
	return baked_meshes[key]

## The one lit shader shared by every baked mesh and scatter batch. Created on
## demand so the battlefield can bind its fog-of-war texture before any bake.
static func shared_material() -> ShaderMaterial:
	if baked_material:
		return baked_material
	baked_material = ShaderMaterial.new()
	var shader = Shader.new()
	# COLOR.a == 0 marks emissive palette parts (team strips, amber, violet).
	# MultiMesh instance colours multiply in for per-instance scenery tinting.
	# Baked vertex colours are sRGB (palette hex / faction colours), so the
	# shader converts them to linear instead of lighting them one lift too pale.
	# fog_tex is the battlefield's fog-of-war map sampled by world XZ (white when
	# unbound, e.g. in the asset tests): unexplored ground darkens and desaturates.
	shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float glow_energy = %.1f;
%s
varying vec3 world_pos;
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float glow = 1.0 - COLOR.a;
	vec3 srgb = clamp(COLOR.rgb, 0.0, 1.0);
	// Lift the mid-greys of the steel palette toward the portrait renders; AgX
	// otherwise compresses them into a flat slate.
	vec3 base = mix(to_linear(srgb), srgb, 0.35);
	float f = fog_level(world_pos);
	ALBEDO = fog_tint(base * (1.0 - glow * 0.7), f);
	ROUGHNESS = 0.8 - glow * 0.4;
	SPECULAR = 0.5 * mix(0.3, 1.0, f);
	EMISSION = base * glow * glow_energy * pow(mix(0.2, 1.0, f), 2.0);
}""" % [GLOW_ENERGY, FOG_SHADER]
	baked_material.shader = shader
	return baked_material

## Fog-of-war sampling shared by the model, ground and water shaders. The texture
## covers the map plus a one-cell border (74 x 74 texels, one per world unit;
## texel 1 is cell 0); outside the map it clamps to the border's explored level.
const FOG_SHADER = """uniform sampler2D fog_tex : hint_default_white, filter_linear, repeat_disable;
float fog_level(vec3 p) {
	return texture(fog_tex, (p.xz + vec2(1.5)) / 74.0).r;
}
vec3 fog_tint(vec3 c, float f) {
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	float light = pow(mix(0.45, 1.0, f), 1.25);
	return mix(vec3(grey), c, mix(0.5, 1.0, f)) * light;
}"""

static func box(parent: Node3D, size: Vector3, p: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.position = p
	n.material_override = material(color, glow)
	parent.add_child(n)
	return n

static func cylinder(parent: Node3D, radius: float, height: float, p: Vector3, color: Color, top: float = -1, glow: bool = false) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = 6
	n.mesh = mesh
	n.position = p
	n.material_override = material(color, glow)
	parent.add_child(n)
	return n

static func ring(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - 0.045
	mesh.outer_radius = radius + 0.045
	mesh.rings = 24
	mesh.ring_segments = 6
	n.mesh = mesh
	n.position.y = 0.13
	n.material_override = material(color, true)
	parent.add_child(n)
	return n

static func entity(kind: String, side: int, accent_override: Color = Color(0, 0, 0, 0)) -> Node3D:
	var root = Node3D.new()
	var accent = CYAN if side == 0 else RED
	if accent_override.a > 0:
		accent = accent_override
	if BLENDER_ASSETS.has(kind):
		var authored = blender_entity(kind, side, accent)
		if authored:
			root.free()
			return authored
	if side == -1:
		if kind == "metal":
			for i in 5:
				var debris = box(root, Vector3(0.8, 0.5 + i * 0.17, 0.7), Vector3(sin(i*2.1), 0.3, cos(i*2.1)) * 0.9, Color("847768"))
				debris.rotation = Vector3(i*0.15, i*1.1, i*0.1)
			box(root, Vector3(0.8, 0.08, 0.12), Vector3(0, 0.95, 0), Color("e7b774"), true)
		else:
			cylinder(root, 1.2, 0.3, Vector3(0, 0.15, 0), DARK)
			cylinder(root, 0.5, 2.2, Vector3(0, 1.2, 0), Color("7d70ae"), 0.22)
			for i in 3:
				cylinder(root, 0.67, 0.08, Vector3(0, 0.6+i*0.6, 0), Color("c9a6ff"), -1, true)
		return bake(root, kind, side, accent)
	if kind in ["core", "generator", "depot", "data_center", "fabricator", "tower"]:
		var r = 2.2 if kind in ["core", "fabricator"] else 1.25
		box(root, Vector3(r*2, 0.25, r*2), Vector3(0, 0.125, 0), DARK)
		for x in [-1, 1]:
			box(root, Vector3(0.09, 0.06, r*1.6), Vector3(x*r*0.9, 0.29, 0), accent, true)
		match kind:
			"core":
				cylinder(root, 1.9, 0.7, Vector3(0, 0.6, 0), STEEL)
				cylinder(root, 1.4, 2.1, Vector3(0, 1.5, 0), DARK, 0.85)
				cylinder(root, 0.7, 1.2, Vector3(0, 2.75, 0), accent, 0.3, true)
				for i in 4:
					var angle = i*PI/2
					box(root, Vector3(0.45, 2.8, 0.45), Vector3(cos(angle)*1.55, 1.5, sin(angle)*1.55), STEEL)
				cylinder(root, 0.07, 1.4, Vector3(0, 3.8, 0), accent, -1, true)
			"generator":
				cylinder(root, 0.85, 1.2, Vector3(0, 0.9, 0), STEEL)
				cylinder(root, 0.5, 0.6, Vector3(0, 1.8, 0), accent, -1, true)
				for i in 3:
					var fin = box(root, Vector3(0.18, 0.8, 2.1), Vector3(0, 1.15, 0), DARK)
					fin.rotation.y = i*PI/3
			"depot":
				box(root, Vector3(1.9, 0.9, 1.7), Vector3(0, 0.7, 0), STEEL)
				for i in 3:
					box(root, Vector3(0.45, 0.45, 0.9), Vector3((i-1)*0.6, 1.35, 0), Color("a49a7a"))
			"data_center":
				for i in 3:
					box(root, Vector3(0.55, 2.0, 1.5), Vector3((i-1)*0.68, 1.25, 0), STEEL)
					for j in 4:
						box(root, Vector3(0.35, 0.09, 0.02), Vector3((i-1)*0.68, 0.7+j*0.4, 0.76), accent, true)
			"fabricator":
				box(root, Vector3(3.5, 1.0, 3.4), Vector3(0, 0.75, 0), STEEL)
				box(root, Vector3(2.5, 0.5, 2.7), Vector3(0, 1.5, 0), DARK)
				for x in [-1, 1]:
					box(root, Vector3(0.28, 2.4, 0.3), Vector3(x*1.65, 1.4, 1.3), accent)
				box(root, Vector3(3.5, 0.25, 0.3), Vector3(0, 2.65, 1.3), STEEL)
				box(root, Vector3(1.5, 0.7, 0.1), Vector3(0, 0.8, 1.73), Color("101c25"))
			"tower":
				cylinder(root, 0.85, 2.6, Vector3(0, 1.5, 0), STEEL, 0.55)
				box(root, Vector3(1.6, 0.55, 1.2), Vector3(0, 2.9, 0), DARK)
				box(root, Vector3(0.25, 0.25, 1.5), Vector3(0, 3, 1), accent)
	else:
		var scale_factor = 1.6 if kind == "walker" else 1.0
		root.scale = Vector3.ONE * scale_factor
		match kind:
			"worker":
				box(root, Vector3(0.75, 0.4, 0.9), Vector3(0, 0.48, 0), STEEL)
				box(root, Vector3(0.45, 0.18, 0.45), Vector3(0, 0.77, 0), accent)
				for x in [-1, 1]:
					box(root, Vector3(0.18, 0.15, 0.6), Vector3(x*0.35, 0.45, 0.6), Color("d1b878"))
			"scout":
				cylinder(root, 0.55, 0.35, Vector3(0, 0.5, 0), STEEL, 0.3)
				box(root, Vector3(0.2, 0.25, 0.65), Vector3(0, 0.72, 0.3), accent)
				cylinder(root, 0.035, 0.7, Vector3(0.25, 0.95, -0.2), accent, -1, true)
			"sentinel":
				box(root, Vector3(0.65, 0.65, 0.6), Vector3(0, 0.9, 0), STEEL)
				box(root, Vector3(0.45, 0.28, 0.4), Vector3(0, 1.4, 0), DARK)
				box(root, Vector3(0.4, 0.08, 0.04), Vector3(0, 1.43, 0.22), accent, true)
				box(root, Vector3(0.2, 0.22, 0.85), Vector3(0.43, 0.94, 0.4), accent)
			"disruptor":
				box(root, Vector3(0.9, 0.3, 1.1), Vector3(0, 0.45, 0), STEEL)
				cylinder(root, 0.22, 0.8, Vector3(0, 0.9, 0), DARK)
				var dish = cylinder(root, 0.7, 0.25, Vector3(0, 1.4, 0), accent, 0.2)
				dish.rotation.x = PI/4
			"walker":
				box(root, Vector3(1.0, 0.5, 1.2), Vector3(0, 1.0, 0), STEEL)
				box(root, Vector3(0.55, 0.45, 0.9), Vector3(0, 1.45, 0), DARK)
				box(root, Vector3(0.28, 0.28, 1.7), Vector3(0, 1.52, 0.8), accent)
		for x in [-1, 1]:
			for z in [-1, 1]:
				box(root, Vector3(0.2, 0.4 if kind != "walker" else 0.7, 0.3), Vector3(x*0.4, 0.23 if kind != "walker" else 0.4, z*0.35), DARK)
	return bake(root, kind, side, accent)

static func bake(root: Node3D, kind: String, side: int, accent: Color = Color.WHITE) -> Node3D:
	var key = kind + str(side) + accent.to_html()
	if not baked_meshes.has(key):
		var vertices = PackedVector3Array()
		var normals = PackedVector3Array()
		var colors = PackedColorArray()
		var indices = PackedInt32Array()
		for child in root.get_children():
			if not child is MeshInstance3D:
				continue
			var arrays = child.mesh.surface_get_arrays(0)
			var offset = vertices.size()
			var glow: bool = child.material_override.emission_enabled
			var color: Color = child.material_override.emission if glow else child.material_override.albedo_color
			# Alpha 0 marks emissive parts for the shared shader below.
			color.a = 0.0 if glow else 1.0
			for i in arrays[Mesh.ARRAY_VERTEX].size():
				vertices.append(child.transform * arrays[Mesh.ARRAY_VERTEX][i])
				normals.append((child.basis.inverse().transposed() * arrays[Mesh.ARRAY_NORMAL][i]).normalized())
				colors.append(color)
			for i in arrays[Mesh.ARRAY_INDEX]:
				indices.append(offset + i)
		var data = []
		data.resize(Mesh.ARRAY_MAX)
		data[Mesh.ARRAY_VERTEX] = vertices
		data[Mesh.ARRAY_NORMAL] = normals
		data[Mesh.ARRAY_COLOR] = colors
		data[Mesh.ARRAY_INDEX] = indices
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
		baked_meshes[key] = mesh
	# Battlefield batches use the current faction's mesh for each kind and side.
	baked_meshes[kind + str(side)] = baked_meshes[key]
	shared_material()
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	var body = MeshInstance3D.new()
	body.mesh = baked_meshes[key]
	body.material_override = baked_material
	root.add_child(body)
	return root
