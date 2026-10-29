shader_type canvas_item;
render_mode blend_mix;
uniform float strength : hint_range(0.0, 1.0) = 0.28;
uniform float radius : hint_range(0.2, 1.5) = 0.78;

void fragment() {
	vec2 centred = (UV - 0.5) * vec2(1.0, 0.85);
	float d = length(centred) / radius;
	float v = smoothstep(0.55, 1.35, d) * strength;
	COLOR = vec4(0.02, 0.03, 0.05, v);
}
