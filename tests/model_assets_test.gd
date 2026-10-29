extends SceneTree

var failures = 0

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func triangle_count(node: Node) -> int:
	var count = 0
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			count += node.mesh.surface_get_array_index_len(surface) / 3
	for child in node.get_children():
		count += triangle_count(child)
	return count

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for kind in DAModels.BLENDER_ASSETS:
		var asset: String = DAModels.BLENDER_ASSETS[kind]
		var detailed = load("res://assets/models/%s.glb" % asset).instantiate()
		var low = load("res://assets/models/%s_low.glb" % asset).instantiate()
		var triangles = triangle_count(detailed)
		expect(triangles > 0 and triangle_count(low) <= triangles, kind + ": valid detail and low meshes")
		var side = -1 if kind in ["metal", "data"] or kind in DAModels.SCENERY_KINDS else 0
		var accent = Color("37cc80")
		var model = DAModels.entity(kind, side, accent)
		expect(model.get_child_count() == 1, kind + ": one combined mesh for batching")
		var mesh: ArrayMesh = model.get_child(0).mesh
		expect(mesh.get_surface_count() == 1, kind + ": one draw surface")
		expect(mesh.surface_get_array_index_len(0) / 3 == triangles, kind + ": all exported geometry retained")
		var bounds = mesh.get_aabb()
		expect(bounds.position.y > -.25 and bounds.end.y > .5, kind + ": upright and grounded")
		expect(model.scale == Vector3.ONE, kind + ": authored dimensions preserved")
		if side == 0:
			var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var found_accent = false
			for color in colors:
				if Vector3(color.r,color.g,color.b).distance_to(Vector3(accent.r,accent.g,accent.b)) < .01:
					found_accent = true
			expect(found_accent, kind + ": faction color applied to team material")
			var other = DAModels.entity(kind, side, Color("ff5533"))
			expect(other.get_child(0).mesh != mesh, kind + ": faction override has independent cache")
			other.free()
		var repeated = DAModels.entity(kind, side, accent)
		expect(repeated.get_child(0).mesh == mesh, kind + ": repeated entities share geometry")
		expect(DAModels.baked_meshes[kind + str(side)] == mesh, kind + ": battlefield batch uses current mesh")
		repeated.free()
		model.free()
		detailed.free()
		low.free()
	for name in DAInterface.ICONS:
		var path = "res://assets/ui/icons/%s.svg" % name
		expect(FileAccess.file_exists(path), name + ": HUD icon exists")
		var image = Image.new()
		expect(FileAccess.file_exists(path) and image.load_svg_from_string(FileAccess.get_file_as_string(path), 2.0) == OK and image.get_width() == 48, name + ": HUD icon rasterises")
	var portraits = 0
	for kind in DAModels.BLENDER_ASSETS:
		if FileAccess.file_exists("res://assets/ui/portraits/%s.png" % DAModels.BLENDER_ASSETS[kind]): portraits += 1
	print("PORTRAITS: %d of %d kinds rendered" % [portraits, DAModels.BLENDER_ASSETS.size()])
	print("BLENDER ASSET CONTRACT: %d failures" % failures)
	quit(1 if failures else 0)
