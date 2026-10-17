// Grain de pellicule, vignette et néon qui grésille.
// À poser sur un ColorRect plein écran, dernier enfant de l'interface.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.07;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.6;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.35;
uniform float flicker_chance : hint_range(0.0, 0.2) = 0.02;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;

	float vignette = smoothstep(0.3, 0.95, distance(SCREEN_UV, vec2(0.5)));
	color *= 1.0 - vignette * vignette_strength;

	// Le néon baisse brièvement, en moyenne toutes les 4 s.
	float tick = floor(TIME * 12.0);
	float dip = step(1.0 - flicker_chance, hash(vec2(tick, 7.0)));
	color *= 1.0 - dip * flicker_strength;

	// Grain renouvelé 24 fois par seconde, comme une pellicule.
	float frame = floor(TIME * 24.0);
	float grain = hash(floor(FRAGCOORD.xy) + vec2(frame * 13.0, frame * 7.0)) - 0.5;
	color += grain * grain_strength;

	COLOR = vec4(color, 1.0);
}
