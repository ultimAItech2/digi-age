class_name DABattlefield
extends Node3D
var sim: DASimulation
var models: Dictionary = {}
var unit_batches: Dictionary = {}
var selections: Dictionary = {}
var camera: Camera3D
var focus: Vector2 = Vector2(16, 36)
var yaw: float = -0.62
var zoom: float = 37.0
var fog: MultiMeshInstance3D
var ghost: Node3D
var ghost_kind: String = ""
var effects: Array = []
var marker: Node3D
var marker_left: float = 0.0
var decorations: Array = []
var terrain: Node3D
var sun: DirectionalLight3D

func setup(world: DASimulation) -> void:
	sim = world
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 350
	camera.current = true
	add_child(camera)
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101e28")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a4bec9")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color("ffe4bd")
	sun.light_energy = 1.0
	sun.shadow_enabled = "--no-shadows" not in OS.get_cmdline_user_args()
	sun.directional_shadow_max_distance = 110
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	make_terrain()
	make_fog()
	marker = Node3D.new()
	add_child(marker)
	DAModels.ring(marker, 0.8, DAModels.CYAN)
	marker.visible = false
	sim.shot.connect(on_shot)
	sim.destroyed.connect(on_destroyed)
	update_camera()
	refresh_fog()

func apply_settings(values: Dictionary) -> void:
	var profile = str(values.get("profile", "normal"))
	var reduced = bool(values.get("reduced_effects", false))
	if sun:
		sun.shadow_enabled = profile != "low" and not reduced and "--no-shadows" not in OS.get_cmdline_user_args()
		sun.directional_shadow_max_distance = 70.0 if profile == "low" else 110.0
	if profile == "low":
		camera.far = 220.0

func make_terrain() -> void:
	terrain = Node3D.new()
	add_child(terrain)
	DAModels.box(terrain, Vector3(76, 0.8, 76), Vector3(35.5, -0.55, 35.5), Color("19272c"))
	var tiles = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(1, 1)
	mm.mesh = mesh
	mm.instance_count = DASimulation.SIZE * DASimulation.SIZE
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	tiles.material_override = mat
	tiles.multimesh = mm
	terrain.add_child(tiles)
	var rng = RandomNumberGenerator.new()
	rng.seed = 1407
	var bands: Array = sim.active_map.road_bands if sim.active_map else [{"axis": "y", "min": 32, "max": 39}, {"axis": "x", "min": 33, "max": 38}]
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var base = Color("4c584c")
			if is_road_cell(x, y, bands):
				base = Color("616258")
			var tint = rng.randf_range(0.97, 1.03)
			mm.set_instance_transform(x*DASimulation.SIZE+y, Transform3D(Basis.IDENTITY, Vector3(x, 0, y)))
			mm.set_instance_color(x*DASimulation.SIZE+y, Color(base.r*tint, base.g*tint, base.b*tint))
	for c in sim.obstacles:
		var n = Node3D.new()
		terrain.add_child(n)
		n.position = Vector3(c.x, 0, c.y)
		var rock = DAModels.cylinder(n, rng.randf_range(0.6, 0.85), rng.randf_range(1.2, 2.8), Vector3(0, 0.5, 0), Color("515950"), 0.3)
		rock.rotation.y = rng.randf_range(0, TAU)
		decorations.append(n)
	var scenery: Array = sim.active_map.scenery if sim.active_map else []
	if scenery.is_empty():
		for x in [3, 68]:
			for y in [6, 15, 57, 65]:
				scenery.append({"kind": "ruin", "pos": Vector2(x, y)})
	for item in scenery:
		if str(item.get("kind", "")) != "ruin":
			continue
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		var n = Node3D.new()
		terrain.add_child(n)
		n.position = Vector3(pos.x, 0, pos.y)
		DAModels.box(n, Vector3(0.3, 2.4, 2), Vector3(0, 1.2, 0), Color("64655c"))
		DAModels.box(n, Vector3(1.9, 1.1, 0.3), Vector3(0.8, 0.55, -0.9), Color("64655c"))
		decorations.append(n)
	var road_x = 35.5
	if sim.active_map and not sim.active_map.starts.is_empty():
		road_x = (sim.active_map.starts[0].x + sim.active_map.starts[1].x) * 0.5
	for y in range(4, 70, 5):
		DAModels.box(terrain, Vector3(0.10, 0.02, 1.3), Vector3(road_x, 0.03, y), Color("8a8265"))

