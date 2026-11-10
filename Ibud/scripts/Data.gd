extends RefCounted

# All tunable game data lives here: zones, enemies, bosses, upgrades.
# Coordinates are Godot world units (the apartment model is scaled 2x,
# the spider is roughly 0.1 units tall).

const PLAYER_BASE_STATS = {
	"max_hp": 100.0,
	"damage": 10.0,
	"fire_rate": 2.6,
	"shot_speed": 15.0,
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
	"lifesteal": 0.0,
	"regen": 0.0,
	"magnet": 0.6,
	"pounce_cd": 2.5,
	"pounce_dmg": 30.0,
	"burst_cd": 8.0,
	"burst_dmg": 20.0,
	"burst_radius": 1.4,
	"extra_jumps": 1,
	"crumb_mult": 1.0,
	"xp_mult": 1.0,
	"revives": 0,
}

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
		"id": "bathroom", "name": "Bathroom",
		"area": [-3.1, -0.7, -11.5, -6.5], "spawn": [-2.6, -1.1, -10.8, -7.0],
		"enemies": ["silverfish", "mosquito"],
		"bonus": "hearts", "bonus_text": "healing drops x3",
	},
	{
		"id": "bedroom", "name": "Bedroom",
		"area": [-10.3, -4.2, -7.8, 0.5], "spawn": [-9.0, -4.8, -7.0, -1.0],
		"enemies": ["moth", "mite"],
		"bonus": "xp", "bonus_text": "+50% XP",
	},
	{
		"id": "kitchen", "name": "Kitchen",
		"area": [-0.7, 4.4, -14.9, -8.0], "spawn": [1.1, 4.2, -12.5, -8.3],
		"enemies": ["roach", "fly"],
		"bonus": "crumbs", "bonus_text": "+50% crumbs",
	},
	{
		"id": "entrance", "name": "Entrance",
		"area": [4.4, 8.9, -11.4, 0.5], "spawn": [4.8, 8.4, -10.8, -3.6],
		"enemies": ["wasp", "beetle"],
		"bonus": "elites", "bonus_text": "more elites, bigger loot",
	},
	{
		"id": "living", "name": "Living room",
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

# In-run upgrades. "relic" upgrades only drop from the named boss.
const UPGRADES = {
	"fangs": {"name": "Sharper Fangs", "desc": "+25% web shot damage", "max": 8},
	"spinnerets": {"name": "Rapid Spinnerets", "desc": "+20% fire rate", "max": 8},
	"split": {"name": "Split Silk", "desc": "+1 web shot per volley", "max": 3},
	"pierce": {"name": "Piercing Thread", "desc": "Shots pierce +1 enemy", "max": 3},
	"venom": {"name": "Venom Glands", "desc": "Shots poison for +4 damage/s", "max": 5},
	"sticky": {"name": "Sticky Silk", "desc": "Shots slow enemies (+20%)", "max": 3},
	"chitin": {"name": "Chitin Plating", "desc": "+25 max HP and heal 25", "max": 8},
	"carapace": {"name": "Thick Carapace", "desc": "-10% damage taken", "max": 5},
	"sprint": {"name": "Eight-Legged Sprint", "desc": "+12% move speed", "max": 5},
	"longsilk": {"name": "Long Silk", "desc": "+25% grapple range, +15% pull", "max": 4},
	"lifedrinker": {"name": "Lifedrinker", "desc": "Heal 1 HP per kill", "max": 4},
	"regen": {"name": "Molting", "desc": "Regenerate +0.6 HP/s", "max": 4},
	"magnet": {"name": "Crumb Magnet", "desc": "+60% pickup range", "max": 3},
	"lucky": {"name": "Lucky Legs", "desc": "+8% crit chance", "max": 6},
	"brutal": {"name": "Brutal Bite", "desc": "+50% crit damage", "max": 4},
	"pounce": {"name": "Pounce Mastery", "desc": "Pounce: -20% cooldown, +40% damage", "max": 4},
	"burst": {"name": "Web Burst+", "desc": "Burst: +25% radius, +50% damage", "max": 4},
	"jump": {"name": "Spring Legs", "desc": "+1 air jump", "max": 2},
	"scavenger": {"name": "Scavenger", "desc": "+25% crumbs", "max": 4},
	"learner": {"name": "Quick Learner", "desc": "+20% XP", "max": 4},
	# Boss relics
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
	"start": {"name": "Head Start", "desc": "Start with +1 random upgrade", "max": 3, "cost": 60},
}
