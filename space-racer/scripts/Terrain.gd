extends Node3D

# The planet surface: a grid of blocks, each one drillable or blastable, drawn
# as chunks of faceted rock (see _build_chunk).

const MeshKit = preload("res://scripts/MeshKit.gd")

signal cell_destroyed(pos: Vector3, kind: int)

enum { EMPTY, ROCK, HARD, ORE_A, ORE_B, BEDROCK, BARRIER, REINFORCED, DEEP, ORE_C, CORE, GAS, LAVA, FUEL }

# What each block is worth when it breaks. Planets flavour the names but the
# blueprint only cares about the class.
const MATERIAL = {ROCK: "rock", HARD: "rock", ORE_A: "metal", ORE_B: "crystal", BARRIER: "rock", REINFORCED: "metal", DEEP: "rock", ORE_C: "core", CORE: "core"}
const WALL_MIN = 2.4      # walls are taller than any ship can hop
const BARRIER_H = 1.0     # barriers are low enough to hop if you're light
const REINFORCED_H = 1.6  # needs a ramp (or a tier-2 drill)

# hardness = drill tier needed; hp = seconds of work at drill power 1.
const KINDS = {
	ROCK: {"hardness": 1, "hp": 1.0},
	HARD: {"hardness": 2, "hp": 2.6},
	ORE_A: {"hardness": 1, "hp": 1.4},
	ORE_B: {"hardness": 2, "hp": 2.2},
	BEDROCK: {"hardness": 99, "hp": 1e9},
	BARRIER: {"hardness": 1, "hp": 1.2},
	REINFORCED: {"hardness": 2, "hp": 3.0},
	DEEP: {"hardness": 3, "hp": 2.6},
	ORE_C: {"hardness": 3, "hp": 3.2},
	CORE: {"hardness": 4, "hp": 6.0},
	FUEL: {"hardness": 1, "hp": 0.6},
	GAS: {"hardness": 1, "hp": 0.4},
	LAVA: {"hardness": 99, "hp": 1e9},
}

const PLANETS = [
	{
		"name": "Cinder", "rock": Color(0.36, 0.21, 0.15), "hard": Color(0.2, 0.14, 0.13), "bedrock": Color(0.1, 0.08, 0.08),
		"ore_a": Color(1.0, 0.5, 0.12), "ore_a_name": "copper", "ore_b": Color(1.0, 0.85, 0.3), "ore_b_name": "sunstone",
		"ground": Color(0.3, 0.2, 0.15), "track": Color(0.17, 0.16, 0.16), "line": Color(0.2, 0.9, 1.0),
		"sun": Color(1.0, 0.86, 0.72), "ambient": Color(0.55, 0.38, 0.32), "sky": Color(0.05, 0.02, 0.03),
		"deep": Color(0.24, 0.1, 0.08), "ore_c": Color(0.95, 0.3, 0.9), "core": Color(1.0, 0.55, 0.15), "gas": Color(0.55, 0.6, 0.25), "lava": Color(1.0, 0.35, 0.05), "back": Color(0.12, 0.06, 0.05),
	},
	{
		"name": "Rime", "rock": Color(0.5, 0.58, 0.68), "hard": Color(0.3, 0.37, 0.5), "bedrock": Color(0.12, 0.14, 0.2),
		"ore_a": Color(0.2, 0.5, 1.0), "ore_a_name": "cobalt", "ore_b": Color(0.55, 1.0, 1.0), "ore_b_name": "frost crystal",
		"ground": Color(0.42, 0.48, 0.56), "track": Color(0.16, 0.17, 0.2), "line": Color(1.0, 0.45, 0.2),
		"sun": Color(0.82, 0.9, 1.0), "ambient": Color(0.4, 0.48, 0.62), "sky": Color(0.02, 0.03, 0.06),
		"deep": Color(0.16, 0.2, 0.32), "ore_c": Color(0.95, 0.3, 0.9), "core": Color(0.6, 0.9, 1.0), "gas": Color(0.5, 0.65, 0.45), "lava": Color(1.0, 0.4, 0.1), "back": Color(0.1, 0.12, 0.18),
	},
	{
		"name": "Moss", "rock": Color(0.32, 0.42, 0.26), "hard": Color(0.18, 0.23, 0.17), "bedrock": Color(0.08, 0.1, 0.08),
		"ore_a": Color(0.45, 1.0, 0.3), "ore_a_name": "verdite", "ore_b": Color(0.85, 0.35, 1.0), "ore_b_name": "amethine",
		"ground": Color(0.24, 0.28, 0.2), "track": Color(0.16, 0.17, 0.15), "line": Color(1.0, 0.85, 0.2),
		"sun": Color(1.0, 0.97, 0.85), "ambient": Color(0.38, 0.45, 0.38), "sky": Color(0.02, 0.04, 0.03),
		"deep": Color(0.14, 0.12, 0.2), "ore_c": Color(0.95, 0.3, 0.9), "core": Color(0.75, 1.0, 0.4), "gas": Color(0.65, 0.75, 0.2), "lava": Color(1.0, 0.4, 0.1), "back": Color(0.07, 0.09, 0.06),
	},
	{
		"name": "Magma", "rock": Color(0.2, 0.17, 0.16), "hard": Color(0.12, 0.1, 0.1), "bedrock": Color(0.06, 0.05, 0.05),
		"ore_a": Color(0.95, 0.75, 0.3), "ore_a_name": "brass", "ore_b": Color(1.0, 0.35, 0.2), "ore_b_name": "fire opal",
		"ground": Color(0.16, 0.12, 0.11), "track": Color(0.12, 0.11, 0.11), "line": Color(1.0, 0.5, 0.15),
		"sun": Color(1.0, 0.75, 0.55), "ambient": Color(0.55, 0.3, 0.22), "sky": Color(0.08, 0.02, 0.01),
		"deep": Color(0.3, 0.08, 0.04), "ore_c": Color(0.95, 0.3, 0.9), "core": Color(1.0, 0.85, 0.3), "gas": Color(0.6, 0.55, 0.25), "lava": Color(1.0, 0.45, 0.08), "back": Color(0.1, 0.03, 0.02),
	},
]

