shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, depth_prepass_alpha;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Scenery sprite cards drawn through a MultiMesh (trees, shrubs, ruins): the
// same camera-facing card as sprite_card.gdshader, with the per-instance data
// a MultiMesh can carry. The instance transform gives the ground point and
// the scale, INSTANCE_CUSTOM.x the atlas column (the variant), COLOR a tint.
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 grid = vec2(1.0);
uniform float anchor_offset = 0.0;

varying vec3 origin;
varying float column;
varying vec3 instance_tint;

void vertex() {
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	fwd.y = 0.0;
	fwd = normalize(fwd);
	float size = length(MODEL_MATRIX[0].xyz);
	origin = MODEL_MATRIX[3].xyz;
	vec3 world = origin + (cam_right * VERTEX.x + cam_up * VERTEX.y - fwd * anchor_offset) * size;
	column = INSTANCE_CUSTOM.x;
	instance_tint = COLOR.rgb;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	// Variants run left to right and wrap onto further rows.
	vec4 col = texture(tex, (vec2(mod(column, grid.x), floor(column / grid.x)) + UV) / grid);
	ALBEDO = fog_tint(col.rgb * instance_tint, fog_level(origin));
	ALPHA = col.a;
}
