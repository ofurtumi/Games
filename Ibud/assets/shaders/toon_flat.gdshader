shader_type spatial;
// Cel/toon shading using Godot's built-in diffuse_toon mode.
// Lights act as highlights over a GI-provided base.
render_mode diffuse_toon, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// How much indirect/GI light contributes vs direct light highlights
uniform float ambient_boost : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
