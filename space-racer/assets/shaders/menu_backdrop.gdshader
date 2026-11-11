shader_type canvas_item;
// Menu backdrop: greys out and dims whatever is behind it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, amount * 1.2).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g) * 0.5, amount), 1.0);
}
