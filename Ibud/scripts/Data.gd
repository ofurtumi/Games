extends RefCounted

# All tunable game data lives here: zones, enemies, bosses, upgrades.
# Coordinates are Godot world units (the apartment model is scaled 2x,
# the spider is roughly 0.1 units tall).

const PLAYER_BASE_STATS = {
	"max_hp": 100.0,
	"damage": 10.0,
	"fire_rate": 2.6,
	"shot_speed": 12.0,
	"shots": 1,
	"pierce": 0,
	"crit": 0.05,
	"crit_mult": 2.0,
	"venom": 0.0,
	"slow_shots": 0.0,
	"chain": 0,
	"armor": 0.0,
	"speed": 1.0,
	"grapple_range": 1.0,
	"grapple_force": 1.0,
	"reel": 1.0,
	"air_gravity": 1.0,
	"sling": 0.0,
	"lifesteal": 0.0,
	"regen": 0.0,
	"magnet": 0.5,
	"pounce_cd": 2.5,
	"pounce_dmg": 30.0,
	"pounce_speed": 1.0,
	"pounce_heal": 0.0,
	"pounce_stun": 0.0,
	"venom_spread": 0.0,
	"burst_cd": 8.0,
	"burst_dmg": 20.0,
	"burst_radius": 1.2,
	"burst_slow": 0.0,
	"burst_echo": 0,
	"crumb_mult": 1.0,
	"xp_mult": 1.0,
	"revives": 0,
}

# Bugs are drawn and collide at this fraction of their listed radius, and move
# at a fraction of their listed speed. Small, deliberate creatures make the
# apartment feel big.
const BUG_SCALE = 0.7
const BUG_PACE = 0.65
const BOSS_PACE = 0.8
const PLAYER_RADIUS = 0.05

# Sugar caches hidden around the apartment each act. Each one is a web point.
const CACHES_PER_ACT = 5

# The nest (shop) sits on top of the living room table.
const NEST_POS = Vector3(-2.95, 1.55, -1.1)

# Outside of this box the player is teleported back to the spawn point.
const WORLD_MIN = Vector3(-12.0, -4.0, -17.0)
const WORLD_MAX = Vector3(11.0, 9.0, 3.0)

# "area" is used to tell which room the player is in, "spawn" is a safe inset
# where enemies and loot may appear. Both are [x_min, x_max, z_min, z_max].
# Order matters: the first matching area wins (bathroom overlaps living).
const ZONES = [
	{
		"id": "bathroom", "color": Color(0.55, 0.85, 1.0), "name": "Bathroom",
		"area": [-3.1, -0.7, -11.5, -6.5], "spawn": [-2.6, -1.1, -10.8, -7.0],
		"enemies": ["silverfish", "mosquito"],
		"bonus": "hearts", "bonus_text": "healing drops x3",
	},
	{
		"id": "bedroom", "color": Color(0.8, 0.65, 1.0), "name": "Bedroom",
		"area": [-10.3, -4.2, -7.8, 0.5], "spawn": [-9.0, -4.8, -7.0, -1.0],
		"enemies": ["moth", "mite"],
		"bonus": "xp", "bonus_text": "+50% XP",
	},
	{
		"id": "kitchen", "color": Color(1.0, 0.75, 0.35), "name": "Kitchen",
		"area": [-0.7, 4.4, -14.9, -8.0], "spawn": [1.1, 4.2, -12.5, -8.3],
		"enemies": ["roach", "fly"],
		"bonus": "crumbs", "bonus_text": "+50% crumbs",
	},
	{
		"id": "entrance", "color": Color(1.0, 0.45, 0.4), "name": "Entrance",
		"area": [4.4, 8.9, -11.4, 0.5], "spawn": [4.8, 8.4, -10.8, -3.6],
		"enemies": ["wasp", "beetle"],
		"bonus": "elites", "bonus_text": "more elites, bigger loot",
	},
	{
		"id": "living", "color": Color(0.6, 1.0, 0.6), "name": "Living room",
		"area": [-4.2, 4.4, -8.0, 0.5], "spawn": [-3.7, 3.7, -7.4, -0.9],
		"enemies": ["ant", "fly"],
		"bonus": "none", "bonus_text": "your nest (shop) is on the table",
	},
]

