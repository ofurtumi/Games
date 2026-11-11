extends RefCounted

# Builds a ship model from a grid loadout (see Parts.gd).
#
# Hull: the frame's cells are extruded into one faceted shell. Each cell's
# height grows with its distance from the frame edge, so wide frames get a
# raised spine; edge corners are pulled in and the sides taper toward the
# belly. Paint patterns colour whole cells (spine stripe, twin stripes, nose).
# Components: one small model per part, standing on its cells, turned with
# its rotation. Thruster nozzles point along their exhaust.
#
# Root meta "rig": flames, nozzles, spinners, drill, shield, accent, brakes.

const Parts = preload("res://scripts/Parts.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const SHIELD_SHADER = preload("res://assets/shaders/shield.gdshader")
const STOCK_FLAME = Color(1.0, 0.55, 0.2)
const C = Parts.CELL

static func build(lo: Dictionary, stats: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.name = "ShipModel"
	var paint = lo.paint
	var mats = {
		"steel": MeshKit.mat(Color(0.6, 0.62, 0.66), 0.0, 0.35, 0.8),
		"dark": MeshKit.mat(Color(0.12, 0.12, 0.14), 0.0, 0.55, 0.5),
		"glow": paint.get("glow", null),
	}
	var rig = {"flames": [], "nozzles": [], "spinners": [], "drill": null, "shield": null, "brakes": [], "accent": STOCK_FLAME}
	var hull = _hull(lo)
	var hmi = MeshInstance3D.new()
	hmi.mesh = hull.mesh
	hmi.material_override = MeshKit.vcol_mat()
	root.add_child(hmi)
	for p in lo.parts:
		_part(root, lo, p, hull, mats, rig)
	for f in rig.flames:
		f.scale = Vector3(1, 1, 0.05)
	var b = MeshKit.bounds(root)
	var m = ShaderMaterial.new()
	m.shader = SHIELD_SHADER
	rig.shield = MeshKit.part(root, MeshKit.sphere(1.0, 20, 10), m, b.get_center(),
		Vector3.ZERO, Vector3(b.size.x * 0.62 + 0.25, b.size.y * 0.8 + 0.3, b.size.z * 0.6 + 0.25), false)
	root.set_meta("rig", rig)
	root.set_meta("sockets", {"nose": Vector3(0, 0.2, b.end.z), "length": b.size.z, "width": b.size.x, "bounds": b})
	return root

# ---------------------------------------------------------------- hull

static func _hull(lo: Dictionary) -> Dictionary:
	var frame = Parts.frame_cells(lo.frame)
	var sz = Parts.frame_size(lo.frame)
	var paint = lo.paint
	# Distance from the edge, in cells (1 = on the edge).
	var depth = {}
	for c in frame:
		depth[c] = 0
	var level = 1
	var changed = true
	while changed:
		changed = false
		var mark = []
		for c in frame:
			if depth[c] != 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n = c + d
				if not frame.has(n) or (depth[n] != 0 and depth[n] < level):
					mark.append(c)
					break
		for c in mark:
			depth[c] = level
			changed = true
		level += 1
	var vh = {}
	var vo = {}
	for vy in sz.y + 1:
		for vx in sz.x + 1:
			var v = Vector2i(vx, vy)
			var n = 0
			var sum = 0.0
			var dir = Vector2.ZERO
			for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var c = v + d
				if frame.has(c):
					n += 1
					sum += minf(depth[c], 3)
					dir += Vector2(d.x + 0.5, d.y + 0.5)
			if n == 0:
				continue
			var hh = 0.1 + 0.09 * sum / n
			var off = Vector2.ZERO
			if n < 4:
				hh *= 0.65
				if dir.length() > 0.01:
					off = dir.normalized()
			vh[v] = hh
			vo[v] = off
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var cols = PackedColorArray()
	var mid = (sz.x - 1) * 0.5
	for c in frame:
		var col = paint.primary
		match paint.pattern:
			"stripe":
				if absf(c.x - mid) < 0.6:
					col = paint.secondary
			"twin":
				if absf(absf(c.x - mid) - maxf(1.0, sz.x * 0.2)) < 0.6:
					col = paint.secondary
			"nose":
				if c.y < sz.y * 0.3:
					col = paint.secondary
		var vs = [c, c + Vector2i(1, 0), c + Vector2i(1, 1), c + Vector2i(0, 1)]
		var t = []
		var bot = []
		for v in vs:
			t.append(_corner(v, vo, sz, 0.12, vh[v]))
			bot.append(_corner(v, vo, sz, 0.3, 0.0))
		_tri(verts, norms, cols, t[0], t[1], t[2], Vector3.UP, col)
		_tri(verts, norms, cols, t[0], t[2], t[3], Vector3.UP, col)
		_tri(verts, norms, cols, bot[0], bot[1], bot[2], Vector3.DOWN, col * 0.5)
		_tri(verts, norms, cols, bot[0], bot[2], bot[3], Vector3.DOWN, col * 0.5)
		for e in [[Vector2i(0, -1), 0, 1], [Vector2i(1, 0), 1, 2], [Vector2i(0, 1), 2, 3], [Vector2i(-1, 0), 3, 0]]:
			if frame.has(c + e[0]):
				continue
			var out = Vector3(-e[0].x, 0.0, -e[0].y)
			var side = col * 0.78
			_tri(verts, norms, cols, t[e[1]], t[e[2]], bot[e[2]], out, side)
			_tri(verts, norms, cols, t[e[1]], bot[e[2]], bot[e[1]], out, side)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "vh": vh}

static func _corner(v: Vector2i, vo: Dictionary, sz: Vector2i, inset: float, y: float) -> Vector3:
	var o = vo[v] * inset * C
	return Vector3((sz.x * 0.5 - v.x) * C + o.x, y, (sz.y * 0.5 - v.y) * C + o.y)

static func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var n = (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward) < 0.0:
		var t = b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v in [a, b, c]:
		verts.append(v)
		norms.append(n)
		cols.append(col)

# Hull top height above a cell.
static func _top(hull: Dictionary, c: Vector2i) -> float:
	var s = 0.0
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		s += hull.vh.get(c + d, 0.0)
	return s * 0.25

# ---------------------------------------------------------------- parts

static func _accent(def: Dictionary, mats: Dictionary) -> Color:
	if mats.glow != null:
		return mats.glow
	return Parts.MECHANICS[def.mech].accent if def.mech != "" else STOCK_FLAME

# Grid direction -> ship-local direction.
static func _dir(g: Vector2i) -> Vector3:
	return Vector3(-g.x, 0.0, -g.y)

static func _part(root: Node3D, lo: Dictionary, p: Dictionary, hull: Dictionary, mats: Dictionary, rig: Dictionary) -> void:
	var def = Parts.PARTS[p.id]
	var cells = Parts.cells_of(p)
	var accent = _accent(def, mats)
	var body = MeshKit.mat(p.color, 0.0, 0.45, 0.3) if p.has("color") else null
	var centre = Vector3.ZERO
	var top = 0.0
	for c in cells:
		centre += Parts.cell_pos(lo.frame, c)
		top = maxf(top, _top(hull, c))
	centre /= cells.size()
	match def.kind:
		"engine":
			var housing = body if body else mats.dark
			for c in cells:
				var pos = Parts.cell_pos(lo.frame, c)
				MeshKit.part(root, MeshKit.box(Vector3(C * 0.92, 0.14, C * 0.92)), housing, Vector3(pos.x, _top(hull, c) + 0.05, pos.z))
			var anchor = Parts.cell_pos(lo.frame, p.cell)
			MeshKit.part(root, MeshKit.cyl(C * 0.32, C * 0.38, 0.12, 8), mats.steel, Vector3(anchor.x, top + 0.15, anchor.z))
			MeshKit.part(root, MeshKit.cyl(C * 0.2, C * 0.2, 0.04, 8), MeshKit.mat(accent, 0.8), Vector3(anchor.x, top + 0.22, anchor.z), Vector3.ZERO, Vector3.ONE, false)
		"thruster":
			var ex = Parts.exhaust_of(p)
			var dir = _dir(ex)
			if ex == Parts.BACK:
				rig.accent = accent
			var flame_mat = MeshKit.add_mat(Color(accent.r, accent.g, accent.b, 0.85))
			# Node basis whose -Z points along the exhaust.
			var basis = Basis.looking_at(dir, Vector3.UP)
			for c in cells:
				var pos = Parts.cell_pos(lo.frame, c)
				var r = C * (0.42 if def.mech == "grind" else 0.34)
				var noz = Node3D.new()
				noz.basis = basis
				noz.position = Vector3(pos.x, _top(hull, c) * 0.6, pos.z) + dir * C * 0.2
				root.add_child(noz)
				MeshKit.part(noz, MeshKit.cyl(r * 0.75, r, C * 0.8, 8), body if body else mats.steel, Vector3(0, 0, -C * 0.1), Vector3(90, 0, 0))
				MeshKit.part(noz, MeshKit.cyl(r * 0.6, r * 0.6, 0.02, 8), MeshKit.mat(accent, 1.0), Vector3(0, 0, -C * 0.5), Vector3(90, 0, 0), Vector3.ONE, false)
				if def.mech == "vex":
					MeshKit.part(noz, MeshKit.torus(r * 0.95, r * 1.15, 12, 4), MeshKit.mat(accent, 0.6), Vector3(0, 0, -C * 0.3), Vector3(90, 0, 0))
				var pivot = Node3D.new()
				pivot.position = Vector3(0, 0, -C * 0.5)
				noz.add_child(pivot)
				# Flame cone hangs off -Z so scaling the pivot's z stretches it.
				MeshKit.part(pivot, MeshKit.cyl(r * 0.6, 0.0, 1.0, 8), flame_mat, Vector3(0, 0, -0.5), Vector3(90, 0, 0), Vector3.ONE, false)
				if ex == Parts.BACK:
					rig.flames.append(pivot)
					rig.nozzles.append(pivot)
		"drill":
			var dir = _dir(Parts.facing_of(p, Vector2i(0, -1)))
			var front = -INF
			var back = INF
			for c in cells:
				var along = Parts.cell_pos(lo.frame, c).dot(dir)
				front = maxf(front, along)
				back = minf(back, along)
			var span = 1 + int(round((front - back) / C))
			var r = (cells.size() / span) * C * 0.55
			var length = span * C + 0.35
			var spin = Node3D.new()
			# Cone runs along the node's +Z, so aim -Z backwards.
			spin.basis = Basis.looking_at(-dir, Vector3.UP)
			spin.position = Vector3(centre.x, top * 0.7 + 0.04, centre.z) - dir * (span * C * 0.5 + C * 0.1)
			root.add_child(spin)
			MeshKit.part(spin, MeshKit.cyl(0.0, r, length, 8), body if body else mats.steel, Vector3(0, 0, length * 0.5), Vector3(90, 0, 0))
			var lean = rad_to_deg(atan2(r, length))
			for k in 3:
				var arm = Node3D.new()
				arm.rotation_degrees = Vector3(0, 0, k * 120.0)
				spin.add_child(arm)
				MeshKit.part(arm, MeshKit.box(Vector3(0.04 + r * 0.12, 0.03 + r * 0.1, length * 0.92)), mats.dark, Vector3(r * 0.5, 0, length * 0.46), Vector3(0, -lean, 0))
			var collar = MeshKit.mat(Parts.MECHANICS.grind.accent) if def.mech == "grind" else mats.dark
			MeshKit.part(spin, MeshKit.cyl(r * 1.05, r * 1.1, C * 0.5, 8), collar, Vector3.ZERO, Vector3(90, 0, 0))
			rig.drill = spin
			rig.spinners.append([spin, Vector3(0, 0, 1), 14.0])
		"shield":
			var plate = body if body else MeshKit.mat(accent.darkened(0.2), 0.0, 0.3, 0.4)
			for c in cells:
				var pos = Parts.cell_pos(lo.frame, c)
				var hh = _top(hull, c)
				if p.id == "emitter":
					MeshKit.part(root, MeshKit.sphere(C * 0.45, 8, 4), mats.steel, Vector3(pos.x, hh + 0.02, pos.z), Vector3.ZERO, Vector3(1, 0.7, 1))
					MeshKit.part(root, MeshKit.sphere(C * 0.22, 6, 3), MeshKit.mat(accent, 1.0), Vector3(pos.x, hh + 0.14, pos.z), Vector3.ZERO, Vector3.ONE, false)
				elif p.id == "plate":
					MeshKit.part(root, MeshKit.box(Vector3(C * 0.98, 0.2, C * 0.98)), body if body else mats.dark, Vector3(pos.x, hh + 0.04, pos.z))
					MeshKit.part(root, MeshKit.box(Vector3(C * 0.9, 0.03, C * 0.2)), MeshKit.mat(Parts.MECHANICS.grind.accent), Vector3(pos.x, hh + 0.15, pos.z), Vector3(0, 35, 0))
				else:
					MeshKit.part(root, MeshKit.box(Vector3(C * 0.75, 0.08, C * 0.75)), plate, Vector3(pos.x, hh + 0.03, pos.z), Vector3(0, 45, 0))
					MeshKit.part(root, MeshKit.sphere(C * 0.12, 6, 3), MeshKit.mat(accent, 0.8), Vector3(pos.x, hh + 0.09, pos.z), Vector3.ZERO, Vector3.ONE, false)
		"fin", "brake":
			var frame = Parts.frame_cells(lo.frame)
			for c in cells:
				var pos = Parts.cell_pos(lo.frame, c)
				var out = Parts.facing_of(p, Vector2i(1, 0))
				if frame.has(c + out):
					continue
				var odir = _dir(out)
				var hh = _top(hull, c)
				# Holder whose -Z points out of the hull.
				var holder = Node3D.new()
				holder.basis = Basis.looking_at(odir, Vector3.UP)
				root.add_child(holder)
				if def.kind == "fin":
					holder.position = Vector3(pos.x, hh * 0.5, pos.z)
					var pts = [Vector2(-C * 0.4, 0.0), Vector2(C * 0.4, 0.0), Vector2(C * 0.9, -C * 1.4), Vector2(C * 0.55, -C * 1.45)]
					MeshKit.part(holder, MeshKit.slab(pts, 0.04), body if body else mats.dark, Vector3.ZERO)
					MeshKit.part(holder, MeshKit.box(Vector3(0.05, 0.05, C * 0.45)), MeshKit.mat(accent, 0.6), Vector3(C * 0.72, 0.02, -C * 1.4), Vector3(0, 90, 0), Vector3.ONE, false)
				else:
					# Flap hinged at the hull edge; Ship.gd swings it up when braking.
					holder.position = Vector3(pos.x, hh, pos.z) + odir * C * 0.25
					var flap = Node3D.new()
					holder.add_child(flap)
					MeshKit.part(flap, MeshKit.box(Vector3(C * 0.85, 0.04, C * 0.7)), body if body else MeshKit.mat(accent.darkened(0.25), 0.0, 0.4, 0.3), Vector3(0, 0, -C * 0.35))
					rig.brakes.append(flap)
		"magnet":
			var ring = Node3D.new()
			ring.position = Vector3(centre.x, top + 0.12, centre.z)
			root.add_child(ring)
			var rad = sqrt(cells.size()) * C * 0.5
			MeshKit.part(ring, MeshKit.torus(rad * 0.75, rad, 20, 4), body if body else mats.steel, Vector3.ZERO)
			for k in 4:
				var a = k * PI * 0.5 + PI * 0.25
				MeshKit.part(ring, MeshKit.box(Vector3(0.08, 0.06, 0.12)), MeshKit.mat(accent, 0.8), Vector3(cos(a) * rad * 0.88, 0.03, sin(a) * rad * 0.88), Vector3(0, -rad_to_deg(a), 0), Vector3.ONE, false)
			MeshKit.part(root, MeshKit.cyl(0.04, 0.06, 0.12, 6), mats.dark, Vector3(centre.x, top + 0.05, centre.z))
			rig.spinners.append([ring, Vector3(0, 1, 0), 1.5])
		"tank":
			var a = Parts.cell_pos(lo.frame, cells[0])
			var b = Parts.cell_pos(lo.frame, cells[cells.size() - 1])
			var holder = Node3D.new()
			holder.position = Vector3(centre.x, top + C * 0.3, centre.z)
			if a.distance_to(b) > 0.01:
				holder.basis = Basis.looking_at((b - a).normalized(), Vector3.UP)
			root.add_child(holder)
			MeshKit.part(holder, MeshKit.cyl(C * 0.32, C * 0.32, a.distance_to(b) + C * 0.8, 8), body if body else mats.steel, Vector3.ZERO, Vector3(90, 0, 0))
			MeshKit.part(holder, MeshKit.cyl(C * 0.34, C * 0.34, C * 0.18, 8), MeshKit.mat(accent, 0.5), Vector3.ZERO, Vector3(90, 0, 0))
		"charges":
			for c in cells:
				var pos = Parts.cell_pos(lo.frame, c)
				var hh = _top(hull, c)
				MeshKit.part(root, MeshKit.cyl(C * 0.28, C * 0.28, C * 0.85, 6), body if body else MeshKit.mat(Color(0.72, 0.12, 0.1)), Vector3(pos.x, hh + C * 0.28, pos.z), Vector3(0, 0, 90))
				MeshKit.part(root, MeshKit.cyl(C * 0.18, C * 0.18, C * 0.9, 6), MeshKit.mat(Color(1.0, 0.3, 0.1), 0.6), Vector3(pos.x, hh + C * 0.28, pos.z), Vector3(0, 0, 90), Vector3.ONE, false)
		"laser", "rocket":
			var dir = _dir(Parts.facing_of(p, Vector2i(0, -1)))
			var holder = Node3D.new()
			holder.basis = Basis.looking_at(-dir, Vector3.UP)
			holder.position = Vector3(centre.x, top + 0.12, centre.z)
			root.add_child(holder)
			var n = cells.size()
			if def.kind == "laser":
				var length = n * C
				MeshKit.part(holder, MeshKit.box(Vector3(C * 0.55, C * 0.5, length * 0.9)), body if body else mats.dark, Vector3.ZERO)
				MeshKit.part(holder, MeshKit.cyl(C * 0.12, C * 0.16, C * 0.8, 6), mats.steel, Vector3(0, 0, length * 0.5 + C * 0.3), Vector3(90, 0, 0))
				MeshKit.part(holder, MeshKit.sphere(C * 0.16, 6, 3), MeshKit.mat(accent, 1.0), Vector3(0, 0, length * 0.5 + C * 0.72), Vector3.ZERO, Vector3.ONE, false)
			elif n <= 2:
				# Slim tube: one cell wide, two barrels stacked.
				var length = n * C
				MeshKit.part(holder, MeshKit.box(Vector3(C * 0.62, C * 0.8, length * 0.9)), body if body else mats.dark, Vector3.ZERO)
				for k in 2:
					MeshKit.part(holder, MeshKit.cyl(C * 0.17, C * 0.17, 0.06, 6), MeshKit.mat(Color(0.05, 0.05, 0.05)), Vector3(0, (k - 0.5) * C * 0.38, length * 0.45 + 0.01), Vector3(90, 0, 0), Vector3.ONE, false)
				MeshKit.part(holder, MeshKit.box(Vector3(C * 0.64, 0.04, C * 0.3)), MeshKit.mat(accent, 0.4), Vector3(0, C * 0.41, -length * 0.2), Vector3.ZERO, Vector3.ONE, false)
			else:
				MeshKit.part(holder, MeshKit.box(Vector3(C * 1.7, C * 0.9, C * 1.6)), body if body else mats.dark, Vector3.ZERO)
				for k in 4:
					var off = Vector3((k % 2 - 0.5) * C * 0.8, (k / 2 - 0.5) * C * 0.42, C * 0.72)
					MeshKit.part(holder, MeshKit.cyl(C * 0.2, C * 0.2, 0.06, 6), MeshKit.mat(Color(0.05, 0.05, 0.05)), off, Vector3(90, 0, 0), Vector3.ONE, false)
				MeshKit.part(holder, MeshKit.box(Vector3(C * 1.72, 0.04, C * 0.3)), MeshKit.mat(accent, 0.4), Vector3(0, C * 0.46, -C * 0.4), Vector3.ZERO, Vector3.ONE, false)
		"hopjet":
			for c in cells:
				var pos = Parts.cell_pos(lo.frame, c)
				var hh = _top(hull, c)
				MeshKit.part(root, MeshKit.cyl(C * 0.35, C * 0.3, 0.1, 8), body if body else mats.dark, Vector3(pos.x, hh + 0.04, pos.z))
				MeshKit.part(root, MeshKit.torus(C * 0.2, C * 0.3, 10, 4), MeshKit.mat(accent, 0.8), Vector3(pos.x, hh + 0.1, pos.z))