var w = 180
var h = 180
var cell = 1.0
var kind = PackedByteArray()
var hp = PackedFloat32Array()
var height = PackedFloat32Array()
var tint = PackedColorArray()
var planet = PLANETS[0]

# Rendering: the grid is drawn as faceted rock, CHUNK x CHUNK cells per mesh.
# Corner vertices are shared between neighbouring cells so plateaus join up;
# corners on a cliff edge are pulled in toward the rock and jittered, which
# turns block edges into sloped, uneven cliffs.
const CHUNK = 16
const DAMAGE_STEPS = 4.0
var vh = PackedFloat32Array()       # corner heights, (w+1)*(h+1)
var vo = PackedVector2Array()       # corner inset offsets
var chunks = {}                     # Vector2i -> MeshInstance3D
var dirty = {}
var rock_mat: ShaderMaterial
var grain_tex: Texture2D
var ground: MeshInstance3D
var _seed = 0
var outside_solid = true    # off for planets floating in space
var lazy = false            # planets: generate and mesh chunks on demand
var focus = Vector3.ZERO    # where to stream around (local space)
var view_r = 120.0
var _pdef = {}
var _pn = []
var _ncx = 1
var _gen = PackedByteArray()

func _ready():
	var tex = NoiseTexture2D.new()
	var nz = FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.06
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	tex.noise = nz
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.generate_mipmaps = true
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = preload("res://assets/shaders/rock.gdshader")
	rock_mat.set_shader_parameter("grain_tex", tex)
	grain_tex = tex
	ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(w * cell + 400.0, h * cell + 400.0)
	ground.mesh = plane
	var gm = rock_mat.duplicate()
	gm.set_shader_parameter("contrast", 0.6)
	gm.set_shader_parameter("scale", 0.12)
	ground.material_override = gm
	add_child(ground)

