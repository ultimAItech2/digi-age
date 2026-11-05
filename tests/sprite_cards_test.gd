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
	for kind in ["core", "fabricator", "data_center", "generator", "depot", "tower", "worker", "scout", "sentinel", "disruptor", "metal"]:
		expect(DASprites.has_sprite(kind), kind + ": sprite present")
		var t = DASprites.texture(kind)
		expect(t != null and t.get_width() > 0, kind + ": texture loads")
		var p = DASprites.portrait(kind)
		expect(p != null and p.get_width() == 128 and p.get_height() == 128, kind + ": 128px square portrait")
	expect(DASprites.sprite_path("walker") == "res://assets/sprites/units/walker.png", "walker mapped")
	expect(not DASprites.has_sprite("walker") or FileAccess.file_exists(DASprites.sprite_path("walker")), "walker only when file exists")
	expect(DASprites.portrait("walker") == null or DASprites.has_sprite("walker"), "no portrait without sprite")
	expect(DASprites.sprite_path("tree") == "", "unmapped kind has no path")
	expect(DASprites.texture("core") == DASprites.texture("core"), "texture cached")
	# Cards, cast shadows and ground discs.
	var core = DASprites.card("core", 0, 5, Color("57ebd5"))
	expect(core.get_child(0) is MeshInstance3D and core.get_child(0).name == "Card", "card child(0) is a MeshInstance3D")
	expect(is_equal_approx(DASprites.card_size("core", 5).x, 5.0 * sqrt(2.0) * 1.05), "core card width = footprint diagonal x 1.05")
	expect(is_equal_approx(DASprites.card_size("worker", 1).y, 1.4) and is_equal_approx(DASprites.card_size("disruptor", 1).y, 1.9), "unit heights 1.4 / 1.9")
	expect(is_equal_approx(DASprites.card_size("metal", 1).x, sqrt(2.0)), "prop card width = cell diagonal")
	var aabb: AABB = core.get_child(0).custom_aabb
	expect(aabb.position.y == 0.0 and aabb.end.y >= 2.5 and aabb.size.x >= 5.0, "core pick box covers footprint and 2.5 units up")
	var worker = DASprites.card("worker", 0, 1, Color.WHITE)
	expect(worker.get_child(0).custom_aabb.end.y >= 0.5, "worker pick box covers 0.5 up")
	var walker = DAModels.entity("walker", 0)
	expect(DASprites.is_card(core) and not DASprites.is_card(walker), "is_card")
	expect(core.get_child(0).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cards cast no real shadow")
	DASprites.set_rise(core, 0.4)
	expect(is_equal_approx(core.get_child(0).get_instance_shader_parameter("rise"), 0.4), "rise is per instance")
	DASprites.set_flip(worker, true)
	expect(is_equal_approx(worker.get_child(0).get_instance_shader_parameter("flip"), 1.0), "flip is per instance")
	DASprites.set_tint(worker, Color(1, 0, 0, 0.5))
	expect(worker.get_child(0).get_instance_shader_parameter("tint") == Color(1, 0, 0, 0.5), "tint is per instance")
	var other = DASprites.card("core", 1, 5, Color("ff795c"))
	expect(other.get_child(0).material_override == core.get_child(0).material_override, "one card material per kind")
	expect(other.get_node("Fx/Ground").material_override != core.get_node("Fx/Ground").material_override, "ground material per side colour")
	expect(is_equal_approx(DASprites.bar_height("core", 5), DASprites.card_size("core", 5).y + 0.3), "bar height above the card")
	var d = DASprites.sun_ground_direction(Vector3(-48, -170.5, 0))
	var yaw = -0.62
	# Screen right is (cos yaw, -sin yaw); the camera sits at (sin yaw, cos yaw) from the focus, so "down" is toward it.
	expect(d.dot(Vector2(cos(yaw), -sin(yaw))) > 0.0 and d.dot(Vector2(sin(yaw), cos(yaw))) > 0.0, "shadow falls lower-right at default yaw")
	expect(absf(DASprites.shadow_length(Vector3(-48, -170.5, 0)) - 0.9) < 0.02, "shadow length from sun elevation")
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
	expect(DASprites.sprite_available("res://assets/sprites/units/drone.png"), "available when the PNG exists")
	expect(DASprites.sprite_available("res://assets/sprites/units/nothing.png") == false, "unavailable without PNG or import")
	# The pick box must also cover the card's base, which sits anchor_offset toward the camera.
	var a = DASprites.anchor_offset("core", 5)
	expect(core.get_child(0).custom_aabb.position.x <= -(2.5 + a) and core.get_child(0).custom_aabb.end.z >= 2.5 + a, "core pick box extends by the anchor offset")
	for n in [core, worker, other, walker]:
		n.free()
	print("SPRITE CARD CONTRACT: %d failures" % failures)
	quit(1 if failures else 0)
