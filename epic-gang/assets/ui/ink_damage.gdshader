// Encre abîmée pour les titres : tremblement, copie rouge décalée,
// encre rongée, bavure et déchirures pendant les "crises".
// À poser sur un ColorRect enfant du Label, qui déborde un peu de son texte.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec4 ghost_color : source_color = vec4(0.56, 0.11, 0.09, 1.0);
uniform vec4 bleed_color : source_color = vec4(0.35, 0.04, 0.03, 1.0);
uniform float ghost_offset_px = 7.0;
uniform float tremble_px = 0.8;
uniform float tear_px = 14.0;
uniform float erosion : hint_range(0.0, 1.0) = 0.7;
uniform float crisis_chance : hint_range(0.0, 0.5) = 0.07;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ink(vec2 uv) {
	vec3 c = texture(screen_texture, uv).rgb;
	return smoothstep(0.38, 0.62, dot(c, vec3(0.299, 0.587, 0.114)));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float tick = floor(TIME * 14.0);
	float crisis = step(1.0 - crisis_chance, hash(vec2(tick, 3.1)));

	// Tremblement permanent, plus des bandes qui se déchirent pendant une crise.
	float tremble = (noise(vec2(FRAGCOORD.y * 0.08, TIME * 9.0)) - 0.5) * 2.0 * tremble_px;
	float band = floor(FRAGCOORD.y / 6.0);
	float tear = (hash(vec2(band, tick)) - 0.5) * 2.0 * tear_px * crisis * step(0.7, hash(vec2(band * 1.7, tick)));
	vec2 uv = SCREEN_UV + vec2((tremble + tear) * px.x, 0.0);

	vec3 color = texture(screen_texture, uv).rgb;
	float mask = ink(uv);

	// Encre rongée : trous fixes dans les lettres, comme une impression usée.
	float wear = noise(FRAGCOORD.xy * 0.35) * 0.6 + noise(FRAGCOORD.xy * 0.06) * 0.4;
	float hole = smoothstep(erosion, erosion + 0.12, 1.0 - wear) * mask;
	color = mix(color, color * 0.18, hole * 0.85);

	// Bavure : halo rouge sombre autour des lettres.
	float halo = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785;
		halo += ink(uv + vec2(cos(a), sin(a)) * px * 3.5);
	}
	halo = clamp(halo / 8.0 - mask, 0.0, 1.0);
	color += bleed_color.rgb * halo * 0.9;

	// Double exposition : copie rouge décalée, plus forte pendant une crise.
	float drift = ghost_offset_px * (1.0 + crisis * 2.5);
	float ghost = ink(uv - vec2(drift, drift * 0.35) * px);
	color += ghost_color.rgb * ghost * (1.0 - mask) * (0.28 + crisis * 0.6);

	COLOR = vec4(color, 1.0);
}
