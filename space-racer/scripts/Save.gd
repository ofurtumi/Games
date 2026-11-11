extends RefCounted

# One save file: inventory, the current build, saved build slots, medals.
# Stored as Godot's text variant format so Vector2i/Color survive as-is.

const Parts = preload("res://scripts/Parts.gd")
const PATH = "user://space_racer_save.txt"
const SLOTS = 6

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var v = str_to_var(f.get_as_text())
	return v if v is Dictionary else {}

static func write(data: Dictionary) -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(var_to_str(data))

# Drops anything a newer/older version of the game doesn't know about.
static func clean_loadout(lo) -> Dictionary:
	if not (lo is Dictionary) or not Parts.FRAMES.has(lo.get("frame", "")):
		return {}
	var parts = []
	for p in lo.get("parts", []):
		if p is Dictionary and Parts.PARTS.has(p.get("id", "")) and Parts.can_place(lo.frame, parts, p):
			parts.append(p)
	var out = lo.duplicate(true)
	out.parts = parts
	if not out.has("paint"):
		out.paint = {"primary": Color.WHITE, "secondary": Color.RED, "pattern": "stripe"}
	if not out.has("name"):
		out.name = "Custom"
	return out
