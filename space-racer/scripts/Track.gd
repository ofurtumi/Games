extends Node3D

# A track is built from a blueprint:
#   nodes    - closed loop of control points (Vector3 on y=0), smoothed into the
#              centreline with a Catmull-Rom spline
#   widths   - half-width of the road at each node, blended along the spline
#   features - [{type, u, offset, width}], u = 0..1 along the loop, offset =
#              -1..1 across it. Types: gate, pad, mine, barrier, wall, ramp.
#              A start/finish gate always sits at u = 0.
# auto_blueprint() makes one from a seed; the track editor edits one; build()
# carves it into the terrain. validate() and cost() feed the editor checklist.
#
# Obstacles are meant to favour some builds: barriers are hopped or drilled;
# reinforced walls need a tier-2 drill, or a ramp in front of them.

const MeshKit = preload("res://scripts/MeshKit.gd")
const TRACK_SHADER = preload("res://assets/shaders/track.gdshader")

const STEP = 1.0
const HALF_WIDTH = 4.5
const MIN_HW = 3.0
const MAX_HW = 8.0
const MIN_LENGTH = 150.0
const MAX_LENGTH = 800.0
const MIN_NODE_GAP = 8.0
const MIN_GATES = 3
const RAMP_LEN = 3.0
const RAMP_H = 0.7

# What the blueprint costs, by material class.
const COST = {
	"road_per_m": {"rock": 0.2},
	"gate": {"metal": 3},
	"pad": {"crystal": 2},
	"mine": {"metal": 1, "rock": 1},
	"barrier": {"rock": 4},
	"wall": {"rock": 6, "metal": 1},
	"ramp": {"metal": 2},
}

var half_width = HALF_WIDTH   # widest point, for broad checks
var hw = PackedFloat32Array()  # half-width at each centreline sample
var blueprint = {}
var pts = PackedVector3Array()
var tangents = PackedVector3Array()
var length = 0.0
var checkpoints = []    # {idx, pos, dir, bar}
var pads = []           # {pos, dir}
var mines = []          # {pos, node, timer}
var ramps = []          # {pos, dir, side, half}

# ---------------------------------------------------------------- blueprint

static func auto_blueprint(sd: int, terrain) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = sd
	var half = minf(terrain.w, terrain.h) * 0.5 * terrain.cell
	var R = half * 0.56
	var a = rng.randf() * TAU
	var b = rng.randf() * TAU
	var nodes = []
	var widths = []
	var n = 12
	for k in n:
		var th = TAU * k / n + rng.randf_range(-0.1, 0.1)
		var r = R * (1.0 + 0.32 * sin(2.0 * th + a) + 0.22 * sin(3.0 * th + b) + rng.randf_range(-0.08, 0.08))
		r = clampf(r, R * 0.4, half - MAX_HW - 9.0)
		nodes.append(Vector3(cos(th) * r, 0.0, sin(th) * r))
		widths.append(snappedf(rng.randf_range(3.8, 6.0), 0.5))
	var features = []
	for k in range(1, 6):
		features.append({"type": "gate", "u": k / 6.0, "offset": 0.0, "width": 1.0})
	var taken = [0.0]
	for k in 5:
		taken.append(k / 6.0 + 1.0 / 6.0)
	var spot = func(gap: float):
		for attempt in 80:
			var u = rng.randf()
			var ok = true
			for t in taken:
				var d = absf(u - t)
				if minf(d, 1.0 - d) < gap:
					ok = false
			if ok:
				taken.append(u)
				return u
		return -1.0
	# A ramp with a reinforced wall just past it: fast builds jump it, drills
	# chew it, everyone else takes the long way round the wall's gap.
	var u = spot.call(0.06)
	if u >= 0.0:
		features.append({"type": "ramp", "u": u, "offset": -0.35, "width": 0.5})
		features.append({"type": "wall", "u": u + 0.022, "offset": 0.0, "width": 1.0})
	for k in 4:
		u = spot.call(0.035)
		if u >= 0.0:
			features.append({"type": "pad", "u": u, "offset": 0.0, "width": 1.0})
	for k in 4:
		u = spot.call(0.035)
		if u >= 0.0:
			features.append({"type": "mine", "u": u, "offset": rng.randf_range(-0.6, 0.6), "width": 1.0})
	for k in 2:
		u = spot.call(0.035)
		if u >= 0.0:
			var full = k == 0
			features.append({"type": "barrier", "u": u, "offset": 0.0 if full else rng.randf_range(-0.5, 0.5), "width": 1.0 if full else 0.5})
	return {"nodes": nodes, "widths": widths, "features": features}

