// Shared fog-of-war sampling for shaders loaded from files. The battlefield
// publishes its fog texture (one texel per cell plus a one-cell border, 74x74;
// 1.0 visible, ~0.55 explored, 0.0 unexplored) through the `fog_of_war` and
// `fog_bounds` globals; the maths matches DAModels.FOG_SHADER so kit meshes and
// terrain tint identically.
global uniform sampler2D fog_of_war : hint_default_white, filter_linear, repeat_disable;
global uniform vec4 fog_bounds;

float fog_level(vec3 p) {
	vec2 uv = (p.xz - fog_bounds.xy) / fog_bounds.zw;
	return texture(fog_of_war, clamp(uv, vec2(0.0), vec2(1.0))).r;
}

vec3 fog_tint(vec3 c, float f) {
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	// Explored ground stays readable: dimmed and a little greyed, not blacked out.
	float light = pow(mix(0.52, 1.0, f), 1.1);
	return mix(vec3(grey), c, mix(0.55, 1.0, f)) * light;
}
