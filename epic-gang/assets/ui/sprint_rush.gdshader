// Effet de course : bords flous en traînées vers le centre, tunnel qui
// respire, et pulsation rouge quand le souffle est épuisé.
// Piloté par le HUD (intensity, exhaustion, pulse).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float exhaustion : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 exhaust_color : source_color = vec4(0.5, 0.04, 0.03, 1.0);

const int SAMPLES = 8;

void fragment() {
	vec2 dir = SCREEN_UV - vec2(0.5);
	float d = length(dir * vec2(1.0, 0.75));
	float edge = smoothstep(0.18, 0.75, d);

	// Flou radial : seuls les bords s'étirent, le centre reste net.
	float stretch = edge * intensity * (0.035 + 0.02 * pulse);
	vec3 color = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		color += texture(screen_texture, SCREEN_UV - dir * stretch * t).rgb;
	}
	color /= float(SAMPLES);

	// Tunnel qui se resserre à chaque inspiration.
	float tunnel = smoothstep(0.24 - 0.07 * pulse, 0.85, d);
	color *= 1.0 - tunnel * (intensity * 0.55 + exhaustion * 0.25);

	// Épuisement : les bords battent en rouge.
	color = mix(color, exhaust_color.rgb, edge * exhaustion * (0.3 + 0.45 * pulse));

	COLOR = vec4(color, 1.0);
}
