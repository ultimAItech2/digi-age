shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Cast shadow of a MultiMesh scenery card: the silhouette laid on the ground
// and sheared along the sun, as sprite_shadow.gdshader does for single cards.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(1.0);
uniform float base_height = 0.0;
uniform vec2 sun_dir = vec2(0.165, 0.986);
uniform float shadow_length = 0.9;
uniform float strength = 0.65;

varying vec3 origin;
varying float column;

void vertex() {
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = normalize(right);
	vec3 across = vec3(sun_dir.y, 0.0, -sun_dir.x);
	across *= dot(across, right) < 0.0 ? -1.0 : 1.0;
	float size = length(MODEL_MATRIX[0].xyz);
	origin = MODEL_MATRIX[3].xyz;
	vec3 world = origin + (across * VERTEX.x + vec3(sun_dir.x, 0.0, sun_dir.y) * (VERTEX.y - base_height) * shadow_length) * size;
	world.y = origin.y + 0.03;
	column = INSTANCE_CUSTOM.x;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float a = texture(tex, (vec2(mod(column, grid.x), floor(column / grid.x)) + UV) / grid).a;
	ALBEDO = vec3(0.0);
	ALPHA = a * strength * mix(0.3, 1.0, fog_level(origin));
}
