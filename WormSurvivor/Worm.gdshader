shader_type canvas_item;

// Parameters for the sine wave
uniform float frequency = 1.5;
uniform float amplitude = 1000.0;
uniform float speed = 2.0;
uniform float direction: hint_range(-1.0, 1.0) = 1.0;

// Uniforms for colors
uniform vec4 color1: source_color = vec4(0.2, 0.5, 0.8, 1.0);
uniform vec4 color2: source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float opacity: hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 color = 0.5 + 0.25 * sin(UV.xyy + TIME * vec3(2, 4, 8));
	COLOR = vec4(color, 1.0);
    // float sine_wave = sin(UV.x * frequency + TIME * speed * direction) * amplitude;
    // uv.y += sine_wave;
    //float t = sin(UV.y * frequency + TIME * speed * direction) + 0.2;
    // vec4 final_color = t > 0.0 ? color1 : color2;
    //vec4 final_color = color1 * t;
	//final_color *= vec4(1.0, 1.0, 1.0, opacity);
    //COLOR = final_color;
}