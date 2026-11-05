shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Sun-cast shadow of a sprite card: the card's silhouette laid flat on the
// ground, each point `t` above the base moved `t * shadow_length` along the
// sun's ground direction (Age of AI's sheared silhouette shadow).
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float anchor_offset = 0.0;
uniform float card_height = 1.0;
uniform vec2 sun_dir = vec2(0.165, 0.986);
uniform float shadow_length = 0.9;
uniform float strength = 0.38;
instance uniform float rise = 1.0;
instance uniform float flip = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);

varying float height_frac;
varying vec3 origin;

void vertex() {
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right.y = 0.0;
	right = normalize(right);
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	fwd.y = 0.0;
	fwd = normalize(fwd);
	origin = MODEL_MATRIX[3].xyz;
	vec3 base = origin - fwd * anchor_offset;
	vec3 world = base + right * VERTEX.x + vec3(sun_dir.x, 0.0, sun_dir.y) * VERTEX.y * shadow_length;
	world.y = origin.y + 0.02;
	height_frac = VERTEX.y / card_height;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	if (height_frac > rise) {
		discard;
	}
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, flip), UV.y);
	float a = texture(tex, uv).a;
	ALBEDO = vec3(0.0);
	ALPHA = a * strength * tint.a * mix(0.3, 1.0, fog_level(origin));
}
