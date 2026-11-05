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
	print("SPRITE CARD CONTRACT: %d failures" % failures)
	quit(1 if failures else 0)