func is_road_cell(x: int, y: int, bands: Array) -> bool:
	for band in bands:
		var axis = str(band.get("axis", "y"))
		var lo = int(band.get("min", 0))
		var hi = int(band.get("max", 0))
		if axis == "y" and y >= lo and y <= hi:
			return true
		if axis == "x" and x >= lo and x <= hi:
			return true
	return false

func make_fog() -> void:
	fog = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(1.02, 1.02)
	mm.mesh = mesh
	mm.instance_count = DASimulation.SIZE * DASimulation.SIZE
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog.material_override = mat
	fog.multimesh = mm
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			mm.set_instance_transform(x*DASimulation.SIZE+y, Transform3D(Basis.IDENTITY, Vector3(x, 0.075, y)))

func refresh_fog() -> void:
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var c = Vector2i(x, y)
			var alpha = 0.0 if sim.visible[0].has(c) else (0.58 if sim.explored[0].has(c) else 1.0)
			fog.multimesh.set_instance_color(x*DASimulation.SIZE+y, Color(0.035, 0.065, 0.08, alpha))
	for n in decorations:
		n.visible = sim.explored[0].has(Vector2i(n.position.x, n.position.z))

func update_camera() -> void:
	var cam_min = sim.active_map.camera_min if sim.active_map else Vector2.ONE
	var cam_max = sim.active_map.camera_max if sim.active_map else Vector2(70, 70)
	focus = focus.clamp(cam_min, cam_max)
	camera.size = zoom
	var offset = Vector3(sin(yaw)*40, 43, cos(yaw)*40)
	camera.position = Vector3(focus.x, 0, focus.y) + offset
	camera.look_at(Vector3(focus.x, 0, focus.y))

func ground_at(screen: Vector2) -> Vector2:
	var p = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return Vector2(p.x, p.z) if p != null else focus

func screen_at(p: Vector2, height: float = 0.0) -> Vector2:
	return camera.unproject_position(Vector3(p.x, height, p.y))

func pan(direction: Vector2, dt: float) -> void:
	var right = Vector2(cos(yaw), -sin(yaw))
	var forward = Vector2(sin(yaw), cos(yaw))
	focus += (right*direction.x + forward*direction.y) * dt * zoom * 0.65
	update_camera()

