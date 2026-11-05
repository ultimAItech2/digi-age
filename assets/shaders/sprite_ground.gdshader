shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://assets/shaders/fog_of_war.gdshaderinc"

// Ground quad under a card or model: a soft contact shadow fading out to the
// quad's edge and, at `ring_frac` of the half-size, the owner's disc ring.
uniform vec4 disc : source_color = vec4(0.0);
uniform float contact_alpha = 0.3;
uniform float ring_frac = 0.67;

varying vec3 origin;

void vertex() {
	origin = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float contact = smoothstep(1.0, 0.45, r) * contact_alpha;
	float ring = smoothstep(ring_frac - 0.06, ring_frac - 0.03, r) * (1.0 - smoothstep(ring_frac + 0.03, ring_frac + 0.06, r));
	float ring_alpha = ring * disc.a * 0.55;
	float a = contact + ring_alpha * (1.0 - contact);
	float f = fog_level(origin);
	ALBEDO = fog_tint(disc.rgb * (ring_alpha / max(a, 0.0001)), f);
	ALPHA = a * mix(0.4, 1.0, f);
}
