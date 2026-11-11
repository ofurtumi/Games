extends RefCounted

# Outpost contracts: small jobs that send you between the modes.
#   haul    - carry materials in your hold to another planet's outpost
#   race    - finish a planet's race in the top N
#   salvage - work N wrecks, anywhere
#   survey  - get down to a planet's mantle or deep layer
#   mine    - pick up N of an ore
# A contract is a dictionary saved as-is: {kind, ...params, reward, have}.
# Planets are indexed like Mining.PLANETS (and their race palettes).

const Parts = preload("res://scripts/Parts.gd")

const PLANET_NAMES = ["CINDER", "RIME", "MOSS", "MAGMA"]
const VALUE = {"rock": 1, "metal": 2, "crystal": 4, "core": 12}
const LAYERS = [[0.3, "MANTLE"], [0.6, "DEEP LAYER"]]
const MAX_ACTIVE = 3

# Pay roughly `value` worth, in materials other than `avoid`.
static func _pay(rng: RandomNumberGenerator, value: int, avoid: String = "") -> Dictionary:
	var out = {}
	var picks = ["metal", "crystal", "core"].filter(func(m): return m != avoid)
	var left = value
	while left > 0:
		var m = picks[rng.randi() % picks.size()]
		if VALUE[m] > left and m != "metal":
			m = "metal"
		out[m] = out.get(m, 0) + 1
		left -= VALUE[m]
	return out

static func make(rng: RandomNumberGenerator, here: int, unlocks: Array) -> Dictionary:
	var kinds = ["haul", "haul", "race", "salvage", "survey", "mine", "bounty"]
	var kind = kinds[rng.randi() % kinds.size()]
	var c = {"kind": kind, "from": here, "have": 0}
	match kind:
		"haul":
			var mat = ["rock", "metal", "metal", "crystal"][rng.randi() % 4]
			c.mat = mat
			c.need = {"rock": 40, "metal": 16, "crystal": 8}[mat] + rng.randi() % 8
			c.to = (here + 1 + rng.randi() % 3) % 4
			c.reward = _pay(rng, int(c.need * VALUE[mat] * 1.7), mat)
		"race":
			c.planet = rng.randi() % 4
			c.place = 1 + rng.randi() % 2
			c.reward = _pay(rng, 30 if c.place == 1 else 20)
		"salvage":
			c.need = 1 + rng.randi() % 2
			c.reward = _pay(rng, 16 * c.need)
			# Sometimes a blueprint you haven't found yet.
			var missing = []
			for id in Parts.NODES:
				if Parts.NODES[id].get("locked", false) and not unlocks.has(Parts.NODES[id].name):
					missing.append(Parts.NODES[id].name)
			if not missing.is_empty() and rng.randf() < 0.4:
				c.blueprint = missing[rng.randi() % missing.size()]
		"survey":
			c.planet = rng.randi() % 4
			var layer = LAYERS[rng.randi() % LAYERS.size()]
			c.depth = layer[0]
			c.layer = layer[1]
			c.reward = _pay(rng, 18 if layer[0] < 0.5 else 34)
		"bounty":
			c.need = 3 + rng.randi() % 3
			c.reward = _pay(rng, 10 * c.need)
		"mine":
			var mat = ["metal", "crystal", "core"][rng.randi() % 3]
			c.mat = mat
			c.need = {"metal": 12, "crystal": 6, "core": 2}[mat] + rng.randi() % 4
			c.reward = _pay(rng, int(c.need * VALUE[mat] * 1.4), mat)
	return c

static func title(c: Dictionary) -> String:
	match c.kind:
		"haul":
			return "Haul %d %s to %s" % [c.need, c.mat, PLANET_NAMES[c.to].capitalize()]
		"race":
			return "Top %d at %s" % [c.place, PLANET_NAMES[c.planet].capitalize()] if c.place > 1 else "Win at %s" % PLANET_NAMES[c.planet].capitalize()
		"salvage":
			return "Salvage %d wreck%s" % [c.need, "" if c.need == 1 else "s"]
		"survey":
			return "Reach %s's %s" % [PLANET_NAMES[c.planet].capitalize(), c.layer.to_lower()]
		"mine":
			return "Mine %d %s" % [c.need, c.mat]
		"bounty":
			return "Destroy %d drones" % c.need
	return "?"

static func progress(c: Dictionary) -> String:
	match c.kind:
		"salvage", "mine", "bounty":
			return "%d / %d" % [c.have, c.need]
		"haul":
			return "to " + PLANET_NAMES[c.to]
	return ""

static func reward_text(c: Dictionary) -> String:
	var bits = []
	for k in c.reward:
		bits.append("%d %s" % [c.reward[k], k])
	if c.has("blueprint"):
		bits.append(c.blueprint.to_upper())
	return "  ".join(bits)

# Does this event finish (or advance) the contract? Returns true when done.
# Events: dock {planet, cargo}, race {planet, place}, salvage {},
# depth {planet, frac}, mined {mat, n}.
static func on_event(c: Dictionary, event: String, data: Dictionary) -> bool:
	match [c.kind, event]:
		["haul", "dock"]:
			if data.planet == c.to and data.cargo.get(c.mat, 0) >= c.need:
				data.cargo[c.mat] -= c.need
				return true
		["race", "race"]:
			return data.planet == c.planet and data.place <= c.place
		["salvage", "salvage"]:
			c.have += 1
			return c.have >= c.need
		["survey", "depth"]:
			return data.planet == c.planet and data.frac >= c.depth
		["bounty", "drone"]:
			c.have += 1
			return c.have >= c.need
		["mine", "mined"]:
			if data.mat == c.mat:
				c.have += data.n
			return c.have >= c.need
	return false
