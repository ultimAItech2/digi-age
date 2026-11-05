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

static func has_sprite(kind: String) -> bool:
	var path = sprite_path(kind)
	return path != "" and FileAccess.file_exists(path)

## The sprite as a texture: the imported (mipmapped) resource when Godot has
## imported it, otherwise the PNG decoded directly so headless runs on a clean
## clone work without an import step. Null when the kind has no sprite.
static func texture(kind: String) -> Texture2D:
	if textures.has(kind):
		return textures[kind]
	var result: Texture2D = null
	var path = sprite_path(kind)
	if has_sprite(kind):
		if DABattlefield.imported(path):
			result = load(path)
		else:
			var image = Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
				result = ImageTexture.create_from_image(image)
	textures[kind] = result
	return result

## Square HUD portrait cut from the sprite: padded to its longer side, then
## scaled to PORTRAIT_SIZE. Null when the kind has no sprite.
static func portrait(kind: String) -> Texture2D:
	if portraits.has(kind):
		return portraits[kind]
	var result: Texture2D = null
	if has_sprite(kind):
		var image = Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(sprite_path(kind))) == OK:
			var side = maxi(image.get_width(), image.get_height())
			var square = Image.create(side, side, false, Image.FORMAT_RGBA8)
			square.fill(Color(0, 0, 0, 0))
			image.convert(Image.FORMAT_RGBA8)
			var offset = Vector2i((side - image.get_width()) / 2, (side - image.get_height()) / 2)
			square.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), offset)
			square.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
			result = ImageTexture.create_from_image(square)
	portraits[kind] = result
	return result
