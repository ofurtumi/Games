extends MeshInstance3D

# Engine ribbon: a flat strip through the nozzle's recent positions, fading
# with age. Rebuilt every frame with ImmediateMesh; cheap at this size.

const MeshKit = preload("res://scripts/MeshKit.gd")

var points = []    # [position, age, strength]
var color = Color.WHITE
var width = 0.2
var life = 0.45
var plane_normal = Vector3.UP   # the ribbon lies flat in the plane with this normal
var im: ImmediateMesh
var strip_mat: Material

func setup(c: Color, w: float) -> void:
	top_level = true
	color = c
	width = w
	im = ImmediateMesh.new()
	mesh = im
	strip_mat = MeshKit.add_mat(Color.WHITE, true)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func push(p: Vector3, delta: float, strength: float) -> void:
	for pt in points:
		pt[1] += delta
	while points.size() > 0 and points[0][1] > life:
		points.pop_front()
	if strength > 0.05:
		points.append([p, 0.0, strength])
	_rebuild()

func clear_points() -> void:
	points.clear()
	_rebuild()

func _rebuild() -> void:
	im.clear_surfaces()
	var n = points.size()
	if n < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, strip_mat)
	for k in n:
		var p: Vector3 = points[k][0]
		var a = 1.0 - points[k][1] / life
		var d: Vector3 = points[mini(k + 1, n - 1)][0] - points[maxi(k - 1, 0)][0]
		d -= plane_normal * d.dot(plane_normal)
		var side = plane_normal.cross(d).normalized() * width * (0.3 + 0.7 * a)
		var c = Color(color.r, color.g, color.b, a * a * points[k][2])
		im.surface_set_color(c)
		im.surface_add_vertex(p + side)
		im.surface_set_color(c)
		im.surface_add_vertex(p - side)
	im.surface_end()