# Fills the grid: noise caves, hard-rock regions, ore veins, a bedrock border.
func generate(sd: int, planet_index: int) -> void:
	_seed = sd
	planet = PLANETS[planet_index % PLANETS.size()]
	ground.material_override.set_shader_parameter("tint", planet.ground)
	var n = w * h
	kind.resize(n)
	hp.resize(n)
	height.resize(n)
	tint.resize(n)
	var cave = _noise(sd, 0.045)
	var hard = _noise(sd + 1, 0.03)
	var ore = _noise(sd + 2, 0.11)
	var hgt = _noise(sd + 3, 0.08)
	var grain = _noise(sd + 4, 0.5)
	for j in h:
		for i in w:
			var idx = j * w + i
			var k = ROCK
			var border = i < 2 or j < 2 or i >= w - 2 or j >= h - 2
			if border:
				k = BEDROCK
			elif cave.get_noise_2d(i, j) > 0.34:
				k = EMPTY
			else:
				var hv = hard.get_noise_2d(i, j)
				var ov = ore.get_noise_2d(i, j)
				if hv > 0.12:
					k = HARD
					if ov < -0.5:
						k = ORE_B
				elif ov > 0.52:
					k = ORE_A
			kind[idx] = k
			hp[idx] = KINDS[k].hp if k != EMPTY else 0.0
			var base_h = WALL_MIN + 1.4 * (hgt.get_noise_2d(i, j) * 0.5 + 0.5)
			if k == BEDROCK:
				base_h = WALL_MIN + 1.8
			elif k == HARD:
				base_h += 0.3
			height[idx] = base_h
			tint[idx] = Color.WHITE * (0.88 + 0.24 * grain.get_noise_2d(i, j))

# A round planet for the mining mode: crust, mantle, deep layer, core, with
# caves, ore by depth and the planet's hazards. Grid must already be sized.
# def: {radius, palette, gas, lava}
func generate_planet(sd: int, def: Dictionary) -> void:
	_seed = sd
	outside_solid = false
	lazy = true
	planet = PLANETS[def.palette]
	ground.visible = false
	var n = w * h
	kind.resize(n)
	hp.resize(n)
	height.resize(n)
	tint.resize(n)
	_pdef = def
	_pn = [_noise(sd, 0.08), _noise(sd + 1, 0.07), _noise(sd + 2, 0.13), _noise(sd + 3, 0.16), _noise(sd + 4, 0.5)]
	_ncx = ceili(w / float(CHUNK))
	_gen.resize(_ncx * ceili(h / float(CHUNK)))
	_gen.fill(0)
	vh.resize((w + 1) * (h + 1))
	vo.resize((w + 1) * (h + 1))
	# Dark disc behind the rock so dug tunnels show the planet's insides (and
	# so the planet has a shape from far away before its rock streams in).
	var R = float(def.radius)
	var back = MeshInstance3D.new()
	back.mesh = MeshKit.cyl(R + 1.0, R + 1.0, 0.1, 96)
	back.position.y = -0.1
	back.material_override = MeshKit.mat(planet.back, 0.0, 0.95)
	add_child(back)
	var rim = MeshInstance3D.new()
	rim.mesh = MeshKit.torus(R - 2.0, R + 1.5, 96, 4)
	rim.position.y = -0.3
	rim.material_override = MeshKit.mat(planet.rock.darkened(0.2), 0.0, 0.95)
	add_child(rim)

# Planets fill themselves in a chunk at a time, the first time anything
# looks at that chunk.
func _ensure(i: int, j: int) -> void:
	if not lazy or i < 0 or j < 0 or i >= w or j >= h:
		return
	var key = (j / CHUNK) * _ncx + (i / CHUNK)
	if _gen[key] != 0:
		return
	_gen[key] = 1
	var i0 = (i / CHUNK) * CHUNK
	var j0 = (j / CHUNK) * CHUNK
	for jj in range(j0, mini(j0 + CHUNK, h)):
		for ii in range(i0, mini(i0 + CHUNK, w)):
			_gen_cell(ii, jj)

