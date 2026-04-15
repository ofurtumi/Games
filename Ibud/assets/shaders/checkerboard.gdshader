shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform float size : hint_range(0.1, 10.0) = 1.0;
uniform vec4 color1 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color2 : source_color = vec4(0.1, 0.1, 0.1, 1.0);

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec3 blend = abs(world_normal);
	blend = normalize(max(blend, 0.00001));
	blend /= (blend.x + blend.y + blend.z);

	vec2 uv_x = world_pos.yz * size;
	vec2 uv_y = world_pos.xz * size;
	vec2 uv_z = world_pos.xy * size;

	float cx = mod(floor(uv_x.x) + floor(uv_x.y), 2.0);
	float cy = mod(floor(uv_y.x) + floor(uv_y.y), 2.0);
	float cz = mod(floor(uv_z.x) + floor(uv_z.y), 2.0);

	float pattern = cx * blend.x + cy * blend.y + cz * blend.z;
	ALBEDO = mix(color1.rgb, color2.rgb, step(0.5, pattern));
	ROUGHNESS = 0.9;
}
