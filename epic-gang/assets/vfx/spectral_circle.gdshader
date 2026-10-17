// Cercle du piège spectral, posé au sol : anneaux qui tournent, tirets comme
// des glyphes, rayons lents et lueur qui pulse.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 color : source_color = vec4(0.6, 0.35, 1.0, 1.0);

float ring(float r, float radius, float width) {
	return smoothstep(width, 0.0, abs(r - radius));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float outer = ring(r, 0.92, 0.035);
	float inner = ring(r, 0.7, 0.025);
	float glyphs = step(0.45, fract(a * 18.0 + TIME * 0.25)) * ring(r, 0.81, 0.05);
	float spokes = ring(abs(fract(a * 6.0 - TIME * 0.12) - 0.5), 0.0, 0.035) * step(0.25, r) * step(r, 0.68) * 0.5;
	float glow = smoothstep(1.0, 0.0, r) * 0.18;
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	float v = (outer + inner + glyphs + spokes) * pulse + glow;
	ALBEDO = color.rgb * v * 1.8;
	ALPHA = clamp(v, 0.0, 1.0);
}
