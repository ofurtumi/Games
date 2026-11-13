extends RefCounted

# The shops' overview panel (V, or a click on its headings, switches view):
#   SHIP  - your build: the frame's grid with what's on it (broken slots
#           scorched), the parts list and the numbers that matter.
#   PARTS - every part you own: owned, fitted, spare. The shop's selected
#           part is marked.
# data: {lo, owned, stats, broken, selected}

const Parts = preload("res://scripts/Parts.gd")
const Ui = preload("res://scripts/Ui.gd")

const KIND_COLORS = {"engine": Color(1.0, 0.55, 0.2), "thruster": Color(0.95, 0.85, 0.3), "drill": Color(0.8, 0.8, 0.85),
	"shield": Color(0.5, 0.65, 1.0), "brake": Color(0.6, 0.62, 0.68), "fin": Color(0.3, 0.85, 1.0), "hopjet": Color(0.5, 1.0, 0.6)}

const MODES = [["ship", "SHIP"], ["parts", "PARTS OWNED"]]

# The view whose heading is at `pos`, or "".
static func tab_at(r: Rect2, pos: Vector2) -> String:
	for i in MODES.size():
		if Rect2(r.position.x + 20 + i * 150, r.position.y + 10, 150, 40).has_point(pos):
			return MODES[i][0]
	return ""

static func draw(c: CanvasItem, r: Rect2, data: Dictionary, mode: String) -> void:
	Ui.segment(c, r, Color(0.03, 0.035, 0.045, 0.9), 10.0)
	Ui.segment(c, Rect2(r.position, Vector2(r.size.x, 4)), Ui.HILITE, 0.0)
	# Tabs.
	var x = r.position.x + 30
	for m in MODES:
		var on = m[0] == mode
		Ui.text(c, Vector2(x, r.position.y + 34), m[1], 18, Color.WHITE if on else Ui.DIM, true)
		if on:
			var w = Ui.font(true).get_string_size(m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			c.draw_rect(Rect2(x, r.position.y + 42, w, 3), Ui.HILITE)
		x += 150
	Ui.text(c, Vector2(r.end.x - 120, r.position.y + 34), "V  SWITCH", 13, Ui.DIM, true)
	var body = Rect2(r.position + Vector2(30, 62), r.size - Vector2(60, 76))
	if mode == "ship":
		_ship(c, body, data)
	else:
		_parts(c, body, data)

static func _ship(c: CanvasItem, b: Rect2, data: Dictionary) -> void:
	var lo = data.lo
	var frame = Parts.frame_cells(lo.frame)
	var sz = Parts.frame_size(lo.frame)
	var cp = minf(22.0, minf(b.size.y / maxf(sz.y, 1), 200.0 / maxf(sz.x, 1)))
	var o = b.position
	var occ = Parts.occupancy(lo.parts)
	for y in sz.y:
		for x in sz.x:
			var cell = Vector2i(x, y)
			if not frame.has(cell):
				continue
			var rr = Rect2(o + Vector2(x, y) * cp, Vector2(cp, cp)).grow(-1)
			var col = Color(0.3, 0.32, 0.36)
			if data.broken.has(cell):
				col = Color(0.32, 0.14, 0.1)
			elif occ.has(cell):
				col = KIND_COLORS.get(Parts.PARTS[lo.parts[occ[cell]].id].kind, Color(0.75, 0.6, 1.0))
			c.draw_rect(rr, col)
	# Parts list.
	var counts = Parts.count_parts(lo)
	var lx = o.x + sz.x * cp + 30
	var y = o.y + 14
	Ui.text(c, Vector2(lx, y), str(lo.get("name", "")).to_upper() + "  ·  " + Parts.FRAMES[lo.frame].name.to_upper(), 16, Color.WHITE, true)
	y += 26
	for id in counts:
		var def = Parts.PARTS[id]
		c.draw_rect(Rect2(lx, y - 11, 10, 10), KIND_COLORS.get(def.kind, Color(0.75, 0.6, 1.0)))
		Ui.text(c, Vector2(lx + 18, y), "%s  x%d" % [def.name, counts[id]], 15, Color(0.85, 0.87, 0.9))
		y += 21
	if not data.broken.is_empty():
		Ui.text(c, Vector2(lx, y + 4), "%d BROKEN SLOTS" % data.broken.size(), 14, Color(1.0, 0.5, 0.35), true)
		y += 25
	# Numbers.
	var st = data.stats
	var line = "TOP %d   ACCEL %d   SHIELD %d   DRILL %s" % [int(st.top), int(st.accel), int(st.shield), str(st.drill_tier) if st.drill_tier > 0 else "-"]
	Ui.text(c, Vector2(b.position.x, b.end.y - 4), line, 15, Color(1.0, 0.82, 0.25), true)

static func _parts(c: CanvasItem, b: Rect2, data: Dictionary) -> void:
	var used = Parts.count_parts(data.lo)
	var x = b.position.x
	var y = b.position.y + 14
	Ui.text(c, Vector2(x + 250, y), "OWNED", 13, Ui.DIM, true)
	Ui.text(c, Vector2(x + 330, y), "FITTED", 13, Ui.DIM, true)
	Ui.text(c, Vector2(x + 410, y), "SPARE", 13, Ui.DIM, true)
	y += 24
	var ids = data.owned.keys().filter(func(id): return Parts.PARTS.has(id) and data.owned[id] > 0)
	ids.sort_custom(func(a, z): return Parts.PARTS[a].name < Parts.PARTS[z].name)
	var col2 = false
	var start_y = y
	for id in ids:
		if y > b.end.y - 6:
			# Second column if the list is long.
			if col2:
				break
			col2 = true
			x += b.size.x * 0.5 + 10
			y = start_y
		var def = Parts.PARTS[id]
		var sel = id == data.get("selected", "")
		if sel:
			c.draw_rect(Rect2(x - 8, y - 15, 480, 20), Color(Ui.HILITE, 0.5))
		c.draw_rect(Rect2(x, y - 11, 10, 10), KIND_COLORS.get(def.kind, Color(0.75, 0.6, 1.0)))
		Ui.text(c, Vector2(x + 18, y), def.name, 15, Color.WHITE if sel else Color(0.85, 0.87, 0.9), sel)
		var spare = data.owned[id] - used.get(id, 0)
		Ui.text(c, Vector2(x + 250, y), str(data.owned[id]), 15, Color.WHITE, true)
		Ui.text(c, Vector2(x + 330, y), str(used.get(id, 0)), 15, Color.WHITE, true)
		Ui.text(c, Vector2(x + 410, y), str(spare), 15, Color(0.5, 1.0, 0.6) if spare > 0 else Ui.DIM, true)
		y += 21
	if ids.is_empty():
		Ui.text(c, Vector2(x, y), "NOTHING YET", 15, Ui.DIM, true)
