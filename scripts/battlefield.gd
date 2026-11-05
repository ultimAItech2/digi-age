class_name DABattlefield
extends Node3D
## 3D presentation of the simulation: an overgrown ruined city that continues
## past the playable grid to the horizon, cut by rivers. Everything here is
## visual only; the grid, pathing and gameplay cells live in DASimulation and
## are never changed by this node.
var sim: DASimulation
var models: Dictionary = {}
var unit_batches: Dictionary = {}
var selections: Dictionary = {}
var camera: Camera3D
var focus: Vector2 = Vector2(16, 36)
var yaw: float = -0.62
var zoom: float = 48.0
var ghost: Node3D
var ghost_kind: String = ""
var effects: Array = []
var marker: Node3D
var marker_left: float = 0.0
var terrain: Node3D
var sun: DirectionalLight3D
var environment: Environment
var water: MeshInstance3D
var water_material: ShaderMaterial
## Fog of war as a texture sampled by world position in every world shader:
## 0 = unexplored, EXPLORED_LEVEL = explored but not visible, 1 = visible.
var fog_image: Image
var fog_texture: ImageTexture
## Kit scenery drawn through MultiMeshes. Each entry:
## {mm, index, transform, order, shown}. `order` in [0,1) gates density;
## obstacles, authored scenery and towers use -1 so they always show.
var scatter: Array = []
var scatter_batches: Dictionary = {}
var scatter_fraction: float = 1.0
var low_effects: bool = false
var shadow_reach: float = 90.0

const GRASS = Color("5a6b48")
const ASPHALT = Color("5c5b55")
const DIRT = Color("726c4c")
const MUD = Color("5a4e38")
const WATER_LEVEL = -0.35
const SCATTER_SEED = 1407
const CAMERA_FOV = 32.0
const CAMERA_ELEVATION = 38.0
const FOG_SIZE = DASimulation.SIZE + 2
const EXPLORED_LEVEL = 0.545
## The world continues this far past every map edge, as a 2-unit height grid.
const RING_EXTENT = 110.0
const RING_STEP = 2.0
const RIVER_DEPTH = 1.4
## River centrelines wandering around `base` on the axis across `along`.
const RIVERS = [
	{"along": "x", "base": -18.0, "a1": 7.0, "f1": 0.04, "p1": 0.5, "a2": 2.0, "f2": 0.1, "width": 4.0},
	{"along": "z", "base": -26.0, "a1": 9.0, "f1": 0.045, "p1": 1.0, "a2": 3.0, "f2": 0.11, "width": 3.5},
	{"along": "z", "base": 112.0, "a1": 8.0, "f1": 0.05, "p1": 2.0, "a2": 2.5, "f2": 0.13, "width": 3.0},
]
const HIDDEN = Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -50, 0))
## Forward+ unlocks SDFGI, SSAO/SSIL, SSR, volumetric fog and PCSS shadows; the
## Compatibility and Dummy renderers take the simpler path.
static var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
const HDRI_PATH = "res://assets/third_party/processed/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
## The HDRI's sun sits at panorama u = 0.594 (tools/hdri_sun.py); the sky shader
## rolls it to the light's azimuth so the scene stays front-lit for the camera.
const HDRI_SUN_U = 0.594
## Yaw -170.5: at the default camera yaw the sun's ground direction is lower
## right on screen, where the photoreal sprites' baked key light (upper left)
## throws their shadows; DASprites shears the card shadows along the same line.
const SUN_ROTATION = Vector3(-48, -170.5, 0)
var sky_rotation: float = 0.0
var vignette: ColorRect
var camera_attributes: CameraAttributesPractical

func setup(world: DASimulation) -> void:
	sim = world
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAMERA_FOV
	camera.near = 1.0
	camera.far = 420
	camera.current = true
	add_child(camera)
	build_environment()
	build_sun()
	make_fog_texture()
	make_terrain()
	for child in terrain.get_children():
		if child is GeometryInstance3D and child.gi_mode == GeometryInstance3D.GI_MODE_DYNAMIC:
			child.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	make_water()
	water.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	marker = Node3D.new()
	add_child(marker)
	DAModels.ring(marker, 0.8, DAModels.CYAN)
	marker.visible = false
	sim.shot.connect(on_shot)
	sim.destroyed.connect(on_destroyed)
	update_camera()
	refresh_fog()

func build_environment() -> void:
	var env = WorldEnvironment.new()
	environment = Environment.new()
	environment.sky = shared_sky()
	environment.background_mode = Environment.BG_SKY if forward_plus else Environment.BG_COLOR
	environment.background_color = Color("9fb3bf")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 1.0 if has_hdri() else 0.8
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0 if has_hdri() else 1.3
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.08
	# Aerial perspective for the far ring; volumetric fog replaces it on Forward+.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("9fb3bf")
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.9
	environment.fog_depth_begin = 80.0
	environment.fog_depth_end = 300.0
	environment.fog_depth_curve = 1.3
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	environment.glow_enabled = true
	environment.glow_normalized = true
	environment.glow_hdr_threshold = 1.2
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	if forward_plus:
		environment.sdfgi_enabled = true
		environment.sdfgi_cascades = 4
		environment.sdfgi_min_cell_size = 0.4
		environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_bounce_feedback = 0.5
		environment.sdfgi_read_sky_light = true
		environment.sdfgi_energy = 1.0
		environment.ssao_enabled = true
		environment.ssao_radius = 1.5
		environment.ssao_intensity = 2.0
		environment.ssao_power = 1.5
		environment.ssao_detail = 0.5
		environment.ssao_horizon = 0.06
		environment.ssao_ao_channel_affect = 0.5
		environment.ssil_enabled = true
		environment.ssil_radius = 3.0
		environment.ssil_intensity = 1.0
		environment.ssil_normal_rejection = 1.0
		environment.ssr_enabled = true
		environment.ssr_max_steps = 48
		environment.ssr_fade_in = 0.15
		environment.ssr_fade_out = 2.0
		environment.ssr_depth_tolerance = 0.2
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.012
		environment.volumetric_fog_albedo = Color(0.85, 0.9, 0.95)
		environment.volumetric_fog_anisotropy = 0.6
		environment.volumetric_fog_length = 160.0
		environment.volumetric_fog_gi_inject = 0.3
		environment.volumetric_fog_ambient_inject = 0.4
		environment.volumetric_fog_sky_affect = 0.0
		environment.volumetric_fog_temporal_reprojection_enabled = true
		environment.fog_enabled = false
	env.environment = environment
	add_child(env)
	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.dof_blur_far_enabled = forward_plus
	camera_attributes.dof_blur_far_distance = camera_distance() + 60.0
	camera_attributes.dof_blur_far_transition = 40.0
	camera_attributes.dof_blur_amount = 0.08
	camera.attributes = camera_attributes

