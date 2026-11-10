extends RefCounted

# Placeholder visuals built from primitives so the game is playable before
# real models exist. Every creature is built facing +Z.

static func mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func ghost_mat(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func sphere(r: float) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m

static func capsule(r: float, h: float) -> CapsuleMesh:
	var m = CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 12
	m.rings = 4
	return m

static func cylinder(r_top: float, r_bottom: float, h: float) -> CylinderMesh:
	var m = CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = 10
	return m

static func box(size: Vector3) -> BoxMesh:
	var m = BoxMesh.new()
	m.size = size
	return m

static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func build_enemy(kind: String, r: float, color: Color) -> Node3D:
	match kind:
		"mouse":
			return _mouse(color)
		"cat":
			return _cat(color)
		"owner":
			return _owner(color)
		"fly", "mosquito", "moth", "wasp":
			return _flier(kind, r, color)
	return _crawler(r, color)

static func _crawler(r: float, color: Color) -> Node3D:
	var root = Node3D.new()
	var body = mat(color, 0.3)
	var dark = mat(color.darkened(0.55))
	part(root, sphere(r), body, Vector3(0, 0, -r * 0.45), Vector3.ZERO, Vector3(0.8, 0.6, 1.2))
	part(root, sphere(r * 0.55), dark, Vector3(0, 0, r * 0.8))
	for i in 3:
		var z = (i - 1) * r * 0.6
		part(root, box(Vector3(r * 2.6, r * 0.12, r * 0.12)), dark, Vector3(0, -r * 0.4, z))
	return root

static func _flier(kind: String, r: float, color: Color) -> Node3D:
	var root = Node3D.new()
	var body = mat(color, 0.3)
	var wing = ghost_mat(Color(1, 1, 1, 0.55))
	var eye = mat(Color(0.8, 0.1, 0.1), 1.0)
	part(root, sphere(r), body, Vector3.ZERO, Vector3.ZERO, Vector3(0.7, 0.7, 1.2))
	part(root, box(Vector3(r * 1.6, r * 0.05, r * 0.9)), wing, Vector3(r * 0.9, r * 0.5, 0), Vector3(0, 0, 20))
	part(root, box(Vector3(r * 1.6, r * 0.05, r * 0.9)), wing, Vector3(-r * 0.9, r * 0.5, 0), Vector3(0, 0, -20))
	part(root, sphere(r * 0.3), eye, Vector3(r * 0.3, r * 0.2, r * 0.95))
	part(root, sphere(r * 0.3), eye, Vector3(-r * 0.3, r * 0.2, r * 0.95))
	if kind == "wasp":
		var black = mat(Color(0.05, 0.05, 0.05))
		part(root, sphere(r * 0.75), black, Vector3(0, 0, -r * 0.5), Vector3.ZERO, Vector3(1.0, 1.0, 0.35))
		part(root, cylinder(0.0, r * 0.2, r * 0.9), black, Vector3(0, 0, -r * 1.5), Vector3(-90, 0, 0))
	return root

static func _mouse(color: Color) -> Node3D:
	var root = Node3D.new()
	var fur = mat(color)
	var pink = mat(Color(0.95, 0.6, 0.65))
	var black = mat(Color(0.03, 0.03, 0.03))
	part(root, capsule(0.16, 0.5), fur, Vector3(0, 0, -0.05), Vector3(90, 0, 0))
	part(root, sphere(0.13), fur, Vector3(0, 0.03, 0.28))
	part(root, sphere(0.06), pink, Vector3(0.09, 0.14, 0.24))
	part(root, sphere(0.06), pink, Vector3(-0.09, 0.14, 0.24))
	part(root, sphere(0.03), pink, Vector3(0, 0.02, 0.41))
	part(root, sphere(0.022), black, Vector3(0.06, 0.08, 0.37))
	part(root, sphere(0.022), black, Vector3(-0.06, 0.08, 0.37))
	part(root, cylinder(0.006, 0.02, 0.45), pink, Vector3(0, -0.05, -0.5), Vector3(-80, 0, 0))
	return root

static func _cat(color: Color) -> Node3D:
	var root = Node3D.new()
	var fur = mat(color)
	var dark = mat(color.darkened(0.3))
	var eye = mat(Color(0.4, 1.0, 0.3), 1.5)
	var pink = mat(Color(0.95, 0.6, 0.65))
	var white = mat(Color(0.95, 0.95, 0.92))
	var patch = mat(Color(0.75, 0.42, 0.15))
	part(root, capsule(0.38, 1.7), fur, Vector3(0, 0.78, 0), Vector3(90, 0, 0))
	part(root, sphere(0.36), fur, Vector3(0, 1.08, 0.95))
	part(root, cylinder(0.0, 0.12, 0.24), dark, Vector3(0.2, 1.45, 0.92))
	part(root, cylinder(0.0, 0.12, 0.24), dark, Vector3(-0.2, 1.45, 0.92))
	part(root, sphere(0.06), eye, Vector3(0.14, 1.14, 1.27))
	part(root, sphere(0.06), eye, Vector3(-0.14, 1.14, 1.27))
	part(root, sphere(0.04), pink, Vector3(0, 1.03, 1.31))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			part(root, cylinder(0.09, 0.09, 0.5), dark, Vector3(0.25 * sx, 0.25, 0.55 * sz))
			part(root, sphere(0.11), white, Vector3(0.25 * sx, 0.07, 0.57 * sz), Vector3.ZERO, Vector3(1.0, 0.65, 1.2))
	# Tortoiseshell patches.
	part(root, sphere(0.2), patch, Vector3(0.22, 0.98, 0.3), Vector3.ZERO, Vector3(1.0, 0.5, 1.4))
	part(root, sphere(0.18), patch, Vector3(-0.25, 0.9, -0.4), Vector3.ZERO, Vector3(1.0, 0.6, 1.3))
	part(root, sphere(0.1), patch, Vector3(0.15, 1.3, 0.95))
	part(root, cylinder(0.04, 0.07, 0.95), dark, Vector3(0, 1.2, -1.05), Vector3(-40, 0, 0))
	return root

static func _owner(shirt_color: Color) -> Node3D:
	var root = Node3D.new()
	var skin = mat(Color(0.93, 0.74, 0.62))
	var shirt = mat(shirt_color)
	var jeans = mat(Color(0.18, 0.22, 0.38))
	var hair = mat(Color(0.25, 0.17, 0.1))
	var slipper = mat(Color(0.75, 0.15, 0.15))
	var black = mat(Color(0.03, 0.03, 0.03))
	part(root, cylinder(0.2, 0.18, 1.7), jeans, Vector3(0.25, 0.85, 0))
	part(root, cylinder(0.2, 0.18, 1.7), jeans, Vector3(-0.25, 0.85, 0))
	part(root, box(Vector3(0.95, 1.25, 0.5)), shirt, Vector3(0, 2.3, 0))
	part(root, sphere(0.3), skin, Vector3(0, 3.25, 0))
	part(root, box(Vector3(0.62, 0.22, 0.62)), hair, Vector3(0, 3.5, -0.03))
	part(root, sphere(0.04), black, Vector3(0.11, 3.28, 0.27))
	part(root, sphere(0.04), black, Vector3(-0.11, 3.28, 0.27))
	# Left arm hangs, right arm reaches forward holding the slipper.
	part(root, cylinder(0.11, 0.1, 1.1), skin, Vector3(-0.6, 2.3, 0))
	part(root, cylinder(0.11, 0.1, 1.0), skin, Vector3(0.6, 2.4, 0.4), Vector3(70, 0, 0))
	part(root, box(Vector3(0.28, 0.08, 0.65)), slipper, Vector3(0.6, 2.25, 0.95))
	return root

# Web nest that works as the in-run shop.
static func build_nest() -> Node3D:
	var root = Node3D.new()
	var silk = mat(Color(0.95, 0.95, 1.0), 0.8)
	part(root, sphere(0.12), silk, Vector3.ZERO)
	part(root, sphere(0.08), silk, Vector3(0.1, -0.03, 0.05))
	part(root, sphere(0.07), silk, Vector3(-0.09, -0.04, -0.04))
	part(root, cylinder(0.01, 0.01, 1.2), ghost_mat(Color(0.8, 0.9, 1.0, 0.5)), Vector3(0, 0.7, 0))
	return root

# Black mesh net bag that a captured boss ends up in.
static func build_net(r: float) -> Node3D:
	var root = Node3D.new()
	var cord = mat(Color(0.03, 0.03, 0.03))
	part(root, sphere(r), ghost_mat(Color(0.0, 0.0, 0.0, 0.25)), Vector3.ZERO)
	for i in 6:
		var ring = TorusMesh.new()
		ring.inner_radius = r * 0.98
		ring.outer_radius = r * 1.02
		ring.rings = 24
		ring.ring_segments = 4
		part(root, ring, cord, Vector3.ZERO, Vector3(90, i * 30.0, 0))
	for i in 3:
		var y = (i - 1) * r * 0.5
		var rr = sqrt(maxf(r * r - y * y, 0.0))
		var band = TorusMesh.new()
		band.inner_radius = rr * 0.98
		band.outer_radius = rr * 1.02
		band.rings = 24
		band.ring_segments = 4
		part(root, band, cord, Vector3(0, y, 0))
	return root

# The player's spider, about `s` long, facing +Z. Returns the root; the eight
# leg pivots are in root.get_meta("legs") so Player.gd can animate them.
static func build_spider(s: float) -> Node3D:
	var root = Node3D.new()
	var body = mat(Color(0.16, 0.11, 0.09))
	var stripe = mat(Color(0.55, 0.35, 0.2))
	var leg_mat = mat(Color(0.12, 0.08, 0.07))
	var eye = mat(Color(0.9, 0.2, 0.15), 1.5)
	# Abdomen behind, cephalothorax in front.
	part(root, sphere(s * 0.32), body, Vector3(0, s * 0.12, -s * 0.28), Vector3.ZERO, Vector3(0.9, 0.8, 1.15))
	part(root, sphere(s * 0.12), stripe, Vector3(0, s * 0.36, -s * 0.3), Vector3.ZERO, Vector3(0.6, 0.3, 1.8))
	part(root, sphere(s * 0.2), body, Vector3(0, s * 0.06, s * 0.14))
	for side in [-1.0, 1.0]:
		part(root, sphere(s * 0.045), eye, Vector3(s * 0.06 * side, s * 0.14, s * 0.3))
		part(root, sphere(s * 0.03), eye, Vector3(s * 0.12 * side, s * 0.12, s * 0.27))
	var legs = []
	for side in [-1.0, 1.0]:
		for i in 4:
			var pivot = Node3D.new()
			pivot.position = Vector3(s * 0.12 * side, s * 0.06, s * (0.24 - i * 0.09))
			# Fan the legs out: front pair points forward, back pair backward.
			pivot.rotation_degrees = Vector3(0, side * (i * 40.0 - 60.0) + (0.0 if side > 0 else 180.0), 0)
			root.add_child(pivot)
			var upper_len = s * 0.42
			# Upper leg rises 30 degrees to the knee, the lower leg drops 55 to the foot.
			part(pivot, box(Vector3(upper_len, s * 0.05, s * 0.05)), leg_mat, Vector3(upper_len * 0.433, upper_len * 0.25, 0), Vector3(0, 0, 30))
			part(pivot, box(Vector3(s * 0.5, s * 0.04, s * 0.04)), leg_mat, Vector3(upper_len * 0.866 + s * 0.143, upper_len * 0.5 - s * 0.205, 0), Vector3(0, 0, -55))
			pivot.set_meta("base_y", pivot.rotation.y)
			legs.append(pivot)
	root.set_meta("legs", legs)
	return root

# Sugar cache: a glowing cube with a tall beacon and a little light of its own.
static func build_cache() -> Node3D:
	var root = Node3D.new()
	part(root, box(Vector3.ONE * 0.09), mat(Color(1.0, 0.97, 0.85), 2.5), Vector3.ZERO, Vector3(0, 0, 0))
	part(root, cylinder(0.012, 0.03, 3.0), ghost_mat(Color(1.0, 0.85, 0.3, 0.45)), Vector3(0, 1.5, 0))
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.45)
	light.light_energy = 1.5
	light.omni_range = 0.7
	light.position = Vector3(0, 0.08, 0)
	root.add_child(light)
	return root