func _gen_cell(i: int, j: int) -> void:
	var def = _pdef
	var rough = _pn[0]
	var cave = _pn[1]
	var ore = _pn[2]
	var pocket = _pn[3]
	var grain = _pn[4]
	var R = float(def.radius)
	var idx = j * w + i
	var c = cell_center(Vector2i(i, j))
	var d = Vector2(c.x, c.z).length()
	var edge = R + rough.get_noise_2d(i, j) * (2.5 + R * 0.03)
	var depth = (edge - d) / R
	var k = EMPTY
	if d < R * 0.16:
		k = CORE
	elif depth > 0.0:
		var ov = ore.get_noise_2d(i, j)
		var pv = pocket.get_noise_2d(i, j)
		if depth < 0.28:
			k = ROCK
			if ov > 0.45:
				k = ORE_A
			elif def.lava and def.get("lava_crust", false) and pv > 0.6:
				k = LAVA
		elif depth < 0.55:
			k = HARD
			if ov < -0.45:
				k = ORE_B
			elif def.lava and pv > 0.55:
				k = LAVA
		else:
			k = DEEP
			if ov > 0.55:
				k = ORE_C
		if k in [ROCK, HARD] and pv < -1.0 + def.gas * 6.0:
			k = GAS
		elif k == HARD and pv > 0.5 and not def.lava:
			k = FUEL
		elif k == ROCK and ov < -0.5:
			k = FUEL
		if depth > 0.05 and depth < 0.75 and cave.get_noise_2d(i, j) > 0.42:
			k = EMPTY
	kind[idx] = k
	hp[idx] = KINDS[k].hp if k != EMPTY else 0.0
	var layer_h = {ROCK: 1.2, ORE_A: 1.3, HARD: 1.5, ORE_B: 1.6, GAS: 1.2, LAVA: 0.6, DEEP: 1.8, ORE_C: 1.9, CORE: 2.4, FUEL: 1.1}
	height[idx] = layer_h.get(k, 1.0) * (0.85 + 0.3 * (grain.get_noise_2d(i + 300, j) * 0.5 + 0.5))
	tint[idx] = Color.WHITE * (0.88 + 0.24 * grain.get_noise_2d(i, j))

# Streaming: build the nearest unbuilt chunks around `focus` (local space)
# within `view_r`, a few milliseconds' worth per frame.
func _stream() -> void:
	var t0 = Time.get_ticks_usec()
	var fx = focus.x / cell + w * 0.5
	var fz = focus.z / cell + h * 0.5
	var r_cells = view_r / cell + CHUNK
	var todo = []
	for cz in ceili(h / float(CHUNK)):
		for cx in _ncx:
			var key = Vector2i(cx, cz)
			if chunks.has(key):
				continue
			var d = Vector2((cx + 0.5) * CHUNK - fx, (cz + 0.5) * CHUNK - fz).length()
			if d < r_cells:
				todo.append([d, key])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	for item in todo:
		var key = item[1]
		var i0 = key.x * CHUNK
		var j0 = key.y * CHUNK
		for vj in range(j0, mini(j0 + CHUNK, h) + 1):
			for vi in range(i0, mini(i0 + CHUNK, w) + 1):
				_update_vertex(vi, vj)
		_build_chunk(key)
		if Time.get_ticks_usec() - t0 > 3000:
			break

# Full redraw. Called once the track has carved itself in.
func rebuild() -> void:
	if lazy:
		return
	vh.resize((w + 1) * (h + 1))
	vo.resize((w + 1) * (h + 1))
	for vj in h + 1:
		for vi in w + 1:
			_update_vertex(vi, vj)
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	dirty.clear()
	for cz in ceili(h / float(CHUNK)):
		for cx in ceili(w / float(CHUNK)):
			_build_chunk(Vector2i(cx, cz))

func _process(_delta):
	if lazy:
		_stream()
	var n = 0
	for key in dirty.keys():
		_build_chunk(key)
		dirty.erase(key)
		n += 1
		if n >= 6:
			break

func _noise(sd: int, freq: float) -> FastNoiseLite:
	var nz = FastNoiseLite.new()
	nz.seed = sd
	nz.frequency = freq
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return nz

func kind_color(k: int) -> Color:
	match k:
		ROCK: return planet.rock
		HARD: return planet.hard
		ORE_A: return planet.ore_a
		ORE_B: return planet.ore_b
		BEDROCK: return planet.bedrock
		BARRIER: return Color(0.8, 0.66, 0.18)
		REINFORCED: return Color(0.38, 0.42, 0.48)
		DEEP: return planet.deep
		ORE_C: return planet.ore_c
		CORE: return planet.core
		GAS: return planet.gas
		LAVA: return planet.lava
		FUEL: return Color(0.25, 0.95, 0.75)
	return Color.BLACK

func kind_glow(k: int) -> float:
	return 0.0

func ore_name(k: int) -> String:
	if k == ORE_A:
		return planet.ore_a_name
	if k == ORE_B:
		return planet.ore_b_name
	return ""