func build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROTATION
	DASprites.set_sun(DASprites.sun_ground_direction(SUN_ROTATION), DASprites.shadow_length(SUN_ROTATION))
	sun.light_color = Color("fff1dc") if has_hdri() else Color("ffe9c8")
	sun.light_energy = 3.0 if has_hdri() else 2.3
	sun.light_angular_distance = 0.5
	sun.light_volumetric_fog_energy = 1.5
	sun.shadow_enabled = "--no-shadows" not in OS.get_cmdline_user_args()
	DASprites.set_shadows_enabled(sun.shadow_enabled)
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_split_2 = 0.4
	sun.directional_shadow_split_3 = 0.65
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.9
	add_child(sun)

static func has_hdri() -> bool:
	return imported(HDRI_PATH)

## True when Godot has imported the file (its .import sidecar names an existing
## .godot/imported artefact); ResourceLoader.exists() is true as soon as the
## sidecar exists, which makes load() print errors on clean clones.
static func imported(path: String) -> bool:
	if not FileAccess.file_exists(path + ".import"):
		return false
	for line in FileAccess.get_file_as_string(path + ".import").split("\n"):
		if line.begins_with("path="):
			return FileAccess.file_exists(line.get_slice("\"", 1))
	return false

## One Sky for the whole process: the Compatibility renderer reports its
## radiance textures as leaked when a Sky is released mid-session (each
## battlefield rebuild), but not when it is released at exit. With the CC0 HDRI
## present the sky is a panorama rolled so its sun matches SUN_ROTATION; without
## it (clean clones, asset tests) the procedural sky stands in.
static var process_sky: Sky
static var sky_shader: Shader

static func shared_sky() -> Sky:
	if not process_sky:
		process_sky = Sky.new()
		process_sky.radiance_size = Sky.RADIANCE_SIZE_256 if forward_plus else Sky.RADIANCE_SIZE_64
		if has_hdri():
			sky_shader = Shader.new()
			sky_shader.code = """shader_type sky;
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float rotation = 0.0;
uniform float energy = 1.0;
void sky() {
	vec3 d = EYEDIR;
	float yaw = atan(d.x, -d.z) + rotation;
	vec2 uv = vec2(yaw / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	COLOR = texture(panorama, uv).rgb * energy;
}"""
			var material = ShaderMaterial.new()
			material.shader = sky_shader
			material.set_shader_parameter("panorama", load(HDRI_PATH))
			# The light at SUN_ROTATION comes from azimuth atan(sin(yaw), cos(yaw)) in
			# panorama space (u = yaw/2pi + 0.5); roll the HDRI sun onto it.
			var light_yaw = deg_to_rad(SUN_ROTATION.y)
			var from = Vector3(sin(light_yaw), 0, cos(light_yaw))
			var target_u = atan2(from.x, -from.z) / TAU + 0.5
			material.set_shader_parameter("rotation", (HDRI_SUN_U - target_u) * TAU)
			process_sky.sky_material = material
		else:
			var sky_material = ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("4a7fb5")
			sky_material.sky_horizon_color = Color("a9c3dc")
			sky_material.ground_bottom_color = Color("3b4a39")
			sky_material.ground_horizon_color = Color("7f9382")
			sky_material.sun_angle_max = 20.0
			sky_material.sun_curve = 0.2
			process_sky.sky_material = sky_material
	return process_sky

func apply_settings(values: Dictionary) -> void:
	var profile = str(values.get("profile", "normal"))
	var reduced = bool(values.get("reduced_effects", false))
	var low = profile == "low"
	low_effects = low or reduced
	shadow_reach = 50.0 if low else 90.0
	var no_shadows = "--no-shadows" in OS.get_cmdline_user_args()
	if sun:
		sun.shadow_enabled = not low and not reduced and not no_shadows
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if (low or not forward_plus) else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		if low or not forward_plus:
			sun.directional_shadow_split_1 = 0.3
		else:
			sun.directional_shadow_split_1 = 0.2
	if forward_plus:
		RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if low else RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	if camera:
		camera.far = 260.0 if low else 400.0
		update_camera()
	if environment:
		environment.glow_enabled = not low
		if forward_plus:
			environment.sdfgi_enabled = not low
			environment.ssao_enabled = not low
			environment.ssil_enabled = not low_effects
			environment.ssr_enabled = not low_effects
			environment.volumetric_fog_enabled = not low_effects
			environment.fog_enabled = low_effects
		else:
			environment.fog_enabled = not low_effects
	if camera_attributes:
		camera_attributes.dof_blur_far_enabled = forward_plus and not low_effects
	var viewport = get_viewport()
	if viewport and forward_plus:
		viewport.use_taa = not low
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low else Viewport.SCREEN_SPACE_AA_DISABLED
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if low else Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 0.77 if low else 1.0
	elif viewport:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	if vignette:
		vignette.visible = not low_effects
	if water_material:
		water_material.set_shader_parameter("animation", 0.0 if low_effects else 1.0)
	scatter_fraction = (0.4 if low else 1.0) * (0.5 if reduced else 1.0)
	if sim:
		refresh_scatter()