func sync(dt: float, selected: Array) -> void:
	for id in models.keys():
		if not sim.entities.has(id):
			models[id].queue_free()
			models.erase(id)
			selections.erase(id)
	var batch_transforms: Dictionary = {}
	for e in sim.entities.values():
		if not models.has(e.id):
			var n = DAModels.entity(e.kind, e.owner, sim.faction_color(e.owner) if e.owner >= 0 else Color.WHITE)
			add_child(n)
			models[e.id] = n
			if e.owner >= 0 and not e.building:
				# Geometry is rendered in shared MultiMeshes; keep the node for picking and rings.
				n.get_child(0).visible = false
				n.get_child(0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				create_unit_batch(e.kind, e.owner)
			if e.owner >= 0:
				var radius = sim.catalog.buildings[e.kind].radius + 0.4 if e.building else 0.65
				selections[e.id] = DAModels.ring(n, radius, DAModels.CYAN if e.owner == 0 else DAModels.RED)
		var model: Node3D = models[e.id]
		model.visible = sim.known(0, e) and (e.get("amount", 1.0) > 0)
		var p = Vector3(e.pos.x, 0, e.pos.y)
		if model.position == Vector3.ZERO or model.position.distance_to(p) > 4:
			model.position = p
		else:
			model.position = model.position.lerp(p, minf(1, dt * 16))
		if e.owner >= 0:
			selections[e.id].visible = selected.has(e.id)
			if e.building:
				var progress = 1.0 if e.complete else 1.0 - e.build_left / sim.catalog.buildings[e.kind].time
				model.scale.y = 0.15 + progress * 0.85
			elif e.order != "idle":
				var direction: Vector2 = e.destination - e.pos
				if not e.path.is_empty():
					direction = e.path[0] - e.pos
				if direction.length() > 0.1:
					model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.y), dt * 10)
		if e.owner >= 0 and not e.building and model.visible:
			var key = e.kind + str(e.owner)
			if not batch_transforms.has(key):
				batch_transforms[key] = []
			batch_transforms[key].append(model.transform)
	for key in unit_batches:
		var transforms: Array = batch_transforms.get(key, [])
		var mm: MultiMesh = unit_batches[key].multimesh
		mm.visible_instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
	for effect in effects.duplicate():
		effect.left -= dt
		if effect.left <= 0:
			effect.node.queue_free()
			effects.erase(effect)
		elif effect.type == "blast":
			effect.node.scale += Vector3.ONE * dt * 5
	if marker_left > 0:
		marker_left -= dt
		marker.scale = Vector3.ONE * (1.0 + marker_left*0.4)
	marker.visible = marker_left > 0

func create_unit_batch(kind: String, side: int) -> void:
	var key = kind + str(side)
	if unit_batches.has(key):
		return
	var batch = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = DAModels.baked_meshes[key]
	mm.instance_count = 128
	mm.visible_instance_count = 0
	batch.multimesh = mm
	batch.material_override = DAModels.baked_material
	add_child(batch)
	unit_batches[key] = batch

func show_marker(p: Vector2) -> void:
	marker.position = Vector3(p.x, 0.1, p.y)
	marker_left = 0.7

func preview(kind: String, p: Vector2, valid: bool) -> void:
	if ghost_kind != kind:
		if ghost:
			ghost.queue_free()
		ghost_kind = kind
		ghost = null
		if kind != "":
			ghost = DAModels.entity(kind, 0)
			add_child(ghost)
	if ghost:
		ghost.position = Vector3(roundf(p.x), 0, roundf(p.y))
		var m = DAModels.material(Color(0.25, 1, 0.7, 0.5) if valid else Color(1, 0.2, 0.15, 0.5), true)
		for child in ghost.get_children():
			if child is MeshInstance3D:
				child.material_override = m

func on_shot(from: Vector2, to: Vector2, owner: int, kind: String) -> void:
	if not sim.seen(0, from) and not sim.seen(0, to):
		return
	var n = Node3D.new()
	add_child(n)
	var start = Vector3(from.x, 1.1, from.y)
	var finish = Vector3(to.x, 0.8, to.y)
	n.position = (start + finish) * 0.5
	if start.distance_to(finish) > 0.01:
		n.look_at(finish)
	DAModels.box(n, Vector3(0.04 if kind != "walker" else 0.12, 0.04, start.distance_to(finish)), Vector3.ZERO, DAModels.CYAN if owner == 0 else DAModels.RED, true)
	effects.append({"node": n, "left": 0.09, "type": "shot"})

func on_destroyed(p: Vector2, _kind: String) -> void:
	if not sim.seen(0, p):
		return
	var n = Node3D.new()
	add_child(n)
	n.position = Vector3(p.x, 0.6, p.y)
	DAModels.cylinder(n, 0.6, 1.0, Vector3.ZERO, Color("ffc787"), 0.1, true)
	effects.append({"node": n, "left": 0.25, "type": "blast"})
