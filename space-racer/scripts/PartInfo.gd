extends RefCounted

# A part's card: name and maker, what it does, its numbers and the rule for
# placing it. The garage draws it across the top; shop menus draw it along
# the bottom for the selected row.

const Parts = preload("res://scripts/Parts.gd")
const Ui = preload("res://scripts/Ui.gd")

const STAT_LABELS = [["power", "Power"], ["thrust", "Thrust"], ["tier", "Tier"], ["shield", "Shield +"],
	["regen", "Regen +"], ["grip", "Grip +"], ["turn", "Turn +"], ["brake", "Brakes +"], ["magnet", "Magnet +"],
	["boost", "Boost +"], ["fuel", "Fuel +"], ["charges", "Charges "], ["jump", "Hop +"], ["dps", "Damage "],
	["range", "Range "], ["ammo", "Rockets "]]

static func rule(def: Dictionary) -> String:
	if def.get("edge", false):
		return "EDGE ONLY"
	if def.get("facing", false):
		return "FACES OPEN SPACE"
	if def.get("nose", false):
		return "NEEDS OPEN SPACE AHEAD"
	if def.has("exhaust"):
		return "NEEDS A FREE CELL BEHIND"
	return ""

static func stats_line(def: Dictionary) -> String:
	var bits = []
	for sl in STAT_LABELS:
		if def.has(sl[0]):
			var v = def[sl[0]]
			var sep = "" if sl[1].ends_with("+") or sl[1].ends_with(" ") else " "
			bits.append(sl[1] + sep + (str(v) if v is int else ("%.2f" % v).rstrip("0").rstrip(".")))
	bits.append("Mass %.2f" % def.mass)
	return "   ".join(bits)

# Draws the card in `band` (about 104 high); text starts `inset` in.
static func draw(c: CanvasItem, band: Rect2, id: String, inset: float = 30.0) -> void:
	Ui.segment(c, band, Color(0.03, 0.035, 0.045, 0.9), 10.0)
	if id == "" or not Parts.PARTS.has(id):
		return
	var def = Parts.PARTS[id]
	var mech = Parts.MECHANICS[def.mech]
	Ui.segment(c, Rect2(band.position, Vector2(band.size.x, 4)), mech.accent, 0.0)
	var x = band.position.x + inset
	var y = band.position.y
	Ui.text(c, Vector2(x, y + 32), def.name.to_upper(), 22, Color.WHITE, true)
	var nw = Ui.font(true).get_string_size(def.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	Ui.text(c, Vector2(x + nw + 14, y + 32), mech.name, 15, mech.accent, true)
	Ui.text(c, Vector2(x, y + 56), Parts.DESC.get(id, ""), 15, Color(0.85, 0.87, 0.9))
	Ui.text(c, Vector2(x, y + 82), stats_line(def), 13, Ui.DIM, true)
	var r = rule(def)
	if r != "":
		var rw = Ui.font(true).get_string_size(r, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24
		Ui.segment(c, Rect2(band.end.x - rw - 20, y + 66, rw, 24), Color(0.95, 0.7, 0.2), 6.0)
		Ui.text(c, Vector2(band.end.x - rw - 8, y + 83), r, 13, Ui.INK, true)
