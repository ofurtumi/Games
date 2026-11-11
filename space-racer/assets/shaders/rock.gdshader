shader_type spatial;
// Terrain and ground. Vertex colour carries the block colour (and baked
// shading), a low-res noise texture is projected from three sides so cliffs
// and plateaus both get grain without UVs.

uniform sampler2D grain_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float scale = 0.22;
uniform float contrast = 0.9;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnorm);
	n /= (n.x + n.y + n.z);
	float t = texture(grain_tex, wpos.xz * scale).r * n.y
		+ texture(grain_tex, wpos.zy * scale).r * n.x
		+ texture(grain_tex, wpos.xy * scale).r * n.z;
	ALBEDO = COLOR.rgb * tint * mix(1.0, 0.45 + 1.1 * t, contrast);
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * (1.2 + 0.8 * t);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