static func widths_of(bp: Dictionary) -> Array:
	var w = bp.get("widths", [])
	if w.size() != bp.nodes.size():
		w = []
		for k in bp.nodes.size():
			w.append(HALF_WIDTH)
	return w

# Centreline samples and the half-width at each: {pts, hw}.
static func layout(bp: Dictionary) -> Dictionary:
	var nodes = bp.nodes
	var widths = widths_of(bp)
	var n = nodes.size()
	var ctrl = []
	for k in n:
		ctrl.append(Vector3(nodes[k].x, widths[k], nodes[k].z))
	var dense = []
	for k in n:
		var p0 = ctrl[(k - 1 + n) % n]
		var p1 = ctrl[k]
		var p2 = ctrl[(k + 1) % n]
		var p3 = ctrl[(k + 2) % n]
		for s in 24:
			dense.append(_catmull(p0, p1, p2, p3, s / 24.0))
	var res = _resample(dense, STEP)
	var out_p = PackedVector3Array()
	var out_w = PackedFloat32Array()
	for p in res:
		out_p.append(Vector3(p.x, 0.0, p.z))
		out_w.append(clampf(p.y, MIN_HW, MAX_HW))
	return {"pts": out_p, "hw": out_w}

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 = t * t
	var t3 = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# Even spacing along the ground; y (the width) just comes along for the ride.
static func _resample(dense: Array, step: float) -> Array:
	var out = [dense[0]]
	var prev: Vector3 = dense[0]
	var acc = 0.0
	var n = dense.size()
	for k in range(1, n + 1):
		var cur: Vector3 = dense[k % n]
		var seg = _flat(prev, cur)
		while acc + seg >= step and seg > 0.0:
			var t = (step - acc) / seg
			prev = prev.lerp(cur, t)
			out.append(prev)
			seg = _flat(prev, cur)
			acc = 0.0
		acc += seg
		prev = cur
	if out.size() > 1 and _flat(out[out.size() - 1], out[0]) < step * 0.5:
		out.pop_back()
	return out

static func side_of(line: PackedVector3Array, i: int) -> Vector3:
	var n = line.size()
	var t = (line[(i + 1) % n] - line[(i - 1 + n) % n]).normalized()
	return Vector3(t.z, 0.0, -t.x)

static func cost(bp: Dictionary, lay: Dictionary = {}) -> Dictionary:
	if lay.is_empty():
		lay = layout(bp)
	var out = {"rock": 0, "metal": 0, "crystal": 0}
	var area = 0.0
	for w in lay.hw:
		area += w / HALF_WIDTH
	out.rock += ceili(area * STEP * COST.road_per_m.rock)
	var features = bp.features.duplicate()
	features.append({"type": "gate"})   # start/finish
	for f in features:
		for m in COST[f.type]:
			out[m] += COST[f.type][m]
	return out

