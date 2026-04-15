shader_type canvas_item;
// Screen-space cartoon outline using Sobel edge detection on the color buffer.
// Works in canvas_item (no depth texture needed).
// Pairs well with toon/flat shading since hard color boundaries = clean edges.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform float threshold : hint_range(0.01, 1.0) = 0.15;
uniform float outline_width : hint_range(0.5, 4.0) = 1.2;

void fragment() {
	vec2 px = outline_width / vec2(textureSize(screen_texture, 0));
	vec2 uv = SCREEN_UV;

	// 3x3 Sobel kernel samples
	vec3 tl = texture(screen_texture, uv + vec2(-px.x, -px.y)).rgb;
	vec3 tc = texture(screen_texture, uv + vec2( 0.0,  -px.y)).rgb;
	vec3 tr = texture(screen_texture, uv + vec2( px.x, -px.y)).rgb;
	vec3 ml = texture(screen_texture, uv + vec2(-px.x,  0.0 )).rgb;
	vec3 mr = texture(screen_texture, uv + vec2( px.x,  0.0 )).rgb;
	vec3 bl = texture(screen_texture, uv + vec2(-px.x,  px.y)).rgb;
	vec3 bc = texture(screen_texture, uv + vec2( 0.0,   px.y)).rgb;
	vec3 br = texture(screen_texture, uv + vec2( px.x,  px.y)).rgb;

	// Sobel gradients
	vec3 gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	vec3 gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;

	float edge = length(gx) + length(gy);
	float outline = step(threshold, edge);

	COLOR = vec4(outline_color.rgb, outline * outline_color.a);
}
