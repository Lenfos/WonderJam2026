shader_type canvas_item;

uniform float speed = 1.5;             // vitesse de pulsation
uniform float cell_px = 3.0;           // taille des groupes qui pulsent ensemble
uniform float threshold = 0.12;        // baisse-le si des fenêtres ne sont pas détectées
uniform vec3 glow_color : source_color = vec3(1.0, 0.85, 0.35);
uniform float glow_strength = 0.9;     // intensité sur la fenêtre elle-même
uniform float halo_strength = 1.4;     // intensité de la lueur autour
uniform float halo_radius = 2.0;       // écartement des échantillons (en pixels de texture)
uniform bool debug_mask = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float window_mask(sampler2D tex, vec2 uv) {
	vec3 c = texture(tex, uv).rgb;
	float yellow = (c.r + c.g) * 0.5 - c.b;
	return smoothstep(threshold, threshold + 0.2, yellow);
}

// Pulsation propre à chaque petit groupe de pixels (jamais complètement éteinte)
float pulse(vec2 uv, vec2 psize, float t) {
	vec2 cell = floor(uv / psize / cell_px);
	float f = sin(t * speed + hash(cell) * 40.0) * 0.5 + 0.5;
	return 0.35 + 0.65 * f;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float w = window_mask(TEXTURE, UV);
	float p = pulse(UV, TEXTURE_PIXEL_SIZE, TIME);

	// 1) La fenêtre elle-même brille
	col.rgb += glow_color * w * glow_strength * p;

	// 2) Halo : on additionne la lueur des fenêtres voisines
	float halo = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 off = vec2(float(x), float(y));
			vec2 uv = UV + off * TEXTURE_PIXEL_SIZE * halo_radius;
			float falloff = 1.0 / (1.0 + dot(off, off));
			halo += window_mask(TEXTURE, uv) * pulse(uv, TEXTURE_PIXEL_SIZE, TIME) * falloff;
		}
	}
	halo = clamp(halo * halo_strength * 0.25, 0.0, 1.0);
	col.rgb += glow_color * halo * (1.0 - w);

	if (debug_mask) {
		COLOR = vec4(vec3(w), 1.0);
	} else {
		COLOR = col;
	}
}