# ai: "crawler" walks and climbs, "flier" flies straight at you,
# "shooter" keeps its distance and fires stingers.
const ENEMIES = {
	"ant": {"name": "Ant", "ai": "crawler", "hp": 18.0, "speed": 1.0, "radius": 0.05, "damage": 6.0, "xp": 3, "crumbs": 1, "pack": 2, "color": Color(0.75, 0.25, 0.15)},
	"mite": {"name": "Dust mite", "ai": "crawler", "hp": 8.0, "speed": 1.1, "radius": 0.035, "damage": 4.0, "xp": 2, "crumbs": 1, "pack": 4, "color": Color(0.8, 0.8, 0.7)},
	"silverfish": {"name": "Silverfish", "ai": "crawler", "hp": 16.0, "speed": 1.6, "radius": 0.05, "damage": 7.0, "xp": 4, "crumbs": 1, "pack": 2, "color": Color(0.65, 0.75, 0.85)},
	"roach": {"name": "Cockroach", "ai": "crawler", "hp": 45.0, "speed": 1.2, "radius": 0.09, "damage": 10.0, "xp": 6, "crumbs": 2, "pack": 1, "color": Color(0.5, 0.3, 0.12)},
	"beetle": {"name": "Beetle", "ai": "crawler", "hp": 80.0, "speed": 0.75, "radius": 0.11, "damage": 14.0, "xp": 8, "crumbs": 3, "pack": 1, "color": Color(0.15, 0.4, 0.3)},
	"fly": {"name": "Fly", "ai": "flier", "hp": 10.0, "speed": 1.3, "radius": 0.05, "damage": 5.0, "xp": 3, "crumbs": 1, "pack": 2, "color": Color(0.25, 0.3, 0.45)},
	"mosquito": {"name": "Mosquito", "ai": "flier", "hp": 8.0, "speed": 1.6, "radius": 0.04, "damage": 6.0, "xp": 3, "crumbs": 1, "pack": 2, "color": Color(0.55, 0.45, 0.4)},
	"moth": {"name": "Moth", "ai": "flier", "hp": 40.0, "speed": 0.9, "radius": 0.09, "damage": 9.0, "xp": 6, "crumbs": 2, "pack": 1, "color": Color(0.8, 0.7, 0.5)},
	"wasp": {"name": "Wasp", "ai": "shooter", "hp": 28.0, "speed": 1.2, "radius": 0.07, "damage": 9.0, "xp": 7, "crumbs": 3, "pack": 1, "color": Color(0.95, 0.8, 0.1)},
}

# center_y: height of the hit volume centre above the node origin.
# hit_height > 0 turns the hit volume into a standing capsule of that height.
const BOSSES = {
	"mouse": {"name": "The Mouse", "ai": "boss", "hp": 700.0, "speed": 2.8, "radius": 0.22, "center_y": 0.0, "hit_height": 0.0, "damage": 18.0, "xp": 60, "crumbs": 0, "pack": 1, "color": Color(0.55, 0.52, 0.5), "zone": "kitchen", "spawn": Vector3(2.6, 0.3, -10.5)},
	# Vaskur is never hurt: "capture" bosses get wrapped in web until the net
	# bar is full, then stay in the apartment playing in their net.
	"cat": {"name": "Vaskur", "ai": "boss", "hp": 2800.0, "speed": 2.6, "radius": 0.75, "center_y": 0.65, "hit_height": 0.0, "damage": 26.0, "xp": 150, "crumbs": 0, "pack": 1, "color": Color(0.26, 0.19, 0.14), "zone": "kitchen", "spawn": Vector3(2.6, 0.0, -10.2), "capture": true, "defeat_text": "Vaskur is bundled up in the net - and loving it."},
	"owner": {"name": "Tumi, the Owner", "ai": "boss", "hp": 7000.0, "speed": 2.0, "radius": 0.55, "center_y": 1.8, "hit_height": 3.6, "damage": 38.0, "xp": 0, "crumbs": 0, "pack": 1, "color": Color(0.3, 0.45, 0.7), "zone": "bedroom", "spawn": Vector3(-7.0, 0.0, -4.0)},
}