# Layout rules. Returns {ok, errors: [String], bad: [Vector3]} - `bad` marks
# where on the map a rule is broken.
static func validate(bp: Dictionary, terrain, lay: Dictionary = {}) -> Dictionary:
	if lay.is_empty():
		lay = layout(bp)
	var line: PackedVector3Array = lay.pts
	var hws: PackedFloat32Array = lay.hw
	var errors = []
	var bad = []
	var length_m = line.size() * STEP
	if length_m < MIN_LENGTH:
		errors.append("Too short: %dm (min %dm)" % [length_m, MIN_LENGTH])
	if length_m > MAX_LENGTH:
		errors.append("Too long: %dm (max %dm)" % [length_m, MAX_LENGTH])
	var nodes = bp.nodes
	for k in nodes.size():
		if nodes[k].distance_to(nodes[(k + 1) % nodes.size()]) < MIN_NODE_GAP:
			errors.append("Two nodes are too close together")
			bad.append(nodes[k])
			break
	var lim = minf(terrain.w, terrain.h) * 0.5 * terrain.cell - 4.0
	for i in line.size():
		var p = line[i]
		if absf(p.x) > lim - hws[i] or absf(p.z) > lim - hws[i]:
			errors.append("Track leaves the map")
			bad.append(p)
			break
	# Road must not overlap itself: samples far apart along the loop must stay
	# both half-widths plus a wall apart.
	var n = line.size()
	var overlap = false
	for i in range(0, n, 2):
		for j in range(i + 2, n, 2):
			var gap = hws[i] + hws[j] + 3.0
			var along = mini(j - i, n - (j - i))
			if along < gap * 2.5:
				continue
			if line[i].distance_squared_to(line[j]) < gap * gap:
				overlap = true
				bad.append(line[i])
				break
		if bad.size() > 12:
			break
	if overlap:
		errors.append("Track runs into itself")
	var gates = 1
	for f in bp.features:
		if f.type == "gate":
			gates += 1
	if gates < MIN_GATES:
		errors.append("Needs at least %d gates (has %d)" % [MIN_GATES, gates])
	return {"ok": errors.is_empty(), "errors": errors, "bad": bad}

# ---------------------------------------------------------------- building

func build(bp: Dictionary, terrain) -> void:
	for c in get_children():
		c.queue_free()
	checkpoints.clear()
	pads.clear()
	mines.clear()
	ramps.clear()
	blueprint = bp.duplicate(true)
	blueprint.widths = widths_of(bp)
	var lay = layout(bp)
	pts = lay.pts
	hw = lay.hw
	half_width = 0.0
	for w in hw:
		half_width = maxf(half_width, w)
	length = pts.size() * STEP
	tangents.resize(pts.size())
	for i in pts.size():
		tangents[i] = (pts[(i + 1) % pts.size()] - pts[(i - 1 + pts.size()) % pts.size()]).normalized()
	_carve(terrain)
	_build_ribbon(terrain)
	var gates = [0.0]
	for f in bp.features:
		if f.type == "gate":
			gates.append(f.u)
	gates.sort()
	for u in gates:
		_build_gate(index_at(u), u == 0.0)
	for f in bp.features:
		match f.type:
			"pad": _build_pad(index_at(f.u))
			"mine": _build_mine(index_at(f.u), f.offset)
			"barrier": _build_barrier(index_at(f.u), f.offset, f.width, terrain, terrain.BARRIER)
			"wall": _build_barrier(index_at(f.u), f.offset, f.width, terrain, terrain.REINFORCED)
			"ramp": _build_ramp(index_at(f.u), f.offset, f.width)

func index_at(u: float) -> int:
	return int(fposmod(u, 1.0) * pts.size()) % pts.size()

func side(i: int) -> Vector3:
	var t = tangents[i]
	return Vector3(t.z, 0.0, -t.x)

func frame_at(i: int) -> Transform3D:
	return Transform3D(Basis(side(i), Vector3.UP, tangents[i]), pts[i])

# Clears the road and walls it in with a two-cell band of rock so caves don't
# eat the edges. Shortcuts through those walls are the miners' business.
func _carve(terrain) -> void:
	var edge = PackedFloat32Array()   # signed distance to the road edge
	edge.resize(terrain.w * terrain.h)
	edge.fill(1e9)
	for i in pts.size():
		var p = pts[i]
		var r = ceili(hw[i] + 3.0)
		var c0 = terrain.world_to_cell(p)
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var c = c0 + Vector2i(di, dj)
				if not terrain.in_bounds(c):
					continue
				var cc = terrain.cell_center(c)
				var d = Vector2(cc.x - p.x, cc.z - p.z).length() - hw[i]
				var idx = c.y * terrain.w + c.x
				if d < edge[idx]:
					edge[idx] = d
	for idx in edge.size():
		var d = edge[idx]
		if d > 1e8:
			continue
		var c = Vector2i(idx % terrain.w, idx / terrain.w)
		if d < 0.3:
			terrain.set_kind(c, terrain.EMPTY)
		elif d < 2.3 and terrain.get_kind(c) == terrain.EMPTY:
			terrain.set_kind(c, terrain.ROCK)

