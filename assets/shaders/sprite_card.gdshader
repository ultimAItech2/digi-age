shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, depth_prepass_alpha;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Photoreal sprite card (scripts/sprite_cards.gd): a bottom-pivoted quad that
// always faces the camera at its authored size, so the baked isometric render
// is never foreshortened. The card's base is moved `anchor_offset` toward the
// camera so the picture's origin row lands on the node's ground point.
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;
uniform float mask_on = 0.0;         // 1.0 when mask_tex marks the faction-coloured parts
uniform vec2 grid = vec2(1.0);       // atlas columns and rows
uniform float anchor_offset = 0.0;
instance uniform vec2 cell = vec2(0.0);   // atlas column (state / frame) and row (facing)
instance uniform vec4 team : source_color = vec4(1.0);
instance uniform vec4 tint : source_color = vec4(1.0);

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float TEAM_GAIN = 2.1;

varying vec3 origin;

void vertex() {
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	fwd.y = 0.0;
	fwd = normalize(fwd);
	origin = MODEL_MATRIX[3].xyz;
	vec3 world = origin - fwd * anchor_offset + cam_right * VERTEX.x + cam_up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = (cell + UV) / grid;
	vec4 col = texture(tex, uv);
	// Masked parts were rendered as worn grey paint. Give them the owner's hue at the
	// paint's own brightness, so shading, chips and dirt in the render show through.
	float painted = mask_on * texture(mask_tex, uv).r;
	float value = dot(col.rgb, LUMA);
	vec3 hue = mix(team.rgb, vec3(dot(team.rgb, LUMA)), 0.15);
	col.rgb = mix(col.rgb, hue * value * TEAM_GAIN, painted);
	float f = fog_level(origin);
	ALBEDO = fog_tint(col.rgb * tint.rgb, f);
	ALPHA = col.a * tint.a;
}