const ACTS = [
	{"boss": "mouse", "quota": 25, "intro": "Act 1 - hunt bugs to lure out the Mouse"},
	{"boss": "cat", "quota": 40, "intro": "Act 2 - the commotion is waking Vaskur the cat"},
	{"boss": "owner", "quota": 55, "intro": "Act 3 - keep hunting... Tumi will notice"},
]

# Boss relics, offered as a pick-one-of-three after each boss.
const UPGRADES = {
	"relic_tail": {"name": "Mouse Tail Whip", "desc": "Shots chain to a nearby enemy for 50% damage", "max": 1, "relic": "mouse"},
	"relic_cheese": {"name": "Cheese Heart", "desc": "+60 max HP and a full heal", "max": 1, "relic": "mouse"},
	"relic_whisker": {"name": "Whisker Sense", "desc": "+15% crit chance, +20% move speed", "max": 1, "relic": "mouse"},
	"relic_claw": {"name": "Vaskur's Favour", "desc": "+60% web shot damage", "max": 1, "relic": "cat"},
	"relic_lives": {"name": "Nine Lives", "desc": "Revive once at half health", "max": 1, "relic": "cat"},
	"relic_catnip": {"name": "Catnip Frenzy", "desc": "+40% fire rate, +1 pierce", "max": 1, "relic": "cat"},
}

# Permanent upgrades bought with silk between runs. Cost = cost * (level + 1).
const META = {
	"hp": {"name": "Tough Hatchling", "desc": "+10 max HP", "max": 10, "cost": 15},
	"dmg": {"name": "Born Hunter", "desc": "+6% damage", "max": 10, "cost": 15},
	"crumbs": {"name": "Hoarder", "desc": "+10% crumbs", "max": 5, "cost": 20},
	"speed": {"name": "Silk Reserves", "desc": "+3% move speed", "max": 5, "cost": 20},
	"start": {"name": "Head Start", "desc": "Start with +1 web point", "max": 3, "cost": 60},
}

# --- the web (in-run skill tree) ---------------------------------------------
# Six spokes run out from the core. A node can be taken once it touches a
# node you own: the core, the previous node on its spoke, or a thread node.
# Thread nodes sit on rings 2 and 4 between two neighbouring spokes, so you
# can climb one spoke and cross over to the next one.
# fx entries are [stat, "add" | "mul", value] applied to the run stats.

const WEB_RINGS = 5
const WEB_THREAD_RINGS = [2, 4]