# Cheap stable per-vertex random in 0..1.
func _hash(i: int, j: int, salt: int) -> float:
	var x = (i * 73856093) ^ (j * 19349663) ^ ((_seed + salt) * 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	return float((x ^ (x >> 16)) & 0xffff) / 65535.0

# Visible height of a block: damage sinks it in a few steps.
func _vis_top(idx: int) -> float:
	var k = kind[idx]
	if k == EMPTY:
		return 0.0
	var frac = clampf(hp[idx] / KINDS[k].hp, 0.0, 1.0)
	var q = ceilf(frac * DAMAGE_STEPS) / DAMAGE_STEPS
	return height[idx] * (0.35 + 0.65 * q)

func _solid_vis(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= w or j >= h:
		return false
	_ensure(i, j)
	return kind[j * w + i] != EMPTY

func _update_vertex(vi: int, vj: int) -> void:
	var sum_h = 0.0
	var n = 0
	var dir = Vector2.ZERO
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var ci = vi + d.x
		var cj = vj + d.y
		if _solid_vis(ci, cj):
			sum_h += _vis_top(cj * w + ci)
			n += 1
			dir += Vector2(d.x + 0.5, d.y + 0.5)
	var v = vj * (w + 1) + vi
	if n == 0:
		vh[v] = 0.0
		vo[v] = Vector2.ZERO
		return
	var hh = sum_h / n + (_hash(vi, vj, 1) - 0.5) * 0.25
	var off = Vector2.ZERO
	if n < 4:
		hh *= 0.88
		if dir.length() > 0.01:
			off = dir.normalized() * (0.12 + 0.3 * _hash(vi, vj, 2))
	vh[v] = maxf(hh, 0.2)
	vo[v] = off

func _corner(vi: int, vj: int, frac_h: float) -> Vector3:
	var v = vj * (w + 1) + vi
	var o = vo[v] * minf(frac_h, 1.0)
	return Vector3((vi - w * 0.5) * cell + o.x, vh[v] * frac_h, (vj - h * 0.5) * cell + o.y)

func _build_chunk(key: Vector2i) -> void:
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var cols = PackedColorArray()
	var i0 = key.x * CHUNK
	var j0 = key.y * CHUNK
	_ensure(i0, j0)
	for j in range(j0, mini(j0 + CHUNK, h)):
		for i in range(i0, mini(i0 + CHUNK, w)):
			var idx = j * w + i
			var k = kind[idx]
			if k == EMPTY:
				continue
			var col = kind_color(k) * tint[idx]
			# Alpha below 1 makes the rock shader glow (lava, cores).
			col.a = 0.35 if k == LAVA or k == CORE or k == FUEL else 1.0
			var a = _corner(i, j, 1.0)
			var b = _corner(i + 1, j, 1.0)
			var c = _corner(i + 1, j + 1, 1.0)
			var d = _corner(i, j + 1, 1.0)
			if _hash(i, j, 3) > 0.5:
				_tri(verts, norms, cols, a, b, c, Vector3.UP, col, col, col)
				_tri(verts, norms, cols, a, c, d, Vector3.UP, col, col, col)
			else:
				_tri(verts, norms, cols, a, b, d, Vector3.UP, col, col, col)
				_tri(verts, norms, cols, b, c, d, Vector3.UP, col, col, col)
			# Cliff faces toward empty neighbours: top edge -> mid -> ground.
			var dark = Color(col.r * 0.72, col.g * 0.72, col.b * 0.72, col.a)
			var midc = Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, col.a)
			for e in [[Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 1)],
					[Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 1)], [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 0)]]:
				if _solid_vis(i + e[0].x, j + e[0].y):
					continue
				var p = e[1] + Vector2i(i, j)
				var q = e[2] + Vector2i(i, j)
				var out = Vector3(e[0].x, 0.0, e[0].y)
				var pt = _corner(p.x, p.y, 1.0)
				var qt = _corner(q.x, q.y, 1.0)
				var pm = _corner(p.x, p.y, 0.45) + out * 0.08 * _hash(p.x, p.y, 4)
				var qm = _corner(q.x, q.y, 0.45) + out * 0.08 * _hash(q.x, q.y, 4)
				var pb = Vector3((p.x - w * 0.5) * cell, 0.0, (p.y - h * 0.5) * cell)
				var qb = Vector3((q.x - w * 0.5) * cell, 0.0, (q.y - h * 0.5) * cell)
				_tri(verts, norms, cols, pt, qt, qm, out, col, col, midc)
				_tri(verts, norms, cols, pt, qm, pm, out, col, midc, midc)
				_tri(verts, norms, cols, pm, qm, qb, out, midc, midc, dark)
				_tri(verts, norms, cols, pm, qb, pb, out, midc, dark, dark)
	var mi: MeshInstance3D = chunks.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = rock_mat
		add_child(mi)
		chunks[key] = mi
	if verts.is_empty():
		mi.mesh = null
		return
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = m

