extends SceneTree
## Builds the terrain texture arrays from the downloaded Poly Haven sets:
## three vertical strips (one slice per layer) that Godot imports as Texture2DArray.
## Run: ./tools/godot.sh --headless --script tools/build_terrain_arrays.gd
const LAYERS = ["aerial_grass_rock", "forest_floor", "brown_mud_leaves_01", "asphalt_02", "rock_face"]
const RAW = "res://assets/third_party/polyhaven/raw/"
const OUT = "res://assets/third_party/processed/"
const MAPS = {"albedo": ["diffuse", 2048, "jpg"], "normal": ["nor_gl", 1024, "png"], "arm": ["arm", 1024, "jpg"]}

func _initialize() -> void:
	var failures = 0
	for map_name in MAPS:
		var suffix: String = MAPS[map_name][0]
		var size: int = MAPS[map_name][1]
		var ext: String = MAPS[map_name][2]
		var strip = Image.create(size, size*LAYERS.size(), false, Image.FORMAT_RGB8)
		for i in LAYERS.size():
			var path = RAW+LAYERS[i]+"/"+LAYERS[i]+"_"+suffix+"_2k.jpg"
			var image = Image.new()
			if image.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
				push_error("cannot load "+path)
				failures += 1
				continue
			image.convert(Image.FORMAT_RGB8)
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
			strip.blit_rect(image, Rect2i(0, 0, size, size), Vector2i(0, i*size))
		var target = OUT+"terrain_"+map_name+"."+ext
		DirAccess.make_dir_recursive_absolute(OUT)
		var error = strip.save_jpg(target, 0.92) if ext == "jpg" else strip.save_png(target)
		if error != OK:
			push_error("cannot save "+target)
			failures += 1
		var sidecar = FileAccess.open(target+".import", FileAccess.WRITE)
		sidecar.store_string("[remap]\n\nimporter=\"2d_array_texture\"\ntype=\"CompressedTexture2DArray\"\n\n[deps]\n\nsource_file=\""+target+"\"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\ncompress/hdr_compression=1\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nslices/horizontal=1\nslices/vertical="+str(LAYERS.size())+"\n")
		sidecar.close()
		print("wrote ", target, " ", strip.get_size())
	quit(1 if failures else 0)