func road_bands() -> Array:
	if sim.active_map:
		return sim.active_map.road_bands
	return [{"axis": "y", "min": 32, "max": 39}, {"axis": "x", "min": 33, "max": 38}]

## Procedural seamless noise textures generated synchronously on the main
## thread (NoiseTexture2D renders on a worker thread and leaks if the game
## quits mid-generation). Cached per parameter set so restarts are free.
static var texture_cache: Dictionary = {}
static var ground_shader: Shader

static func noise_texture(seed_value: int, frequency: float, normal_map: bool = false, bump: float = 8.0, cellular: bool = false, size: int = 256) -> ImageTexture:
	var key = "%d:%s:%s:%s:%s:%d" % [seed_value, frequency, normal_map, bump, cellular, size]
	if texture_cache.has(key):
		return texture_cache[key]
	var noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	if cellular:
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	else:
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
	var image: Image = noise.get_seamless_image(size, size, false, false, 0.15, true)
	if normal_map:
		image.bump_map_to_normal_map(bump)
	image.generate_mipmaps()
	var texture = ImageTexture.create_from_image(image)
	texture_cache[key] = texture
	return texture

## World-triplanar ground shader: a two-tone mottle ramp and a detail layer
## (fine grain or cracks) multiply the vertex colour; a bump layer adds relief;
## the fog-of-war texture tints the result.
func ground_material(mottle: ImageTexture, detail: ImageTexture, normal: ImageTexture, dark: Color, light: Color, mottle_scale: float, detail_scale: float, detail_strength: float, detail_edge: float, normal_strength: float) -> ShaderMaterial:
	if not ground_shader:
		ground_shader = Shader.new()
		ground_shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D mottle_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 dark_tint : source_color = vec3(0.7, 0.72, 0.6);
uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 0.95);
uniform float mottle_scale = 0.08;
uniform float detail_scale = 0.3;
uniform float detail_strength = 0.3;
uniform float detail_edge = 0.5;
uniform float normal_strength = 0.8;
%s
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float triplanar(sampler2D tex, vec3 p, vec3 w, float s) {
	return texture(tex, p.zy * s).r * w.x + texture(tex, p.xz * s).r * w.y + texture(tex, p.xy * s).r * w.z;
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void fragment() {
	vec3 w = abs(world_normal);
	w /= (w.x + w.y + w.z);
	float mottle = triplanar(mottle_tex, world_pos, w, mottle_scale);
	float detail = triplanar(detail_tex, world_pos, w, detail_scale);
	vec3 ramp = mix(dark_tint, light_tint, smoothstep(0.15, 0.85, mottle));
	ramp *= 1.0 - detail_strength * (1.0 - smoothstep(0.0, detail_edge, detail));
	float f = fog_level(world_pos);
	ALBEDO = fog_tint(to_linear(clamp(COLOR.rgb, 0.0, 1.0)) * ramp, f);
	NORMAL_MAP = texture(normal_tex, world_pos.xz * mottle_scale).rgb;
	NORMAL_MAP_DEPTH = normal_strength * w.y;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15 * f;
}""" % DAModels.FOG_SHADER
	var mat = ShaderMaterial.new()
	mat.shader = ground_shader
	mat.set_shader_parameter("mottle_tex", mottle)
	mat.set_shader_parameter("detail_tex", detail)
	mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("dark_tint", dark)
	mat.set_shader_parameter("light_tint", light)
	mat.set_shader_parameter("mottle_scale", mottle_scale)
	mat.set_shader_parameter("detail_scale", detail_scale)
	mat.set_shader_parameter("detail_strength", detail_strength)
	mat.set_shader_parameter("detail_edge", detail_edge)
	mat.set_shader_parameter("normal_strength", normal_strength)
	mat.set_shader_parameter("fog_tex", fog_texture)
	return mat

func grass_material() -> ShaderMaterial:
	return ground_material(
		noise_texture(SCATTER_SEED + 1, 0.02), noise_texture(SCATTER_SEED + 9, 0.12), noise_texture(SCATTER_SEED + 2, 0.045, true, 7.0),
		Color(0.68, 0.76, 0.52), Color(1.0, 1.0, 0.9), 0.08, 0.35, 0.16, 0.6, 0.8)

func road_material() -> ShaderMaterial:
	return ground_material(
		noise_texture(SCATTER_SEED + 3, 0.03), noise_texture(SCATTER_SEED + 4, 0.1, false, 8.0, true), noise_texture(SCATTER_SEED + 4, 0.1, true, 7.0, true),
		Color(0.72, 0.72, 0.7), Color(1.0, 1.0, 0.98), 0.07, 0.09, 0.4, 0.14, 0.9)

## Ground tones shared by the map tiles and the outer ring. Vertex colours carry
## the base tone; the shader's mottle ramp (tints below 1.0 on average) darkens
## slightly, so bases are lifted a little by `gain`.
const GAIN = 1.25
static var dirt_noise: FastNoiseLite
static var moss_noise: FastNoiseLite

static func ground_noise() -> void:
	if dirt_noise:
		return
	dirt_noise = FastNoiseLite.new()
	dirt_noise.seed = SCATTER_SEED + 7
	dirt_noise.frequency = 0.055
	dirt_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moss_noise = FastNoiseLite.new()
	moss_noise.seed = SCATTER_SEED + 8
	moss_noise.frequency = 0.11

static func grass_tone(x: float, z: float, tint: float) -> Color:
	var dirt_mix = clampf((dirt_noise.get_noise_2d(x, z) - 0.18) * 2.4, 0.0, 1.0)
	var base = GRASS.lerp(DIRT, dirt_mix * 0.6)
	var moss = 1.0 + moss_noise.get_noise_2d(x, z) * 0.1
	return Color(base.r * tint * GAIN * moss, base.g * tint * GAIN * moss, base.b * tint * GAIN * moss)

const TERRAIN_ALBEDO = "res://assets/third_party/processed/terrain_albedo.jpg"
const TERRAIN_NORMAL = "res://assets/third_party/processed/terrain_normal.png"
const TERRAIN_ARM = "res://assets/third_party/processed/terrain_arm.jpg"
const CONTROL_SIZE = 256
static var terrain_shader: Shader
var terrain_material: ShaderMaterial

static func has_terrain_textures() -> bool:
	return imported(TERRAIN_ALBEDO) and imported(TERRAIN_NORMAL) and imported(TERRAIN_ARM)

func make_terrain() -> void:
	terrain = Node3D.new()
	add_child(terrain)
	ground_noise()
	var rng = RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	var bands: Array = road_bands()
	var world: Dictionary = cached_world(bands)
	var ground = MeshInstance3D.new()
	ground.mesh = world.mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if has_terrain_textures():
		if not terrain_shader:
			terrain_shader = load("res://assets/shaders/terrain.gdshader")
		terrain_material = ShaderMaterial.new()
		terrain_material.shader = terrain_shader
		terrain_material.set_shader_parameter("albedo_arr", load(TERRAIN_ALBEDO))
		terrain_material.set_shader_parameter("normal_arr", load(TERRAIN_NORMAL))
		terrain_material.set_shader_parameter("arm_arr", load(TERRAIN_ARM))
		terrain_material.set_shader_parameter("control_tex", ImageTexture.create_from_image(world.control))
		terrain_material.set_shader_parameter("macro_tex", noise_texture(SCATTER_SEED + 1, 0.02))
		terrain_material.set_shader_parameter("control_bounds", Vector4(world.origin, world.origin, world.extent, world.extent))
		terrain_material.set_shader_parameter("single_scale", 0.0 if forward_plus else 1.0)
		ground.material_override = terrain_material
	else:
		ground.material_override = grass_material()
	terrain.add_child(ground)
	# Lane dashes along the main avenue between the two bases, drawn with the
	# shared kit shader so the fog of war tints them too.
	var road_x = 35.5
	if sim.active_map and not sim.active_map.starts.is_empty():
		road_x = (sim.active_map.starts[0].x + sim.active_map.starts[1].x) * 0.5
	var dashes = MultiMeshInstance3D.new()
	var dash_mm = MultiMesh.new()
	dash_mm.transform_format = MultiMesh.TRANSFORM_3D
	dash_mm.use_colors = true
	var dash = BoxMesh.new()
	dash.size = Vector3(0.10, 0.02, 1.3)
	dash_mm.mesh = dash
	var dash_rows = range(4, 70, 5)
	dash_mm.instance_count = dash_rows.size()
	for i in dash_rows.size():
		dash_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(road_x, 0.03, dash_rows[i])))
		dash_mm.set_instance_color(i, Color("8a8265"))
	dashes.multimesh = dash_mm
	dashes.material_override = DAModels.shared_material()
	dashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(dashes)
	var pending: Dictionary = {}
	# Impassable cells read as collapsed buildings, blast barriers and rubble;
	# solid 3x3 obstacle blocks occasionally carry a ruined tower.
	var claimed: Dictionary = {}
	var towers: Dictionary = {}
	for c in sim.obstacles:
		var solid = true
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if not sim.obstacles.has(c + Vector2i(dx, dy)):
					solid = false
		for t in towers:
			if absi(t.x - c.x) < 4 and absi(t.y - c.y) < 4:
				solid = false
		if solid and rng.randf() < 0.6:
			towers[c] = true
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					claimed[c + Vector2i(dx, dy)] = true
	for c in sim.obstacles:
		var roll = rng.randf()
		var kind = "rubble"
		var yaw_angle = rng.randf_range(0, TAU)
		var scale = rng.randf_range(0.8, 1.15)
		var jitter = Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		if towers.has(c):
			kind = DAModels.HIGHRISE_KINDS[rng.randi_range(0, DAModels.HIGHRISE_KINDS.size() - 1)]
			yaw_angle = rng.randi_range(0, 3) * PI * 0.5
			scale = rng.randf_range(0.7, 0.85)
			jitter = Vector2.ZERO
		elif claimed.has(c):
			continue
		elif roll < 0.12 and (c.x + c.y) % 3 == 0:
			kind = "ruin"
			yaw_angle = rng.randi_range(0, 3) * PI * 0.5
			scale = rng.randf_range(0.72, 0.88)
			jitter = Vector2.ZERO
		elif roll < 0.3:
			kind = "barrier"
			yaw_angle = rng.randi_range(0, 3) * PI * 0.5 + rng.randf_range(-0.15, 0.15)
			scale = rng.randf_range(0.85, 1.1)
			jitter = Vector2.ZERO
		queue_scenery(pending, kind, Vector2(c.x, c.y) + jitter, 0.0, yaw_angle, scale, Color(1, 1, 1).lerp(Color(0.8, 0.82, 0.78), rng.randf()), -1.0)
	var scenery: Array = sim.active_map.scenery if sim.active_map else []
	if scenery.is_empty():
		for x in [3, 68]:
			for y in [6, 15, 57, 65]:
				scenery.append({"kind": "ruin", "pos": Vector2(x, y)})
	for item in scenery:
		var kind = str(item.get("kind", ""))
		if kind not in DAModels.SCENERY_KINDS:
			continue
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		queue_scenery(pending, kind, pos, 0.0, 0.0, 1.0, Color.WHITE, -1.0)
	scatter_vegetation(pending, rng, bands, scenery)
	for kind in pending:
		build_scatter_batch(kind, pending[kind], false)
	for kind in world.scatter:
		build_scatter_batch(kind, world.scatter[kind], true)

## The whole ground (map plus outer ring) as one heightmap mesh, with the
## control image the terrain shader blends its layers from. Cached per map.
func cached_world(bands: Array) -> Dictionary:
	var key = (sim.active_map.map_id if sim.active_map else "legacy") + str(bands)
	if not ring_cache.has(key):
		ring_cache[key] = build_world(bands, sim.obstacles, sim.bases)
	return ring_cache[key]

static func build_world(bands: Array, obstacles: Dictionary, bases: Array) -> Dictionary:
	ground_noise()
	var rng = RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED + 99
	var n = int(round((DASimulation.SIZE + 2.0 * RING_EXTENT) / RING_STEP)) + 1
	var origin = -0.5 - RING_EXTENT
	var extent = (n - 1) * RING_STEP
	var heights = PackedFloat32Array()
	heights.resize(n * n)
	for i in n:
		for j in n:
			heights[i * n + j] = ring_height(origin + i * RING_STEP, origin + j * RING_STEP)
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for i in n:
		for j in n:
			var x = origin + i * RING_STEP
			var z = origin + j * RING_STEP
			var h = heights[i * n + j]
			vertices[i * n + j] = Vector3(x, h, z)
			var hx = heights[mini(i + 1, n - 1) * n + j] - heights[maxi(i - 1, 0) * n + j]
			var hz = heights[i * n + mini(j + 1, n - 1)] - heights[i * n + maxi(j - 1, 0)]
			normals[i * n + j] = Vector3(-hx / (2.0 * RING_STEP), 1.0, -hz / (2.0 * RING_STEP)).normalized()
			# Gentle tone variation; the textures carry the detail now.
			var moss = 1.0 + moss_noise.get_noise_2d(x, z) * 0.12
			var dirt = clampf((dirt_noise.get_noise_2d(x, z) - 0.18) * 2.4, 0.0, 1.0)
			var tint = rng.randf_range(0.97, 1.03) * moss
			colors[i * n + j] = Color(tint, tint * (1.0 - dirt * 0.08), tint * (1.0 - dirt * 0.15))
	var index = PackedInt32Array()
	var road_quads: Dictionary = {}
	for i in n - 1:
		for j in n - 1:
			var cx = origin + (i + 0.5) * RING_STEP
			var cz = origin + (j + 0.5) * RING_STEP
			var on_road = false
			for band in bands:
				if band_covers(band, cx, cz):
					on_road = true
			var corners = [i * n + j, i * n + j + 1, (i + 1) * n + j, (i + 1) * n + j + 1]
			if on_road:
				for c in corners:
					if river_depth(vertices[c].x, vertices[c].z) < -0.12:
						on_road = false
			if on_road:
				road_quads[Vector2i(i, j)] = true
			index.append(corners[0])
			index.append(corners[2])
			index.append(corners[1])
			index.append(corners[2])
			index.append(corners[3])
			index.append(corners[1])
	var mesh = ArrayMesh.new()
	var data = []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_NORMAL] = normals
	data[Mesh.ARRAY_COLOR] = colors
	data[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	return {"mesh": mesh, "origin": origin, "extent": extent, "control": build_control(bands, obstacles, bases, origin, extent), "scatter": ring_scatter(rng, n, origin, road_quads)}

## Control image: R asphalt (road bands, ending at the river banks), G worn
## ground around obstacles, ruins and bases, B forest floor under the groves.
static func build_control(bands: Array, obstacles: Dictionary, bases: Array, origin: float, extent: float) -> Image:
	var image = Image.create(CONTROL_SIZE, CONTROL_SIZE, false, Image.FORMAT_RGBA8)
	var step = extent / CONTROL_SIZE
	var grove = FastNoiseLite.new()
	grove.seed = SCATTER_SEED + 51
	grove.frequency = 0.05
	grove.fractal_octaves = 2
	var worn = PackedFloat32Array()
	worn.resize(CONTROL_SIZE * CONTROL_SIZE)
	var stamp = func(wx: float, wz: float, radius: float, strength: float):
		var cx = int((wx - origin) / step)
		var cz = int((wz - origin) / step)
		var r = int(ceil(radius / step))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var px = cx + dx
				var pz = cz + dz
				if px < 0 or pz < 0 or px >= CONTROL_SIZE or pz >= CONTROL_SIZE:
					continue
				var d = Vector2(dx, dz).length() * step / radius
				if d > 1.0:
					continue
				var k = pz * CONTROL_SIZE + px
				worn[k] = maxf(worn[k], strength * (1.0 - d * d))
	for c in obstacles:
		stamp.call(float(c.x), float(c.y), 2.6, 0.75)
	for b in bases:
		stamp.call(b.x, b.y, 9.0, 0.55)
	for pz in CONTROL_SIZE:
		for px in CONTROL_SIZE:
			var wx = origin + (px + 0.5) * step
			var wz = origin + (pz + 0.5) * step
			var asphalt = 0.0
			for band in bands:
				var lo = float(band.get("min", 0)) - 0.5
				var hi = float(band.get("max", 0)) + 0.5
				var t = wz if str(band.get("axis", "y")) == "y" else wx
				# Soft half-metre edge so the asphalt does not end on a texel step.
				var inside = minf(t - lo, hi - t)
				asphalt = maxf(asphalt, clampf(inside / 0.8 + 0.5, 0.0, 1.0))
			if river_depth(wx, wz) < -0.12:
				asphalt = 0.0
			var forest = clampf((grove.get_noise_2d(wx, wz) + 0.05) * 2.2, 0.0, 1.0)
			image.set_pixel(px, pz, Color(asphalt, worn[pz * CONTROL_SIZE + px], forest, 1.0))
	return image

func queue_scenery(pending: Dictionary, kind: String, p: Vector2, height: float, yaw_angle: float, scale: float, tint: Color, order: float) -> void:
	if not pending.has(kind):
		pending[kind] = []
	var basis = Basis.from_euler(Vector3(0, yaw_angle, 0)).scaled(Vector3.ONE * scale)
	pending[kind].append({"transform": Transform3D(basis, Vector3(p.x, height, p.y)), "tint": tint, "order": order})

## Seeded noise mask picks the cells for trees, shrubs and loose rubble,
## avoiding roads, obstacles, base areas, deposits, buildings and authored scenery.
func scatter_vegetation(pending: Dictionary, rng: RandomNumberGenerator, bands: Array, scenery: Array) -> void:
	var blocked: Dictionary = {}
	for c in sim.obstacles:
		blocked[c] = true
	var starts: Array = sim.active_map.starts if sim.active_map and sim.active_map.starts.size() >= 2 else [Vector2(12, 36), Vector2(59, 36)]
	for s in starts:
		block_area(blocked, Vector2i(s), 8)
	for e in sim.entities.values():
		if e.owner == -1:
			block_area(blocked, Vector2i(e.pos), 2)
		elif e.building:
			block_area(blocked, Vector2i(e.pos), int(ceil(sim.catalog.buildings[e.kind].radius)) + 1)
	for item in scenery:
		block_area(blocked, Vector2i(item.get("pos", Vector2.ZERO)), 2)
	var map_salt = hash(sim.active_map.map_id) % 1000 if sim.active_map else 0
	var grove = FastNoiseLite.new()
	grove.seed = SCATTER_SEED + 20 + map_salt
	grove.frequency = 0.085
	grove.fractal_octaves = 2
	var shrub = FastNoiseLite.new()
	shrub.seed = SCATTER_SEED + 21 + map_salt
	shrub.frequency = 0.14
	shrub.fractal_octaves = 2
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var c = Vector2i(x, y)
			if blocked.has(c) or is_road_cell(x, y, bands):
				continue
			var near_road = false
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					if is_road_cell(x + dx, y + dy, bands):
						near_road = true
			var g = grove.get_noise_2d(x, y)
			var s = shrub.get_noise_2d(x, y)
			var kind = ""
			if g > 0.26 and rng.randf() < 0.5:
				kind = "tree"
			elif s > 0.15 and rng.randf() < 0.5:
				kind = "bush"
			elif rng.randf() < (0.06 if near_road else 0.015):
				kind = "rubble"
			elif g > 0.05 and rng.randf() < 0.08:
				kind = "bush"
			if kind == "":
				continue
			var p = Vector2(x, y) + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
			var scale = rng.randf_range(0.75, 1.3) if kind == "tree" else rng.randf_range(0.7, 1.2)
			queue_scenery(pending, kind, p, 0.0, rng.randf_range(0, TAU), scale, scenery_tint(kind, rng), rng.randf())

## Per-instance tint: cooler/darker to warmer/yellower foliage; weathered greys for masonry.
static func scenery_tint(kind: String, rng: RandomNumberGenerator) -> Color:
	if kind in ["tree", "bush"]:
		var leaf = Color(0.8, 0.92, 0.78).lerp(Color(1.0, 0.98, 0.72), rng.randf()) * rng.randf_range(0.8, 1.05)
		leaf.a = 1.0
		return leaf
	if kind in DAModels.HIGHRISE_KINDS:
		return Color(1, 1, 1).lerp(Color(0.72, 0.74, 0.8), rng.randf()) * rng.randf_range(0.85, 1.05)
	return Color(1, 1, 1).lerp(Color(0.82, 0.84, 0.78), rng.randf())

static func block_area(blocked: Dictionary, center: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			blocked[center + Vector2i(dx, dy)] = true

func build_scatter_batch(kind: String, entries: Array, low: bool) -> void:
	var batch = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = DAModels.scenery_mesh(kind, low)
	mm.instance_count = entries.size()
	for i in entries.size():
		mm.set_instance_transform(i, HIDDEN)
		mm.set_instance_color(i, entries[i].tint)
		scatter.append({"mm": mm, "index": i, "transform": entries[i].transform, "order": entries[i].order, "shown": false})
	batch.multimesh = mm
	batch.material_override = DAModels.shared_material()
	batch.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	if kind == "bush" or (low and kind != "tree" and kind not in DAModels.HIGHRISE_KINDS):
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(batch)
	scatter_batches[kind + ("_low" if low else "")] = batch

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

## ---- The world outside the map ---------------------------------------------
## A 2-unit height grid from RING_EXTENT before the map to RING_EXTENT past it
## (the quads under the map are skipped), rolling gently, carved by rivers,
## with the map's roads continuing until they reach a bank. Built once per
## map per process (static cache) because the result never changes.
static var ring_cache: Dictionary = {}
static var rolling_noise: FastNoiseLite

static func river_depth(x: float, z: float) -> float:
	var depth = 0.0
	for r in RIVERS:
		var t = x if r.along == "x" else z
		var centre = r.base + r.a1 * sin(r.f1 * t + r.p1) + r.a2 * sin(r.f2 * t)
		var d = absf((z if r.along == "x" else x) - centre)
		var inner = r.width * 0.6
		var outer = r.width + 3.5
		var s = clampf((d - inner) / (outer - inner), 0.0, 1.0)
		s = s * s * (3.0 - 2.0 * s)
		depth = minf(depth, -RIVER_DEPTH * (1.0 - s))
	return depth

## Height of the outer world; 0 along the map edge so it meets the flat tiles.
static func ring_height(x: float, z: float) -> float:
	if not rolling_noise:
		rolling_noise = FastNoiseLite.new()
		rolling_noise.seed = SCATTER_SEED + 40
		rolling_noise.frequency = 0.02
		rolling_noise.fractal_octaves = 2
	var edge = maxf(maxf(-0.5 - x, x - 71.5), maxf(-0.5 - z, z - 71.5))
	var fade = clampf((edge - 3.0) / 10.0, 0.0, 1.0)
	var roll = rolling_noise.get_noise_2d(x, z) * 0.9 * fade
	var depth = river_depth(x, z)
	return roll * (1.0 + depth / RIVER_DEPTH) + depth

static func band_covers(band: Dictionary, x: float, z: float) -> bool:
	var lo = float(band.get("min", 0)) - 0.5
	var hi = float(band.get("max", 0)) + 0.5
	if str(band.get("axis", "y")) == "y":
		return z >= lo and z <= hi
	return x >= lo and x <= hi

## Denser growth and a ruined skyline outside the map: tower clusters follow a
## city mask, groves a second mask; nothing lands in rivers or on the roads.
static func ring_scatter(rng: RandomNumberGenerator, n: int, origin: float, road_quads: Dictionary) -> Dictionary:
	var pending: Dictionary = {}
	var city = FastNoiseLite.new()
	city.seed = SCATTER_SEED + 50
	city.frequency = 0.022
	city.fractal_octaves = 2
	var grove = FastNoiseLite.new()
	grove.seed = SCATTER_SEED + 51
	grove.frequency = 0.05
	grove.fractal_octaves = 2
	var shrub = FastNoiseLite.new()
	shrub.seed = SCATTER_SEED + 52
	shrub.frequency = 0.12
	for i in n - 1:
		for j in n - 1:
			var cx = origin + (i + 0.5) * RING_STEP
			var cz = origin + (j + 0.5) * RING_STEP
			var edge = maxf(maxf(-0.5 - cx, cx - (DASimulation.SIZE - 0.5)), maxf(-0.5 - cz, cz - (DASimulation.SIZE - 0.5)))
			if edge < 1.0 or road_quads.has(Vector2i(i, j)):
				continue
			var c = city.get_noise_2d(cx, cz)
			var g = grove.get_noise_2d(cx, cz)
			var s = shrub.get_noise_2d(cx, cz)
			var kind = ""
			var order = rng.randf()
			var jitter = 0.9
			var scale = 1.0
			if i % 3 == 0 and j % 3 == 0 and c > 0.1 and edge > 4.0 and rng.randf() < 0.3 + c:
				kind = DAModels.HIGHRISE_KINDS[rng.randi_range(0, DAModels.HIGHRISE_KINDS.size() - 1)]
				order = -1.0
				jitter = 0.8
				scale = rng.randf_range(0.85, 1.35)
			elif c > 0.04 and rng.randf() < 0.14:
				kind = "ruin"
				order = -1.0
				scale = rng.randf_range(0.8, 1.15)
			elif c > -0.05 and rng.randf() < 0.12:
				kind = "rubble"
				scale = rng.randf_range(0.8, 1.3)
			elif g > 0.0 and rng.randf() < 0.3 + g:
				kind = "tree"
				scale = rng.randf_range(0.8, 1.45)
			elif s > 0.08 and rng.randf() < 0.45:
				kind = "bush"
				scale = rng.randf_range(0.8, 1.3)
			elif rng.randf() < 0.05:
				kind = "bush" if rng.randf() < 0.7 else "rubble"
				scale = rng.randf_range(0.8, 1.2)
			if kind == "":
				continue
			var p = Vector2(cx + rng.randf_range(-jitter, jitter), cz + rng.randf_range(-jitter, jitter))
			var h = ring_height(p.x, p.y)
			# Banks: willows and scrub down to the water line, nothing in the river.
			if h < -0.3 or (h < -0.05 and kind not in ["tree", "bush"]):
				continue
			var yaw_angle = rng.randi_range(0, 3) * PI * 0.5 + rng.randf_range(-0.12, 0.12) if kind in DAModels.HIGHRISE_KINDS or kind == "ruin" else rng.randf_range(0, TAU)
			if not pending.has(kind):
				pending[kind] = []
			var basis = Basis.from_euler(Vector3(0, yaw_angle, 0)).scaled(Vector3.ONE * scale)
			pending[kind].append({"transform": Transform3D(basis, Vector3(p.x, h, p.y)), "tint": scenery_tint(kind, rng), "order": order})
	return pending

## Rivers through the outer ring: one plane at the water line, visible where the
## ring is carved below it, with two scrolling noise normal layers and a fresnel tint.
func make_water() -> void:
	water = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = Vector2.ONE * (DASimulation.SIZE + RING_EXTENT * 2.0)
	water.mesh = mesh
	water.position = Vector3(35.5, WATER_LEVEL, 35.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D noise_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.165, 0.373, 0.471);
uniform vec3 deep_color : source_color = vec3(0.05, 0.16, 0.24);
uniform float wave_strength = 0.4;
uniform float animation = 1.0;
%s
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float t = TIME * animation;
	vec2 uv_a = world_pos.xz * 0.035 + vec2(t * 0.011, t * 0.007);
	vec2 uv_b = world_pos.xz * 0.08 - vec2(t * 0.009, t * 0.014);
	vec3 n_a = texture(noise_a, uv_a).xyz * 2.0 - 1.0;
	vec3 n_b = texture(noise_b, uv_b).xyz * 2.0 - 1.0;
	vec3 n_world = normalize(vec3((n_a.x + n_b.x) * wave_strength, 1.0, (n_a.y + n_b.y) * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float ripple = 0.5 + 0.35 * (n_a.x + n_b.y);
	float f = fog_level(world_pos);
	ALBEDO = fog_tint(mix(deep_color, shallow_color, 0.35 + 0.65 * fresnel) * (0.8 + 0.4 * ripple), f);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.55 * f;
}""" % DAModels.FOG_SHADER
	water_material.shader = shader
	water_material.set_shader_parameter("noise_a", noise_texture(SCATTER_SEED + 30, 0.03, true, 6.0))
	water_material.set_shader_parameter("noise_b", noise_texture(SCATTER_SEED + 31, 0.06, true, 5.0))
	water_material.set_shader_parameter("shallow_color", Color("2a5f78"))
	water_material.set_shader_parameter("fog_tex", fog_texture)
	water.material_override = water_material
	add_child(water)

## ---- Fog of war ---------------------------------------------------------------
## One texel per cell plus a border at the explored level, so the world outside
## the map reads as known-but-quiet. Shaders sample it bilinearly by world XZ.
func make_fog_texture() -> void:
	fog_image = Image.create(FOG_SIZE, FOG_SIZE, false, Image.FORMAT_R8)
	fog_image.fill(Color(EXPLORED_LEVEL, 0, 0))
	fog_texture = ImageTexture.create_from_image(fog_image)
	DAModels.shared_material().set_shader_parameter("fog_tex", fog_texture)
	RenderingServer.global_shader_parameter_set("fog_of_war", fog_texture)
	RenderingServer.global_shader_parameter_set("fog_bounds", Vector4(-1.5, -1.5, FOG_SIZE, FOG_SIZE))

func refresh_fog() -> void:
	var raw = PackedFloat32Array()
	raw.resize(FOG_SIZE * FOG_SIZE)
	raw.fill(EXPLORED_LEVEL)
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			var c = Vector2i(x, y)
			raw[(y + 1) * FOG_SIZE + x + 1] = 1.0 if sim.visible[0].has(c) else (EXPLORED_LEVEL if sim.explored[0].has(c) else 0.0)
	# A [1 2 1] blur in each axis softens the cell steps before bilinear sampling.
	var pass_x = PackedFloat32Array()
	pass_x.resize(FOG_SIZE * FOG_SIZE)
	for y in FOG_SIZE:
		var row = y * FOG_SIZE
		for x in FOG_SIZE:
			pass_x[row + x] = (raw[row + maxi(x - 1, 0)] + raw[row + x] * 2.0 + raw[row + mini(x + 1, FOG_SIZE - 1)]) * 0.25
	var bytes = PackedByteArray()
	bytes.resize(FOG_SIZE * FOG_SIZE)
	for y in FOG_SIZE:
		var up = maxi(y - 1, 0) * FOG_SIZE
		var row = y * FOG_SIZE
		var down = mini(y + 1, FOG_SIZE - 1) * FOG_SIZE
		for x in FOG_SIZE:
			bytes[row + x] = int((pass_x[up + x] + pass_x[row + x] * 2.0 + pass_x[down + x]) * 0.25 * 255.0 + 0.5)
	fog_image.set_data(FOG_SIZE, FOG_SIZE, false, Image.FORMAT_R8, bytes)
	fog_texture.update(fog_image)
	refresh_scatter()

## Scenery follows the density setting only; the fog texture tints it in place.
func refresh_scatter() -> void:
	for entry in scatter:
		var show = entry.order < scatter_fraction
		if show != entry.shown:
			entry.shown = show
			entry.mm.set_instance_transform(entry.index, entry.transform if show else HIDDEN)

## ---- Camera -------------------------------------------------------------------
## Perspective camera on a fixed elevation; `zoom` is the height of the view at
## the focus point, as it was for the orthographic size, so the zoom limits and
## the edge-pan speed keep their feel.
func camera_distance() -> float:
	return zoom * 0.5 / tan(deg_to_rad(CAMERA_FOV * 0.5))

func update_camera() -> void:
	var cam_min = sim.active_map.camera_min if sim.active_map else Vector2.ONE
	var cam_max = sim.active_map.camera_max if sim.active_map else Vector2(70, 70)
	focus = focus.clamp(cam_min, cam_max)
	var distance = camera_distance()
	var elevation = deg_to_rad(CAMERA_ELEVATION)
	var offset = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	camera.position = Vector3(focus.x, 0, focus.y) + offset
	camera.look_at(Vector3(focus.x, 0, focus.y))
	if sun:
		sun.directional_shadow_max_distance = distance + shadow_reach

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

## Screen-right on the ground for the current yaw (see update_camera).
func camera_right_ground() -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))

