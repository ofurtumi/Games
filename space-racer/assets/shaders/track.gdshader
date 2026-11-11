shader_type spatial;
// Track ribbon: UV.x is distance along the track (m), UV.y goes 0..1 across.
// Asphalt grain, red/white kerbs, white edge lines, a dashed centre line and
// a chequered start/finish band. No glow.

uniform sampler2D grain_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.17);
uniform vec3 kerb_a : source_color = vec3(0.75, 0.1, 0.08);
uniform vec3 kerb_b : source_color = vec3(0.9, 0.88, 0.85);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float width_m = max(UV2.x, 1.0);
	float v = UV.y / width_m;
	float g = texture(grain_tex, wpos.xz * 0.35).r;
	vec3 c = base_color * (0.75 + 0.5 * g);
	// Tyre-worn racing line: slightly darker strip.
	c *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.25, abs(v - 0.5)));
	float kw = 0.8 / width_m;
	float edge = 1.0 - step(kw, v) * step(v, 1.0 - kw);
	vec3 kerb = mix(kerb_a, kerb_b, step(0.5, fract(u / 2.0)));
	c = mix(c, kerb * (0.85 + 0.3 * g), edge);
	float lw = 0.15 / width_m;
	float line = (step(kw, v) * step(v, kw + lw)) + (step(1.0 - kw - lw, v) * step(v, 1.0 - kw));
	c = mix(c, vec3(0.85) * (0.8 + 0.3 * g), line);
	float dash = step(0.5 - lw * 0.5, v) * step(v, 0.5 + lw * 0.5) * step(0.6, fract(u / 6.0));
	c = mix(c, vec3(0.75), dash * 0.8);
	float start = step(u, 2.0);
	float checker = mod(floor(u * 1.5) + floor(v * width_m * 1.5), 2.0);
	c = mix(c, vec3(0.08 + 0.8 * checker), start);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
