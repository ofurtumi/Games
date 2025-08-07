shader_type canvas_item;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	if (
		UV.x < 0.48 || UV.x > 0.52 ||
		UV.y < 0.48 || UV.y > 0.52 ) {
		COLOR = vec4(1,1,1,0.5);
	} else {
		COLOR = vec4(0,0,0,0.5);
	}

	if (
		( UV.x < 0.48 && UV.y < 0.48 ) ||
		( UV.x > 0.52 && UV.y < 0.48 ) ||
		( UV.x < 0.48 && UV.y > 0.52 ) ||
		( UV.x > 0.52 && UV.y > 0.52 )) {
		COLOR = vec4(0,0,0,0);
	}

}

//void light() {
	// Called for every pixel for every light affecting the CanvasItem.
	// Uncomment to replace the default light processing function with this one.
//}
