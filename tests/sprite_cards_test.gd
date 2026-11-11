extends SceneTree

## Contract for the photoreal sprite cards (scripts/sprite_cards.gd):
## kind mapping, texture loading, portraits, card geometry and depth cues.

var failures = 0

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for kind in ["core", "fabricator", "data_center", "generator", "depot", "tower", "lab", "worker", "scout", "sentinel", "disruptor", "walker", "warden", "mortar", "phantom", "metal", "data"]:
		expect(DASprites.has_sprite(kind), kind + ": sprite present")
		var t = DASprites.texture(kind)
		expect(t != null and t.get_width() > 0, kind + ": texture loads")
		var p = DASprites.portrait(kind)
		expect(p != null and p.get_width() == 128 and p.get_height() == 128, kind + ": 128px square portrait")
		expect(not DASprites.atlas(kind).is_empty() and DASprites.mask(kind) != null, kind + ": rendered atlas with a faction mask")
	expect(DASprites.sprite_path("walker") == "res://assets/sprites/rendered/walker.png", "a kind's sprite is its rendered atlas")
	expect(DASprites.facing_row(Vector2(1, 0)) == 0 and DASprites.facing_row(Vector2(0, 1)) == 2 and DASprites.facing_row(Vector2(-1, 0)) == 4 and DASprites.facing_row(Vector2(1, -1)) == 7, "eight facings from +x turning toward +y")
	var core_cols: int = DASprites.atlas("core").cols
	expect(DASprites.state_cell("core", "stage0") == Vector2i(0, 0) and DASprites.state_cell("core", "complete") == Vector2i(3, 0) and DASprites.state_cell("core", "wreck") == Vector2i(9 % core_cols, 9 / core_cols), "building states run left to right and wrap onto rows")
	expect(DASprites.atlas("core").cols * DASprites.atlas("core").frame[0] <= 4096, "wrapped atlases stay within 4096 px")
	expect(DASprites.idle_cell("tower", 0.0) == DASprites.state_cell("tower", "complete") and DASprites.idle_cell("tower", 0.13) == DASprites.state_cell("tower", "idle1") and DASprites.idle_cell("tower", 0.76) == DASprites.state_cell("tower", "complete"), "finished buildings loop complete, idle1..idle5")
	expect(DASprites.death_column("worker", 0.0) == 15 and DASprites.death_column("worker", 99.0) == 20, "death plays once and holds its last frame")
	expect(not DASprites.atlas("flag").is_empty() and DASprites.mask("flag") != null, "rally flag atlas with a faction mask")
	expect(DASprites.anim_column("worker", "idle", 3.0) == 0 and DASprites.anim_column("worker", "move", 0.0) == 1 and DASprites.anim_column("worker", "attack", 0.0) == 9, "unit animations by column")
	expect(DASprites.sprite_path("no_such_kind") == "", "unmapped kind has no path")
	expect(not DASprites.atlas("tree").is_empty() and DASprites.atlas("tree").cols >= 4, "scenery atlases carry their variants in columns")
	expect(DASprites.texture("core") == DASprites.texture("core"), "texture cached")
	# Cards, cast shadows and ground discs.
	var core = DASprites.card("core", 0, 5, Color("57ebd5"))
	expect(core.get_child(0) is MeshInstance3D and core.get_child(0).name == "Card", "card child(0) is a MeshInstance3D")
	var core_entry: Dictionary = DASprites.atlas("core")
	expect(is_equal_approx(DASprites.card_size("core", 5).x, core_entry.frame[0] / float(core_entry.ppu)) and DASprites.card_size("core", 5).x >= 5.0 * sqrt(2.0) * 0.9, "core card is its frame at the render scale and spans the footprint")
	expect(DASprites.card_size("walker", 1).y > DASprites.card_size("worker", 1).y, "the siege walker is drawn larger than a worker")
	expect(DASprites.drawn_box("core", 5).size.y < DASprites.card_size("core", 5).y, "drawn box is tighter than the frame")
	var aabb: AABB = core.get_child(0).custom_aabb
	expect(aabb.position.y == 0.0 and aabb.end.y >= 2.5 and aabb.size.x >= 5.0, "core pick box covers footprint and 2.5 units up")
	var worker = DASprites.card("worker", 0, 1, Color.WHITE)
	expect(worker.get_child(0).custom_aabb.end.y >= 0.5, "worker pick box covers 0.5 up")
	var walker = DAModels.entity("walker", 0)
	expect(DASprites.is_card(core) and not DASprites.is_card(walker), "is_card")
	expect(core.get_child(0).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cards cast no real shadow")
	DASprites.set_frame(worker, 5, 3)
	expect(worker.get_child(0).get_instance_shader_parameter("cell") == Vector2(5, 3) and worker.get_node("Fx/Shadow").get_instance_shader_parameter("cell") == Vector2(5, 3), "atlas cell is per instance, shadow included")
	expect(Color(core.get_child(0).get_instance_shader_parameter("team")) == Color("57ebd5"), "card painted in the owner's colour")
	DASprites.set_tint(worker, Color(1, 0, 0, 0.5))
	expect(worker.get_child(0).get_instance_shader_parameter("tint") == Color(1, 0, 0, 0.5), "tint is per instance")
	var other = DASprites.card("core", 1, 5, Color("ff795c"))
	expect(other.get_child(0).material_override == core.get_child(0).material_override, "one card material per kind")
	expect(other.get_node("Fx/Ground").material_override != core.get_node("Fx/Ground").material_override, "ground material per side colour")
	expect(DASprites.bar_height("core", 5) > 4.0 and DASprites.bar_height("core", 5) < DASprites.card_size("core", 5).y / 0.866 + 0.3, "bar height just above the drawn picture")
	var d = DASprites.sun_ground_direction(DABattlefield.SUN_ROTATION)
	var yaw = DABattlefield.CAMERA_YAW
	# Screen right is (cos yaw, -sin yaw); the camera sits at (sin yaw, cos yaw) from the focus, so "down" is toward it.
	expect(d.dot(Vector2(cos(yaw), -sin(yaw))) > 0.5 and d.dot(Vector2(sin(yaw), cos(yaw))) < 0.0, "shadow falls to screen right and a little away from the camera")
	expect(absf(DASprites.shadow_length(DABattlefield.SUN_ROTATION) - 0.9) < 0.02, "shadow length from sun elevation")
	DASprites.set_shadows_enabled(false)
	expect(not core.get_node("Fx/Shadow").visible, "shadow toggle")
	DASprites.set_shadows_enabled(true)
	expect(core.get_node("Fx/Ground").mesh is PlaneMesh, "ground disc present")
	var disc = DASprites.ground_only(walker, Color("57ebd5"), 2.0)
	expect(disc.get_parent() == walker and not (walker.get_child(0) is MeshInstance3D and walker.get_child(0).name == "Card"), "ground disc added under a 3D model without making it a card")
	# Review fixes: exported builds pack the imported texture, not the PNG; portraits must come from the texture.
	var small = ImageTexture.create_from_image(Image.create(64, 32, false, Image.FORMAT_RGBA8))
	var pf = DASprites.portrait_from_texture(small)
	expect(pf != null and pf.get_width() == 128 and pf.get_height() == 128, "portrait cut from any texture")
	expect(DASprites.sprite_available("res://assets/sprites/rendered/worker.png"), "available when the PNG exists")
	expect(DASprites.sprite_available("res://assets/sprites/rendered/nothing.png") == false, "unavailable without PNG or import")
	# The pick box must also cover the card's base, which sits anchor_offset toward the camera.
	var a = DASprites.anchor_offset("core", 5)
	expect(core.get_child(0).custom_aabb.position.x <= -(2.5 + a) and core.get_child(0).custom_aabb.end.z >= 2.5 + a, "core pick box extends by the anchor offset")
	# The Compatibility renderer path: each card owns its material, and the same calls reach it.
	DASprites.own_materials = true
	var solo = DASprites.card("worker", 0, 1, Color("57ebd5"))
	var twin = DASprites.card("worker", 0, 1, Color("57ebd5"))
	expect(solo.get_child(0).material_override != twin.get_child(0).material_override and solo.get_node("Fx/Shadow").material_override != twin.get_node("Fx/Shadow").material_override, "own-material cards do not share a material")
	expect(not solo.get_child(0).material_override.shader.code.contains("instance uniform") and solo.get_child(0).material_override.get_shader_parameter("tex") == DASprites.texture("worker"), "their shader has no per-instance uniforms and keeps the atlas")
	DASprites.set_frame(solo, 7, 2)
	DASprites.set_tint(solo, Color(0.5, 1, 1, 0.5))
	expect(DASprites.param(solo.get_child(0), "cell") == Vector2(7, 2) and DASprites.param(solo.get_node("Fx/Shadow"), "cell") == Vector2(7, 2) and DASprites.param(twin.get_child(0), "cell") != Vector2(7, 2), "a frame set on one card does not change another")
	expect(Color(DASprites.param(solo.get_child(0), "team")) == Color("57ebd5") and DASprites.param(solo.get_child(0), "tint") == Color(0.5, 1, 1, 0.5), "team colour and tint reach an own-material card")
	expect(solo.get_child(0).get_instance_shader_parameter("cell") == null, "and no per-instance parameter is used")
	DASprites.own_materials = false
	expect(DASprites.param(worker.get_child(0), "cell") == Vector2(5, 3), "the shared-material path still reads back through the same helper")
	for n in [core, worker, other, walker, solo, twin]:
		n.free()
	print("SPRITE CARD CONTRACT: %d failures" % failures)
	quit(1 if failures else 0)
