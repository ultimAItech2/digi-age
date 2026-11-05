shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Layers: 0 grass, 1 forest floor, 2 mud, 3 asphalt, 4 rock (tools/build_terrain_arrays.gd).
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray arm_arr : filter_linear_mipmap_anisotropic, repeat_enable;
// R asphalt, G worn ground, B forest floor; covers control_bounds in world XZ.
uniform sampler2D control_tex : filter_linear, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 control_bounds = vec4(-110.5, -110.5, 292.0, 292.0);
uniform float macro_tiling = 0.11;
uniform float detail_tiling = 0.55;
uniform float normal_strength = 1.0;
uniform float single_scale = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 vertex_tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_tint = COLOR.rgb;
}

vec3 sample_layer(sampler2DArray arr, vec2 uv, float layer, float macro_w) {
	vec3 a = texture(arr, vec3(uv * macro_tiling, layer)).rgb;
	if (single_scale > 0.5) return a;
	vec3 b = texture(arr, vec3(uv * detail_tiling + vec2(0.37, 0.61), layer)).rgb;
	return mix(b, a, macro_w);
}

void fragment() {
	vec2 cuv = (world_pos.xz - control_bounds.xy) / control_bounds.zw;
	vec3 control = texture(control_tex, clamp(cuv, vec2(0.0), vec2(1.0))).rgb;
	float macro = texture(macro_tex, world_pos.xz * 0.012).r;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock_w = smoothstep(0.32, 0.6, slope);
	float bank = smoothstep(0.05, -0.55, world_pos.y);
	float mud_w = max(control.g, bank) * (1.0 - rock_w);
	float asphalt_w = control.r * (1.0 - rock_w) * (1.0 - bank);
	float forest_w = control.b * (1.0 - mud_w) * (1.0 - asphalt_w) * (1.0 - rock_w);
	// Verges: moss creeps over the asphalt edge.
	float verge = smoothstep(0.08, 0.45, control.r) * (1.0 - smoothstep(0.45, 0.9, control.r));
	forest_w = max(forest_w, verge * 0.5 * (1.0 - rock_w));
	asphalt_w *= 1.0 - verge * 0.5;
	float grass_w = clamp(1.0 - (rock_w + mud_w + asphalt_w + forest_w), 0.0, 1.0);
	float total = grass_w + forest_w + mud_w + asphalt_w + rock_w;
	vec4 w = vec4(grass_w, forest_w, mud_w, asphalt_w) / total;
	rock_w /= total;
	float macro_w = 0.5 + 0.2 * (macro - 0.5);
	vec2 uv = world_pos.xz;
	vec3 albedo = vec3(0.0);
	vec3 nm = vec3(0.0);
	vec3 arm = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float wi = w[i];
		if (wi < 0.004) continue;
		albedo += sample_layer(albedo_arr, uv, float(i), macro_w) * wi;
		nm += (sample_layer(normal_arr, uv, float(i), macro_w) * 2.0 - 1.0) * wi;
		arm += sample_layer(arm_arr, uv, float(i), macro_w) * wi;
	}
	if (rock_w > 0.004) {
		// Triplanar rock on the slopes so the cliffs do not stretch.
		vec3 bw = abs(world_normal);
		bw /= bw.x + bw.y + bw.z;
		vec3 ra = texture(albedo_arr, vec3(world_pos.zy * macro_tiling, 4.0)).rgb * bw.x + texture(albedo_arr, vec3(world_pos.xz * macro_tiling, 4.0)).rgb * bw.y + texture(albedo_arr, vec3(world_pos.xy * macro_tiling, 4.0)).rgb * bw.z;
		vec3 rarm = texture(arm_arr, vec3(world_pos.xz * macro_tiling, 4.0)).rgb;
		albedo += ra * rock_w;
		arm += rarm * rock_w;
		nm += vec3(0.0, 0.0, 1.0) * rock_w;
	}
	albedo *= 0.86 + 0.28 * macro;
	albedo *= vertex_tint;
	float f = fog_level(world_pos);
	ALBEDO = fog_tint(albedo, f);
	// Texture tangent space maps U to world +X and V to world +Z, so bend the
	// geometric normal directly instead of relying on mesh tangents.
	vec3 bent = normalize(world_normal + vec3(nm.x, 0.0, nm.y) * normal_strength * clamp(world_normal.y, 0.0, 1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	AO = mix(1.0, arm.r, 0.8);
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = clamp(arm.g, 0.35, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3 * mix(0.3, 1.0, f);
}
