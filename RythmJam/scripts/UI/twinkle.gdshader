shader_type canvas_item;

uniform float speed = 1.2;
uniform float amount = 1.0;        // 1 = la fenêtre s'éteint complètement
uniform float cell_px = 3.0;       // taille des groupes qui clignotent ensemble
uniform float threshold = 0.12;    // baisse-le si des fenêtres ne sont pas détectées
uniform float sample_dist = 3.0;   // distance (en pixels) où on prend la couleur de l'immeuble
uniform bool debug_mask = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float window_mask(vec2 uv) {
	vec3 c = texture(TEXTURE, uv).rgb;
	float yellow = (c.r + c.g) * 0.5 - c.b;
	return smoothstep(threshold, threshold + 0.2, yellow);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float is_window = window_mask(UV);

	// Couleur de l'entourage : moyenne des voisins qui ne sont pas des fenêtres
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	vec2 px = TEXTURE_PIXEL_SIZE * sample_dist;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			if (x == 0 && y == 0) {
				continue;
			}
			vec2 uv = UV + vec2(float(x), float(y)) * px;
			float w = 1.0 - window_mask(uv);
			sum += texture(TEXTURE, uv).rgb * w;
			wsum += w;
		}
	}
	vec3 surround = wsum > 0.001 ? sum / wsum : col.rgb * 0.3;

	// Clignotement par petit groupe de pixels
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE / cell_px);
	float flicker = sin(TIME * speed + hash(cell) * 40.0) * 0.5 + 0.5;
	float on = smoothstep(0.1, 0.35, flicker);

	// La fenêtre éteinte prend la couleur de l'immeuble au lieu du noir
	col.rgb = mix(col.rgb, surround, is_window * (1.0 - on) * amount);

	if (debug_mask) {
		COLOR = vec4(vec3(is_window), 1.0);
	} else {
		COLOR = col;
	}
}