shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Sun-cast shadow of a sprite card: the card's silhouette laid flat on the
// ground, each point `t` above the base moved `t * shadow_length` along the
// sun's ground direction (Age of AI's sheared silhouette shadow). The width
// runs along the world axis perpendicular to the sun, mirrored to follow the
// camera's right, so rotating the view never collapses the shadow to a line.
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(1.0);
uniform float base_height = 0.0;     // height of the picture's origin row above the card's bottom edge
instance uniform vec2 cell = vec2(0.0);
uniform vec2 sun_dir = vec2(0.165, 0.986);
uniform float shadow_length = 0.9;
uniform float strength = 0.65;
instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 origin;

void vertex() {
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = normalize(right);
	vec3 across = vec3(sun_dir.y, 0.0, -sun_dir.x);
	across *= dot(across, right) < 0.0 ? -1.0 : 1.0;
	origin = MODEL_MATRIX[3].xyz;
	vec3 world = origin + across * VERTEX.x + vec3(sun_dir.x, 0.0, sun_dir.y) * (VERTEX.y - base_height) * shadow_length;
	world.y = origin.y + 0.02;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = (cell + UV) / grid;
	float a = texture(tex, uv).a;
	ALBEDO = vec3(0.0);
	ALPHA = a * strength * tint.a * mix(0.3, 1.0, fog_level(origin));
}
