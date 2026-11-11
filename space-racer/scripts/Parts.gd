extends RefCounted

# Grid ship building. A ship is a frame (a grid shape, nose at the top) with
# components placed on it. Every component is shaped (polyomino cells) and can
# be rotated; rules are checked in the rotated direction:
#   edge     - at least one cell must touch the outside of the frame
#   facing   - must face open space (fins, brakes stick out that side)
#   nose     - drills need open space in the direction they point
#   exhaust  - every cell needs a free cell behind it, in the exhaust direction
# Engines make power; thrusters turn it into thrust, so thrust past the
# engines' power is wasted. Thrusters facing back push you forward, facing
# forward they brake, facing sideways they push you sideways into turns.
#
# Loadout: {name, frame, parts: [{id, cell: Vector2i, rot: 0..3, color?}],
#           paint: {primary, secondary, pattern, glow}}
# Grid coords: x right, y down (towards the tail). Ship local space: +Z is
# the nose, +X is the left side when the ship points up the screen.

const CELL = 0.38   # metres per grid cell

const MECHANICS = {
	"": {"name": "Stock", "accent": Color(0.85, 0.85, 0.85)},
	"vex": {"name": "Vex Velocity", "accent": Color(0.2, 0.85, 1.0)},
	"grind": {"name": "Grindhaus", "accent": Color(1.0, 0.72, 0.1)},
	"aegis": {"name": "Aegis Works", "accent": Color(0.55, 0.55, 1.0)},
	"lode": {"name": "Lodestone", "accent": Color(1.0, 0.28, 0.35)},
	"arc": {"name": "Arclight Arms", "accent": Color(0.45, 1.0, 0.45)},
}

const FRAMES = {
	"basic": {"name": "Basic frame", "mech": "", "mass": 0.5, "rows": [
		"..#..",
		"..#..",
		".###.",
		".###.",
		"#####",
		".###.",
	]},
	"dart": {"name": "Dart frame", "mech": "vex", "mass": 0.35, "rows": [
		"..#..",
		"..#..",
		"..#..",
		".###.",
		".###.",
		"#####",
		"#.#.#",
	]},
	"demo": {"name": "Demo", "mech": "", "mass": 0.5, "hidden": true, "rows": [
		"######",
		"######",
		"######",
		"######",
		"######",
		"######",
	]},
	"advanced": {"name": "Advanced frame", "mech": "grind", "mass": 0.9, "rows": [
		"....##....",
		"....##....",
		"....##....",
		"..######..",
		"..######..",
		"...####...",
		"...####...",
		"...####...",
		"##########",
		"##########",
	]},
}

# A plain square plate used to show single parts in the garage preview.
const DEMO_FRAME = "demo"

const BACK = Vector2i(0, 1)

