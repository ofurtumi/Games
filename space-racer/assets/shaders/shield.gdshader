shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
// Fresnel bubble. `strength` follows shield charge, `hit` flashes on impact.

uniform vec4 color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float strength = 0.5;
uniform float hit = 0.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float bands = 0.5 + 0.5 * sin(TIME * 6.0 + UV.y * 40.0);
	ALBEDO = color.rgb * (f * strength * (0.75 + 0.25 * bands) + hit * (0.15 + f * 1.5));
	ALPHA = 1.0;
}
