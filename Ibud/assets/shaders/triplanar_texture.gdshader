shader_type spatial;

// Triplanar texture shader using WORLD space position.
// Texture stays fixed in the world regardless of camera movement.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale : hint_range(0.01, 10.0) = 1.0;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Convert view-space position and normal to world space
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Blend weights based on world-space normal
	vec3 blend = abs(world_normal);
	blend = normalize(max(blend, 0.00001));
	blend /= (blend.x + blend.y + blend.z);

	// Sample texture from each world axis
	vec4 col_x = texture(albedo_texture, world_pos.yz * texture_scale);
	vec4 col_y = texture(albedo_texture, world_pos.xz * texture_scale);
	vec4 col_z = texture(albedo_texture, world_pos.xy * texture_scale);

	vec4 color = col_x * blend.x + col_y * blend.y + col_z * blend.z;

	ALBEDO = (color * albedo_tint).rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