const PARTS = {
	"engine_1": {"name": "Core engine", "mech": "", "kind": "engine", "mass": 0.3, "power": 30.0,
		"shape": [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]},
	"engine_v": {"name": "Needle core", "mech": "vex", "kind": "engine", "mass": 0.2, "power": 45.0,
		"shape": [Vector2i(0, -1), Vector2i(0, 0), Vector2i(0, 1)]},
	"engine_2": {"name": "Fusion core", "mech": "grind", "kind": "engine", "mass": 0.6, "power": 70.0,
		"shape": [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
			Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(1, 2)]},

	"thruster": {"name": "Thruster", "mech": "", "kind": "thruster", "mass": 0.05, "thrust": 14.0, "exhaust": BACK,
		"shape": [Vector2i(0, 0)]},
	"thruster_v": {"name": "Ion thruster", "mech": "vex", "kind": "thruster", "mass": 0.04, "thrust": 20.0, "exhaust": BACK,
		"shape": [Vector2i(0, 0)]},
	"burner": {"name": "Hauler burner", "mech": "grind", "kind": "thruster", "mass": 0.25, "thrust": 32.0, "exhaust": BACK,
		"shape": [Vector2i(0, 0), Vector2i(1, 0)]},

	"drill_1": {"name": "Pilot drill", "mech": "", "kind": "drill", "mass": 0.1, "tier": 1, "power": 3.5, "nose": true,
		"shape": [Vector2i(0, 0), Vector2i(0, 1)]},
	"drill_2": {"name": "Auger", "mech": "grind", "kind": "drill", "mass": 0.3, "tier": 2, "power": 6.0, "nose": true,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
	"drill_3": {"name": "Maw", "mech": "grind", "kind": "drill", "mass": 0.6, "tier": 3, "power": 11.0, "nose": true,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)]},

	"shield": {"name": "Shield plate", "mech": "aegis", "kind": "shield", "mass": 0.05, "shield": 25.0, "edge": true,
		"shape": [Vector2i(0, 0)]},
	"emitter": {"name": "Bubble emitter", "mech": "aegis", "kind": "shield", "mass": 0.1, "shield": 30.0, "regen": 4.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0)]},
	"plate": {"name": "Slab armour", "mech": "grind", "kind": "shield", "mass": 0.3, "shield": 40.0, "impact": 0.8, "edge": true,
		"shape": [Vector2i(0, 0), Vector2i(1, 0)]},

	"fin": {"name": "Razor fin", "mech": "vex", "kind": "fin", "mass": 0.03, "grip": 1.2, "turn": 0.15, "facing": true,
		"shape": [Vector2i(0, 0)]},
	"brake": {"name": "Air brake", "mech": "", "kind": "brake", "mass": 0.05, "brake": 0.5, "facing": true,
		"shape": [Vector2i(0, 0)]},
	"brake_2": {"name": "Retro flaps", "mech": "vex", "kind": "brake", "mass": 0.08, "brake": 1.1, "facing": true,
		"shape": [Vector2i(0, 0), Vector2i(0, 1)]},

	"magnet": {"name": "Lode coil", "mech": "lode", "kind": "magnet", "mass": 0.15, "magnet": 4.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
	"magnet_2": {"name": "Lode ring", "mech": "lode", "kind": "magnet", "mass": 0.3, "magnet": 9.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]},

	"tank": {"name": "Boost tank", "mech": "vex", "kind": "tank", "mass": 0.06, "boost": 0.5, "fuel": 60.0,
		"shape": [Vector2i(0, 0), Vector2i(0, 1)]},
	"charges": {"name": "Charge rack", "mech": "grind", "kind": "charges", "mass": 0.15, "charges": 2,
		"shape": [Vector2i(0, 0), Vector2i(0, 1)]},
	"hopjet": {"name": "Hop jet", "mech": "", "kind": "hopjet", "mass": 0.05, "jump": 1.5,
		"shape": [Vector2i(0, 0)]},

	"laser": {"name": "Cutting laser", "mech": "arc", "kind": "laser", "mass": 0.12, "dps": 6.5, "tier": 2, "range": 9.0, "nose": true,
		"shape": [Vector2i(0, 0), Vector2i(0, 1)]},
	"laser_2": {"name": "Lance", "mech": "arc", "kind": "laser", "mass": 0.25, "dps": 12.0, "tier": 3, "range": 14.0, "nose": true,
		"shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]},
	"rocket": {"name": "Rocket pod", "mech": "arc", "kind": "rocket", "mass": 0.3, "ammo": 4, "nose": true,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
}

# One line each, shown in the garage.
const DESC = {
	"engine_1": "Makes power for your thrusters.",
	"engine_v": "Light, slim, a lot of power for its size.",
	"engine_2": "Huge power. Huge.",
	"thruster": "Pushes away from its exhaust. Needs a free cell behind it.",
	"thruster_v": "Stronger, lighter thruster.",
	"burner": "Two-cell brute. Lots of thrust, lots of weight.",
	"drill_1": "Breaks rock. Points where it faces; needs open space ahead.",
	"drill_2": "Breaks hard rock and reinforced walls.",
	"drill_3": "Breaks anything short of a planet's core.",
	"shield": "Adds shield. Must sit on an edge.",
	"emitter": "Adds shield and regenerates it.",
	"plate": "Big shield, softer impacts. Heavy. Edge only.",
	"fin": "More grip and sharper turns. Sticks out the side it faces.",
	"brake": "Stronger brakes and harder drifts. Faces open space.",
	"brake_2": "Much stronger brakes. Faces open space.",
	"magnet": "Pulls ore chunks in from further away.",
	"magnet_2": "Pulls ore from a long way off.",
	"tank": "More boost, and more fuel out in the field.",
	"charges": "Two seismic charges per rack (F).",
	"hopjet": "Hop higher.",
	"laser": "Hold to cut rock at range and pop mines. Boost in races, fuel in the field.",
	"laser_2": "Longer, hotter beam. Cuts anything a Maw can.",
	"rocket": "Four rockets. Blow open walls, clear mines. Reloads at gates.",
}

const PALETTE = [
	Color(0.92, 0.92, 0.95), Color(0.55, 0.57, 0.6), Color(0.25, 0.26, 0.29), Color(0.1, 0.1, 0.12),
	Color(0.85, 0.15, 0.15), Color(0.95, 0.45, 0.1), Color(0.98, 0.78, 0.15), Color(0.55, 0.8, 0.2),
	Color(0.2, 0.6, 0.3), Color(0.15, 0.7, 0.7), Color(0.2, 0.9, 1.0), Color(0.2, 0.35, 0.85),
	Color(0.45, 0.3, 0.85), Color(0.75, 0.3, 0.8), Color(0.95, 0.45, 0.65), Color(0.5, 0.33, 0.2),
]
const PATTERNS = ["stripe", "twin", "nose", "none"]

static func _p(id: String, x: int, y: int, rot: int = 0) -> Dictionary:
	return {"id": id, "cell": Vector2i(x, y), "rot": rot}

static func presets() -> Array:
	return [
		{"name": "Stock", "frame": "basic", "paint": {"primary": Color(0.92, 0.92, 0.95), "secondary": Color(0.85, 0.15, 0.15), "pattern": "stripe"},
			"parts": [_p("drill_1", 2, 0), _p("engine_1", 2, 3), _p("thruster", 1, 5), _p("thruster", 3, 5),
				_p("brake", 0, 4, 2), _p("brake", 4, 4), _p("shield", 2, 5)]},
		{"name": "Grinder", "frame": "advanced", "paint": {"primary": Color(0.95, 0.62, 0.1), "secondary": Color(0.12, 0.12, 0.14), "pattern": "twin"},
			"parts": [_p("drill_3", 4, 0), _p("engine_2", 4, 7), _p("burner", 0, 9), _p("burner", 8, 9), _p("burner", 6, 9),
				_p("plate", 0, 8), _p("plate", 8, 8), _p("magnet", 2, 3), _p("magnet", 6, 3), _p("brake", 3, 5, 2), _p("brake", 6, 5)]},
		{"name": "Corvette", "frame": "dart", "paint": {"primary": Color(0.1, 0.12, 0.16), "secondary": Color(0.2, 0.9, 1.0), "pattern": "stripe"},
			"parts": [_p("engine_v", 2, 2), _p("thruster_v", 0, 6), _p("thruster_v", 2, 6), _p("thruster_v", 4, 6),
				_p("fin", 0, 5, 2), _p("fin", 4, 5), _p("tank", 1, 3), _p("tank", 3, 3), _p("brake_2", 2, 5, 1), _p("hopjet", 2, 4), _p("brake", 2, 0, 3)]},
		{"name": "Scavenger", "frame": "advanced", "paint": {"primary": Color(0.3, 0.75, 0.45), "secondary": Color(0.95, 0.95, 0.95), "pattern": "nose"},
			"parts": [_p("drill_2", 4, 0), _p("engine_1", 4, 4), _p("engine_1", 4, 9), _p("thruster", 0, 9), _p("thruster", 1, 9), _p("thruster", 8, 9), _p("thruster", 9, 9),
				_p("magnet_2", 3, 5), _p("shield", 2, 3), _p("shield", 7, 3), _p("shield", 0, 8), _p("shield", 9, 8), _p("emitter", 2, 8)]},
		{"name": "Sapper", "frame": "basic", "paint": {"primary": Color(0.6, 0.3, 0.9), "secondary": Color(0.3, 1.0, 0.9), "pattern": "stripe"},
			"parts": [_p("drill_1", 2, 0), _p("engine_1", 2, 3), _p("thruster", 1, 5), _p("thruster", 3, 5),
				_p("charges", 1, 4, 1), _p("shield", 4, 4), _p("hopjet", 2, 5)]},
	]

# ---------------------------------------------------------------- geometry

static func frame_cells(frame_id: String) -> Dictionary:
	var out = {}
	var rows = FRAMES[frame_id].rows
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				out[Vector2i(x, y)] = true
	return out

static func frame_size(frame_id: String) -> Vector2i:
	var rows = FRAMES[frame_id].rows
	return Vector2i(rows[0].length(), rows.size())

static func rotate(v: Vector2i, rot: int) -> Vector2i:
	for i in rot % 4:
		v = Vector2i(-v.y, v.x)
	return v

static func cells_of(p: Dictionary) -> Array:
	var out = []
	for s in PARTS[p.id].shape:
		out.append(p.cell + rotate(s, p.get("rot", 0)))
	return out

# A direction on the part, turned with it.
static func facing_of(p: Dictionary, base: Vector2i) -> Vector2i:
	return rotate(base, p.get("rot", 0))

static func exhaust_of(p: Dictionary) -> Vector2i:
	return rotate(PARTS[p.id].get("exhaust", BACK), p.get("rot", 0))

# Grid cell centre in ship-local metres.
static func cell_pos(frame_id: String, c: Vector2) -> Vector3:
	var sz = frame_size(frame_id)
	return Vector3((sz.x * 0.5 - (c.x + 0.5)) * CELL, 0.0, (sz.y * 0.5 - (c.y + 0.5)) * CELL)

# Which part covers each cell: Vector2i -> part index.
static func occupancy(parts: Array, skip: int = -1) -> Dictionary:
	var occ = {}
	for i in parts.size():
		if i == skip:
			continue
		for c in cells_of(parts[i]):
			occ[c] = i
	return occ

# Why `p` can't go there, or "" if it can.
static func placement_error(frame_id: String, parts: Array, p: Dictionary, skip: int = -1) -> String:
	var def = PARTS[p.id]
	var frame = frame_cells(frame_id)
	var occ = occupancy(parts, skip)
	var cells = cells_of(p)
	for c in cells:
		if not frame.has(c):
			return "off the frame"
		if occ.has(c):
			return "overlaps"
	if def.get("edge", false):
		var touches = false
		for c in cells:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not frame.has(c + d):
					touches = true
		if not touches:
			return "must be on an edge"
	if def.get("nose", false):
		var fwd = facing_of(p, Vector2i(0, -1))
		for c in cells:
			var ahead = c + fwd
			if not cells.has(ahead) and frame.has(ahead):
				return "needs open space ahead"
	if def.get("facing", false):
		var out = facing_of(p, Vector2i(1, 0))
		var open = false
		for c in cells:
			if not frame.has(c + out):
				open = true
		if not open:
			return "must face open space"
	if def.has("exhaust"):
		var ex = exhaust_of(p)
		for c in cells:
			var behind = c + ex
			if cells.has(behind):
				continue
			if occ.has(behind):
				return "exhaust blocked"
	if blocks_exhaust(parts, p, skip):
		return "in a thruster's exhaust"
	return ""

# A part may not sit where an existing thruster exhausts.
static func blocks_exhaust(parts: Array, p: Dictionary, skip: int = -1) -> bool:
	var cells = cells_of(p)
	for i in parts.size():
		if i == skip or not PARTS[parts[i].id].has("exhaust"):
			continue
		var ex = exhaust_of(parts[i])
		for c in cells_of(parts[i]):
			if cells.has(c + ex):
				return true
	return false

static func can_place(frame_id: String, parts: Array, p: Dictionary, skip: int = -1) -> bool:
	return placement_error(frame_id, parts, p, skip) == ""

# ---------------------------------------------------------------- stats

static func mechanics_in(lo: Dictionary) -> Array:
	var out = []
	var fm = FRAMES[lo.frame].mech
	if fm != "":
		out.append(fm)
	for p in lo.parts:
		var m = PARTS[p.id].mech
		if m != "" and not out.has(m):
			out.append(m)
	return out

static func stats(lo: Dictionary) -> Dictionary:
	var frame = FRAMES[lo.frame]
	var ncells = frame_cells(lo.frame).size()
	var sz = frame_size(lo.frame)
	var s = {
		"mass": frame.mass + ncells * 0.02, "power": 0.0, "thrust": 0.0, "thrust_raw": 0.0,
		"accel": 0.0, "top": 0.0, "boost": 1.0, "turn": 3.0, "grip": 6.0, "brake": 1.0,
		"shield": 60.0, "regen": 0.0, "impact": 1.0, "magnet": 2.0, "charges": 0, "jump": 0.0,
		"drill_tier": 0, "drill_power": 0.0, "drill_radius": 0.0, "drill_drag": 0.0,
		"engines": 0, "engine_scale": 1.0, "strafe": 0.0, "retro": 0.0, "drills": [], "fuel": 100.0,
		"lasers": [], "launchers": [], "ammo": 0,
		"radius": maxf(sz.x * CELL * 0.5 * 0.8, 0.5), "length": sz.y * CELL, "width": sz.x * CELL,
		"can_move": false,
	}
	var hop = 0.0
	var side = 0
	for p in lo.parts:
		var d = PARTS[p.id]
		s.mass += d.mass
		match d.kind:
			"engine":
				s.power += d.power
			"thruster":
				var n = d.shape.size()
				var ex = exhaust_of(p)
				if ex == BACK:
					s.thrust_raw += d.thrust
					s.engines += n
				elif ex == Vector2i(0, -1):
					s.retro += d.thrust
					s.brake += 0.4 * n
				else:
					s.strafe += d.thrust * 0.5
					side += n
			"drill":
				var fwd = facing_of(p, Vector2i(0, -1))
				var centre = Vector3.ZERO
				for c in cells_of(p):
					centre += cell_pos(lo.frame, c)
				centre /= d.shape.size()
				var dir = Vector3(-fwd.x, 0.0, -fwd.y)
				var span = 3.0 if d.tier == 3 else 2.0
				s.drills.append({"tier": d.tier, "power": d.power, "dir": dir,
					"pos": centre + dir * (span * CELL * 0.5 + 0.35), "radius": 0.35 + d.shape.size() * 0.12, "forward": fwd == Vector2i(0, -1)})
				if d.tier > s.drill_tier:
					s.drill_tier = d.tier
					s.drill_power = d.power
					s.drill_drag = [0.0, 3.0, 2.2, 1.4][d.tier]
		if d.kind == "laser" or d.kind == "rocket":
			var wf = facing_of(p, Vector2i(0, -1))
			var wc = Vector3.ZERO
			for c in cells_of(p):
				wc += cell_pos(lo.frame, c)
			wc /= d.shape.size()
			var wdir = Vector3(-wf.x, 0.0, -wf.y)
			var w = {"pos": wc + wdir * (CELL * d.shape.size() * 0.4 + 0.2), "dir": wdir}
			if d.kind == "laser":
				w.merge({"dps": d.dps, "tier": d.tier, "range": d.range})
				s.lasers.append(w)
			else:
				s.launchers.append(w)
				s.ammo += d.ammo
		s.grip += d.get("grip", 0.0)
		s.turn += d.get("turn", 0.0)
		s.brake += d.get("brake", 0.0)
		s.shield += d.get("shield", 0.0)
		s.regen += d.get("regen", 0.0)
		s.magnet += d.get("magnet", 0.0)
		s.boost += d.get("boost", 0.0)
		s.charges += d.get("charges", 0)
		s.impact *= d.get("impact", 1.0)
		hop += d.get("jump", 0.0)
		s.fuel += d.get("fuel", 0.0)
	s.thrust = minf(s.thrust_raw, s.power)
	s.can_move = s.thrust > 0.0
	s.accel = s.thrust / s.mass
	# Top speed follows thrust-to-mass: big engines on a heavy frame still
	# haul, they just don't fly.
	s.top = maxf(9.0 + 0.8 * s.accel, 8.0)
	s.turn = (s.turn + side * 0.35) / sqrt(s.mass)
	s.jump = 9.5 / sqrt(s.mass) + hop
	if s.drill_tier > 0:
		s.drill_radius = maxf(s.radius + 0.25, 0.8)
	# Forward drills clear a hole the ship fits through.
	for dr in s.drills:
		if dr.forward:
			dr.radius = maxf(dr.radius, s.radius + 0.25)
	s.strafe = minf(s.strafe, s.power)
	s.retro = minf(s.retro, s.power)
	s.cargo = ncells * 3
	# Fuel burned per second at full thrust: heavy ships with big thrust
	# drink it, light ones sip.
	s.fuel_burn = 0.045 * (s.thrust + s.strafe * 0.5) * sqrt(s.mass)
	s.economy = clampf(1.5 / maxf(s.fuel_burn, 0.1), 0.0, 1.0)
	s.engine_scale = clampf(s.mass * 0.5, 0.6, 1.4)
	return s

# Random but legal: drop random parts at random spots until it gets full.
static func random_loadout(rng: RandomNumberGenerator) -> Dictionary:
	var frames = FRAMES.keys().filter(func(f): return not FRAMES[f].get("hidden", false))
	var frame = frames[rng.randi() % frames.size()]
	var cells = frame_cells(frame).keys()
	var parts = []
	var ids = PARTS.keys()
	var order = [["engine_1", "engine_v", "engine_2"][rng.randi() % 3]]
	for k in 3:
		order.append(["thruster", "thruster_v", "burner"][rng.randi() % 3])
	for k in 30:
		order.append(ids[rng.randi() % ids.size()])
	for id in order:
		for attempt in 40:
			var c = cells[rng.randi() % cells.size()]
			var p = {"id": id, "cell": c, "rot": 0 if PARTS[id].kind in ["thruster", "drill"] else rng.randi() % 4}
			if can_place(frame, parts, p):
				parts.append(p)
				break
	var paint = PALETTE[rng.randi() % PALETTE.size()]
	var trim = PALETTE[rng.randi() % PALETTE.size()]
	return {"name": "Random", "frame": frame, "parts": parts,
		"paint": {"primary": paint, "secondary": trim, "pattern": PATTERNS[rng.randi() % PATTERNS.size()]}}

# A loadout with just `id` on the demo plate, placed where its rule wants it.
static func demo_loadout(id: String) -> Dictionary:
	var def = PARTS[id]
	var lo_c = Vector2i(99, 99)
	var hi_c = Vector2i(-99, -99)
	for c in def.shape:
		lo_c = Vector2i(mini(lo_c.x, c.x), mini(lo_c.y, c.y))
		hi_c = Vector2i(maxi(hi_c.x, c.x), maxi(hi_c.y, c.y))
	var size = hi_c - lo_c + Vector2i.ONE
	var want = Vector2i((6 - size.x) / 2, (6 - size.y) / 2)
	if def.get("nose", false):
		want.y = 0
	elif def.has("exhaust"):
		want.y = 6 - size.y
	elif def.get("facing", false) or def.get("edge", false):
		want.x = 6 - size.x
	return {"name": def.name, "frame": DEMO_FRAME, "parts": [{"id": id, "cell": want - lo_c, "rot": 0}],
		"paint": {"primary": Color(0.2, 0.21, 0.24), "secondary": Color(0.2, 0.21, 0.24), "pattern": "none"}}