# UV.x = metres along, UV.y = metres across from the left edge, UV2.x = road
# width there, so kerbs stay the same size however wide the road gets.
func _build_ribbon(terrain) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n = pts.size()
	for i in n:
		var j = (i + 1) % n
		var li = pts[i] + side(i) * hw[i]
		var ri = pts[i] - side(i) * hw[i]
		var lj = pts[j] + side(j) * hw[j]
		var rj = pts[j] - side(j) * hw[j]
		var ui = i * STEP
		var uj = (i + 1) * STEP
		var wi = hw[i] * 2.0
		var wj = hw[j] * 2.0
		_quad_tri(st, [li, ri, rj], [Vector2(ui, 0), Vector2(ui, wi), Vector2(uj, wj)], [wi, wi, wj])
		_quad_tri(st, [li, rj, lj], [Vector2(ui, 0), Vector2(uj, wj), Vector2(uj, 0)], [wi, wj, wj])
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position.y = 0.02
	var m = ShaderMaterial.new()
	m.shader = TRACK_SHADER
	m.set_shader_parameter("base_color", terrain.planet.track)
	m.set_shader_parameter("grain_tex", terrain.grain_tex)
	mi.material_override = m
	add_child(mi)

static func _quad_tri(st: SurfaceTool, v: Array, uv: Array, w: Array) -> void:
	var n = (v[2] - v[0]).cross(v[1] - v[0])
	var order = [0, 1, 2] if n.y > 0.0 else [0, 2, 1]
	for k in order:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[k])
		st.set_uv2(Vector2(w[k], 0.0))
		st.add_vertex(v[k])

# Gantry: two steel legs and a beam with a banner. The next gate to take is
# lit up by Main.
func _build_gate(idx: int, start: bool) -> void:
	var steel = MeshKit.mat(Color(0.5, 0.52, 0.56), 0.0, 0.4, 0.7)
	var gate = Node3D.new()
	gate.transform = frame_at(idx)
	add_child(gate)
	var w = hw[idx]
	var bar = MeshKit.mat(Color(0.95, 0.95, 0.95) if start else Color(0.18, 0.4, 0.85), 0.0)
	bar.emission_enabled = true
	bar.emission = bar.albedo_color
	bar.emission_energy_multiplier = 0.0
	for s in [-1.0, 1.0]:
		MeshKit.part(gate, MeshKit.box(Vector3(0.3, 3.8, 0.3)), steel, Vector3(s * (w + 0.2), 1.9, 0))
		MeshKit.part(gate, MeshKit.box(Vector3(0.6, 0.2, 0.6)), steel, Vector3(s * (w + 0.2), 0.1, 0))
	MeshKit.part(gate, MeshKit.box(Vector3(w * 2.0 + 0.7, 0.22, 0.22)), steel, Vector3(0, 3.8, 0))
	MeshKit.part(gate, MeshKit.box(Vector3(w * 1.6, 0.55, 0.06)), bar, Vector3(0, 3.4, 0))
	checkpoints.append({"idx": idx, "pos": pts[idx], "dir": tangents[idx], "bar": bar})

func _build_pad(idx: int) -> void:
	var glow = MeshKit.mat(Color(0.25, 0.85, 0.5), 0.3)
	var left = [Vector2(-1.4, -0.4), Vector2(0.0, 0.7), Vector2(0.0, 0.15), Vector2(-1.4, -0.95)]
	var right = [Vector2(1.4, -0.4), Vector2(1.4, -0.95), Vector2(0.0, 0.15), Vector2(0.0, 0.7)]
	var pad = Node3D.new()
	pad.transform = frame_at(idx)
	pad.position.y = 0.05
	add_child(pad)
	for row in 3:
		MeshKit.part(pad, MeshKit.slab(left, 0.05), glow, Vector3(0, 0, -1.2 + row * 1.1), Vector3.ZERO, Vector3.ONE, false)
		MeshKit.part(pad, MeshKit.slab(right, 0.05), glow, Vector3(0, 0, -1.2 + row * 1.1), Vector3.ZERO, Vector3.ONE, false)
	pads.append({"pos": pts[idx], "dir": tangents[idx]})

func _build_mine(idx: int, offset: float) -> void:
	var pos = pts[idx] + side(idx) * offset * hw[idx]
	var node = build_mine()
	node.position = pos + Vector3(0, 0.55, 0)
	add_child(node)
	mines.append({"pos": pos, "node": node, "timer": 0.0})

