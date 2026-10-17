// Effets "dans le monde", dessinés sous le HUD (l'interface reste nette) :
// vue perdue, vision spectrale, accélération et onde de choc, en une passe.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Sacrifice "vision" : flou et image dédoublée qui dérive.
uniform float vision : hint_range(0.0, 1.0) = 0.0;
// Pouvoir "spectral_vision" : monde bleu froid, désaturé, qui tremble.
uniform float spectral : hint_range(0.0, 1.0) = 0.0;
// Pouvoir "speed_boost" : traînées de vent sur les bords.
uniform float boost : hint_range(0.0, 1.0) = 0.0;
// Pouvoir "shockwave" : progression de l'anneau (0 = inactif, 1 = fini).
uniform float shock : hint_range(0.0, 1.0) = 0.0;
uniform vec2 shock_center = vec2(0.5, 0.5);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	// Onde de choc : un anneau qui s'élargit et réfracte l'image.
	float band = 0.0;
	if (shock > 0.0 && shock < 1.0) {
		vec2 d = (uv - shock_center) * vec2(aspect, 1.0);
		float dist = length(d);
		band = 1.0 - smoothstep(0.0, 0.07, abs(dist - shock * 1.3));
		vec2 push = normalize(d + 1e-5) * band * 0.04 * (1.0 - shock);
		uv -= push / vec2(aspect, 1.0);
	}

	// Vision spectrale : léger tremblement fantôme.
	uv.x += sin(uv.y * 38.0 + TIME * 6.0) * 0.0016 * spectral;

	vec3 color;
	if (vision > 0.0) {
		float lod = vision * 1.7;
		vec2 drift = vec2(sin(TIME * 0.55), cos(TIME * 0.4)) * 0.01 * vision;
		vec3 a = textureLod(screen_texture, uv, lod).rgb;
		vec3 b = textureLod(screen_texture, uv + drift, lod).rgb;
		color = mix(a, b, 0.35 * vision);
	} else {
		color = texture(screen_texture, uv).rgb;
	}

	// Accélération : les bords s'étirent vers l'arrière, traînées de vent.
	if (boost > 0.0) {
		vec2 dir = uv - vec2(0.5);
		float edge = smoothstep(0.2, 0.7, length(dir * vec2(aspect, 1.0)));
		vec3 smear = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			smear += texture(screen_texture, uv - dir * 0.05 * boost * edge * float(i) / 5.0).rgb;
		}
		color = mix(color, smear / 6.0, edge);
		float angle = atan(dir.y, dir.x);
		float streak = step(0.965, hash(vec2(floor(angle * 90.0), floor(TIME * 18.0))));
		color += vec3(0.75, 0.85, 1.0) * streak * edge * boost * 0.35;
		color = mix(color, color * vec3(0.85, 0.95, 1.15), boost * 0.45);
	}

	// Vision spectrale : bleu froid désaturé.
	float lum = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(lum) * vec3(0.5, 0.72, 1.0) * 1.15, spectral * 0.85);

	// Onde de choc : l'anneau brille légèrement en bleu.
	color += vec3(0.45, 0.65, 1.0) * band * 0.3 * (1.0 - shock);

	COLOR = vec4(color, 1.0);
}
