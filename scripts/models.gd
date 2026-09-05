class_name DAModels
extends RefCounted
## Original procedural low-poly assets. No external asset dependencies.
const CYAN = Color("57ebd5")
const RED = Color("ff795c")
const DARK = Color("1b2c35")
const STEEL = Color("536872")
static var materials: Dictionary = {}
static var baked_meshes: Dictionary = {}
static var baked_material: ShaderMaterial

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
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = m
	return m

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
	return bake(root, kind, side)

static func bake(root: Node3D, kind: String, side: int, _accent: Color = Color.WHITE) -> Node3D:
	var key = kind + str(side)
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
			var color: Color = child.material_override.albedo_color
			color.a = 0.0 if child.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED else 1.0
			for i in arrays[Mesh.ARRAY_VERTEX].size():
				vertices.append(child.transform * arrays[Mesh.ARRAY_VERTEX][i])
				normals.append((child.basis * arrays[Mesh.ARRAY_NORMAL][i]).normalized())
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
	if not baked_material:
		baked_material = ShaderMaterial.new()
		var shader = Shader.new()
		shader.code = "shader_type spatial; render_mode diffuse_burley; void fragment(){ ALBEDO = COLOR.rgb; ROUGHNESS = 0.8; EMISSION = COLOR.rgb * (1.0-COLOR.a)*0.4; }"
		baked_material.shader = shader
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	var body = MeshInstance3D.new()
	body.mesh = baked_meshes[key]
	body.material_override = baked_material
	root.add_child(body)
	return root