# A low wall of blocks across the road (or part of it).
func _build_barrier(idx: int, offset: float, width: float, terrain, kind: int) -> void:
	var centre = offset * hw[idx]
	var half = width * hw[idx]
	for along in [-0.5, 0.5]:
		var p0 = pts[idx] + tangents[idx] * along
		var lat = -half
		while lat <= half:
			var p = p0 + side(idx) * (centre + lat)
			if absf(centre + lat) < hw[idx] - 0.5:
				terrain.set_kind(terrain.world_to_cell(p), kind)
			lat += 0.5

# Wedge rising toward the direction of travel. Main launches ships off its lip.
func _build_ramp(idx: int, offset: float, width: float) -> void:
	var half = width * hw[idx]
	var node = Node3D.new()
	node.transform = frame_at(idx)
	node.position += side(idx) * offset * hw[idx]
	add_child(node)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a = Vector3(-half, 0, -RAMP_LEN * 0.5)
	var b = Vector3(half, 0, -RAMP_LEN * 0.5)
	var c = Vector3(half, RAMP_H, RAMP_LEN * 0.5)
	var d = Vector3(-half, RAMP_H, RAMP_LEN * 0.5)
	var e = Vector3(half, 0, RAMP_LEN * 0.5)
	var f = Vector3(-half, 0, RAMP_LEN * 0.5)
	for tri in [[a, b, c, Vector3(0, 1, -0.3)], [a, c, d, Vector3(0, 1, -0.3)], [f, d, c, Vector3(0, 0, 1)], [f, c, e, Vector3(0, 0, 1)],
			[b, e, c, Vector3(1, 0, 0)], [a, d, f, Vector3(-1, 0, 0)]]:
		var nrm = (tri[2] - tri[0]).cross(tri[1] - tri[0])
		var order = [0, 1, 2] if nrm.dot(tri[3]) > 0.0 else [0, 2, 1]
		nrm = nrm.normalized() * (1.0 if nrm.dot(tri[3]) > 0.0 else -1.0)
		for k in order:
			st.set_normal(nrm)
			st.add_vertex(tri[k])
	var mi = MeshKit.part(node, st.commit(), MeshKit.mat(Color(0.75, 0.6, 0.15), 0.0, 0.6, 0.3), Vector3.ZERO)
	for k in 3:
		MeshKit.part(node, MeshKit.box(Vector3(half * 2.0, 0.02, 0.18)), MeshKit.mat(Color(0.1, 0.1, 0.1)), Vector3(0, RAMP_H * (0.25 + k * 0.3) + 0.02, -RAMP_LEN * 0.5 + RAMP_LEN * (0.25 + k * 0.3)), Vector3(-rad_to_deg(atan2(RAMP_H, RAMP_LEN)), 0, 0))
	ramps.append({"pos": node.position, "dir": tangents[idx], "side": side(idx), "half": half})

static func build_mine() -> Node3D:
	var root = Node3D.new()
	var shell = MeshKit.mat(Color(0.12, 0.12, 0.14), 0.0, 0.4, 0.7)
	var core = MeshKit.mat(Color(1.0, 0.15, 0.1), 1.0)
	MeshKit.part(root, MeshKit.sphere(0.42, 8, 4), shell, Vector3.ZERO)
	MeshKit.part(root, MeshKit.sphere(0.22, 6, 3), core, Vector3(0, 0.3, 0), Vector3.ZERO, Vector3.ONE, false)
	for k in 6:
		var a = k * TAU / 6.0
		MeshKit.part(root, MeshKit.cyl(0.0, 0.08, 0.35, 4), shell, Vector3(cos(a) * 0.48, 0, sin(a) * 0.48), Vector3(0, -rad_to_deg(a), -90))
	return root

# Nearest centreline sample: a local search from `hint` and a global fallback
# when the ship has wandered off (shortcuts!).
func nearest(p: Vector3, hint: int) -> int:
	var n = pts.size()
	var best = hint
	var best_d = INF
	for o in range(-30, 31):
		var i = (hint + o + n) % n
		var d = pts[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	if best_d > (half_width + 1.0) * (half_width + 1.0):
		for i in n:
			var d = pts[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best