const WEB_SPOKES = [
	{"id": "movement", "name": "Movement", "color": Color(0.45, 0.95, 0.55), "nodes": [
		{"name": "Long Silk", "desc": "+30% grapple range, reel in 20% faster", "fx": [["grapple_range", "add", 0.3], ["grapple_force", "add", 0.2]]},
		{"name": "Eight-Legged Sprint", "desc": "+12% move speed", "fx": [["speed", "add", 0.12]]},
		{"name": "Swift Reel", "desc": "Reel in 40% faster", "fx": [["reel", "add", 0.4]]},
		{"name": "Featherweight", "desc": "Fall 25% slower", "fx": [["air_gravity", "mul", 0.75]]},
		{"name": "Slingshot", "desc": "Letting go of a grapple flings you onward", "fx": [["sling", "add", 1.0]]},
	]},
	{"id": "damage", "name": "Damage", "color": Color(1.0, 0.4, 0.35), "nodes": [
		{"name": "Sharper Fangs", "desc": "+20% damage", "fx": [["damage", "mul", 1.2]]},
		{"name": "Lucky Legs", "desc": "+8% crit chance", "fx": [["crit", "add", 0.08]]},
		{"name": "Sharper Fangs II", "desc": "+20% damage", "fx": [["damage", "mul", 1.2]]},
		{"name": "Brutal Bite", "desc": "+75% crit damage", "fx": [["crit_mult", "add", 0.75]]},
		{"name": "Apex Predator", "desc": "+35% damage, +10% crit chance", "fx": [["damage", "mul", 1.35], ["crit", "add", 0.1]]},
	]},
	{"id": "shooting", "name": "Shooting", "color": Color(0.45, 0.8, 1.0), "nodes": [
		{"name": "Rapid Spinnerets", "desc": "+20% fire rate", "fx": [["fire_rate", "mul", 1.2]]},
		{"name": "Piercing Thread", "desc": "Shots pierce +1 bug", "fx": [["pierce", "add", 1]]},
		{"name": "Split Silk", "desc": "+1 web shot per volley", "fx": [["shots", "add", 1]]},
		{"name": "Taut Silk", "desc": "+20% fire rate, +20% shot speed", "fx": [["fire_rate", "mul", 1.2], ["shot_speed", "mul", 1.2]]},
		{"name": "Silk Storm", "desc": "+2 web shots per volley", "fx": [["shots", "add", 2]]},
	]},
	{"id": "pouncing", "name": "Pouncing", "color": Color(1.0, 0.7, 0.3), "nodes": [
		{"name": "Pounce Mastery", "desc": "Pounce: -20% cooldown, +40% damage", "fx": [["pounce_cd", "mul", 0.8], ["pounce_dmg", "mul", 1.4]]},
		{"name": "Long Leap", "desc": "Pounce travels 25% further", "fx": [["pounce_speed", "mul", 1.25]]},
		{"name": "Feeding Bite", "desc": "Each pounce hit heals 4 HP", "fx": [["pounce_heal", "add", 4.0]]},
		{"name": "Pounce Mastery II", "desc": "Pounce: -20% cooldown, +40% damage", "fx": [["pounce_cd", "mul", 0.8], ["pounce_dmg", "mul", 1.4]]},
		{"name": "Ambush", "desc": "Pounce stuns for 1s and hits 60% harder", "fx": [["pounce_stun", "add", 1.0], ["pounce_dmg", "mul", 1.6]]},
	]},
	{"id": "poison", "name": "Poison", "color": Color(0.7, 1.0, 0.25), "nodes": [
		{"name": "Venom Glands", "desc": "Shots poison for 4 damage/s", "fx": [["venom", "add", 4.0]]},
		{"name": "Sticky Silk", "desc": "Shots slow bugs by 20%", "fx": [["slow_shots", "add", 0.2]]},
		{"name": "Venom Glands II", "desc": "Poison +4 damage/s", "fx": [["venom", "add", 4.0]]},
		{"name": "Toxic Bloom", "desc": "Poisoned bugs spread venom when they die", "fx": [["venom_spread", "add", 1.0]]},
		{"name": "Necrosis", "desc": "Poison damage x2", "fx": [["venom", "mul", 2.0]]},
	]},
	{"id": "aoe", "name": "Web Burst", "color": Color(0.95, 0.9, 1.0), "nodes": [
		{"name": "Wide Burst", "desc": "Burst: +25% radius, +50% damage", "fx": [["burst_radius", "mul", 1.25], ["burst_dmg", "mul", 1.5]]},
		{"name": "Quick Weave", "desc": "Burst cooldown -20%", "fx": [["burst_cd", "mul", 0.8]]},
		{"name": "Wide Burst II", "desc": "Burst: +20% radius, +50% damage", "fx": [["burst_radius", "mul", 1.2], ["burst_dmg", "mul", 1.5]]},
		{"name": "Snare", "desc": "Burst slows harder and for longer", "fx": [["burst_slow", "add", 0.25]]},
		{"name": "Aftershock", "desc": "Burst goes off a second time 0.6s later", "fx": [["burst_echo", "add", 1]]},
	]},
]