## The visual for an entity: a photoreal sprite card when the kind has one,
## otherwise the Blender model with the same ground disc under it so mixed
## kinds share the depth cues. `accent.a == 0` draws no owner disc (ghosts).
func entity_node(e: Dictionary, accent: Color = Color(0, 0, 0, 0)) -> Node3D:
	var owner: int = e.get("owner", -1)
	var color: Color = accent if accent.a > 0 else (sim.faction_color(owner) if owner >= 0 else Color.WHITE)
	var disc = color if owner >= 0 and accent.a == 0 else Color(color.r, color.g, color.b, 0.0)
	var cells = (sim.catalog.buildings[e.kind].radius * 2 + 1) if e.get("building", false) else 1
	if DASprites.has_sprite(e.kind):
		return DASprites.card(e.kind, owner, cells, disc)
	var n = DAModels.entity(e.kind, owner, color)
	if owner >= 0 and accent.a == 0:
		var diameter = DASprites.CONTACT_SCALE * (1.0 if not e.get("building", false) else cells * sqrt(2.0))
		var ring_radius = 0.65 if not e.get("building", false) else (cells - 1) * 0.5 + 0.4
		DASprites.ground_only(n, disc, diameter, ring_radius)
	return n

func sync(dt: float, selected: Array) -> void:
	for id in models.keys():
		if not sim.entities.has(id):
			models[id].queue_free()
			models.erase(id)
			selections.erase(id)
	var batch_transforms: Dictionary = {}
	for e in sim.entities.values():
		if not models.has(e.id):
			var n = entity_node(e)
			add_child(n)
			models[e.id] = n
			if e.owner >= 0 and not e.building and not DASprites.is_card(n):
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
				if DASprites.is_card(model):
					DASprites.set_rise(model, progress)
				else:
					model.scale.y = 0.15 + progress * 0.85
			elif e.order != "idle":
				var direction: Vector2 = e.destination - e.pos
				if not e.path.is_empty():
					direction = e.path[0] - e.pos
				if direction.length() > 0.1:
					if DASprites.is_card(model):
						DASprites.set_flip(model, direction.dot(camera_right_ground()) < 0.0)
					else:
						model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.y), dt * 10)
		if e.owner >= 0 and not e.building and model.visible and not DASprites.is_card(model):
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
	batch.material_override = DAModels.shared_material()
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
			ghost = entity_node({"kind": kind, "owner": 0, "building": true}, Color(1, 1, 1, 0))
			add_child(ghost)
	if ghost:
		ghost.position = Vector3(roundf(p.x), 0, roundf(p.y))
		if DASprites.is_card(ghost):
			DASprites.set_tint(ghost, Color(0.25, 1, 0.7, 0.5) if valid else Color(1, 0.2, 0.15, 0.5))
			return
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
