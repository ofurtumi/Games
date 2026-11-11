extends RefCounted

# Low-poly building blocks. Everything is flat shaded on purpose: hard facets
# read well from the fixed camera and stay readable at any zoom.

const BLOCK_SHADER = preload("res://assets/shaders/block.gdshader")

static func mat(color: Color, emission: float = 0.0, rough: float = 0.75, metal: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

# Vertex-coloured, for generated meshes that bake their colours in.
static func vcol_mat() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.45
	m.metallic = 0.15
	return m

# Additive, unshaded: engine flames, trails, holo stuff.
static func add_mat(color: Color, use_vertex_color: bool = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = use_vertex_color
	return m

# Material for MultiMesh blocks/debris: instance color + per-instance glow in
# INSTANCE_CUSTOM.r, lighter tops and a fake ambient occlusion toward the base.
static func block_mat() -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = BLOCK_SHADER
	return m

static func box(size: Vector3) -> BoxMesh:
	var m = BoxMesh.new()
	m.size = size
	return m

static func cyl(r_top: float, r_bottom: float, h: float, segs: int = 8) -> CylinderMesh:
	var m = CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m

static func sphere(r: float, segs: int = 8, rings: int = 4) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m

static func torus(inner: float, outer: float, rings: int = 18, segs: int = 6) -> TorusMesh:
	var m = TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = segs
	return m

static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# One flat-shaded triangle. Godot treats clockwise as the front face, so the
# winding is flipped if needed to make the face point along `outward`.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n = (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(outward) < 0.0:
		var t = b
		b = c
		c = t
		n = -n
	st.set_normal(n.normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

# Lofts a closed cross-section along Z. `stations` is an array of
# [z, width, height, y_bottom]; `section` is a closed loop of Vector2 where x is
# a fraction of the width (-0.5..0.5) and y a fraction of the height (0..1).
static func loft(stations: Array, section: Array, caps: bool = true) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings = []
	for s in stations:
		var ring = []
		for p in section:
			ring.append(Vector3(p.x * s[1], s[3] + p.y * s[2], s[0]))
		rings.append(ring)
	var n = section.size()
	for k in range(rings.size() - 1):
		var r0 = rings[k]
		var r1 = rings[k + 1]
		var axis = Vector3(0, stations[k][3] + stations[k][2] * 0.5, (stations[k][0] + stations[k + 1][0]) * 0.5)
		for i in n:
			var a = r0[i]
			var b = r0[(i + 1) % n]
			var c = r1[(i + 1) % n]
			var d = r1[i]
			var mid = (a + b + c + d) * 0.25
			var out = mid - axis
			out.z = 0.0
			_tri(st, a, b, c, out)
			_tri(st, a, c, d, out)
	if caps:
		for k in [0, rings.size() - 1]:
			var ring = rings[k]
			var center = Vector3.ZERO
			for p in ring:
				center += p
			center /= ring.size()
			var out = Vector3(0, 0, -1 if k == 0 else 1)
			for i in n:
				_tri(st, center, ring[i], ring[(i + 1) % n], out)
	return st.commit()

# A convex outline in the XZ plane (Vector2(x, z)) extruded to `thickness`.
# Wings, fins, plates, chevrons.
static func slab(points: Array, thickness: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h = thickness * 0.5
	var center = Vector2.ZERO
	for p in points:
		center += p
	center /= points.size()
	var n = points.size()
	var ct = Vector3(center.x, h, center.y)
	var cb = Vector3(center.x, -h, center.y)
	for i in n:
		var p = points[i]
		var q = points[(i + 1) % n]
		var pt = Vector3(p.x, h, p.y)
		var qt = Vector3(q.x, h, q.y)
		var pb = Vector3(p.x, -h, p.y)
		var qb = Vector3(q.x, -h, q.y)
		_tri(st, ct, pt, qt, Vector3.UP)
		_tri(st, cb, pb, qb, Vector3.DOWN)
		var mid = (p + q) * 0.5 - center
		var out = Vector3(mid.x, 0, mid.y)
		_tri(st, pt, qt, qb, out)
		_tri(st, pt, qb, pb, out)
	return st.commit()

# Merged world-space AABB of every mesh under `root`, relative to root.
static func bounds(root: Node3D) -> AABB:
	var box_out = AABB()
	var first = true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf = root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() else _local_xf(root, mi)
		var b = xf * mi.get_aabb()
		if first:
			box_out = b
			first = false
		else:
			box_out = box_out.merge(b)
	return box_out

static func _local_xf(root: Node3D, node: Node3D) -> Transform3D:
	var xf = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = n.transform * xf
		n = n.get_parent()
	return xf
