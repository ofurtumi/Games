shader_type spatial;
// MultiMesh blocks and debris. Instance colour comes in through COLOR,
// INSTANCE_CUSTOM.r is glow strength (ore veins, sparks, nanobots).
// Tops are lit a touch brighter and sides darken toward the base, which fakes
// ambient occlusion and makes walls read as walls from the fixed camera.

varying float glow;
varying float top;
varying float ao;

void vertex() {
	glow = INSTANCE_CUSTOM.r;
	top = step(0.5, NORMAL.y);
	ao = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float shade = mix(mix(0.3, 0.8, ao), 1.0, top);
	ALBEDO = c * shade;
	ROUGHNESS = 0.9;
	EMISSION = c * glow * mix(0.6, 1.0, top);
}