# Thread nodes. Index i sits between spoke i and spoke i + 1 (wrapping).
const WEB_THREADS = {
	2: [
		{"name": "Chitin Plating", "desc": "+25 max HP", "fx": [["max_hp", "add", 25.0]]},
		{"name": "Crumb Magnet", "desc": "+60% pickup range", "fx": [["magnet", "mul", 1.6]]},
		{"name": "Molting", "desc": "Regenerate 0.6 HP/s", "fx": [["regen", "add", 0.6]]},
		{"name": "Chitin Plating", "desc": "+25 max HP", "fx": [["max_hp", "add", 25.0]]},
		{"name": "Quick Learner", "desc": "+20% XP", "fx": [["xp_mult", "add", 0.2]]},
		{"name": "Scavenger", "desc": "+25% crumbs", "fx": [["crumb_mult", "add", 0.25]]},
	],
	4: [
		{"name": "Thick Carapace", "desc": "-10% damage taken", "fx": [["armor", "add", 0.1]]},
		{"name": "Lifedrinker", "desc": "Heal 1 HP per kill", "fx": [["lifesteal", "add", 1.0]]},
		{"name": "Hardened Chitin", "desc": "+40 max HP", "fx": [["max_hp", "add", 40.0]]},
		{"name": "Thick Carapace", "desc": "-10% damage taken", "fx": [["armor", "add", 0.1]]},
		{"name": "Deep Molting", "desc": "Regenerate 0.8 HP/s", "fx": [["regen", "add", 0.8]]},
		{"name": "Lifedrinker", "desc": "Heal 1 HP per kill", "fx": [["lifesteal", "add", 1.0]]},
	],
}

# Flattens the web into id -> {name, desc, fx, kind, spoke, ring, color, links}.
# ids: "core", "<spoke>_<ring>", "thread_<ring>_<i>".
static func build_web() -> Dictionary:
	var web = {"core": {"name": "Core", "desc": "Where every spider starts.", "fx": [], "kind": "core", "spoke": -1, "ring": 0, "color": Color.WHITE, "links": []}}
	var n = WEB_SPOKES.size()
	for i in n:
		var spoke = WEB_SPOKES[i]
		for r in range(1, WEB_RINGS + 1):
			var node = spoke["nodes"][r - 1].duplicate()
			node["kind"] = "capstone" if r == WEB_RINGS else "spoke"
			node["spoke"] = i
			node["ring"] = r
			node["color"] = spoke["color"]
			node["links"] = []
			web["%s_%d" % [spoke["id"], r]] = node
	for i in n:
		var spoke = WEB_SPOKES[i]
		_link(web, "core", "%s_1" % spoke["id"])
		for r in range(1, WEB_RINGS):
			_link(web, "%s_%d" % [spoke["id"], r], "%s_%d" % [spoke["id"], r + 1])
	for r in WEB_THREAD_RINGS:
		for i in n:
			var id = "thread_%d_%d" % [r, i]
			var node = WEB_THREADS[r][i].duplicate()
			node["kind"] = "thread"
			node["spoke"] = i
			node["ring"] = r
			node["color"] = Color(0.85, 0.85, 0.85)
			node["links"] = []
			web[id] = node
			_link(web, id, "%s_%d" % [WEB_SPOKES[i]["id"], r])
			_link(web, id, "%s_%d" % [WEB_SPOKES[(i + 1) % n]["id"], r])
	return web

static func _link(web: Dictionary, a: String, b: String):
	web[a]["links"].append(b)
	web[b]["links"].append(a)
