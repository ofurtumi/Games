extends RefCounted

# The outpost's terminal, drawn by GtMenu when it's showing a station: an old
# green CRT with the sections down the left and a vector plan of the station
# on the right. The highlighted section's room lights up on the plan, with a
# leader line from the list. Rows carry `place` (a room below) and `desc`.
# crt: {name, line, credits}

const GREEN = Color(0.35, 1.0, 0.45)
const MID = Color(0.22, 0.65, 0.3)
const DIM = Color(0.12, 0.35, 0.16)
const BG = Color(0.008, 0.03, 0.012)
const ROW_H = 34.0

# Rooms on the plan, in plan units (the plan is 100 x 64): rect + label.
const PLACES = {
	"nav": [Rect2(40, 2, 20, 9), "NAV DECK"],
	"blueprints": [Rect2(14, 10, 18, 10), "DRAFTING"],
	"comms": [Rect2(68, 10, 18, 10), "COMMS"],
	"contracts": [Rect2(38, 16, 24, 10), "JOB BOARD"],
	"shop": [Rect2(6, 24, 20, 12), "PARTS SHOP"],
	"cards": [Rect2(26, 29, 12, 9), "CARDS"],
	"market": [Rect2(74, 24, 20, 12), "MARKET"],
	"cargo": [Rect2(62, 29, 12, 9), "CARGO"],
	"garage": [Rect2(12, 42, 24, 13), "GARAGE BAY"],
	"chute": [Rect2(66, 42, 22, 13), "DROP CHUTE"],
	"pad": [Rect2(38, 46, 24, 10), "LAUNCH PAD"],
	"airlock": [Rect2(44, 57, 12, 6), "AIRLOCK"],
}

static var _font: Font

static func font() -> Font:
	if _font == null:
		var f = SystemFont.new()
		f.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New", "monospace"])
		_font = f
	return _font

static func screen(size: Vector2) -> Rect2:
	var w = minf(size.x - 80.0, 1400.0)
	var h = minf(size.y - 80.0, 780.0)
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)

static func row_rect(size: Vector2, i: int) -> Rect2:
	var s = screen(size)
	return Rect2(s.position.x + 36, s.position.y + 110 + i * ROW_H, 400, ROW_H - 4)

static func _plan_rect(size: Vector2) -> Rect2:
	var s = screen(size)
	var x0 = s.position.x + 480
	return Rect2(x0, s.position.y + 100, s.end.x - x0 - 40, s.size.y - 220)

static func _to(pr: Rect2, r: Rect2) -> Rect2:
	var k = Vector2(pr.size.x / 100.0, pr.size.y / 64.0)
	return Rect2(pr.position + r.position * k, r.size * k)

static func draw(c: CanvasItem, size: Vector2, crt: Dictionary, rows: Array, selected: int, t: float, val: Callable) -> void:
	var f = font()
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
	var s = screen(size)
	c.draw_rect(s, BG)
	c.draw_rect(s, MID, false, 2.0)
	# Header.
	c.draw_string(f, s.position + Vector2(36, 48), crt.get("name", "OUTPOST"), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, GREEN)
	c.draw_string(f, s.position + Vector2(36, 76), crt.get("line", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MID)
	c.draw_string(f, Vector2(s.end.x - 360, s.position.y + 48), "%d CR" % crt.get("credits", 0), HORIZONTAL_ALIGNMENT_RIGHT, 320, 26, GREEN)
	c.draw_string(f, Vector2(s.end.x - 360, s.position.y + 76), "DOCKED  ::  " + ("_" if fmod(t, 1.0) < 0.5 else " "), HORIZONTAL_ALIGNMENT_RIGHT, 320, 15, MID)
	c.draw_line(s.position + Vector2(30, 90), Vector2(s.end.x - 30, s.position.y + 90), DIM, 1.0)
	# Sections.
	for i in rows.size():
		var r = rows[i]
		var rr = row_rect(size, i)
		var on = i == selected
		if on:
			c.draw_rect(rr, GREEN)
		var ink = BG if on else GREEN
		c.draw_string(f, rr.position + Vector2(12, 22), ("> " if on else "  ") + str(r.label).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
		var v = val.call(r.get("value", ""))
		if str(v) != "":
			c.draw_string(f, rr.position + Vector2(0, 22), str(v).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 12, 14, BG if on else MID)
	# The plan.
	var pr = _plan_rect(size)
	var hull = PackedVector2Array()
	for p in [Vector2(30, 0), Vector2(70, 0), Vector2(98, 20), Vector2(98, 40), Vector2(70, 64), Vector2(30, 64), Vector2(2, 40), Vector2(2, 20), Vector2(30, 0)]:
		hull.append(pr.position + p * Vector2(pr.size.x / 100.0, pr.size.y / 64.0))
	c.draw_polyline(hull, MID, 2.0)
	# Corridors: a spine and a ring.
	var k = Vector2(pr.size.x / 100.0, pr.size.y / 64.0)
	c.draw_line(pr.position + Vector2(50, 11) * k, pr.position + Vector2(50, 57) * k, DIM, 3.0)
	c.draw_line(pr.position + Vector2(16, 40) * k, pr.position + Vector2(84, 40) * k, DIM, 3.0)
	c.draw_line(pr.position + Vector2(23, 20) * k, pr.position + Vector2(77, 20) * k, DIM, 3.0)
	var here = rows[selected].get("place", "") if selected >= 0 and selected < rows.size() else ""
	for key in PLACES:
		var pl = PLACES[key]
		var rr = _to(pr, pl[0])
		var on = key == here
		if on:
			var blink = 0.55 + 0.45 * sin(t * 6.0)
			c.draw_rect(rr, Color(GREEN, 0.25 * blink))
			c.draw_rect(rr, GREEN, false, 3.0)
		else:
			c.draw_rect(rr, BG)
			c.draw_rect(rr, MID, false, 1.5)
		c.draw_string(f, rr.position + Vector2(0, rr.size.y * 0.5 + 6), pl[1], HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 13, GREEN if on else MID)
	# Leader from the list to the room.
	if here != "" and PLACES.has(here):
		var a = row_rect(size, selected)
		var from = Vector2(a.end.x + 6, a.get_center().y)
		var to = _to(pr, PLACES[here][0])
		var tip = Vector2(to.position.x, to.get_center().y)
		var mid = Vector2(pr.position.x - 14, from.y)
		c.draw_polyline(PackedVector2Array([from, mid, Vector2(mid.x, tip.y), tip]), Color(GREEN, 0.8), 1.5)
		c.draw_circle(tip, 4, GREEN)
	# What the highlighted section is.
	var desc = rows[selected].get("desc", "") if selected >= 0 and selected < rows.size() else ""
	c.draw_line(Vector2(s.position.x + 30, s.end.y - 92), Vector2(s.end.x - 30, s.end.y - 92), DIM, 1.0)
	c.draw_string(f, Vector2(s.position.x + 36, s.end.y - 58), desc, HORIZONTAL_ALIGNMENT_LEFT, s.size.x - 72, 17, GREEN)
	c.draw_string(f, Vector2(s.position.x + 36, s.end.y - 26), "UP / DOWN  SECTION     ENTER  OPEN     ESC  LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	# Scanlines and a dark rim.
	var y = s.position.y
	while y < s.end.y:
		c.draw_line(Vector2(s.position.x, y), Vector2(s.end.x, y), Color(0, 0, 0, 0.22), 1.0)
		y += 3.0
	for e in 6:
		c.draw_rect(s.grow(-e * 3.0), Color(0, 0, 0, 0.08), false, 3.0)
