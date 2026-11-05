shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, depth_prepass_alpha;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Photoreal sprite card (scripts/sprite_cards.gd): a bottom-pivoted quad that
// always faces the camera at its authored size, so the baked isometric render
// is never foreshortened. The card's base is moved `anchor_offset` toward the
// camera (half the footprint diagonal for buildings) so the drawn footprint
// diamond covers the grid cells while the node stays at the footprint centre.
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float anchor_offset = 0.0;
uniform float card_height = 1.0;
instance uniform float rise = 1.0;   // construction: fraction of the height drawn, bottom up
instance uniform float flip = 0.0;   // 1.0 mirrors the card (unit walking screen-left)
instance uniform vec4 tint : source_color = vec4(1.0);

varying float height_frac;
varying vec3 origin;

void vertex() {
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	fwd.y = 0.0;
	fwd = normalize(fwd);
	origin = MODEL_MATRIX[3].xyz;
	vec3 world = origin - fwd * anchor_offset + cam_right * VERTEX.x + cam_up * VERTEX.y;
	height_frac = VERTEX.y / card_height;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	if (height_frac > rise) {
		discard;
	}
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, flip), UV.y);
	vec4 col = texture(tex, uv);
	float f = fog_level(origin);
	ALBEDO = fog_tint(col.rgb * tint.rgb, f);
	ALPHA = col.a * tint.a;
}
