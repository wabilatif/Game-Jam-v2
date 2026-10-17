// Vision spectrale : contour lumineux rouge qui pulse, visible à travers les
// murs et le brouillard. Posé en material_overlay sur le monstre.
shader_type spatial;
render_mode unshaded, depth_test_disabled, fog_disabled, cull_back;

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.07, 1.0);
uniform float pulse_speed = 6.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);
	ALBEDO = color.rgb;
	// Contour vif + léger remplissage pour rester lisible de loin.
	ALPHA = clamp(rim * 1.6 * pulse + 0.32 * pulse, 0.0, 1.0);
}