# Flat-shaded triangle facing `outward` (Godot fronts are clockwise).
static func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n = (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward) < 0.0:
		var t = b
		b = c
		c = t
		var tc = cb
		cb = cc
		cc = tc
		n = -n
	n = n.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	cols.append(ca)
	cols.append(cb)
	cols.append(cc)

# A cell changed: refresh its four corners and redraw every chunk they touch.
func _touch(c: Vector2i) -> void:
	if vh.is_empty():
		return
	for dj in 2:
		for di in 2:
			_update_vertex(c.x + di, c.y + dj)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var n = c + Vector2i(di, dj)
			if in_bounds(n):
				var key = Vector2i(n.x / CHUNK, n.y / CHUNK)
				if not lazy or chunks.has(key):
					dirty[key] = true

# Damaged blocks sink, so you can see your drill making progress (and a
# half-drilled wall becomes hoppable).
func _top(idx: int) -> float:
	var k = kind[idx]
	if k == EMPTY:
		return 0.0
	var frac = clampf(hp[idx] / KINDS[k].hp, 0.0, 1.0)
	return height[idx] * (0.35 + 0.65 * frac)

func top_of(c: Vector2i) -> float:
	if not in_bounds(c):
		return 99.0
	_ensure(c.x, c.y)
	return _top(c.y * w + c.x)

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell + w * 0.5), floori(p.z / cell + h * 0.5))

func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x - w * 0.5 + 0.5) * cell, 0.0, (c.y - h * 0.5 + 0.5) * cell)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return outside_solid
	_ensure(c.x, c.y)
	return kind[c.y * w + c.x] != EMPTY

func get_kind(c: Vector2i) -> int:
	if not in_bounds(c):
		return BEDROCK if outside_solid else EMPTY
	_ensure(c.x, c.y)
	return kind[c.y * w + c.x]

func set_kind(c: Vector2i, k: int) -> void:
	if not in_bounds(c):
		return
	_ensure(c.x, c.y)
	var idx = c.y * w + c.x
	if kind[idx] == BEDROCK:
		return
	kind[idx] = k
	hp[idx] = KINDS[k].hp if k != EMPTY else 0.0
	if k == BARRIER:
		height[idx] = BARRIER_H
	elif k == REINFORCED:
		height[idx] = REINFORCED_H
	elif k == ROCK and height[idx] < WALL_MIN:
		height[idx] = WALL_MIN
	_touch(c)

# Returns -1 if the tool is too weak (clank), 0 if the block took damage,
# 1 if it broke.
func damage(c: Vector2i, amount: float, tier: int) -> int:
	if not in_bounds(c):
		return -1
	_ensure(c.x, c.y)
	var idx = c.y * w + c.x
	var k = kind[idx]
	if k == EMPTY:
		return 0
	if tier < KINDS[k].hardness:
		return -1
	var before = _vis_top(idx)
	hp[idx] -= amount
	if hp[idx] <= 0.0:
		kind[idx] = EMPTY
		_touch(c)
		cell_destroyed.emit(cell_center(c) + Vector3(0, height[idx] * 0.5, 0), k)
		return 1
	if _vis_top(idx) != before:
		_touch(c)
	return 0

# Explosion: everything in the radius up to `tier` hardness takes heavy damage.
func blast(p: Vector3, radius: float, tier: int) -> int:
	var c0 = world_to_cell(p)
	var r = ceili(radius / cell)
	var broken = 0
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var c = c0 + Vector2i(di, dj)
			var d = cell_center(c).distance_to(Vector3(p.x, 0, p.z))
			if d <= radius:
				if damage(c, 99.0, tier) == 1:
					broken += 1
	return broken
