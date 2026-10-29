// Shared fog-of-war tint. The battlefield publishes a 96x96 R8 texture
// (1.0 visible, 0.75 explored, 0.45 unexplored) covering the 72x72 grid
// plus a 12-cell margin, through the `fog_of_war` / `fog_bounds` globals.
global uniform sampler2D fog_of_war : filter_linear, repeat_disable;
global uniform vec4 fog_bounds;

float fog_visibility(vec2 world_xz) {
	vec2 uv = (world_xz - fog_bounds.xy) / fog_bounds.zw;
	uv = clamp(uv, vec2(0.5 / 96.0), vec2(1.0 - 0.5 / 96.0));
	return texture(fog_of_war, uv).r;
}

vec3 fog_tint(vec3 albedo, vec2 world_xz) {
	float vis = fog_visibility(world_xz);
	float luma = dot(albedo, vec3(0.3, 0.59, 0.11));
	// Explored: cooler and flatter. Unexplored: dark desaturated blue-grey.
	vec3 explored = mix(albedo, vec3(luma) * vec3(0.82, 0.9, 1.0), 0.45);
	vec3 unexplored = mix(albedo, vec3(luma) * vec3(0.55, 0.65, 0.85), 0.8) * 0.5;
	float explored_w = smoothstep(0.45, 0.75, vis);
	float visible_w = smoothstep(0.75, 1.0, vis);
	return mix(mix(unexplored, explored, explored_w), albedo, visible_w);
}
