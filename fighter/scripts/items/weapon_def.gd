class_name WeaponDef
extends RefCounted
## A weapon / throwable definition, loaded from JSON in data/items/ or user://items/.
## Every field below can be set in JSON by name. Missing fields keep these defaults.

var id := ""
var name := ""
var kind := "gun" # gun | melee | throwable
var style := "" # fallback sprite name
var sprite := "" # sprite name in assets/sprites/atlas.json (defaults to id, then style)
var color := Color(0.6, 0.62, 0.66)
var size := Vector2i(6, 3)
var spawn_weight := 10.0
var move_mult := 1.0 # movement speed multiplier while held

# --- guns ---
var damage := 10.0
var fire_rate := 0.3 # seconds between shots
var auto := false
var ammo := 10
var pellets := 1
var spread := 2.0 # degrees
var bullet_speed := 500.0
var bullet_range := 400.0 # JSON key: "range"
var bullet_gravity := 0.0
var bullet_size := 1.0
var bullet_color := Color(1.0, 0.92, 0.55)
var knockback := 60.0
var terrain_damage := 5.0
var recoil := 0.0 # pushes the shooter back
var charge_time := 0.0 # >0: hold to charge, fires on release
var charge_scales := false # true: partial charge fires weaker; false: needs full charge
var spin_up := 0.0 # >0: hold this long before an auto weapon starts firing
var pierce := 0 # fighters a bullet passes through
var explosion := {} # {radius, damage, terrain_damage, knockback, fire?} on bullet impact

# --- melee ---
var reach := 12.0
var swing_time := 0.3
var shield := false # holding aim blocks bullets from the front

# --- throwables ---
var fuse := 2.5
var count := 1
var sticky := false
var cursed := false # sticks to whoever throws it
var impact := false # explodes on first contact
var fire := {} # {count, dps, duration}: spawns flames on detonation

var raw := {}


static func from_dict(d: Dictionary) -> WeaponDef:
	var w := WeaponDef.new()
	w.raw = d
	for key in d:
		var v = d[key]
		var prop: String = "bullet_range" if key == "range" else key
		if not (prop in w):
			push_warning("Item '%s': unknown field '%s'" % [d.get("id", "?"), key])
			continue
		match typeof(w.get(prop)):
			TYPE_COLOR: w.set(prop, Color.html(String(v)))
			TYPE_VECTOR2I: w.set(prop, Vector2i(int(v[0]), int(v[1])))
			TYPE_INT: w.set(prop, int(v))
			TYPE_FLOAT: w.set(prop, float(v))
			TYPE_BOOL: w.set(prop, bool(v))
			_: w.set(prop, v)
	if w.name == "":
		w.name = w.id.capitalize()
	return w
