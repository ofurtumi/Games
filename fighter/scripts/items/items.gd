class_name Items
extends RefCounted
## Registry of all WeaponDefs. Loads res://data/items then user://items (mods override by id).

const DIRS := ["res://data/items", "user://items"]

static var defs := {} # id -> WeaponDef


static func load_all() -> void:
	defs.clear()
	for dir in DIRS:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".json"):
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + f))
			if data is Dictionary:
				_register(data)
			elif data is Array:
				for d in data:
					_register(d)
			else:
				push_error("Could not parse item file %s/%s" % [dir, f])


static func _register(d: Dictionary) -> void:
	var w := WeaponDef.from_dict(d)
	if w.id == "":
		push_error("Item without id: %s" % d)
		return
	defs[w.id] = w


static func get_def(id: String) -> WeaponDef:
	return defs.get(id)


static func pick_random(rng: RandomNumberGenerator) -> WeaponDef:
	var total := 0.0
	for w in defs.values():
		total += w.spawn_weight
	var r := rng.randf() * total
	for w in defs.values():
		r -= w.spawn_weight
		if r <= 0.0:
			return w
	return defs.values()[0] if not defs.is_empty() else null
