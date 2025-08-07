shader_type spatial;
uniform sampler2D noise;
uniform float height_scale = 0.5;
uniform sampler2D normalmap;
varying vec2 tex_position;

void vertex() {
  tex_position = VERTEX.xz / 2.0 + 0.5;
  float height = texture(noise, tex_position).x;
  VERTEX.y += height * height_scale;
  COLOR.r += height * height_scale;
  COLOR.a = 0.25;
}

void fragment() {
  NORMAL_MAP = texture(normalmap, tex_position * height_scale).xyz;
  METALLIC = 0.0;
  ROUGHNESS = 0.01;
  ALBEDO = vec3(0.1, 0.3, 0.5);
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
