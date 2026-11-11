extends Control

# In-race HUD: lap time, speed, shield/boost gauges, cargo, short banners.
# In the garage it shows the build's stats instead. Kept deliberately bare.

const Parts = preload("res://scripts/Parts.gd")
const Ui = preload("res://scripts/Ui.gd")
const MAT_COLORS = {"rock": Color(0.7, 0.6, 0.5), "metal": Color(1.0, 0.6, 0.25), "crystal": Color(0.5, 0.9, 1.0)}
const PANEL = Color(0.03, 0.035, 0.045, 0.78)

var main
var _flash = {}

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func flash(ore: String) -> void:
	_flash[ore] = 0.35

static func laptime(t: float) -> String:
	if t < 0.0:
		return "-:--.--"
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

# Segmented gauge, GT tacho style.
func _gauge(r: Rect2, frac: float, color: Color, segs: int = 16) -> void:
	var gap = 3.0
	var sw = (r.size.x - gap * (segs - 1)) / segs
	var lit = int(round(clampf(frac, 0.0, 1.0) * segs))
	for i in segs:
		var sr = Rect2(r.position.x + i * (sw + gap), r.position.y, sw, r.size.y)
		Ui.segment(self, sr, color if i < lit else Color(1, 1, 1, 0.1), 3.0)

func _draw():
	if main == null or main.ship == null or main.ship.stats.is_empty():
		return
	if main.garage:
		_garage_stats()
		return
	if main.mode != "race":
		return
	if main.menu_open():
		return
	for k in _flash.keys():
		_flash[k] -= get_process_delta_time()
		if _flash[k] <= 0.0:
			_flash.erase(k)
	var vp = size
	var ship = main.ship
	var st = ship.stats

	# Lap block, top left.
	Ui.segment(self, Rect2(-20, 18, 330, 74), PANEL)
	Ui.text(self, Vector2(28, 44), "LAP %d" % main.lap, 16, Ui.DIM, true)
	Ui.text(self, Vector2(28, 80), laptime(main.lap_time), 38, Color.WHITE, true)
	Ui.segment(self, Rect2(-20, 96, 250, 28), PANEL)
	Ui.text(self, Vector2(28, 116), "BEST  " + laptime(main.best_lap), 15, Color(0.95, 0.85, 0.4))
	# Medal targets: filled once won on this track.
	var won = main.medals_won()
	var mx = 28.0
	for i in range(main.MEDALS.size() - 1, -1, -1):
		var m = main.MEDALS[i]
		var has = won.has(m.name)
		Ui.segment(self, Rect2(mx - 6, 150, 92, 22), Color(m.color, 0.9) if has else Color(0.03, 0.035, 0.045, 0.78), 6.0)
		Ui.text(self, Vector2(mx + 4, 166), laptime(main.medal_time(m)), 14, Ui.INK if has else m.color, true)
		mx += 98

	# Gate pips under it.
	var n = main.track.checkpoints.size()
	for i in n:
		var passed = (main.next_cp == 0 and i > 0) or (i > 0 and i < main.next_cp)
		var col = Color(0.95, 0.95, 0.95) if passed else (Ui.HILITE if i == main.next_cp else Color(1, 1, 1, 0.15))
		Ui.segment(self, Rect2(30 + i * 22, 132, 16, 8), col, 3.0)

	# Speed and gauges, bottom right.
	var bx = vp.x - 360
	var by = vp.y - 150
	Ui.segment(self, Rect2(bx, by, 380, 132), PANEL)
	var kmh = int(ship.vel.length() * 3.6)
	Ui.text(self, Vector2(bx + 30, by + 66), str(kmh), 56, Color.WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	Ui.text(self, Vector2(bx + 238, by + 66), "km/h", 16, Ui.DIM)
	var sh_col = Color(0.45, 0.6, 1.0) if not ship.exposed else Color(1.0, 0.25, 0.25)
	_gauge(Rect2(bx + 40, by + 84, 290, 12), ship.shield / st.shield, sh_col)
	_gauge(Rect2(bx + 34, by + 104, 290, 12), ship.boost / ship.boost_max, Color(0.3, 0.85, 1.0))
	if ship.drifting:
		var dc = ship.drift_charge
		var c = Color(1.0, 0.85, 0.3) if dc < 0.8 else (Color(1.0, 0.45, 0.1) if dc < 1.6 else Color(1.0, 0.3, 0.85))
		Ui.segment(self, Rect2(bx + 40, by + 12, 120.0 * minf(dc / 2.0, 1.0), 6), c, 3.0)
	for i in st.charges:
		Ui.segment(self, Rect2(bx + 270 + i * 18, by + 12, 12, 10), Color(0.9, 0.2, 0.15) if i < ship.charges else Color(1, 1, 1, 0.15), 3.0)

	for i in st.ammo:
		Ui.segment(self, Rect2(bx + 40 + i * 14, by + 121, 9, 6), Color(0.45, 1.0, 0.45) if i < ship.ammo else Color(1, 1, 1, 0.15), 2.0)
	_minimap(Rect2(16, vp.y - 246, 230, 230))

	# Cargo, top right: colour chip + count.
	var cx = vp.x - 40
	for m in ["crystal", "metal", "rock"]:
		var s = str(main.inventory.get(m, 0))
		var w = Ui.font(true).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		cx -= w + 34
		var bump = 3.0 if _flash.has(m) else 0.0
		draw_rect(Rect2(cx - bump * 0.5, 30 - bump * 0.5, 12 + bump, 12 + bump), MAT_COLORS[m])
		Ui.text(self, Vector2(cx + 18, 43), s, 20, Color.WHITE, true)

	# Banners.
	var ny = vp.y * 0.24
	for msg in main.messages:
		var age = 2.2 - msg.t
		var slide = Ui.ease_out(age / 0.25)
		var a = clampf(msg.t / 0.3, 0.0, 1.0)
		var w = 520.0
		var r = Rect2((vp.x - w) * 0.5 + (1.0 - slide) * -300.0, ny, w, 42)
		Ui.segment(self, r, Color(0.03, 0.035, 0.045, 0.8 * a))
		Ui.segment(self, Rect2(r.position.x, r.end.y - 3, w, 3), Color(msg.color, a), 0.0)
		Ui.text(self, Vector2(r.position.x, r.position.y + 29), msg.text, 22, Color(1, 1, 1, a), true, HORIZONTAL_ALIGNMENT_CENTER, w)
		ny += 50

# Track outline, gates (next one lit), the player and anyone else racing.
func _minimap(r: Rect2) -> void:
	var pts = main.track.pts
	if pts.is_empty():
		return
	var lo = Vector2(INF, INF)
	var hi = Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var inner = r.grow(-18)
	var k = minf(inner.size.x / maxf(hi.x - lo.x, 1.0), inner.size.y / maxf(hi.y - lo.y, 1.0))
	var off = inner.position + (inner.size - (hi - lo) * k) * 0.5
	var to_px = func(p: Vector3) -> Vector2: return off + (Vector2(p.x, p.z) - lo) * k
	Ui.segment(self, r, PANEL, 10.0)
	var line = PackedVector2Array()
	for i in range(0, pts.size(), 2):
		line.append(to_px.call(pts[i]))
	line.append(line[0])
	draw_polyline(line, Color(0, 0, 0, 0.6), 7.0)
	draw_polyline(line, Color(0.82, 0.84, 0.88), 3.0)
	for i in main.track.checkpoints.size():
		var g = main.track.checkpoints[i]
		var c = to_px.call(g.pos)
		var n = Vector2(-g.dir.z, g.dir.x) * 7.0
		var col = Ui.HILITE if i == main.next_cp else (Color.WHITE if i == 0 else Color(1, 1, 1, 0.45))
		draw_line(c - n, c + n, col, 3.0 if i == main.next_cp else 2.0)
	for rv in main.rivals:
		draw_circle(to_px.call(rv.position), 4.0, Color(1.0, 0.35, 0.3))
	var sp = to_px.call(main.ship.position)
	var f = Vector2(sin(main.ship.heading), cos(main.ship.heading))
	var sn = Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([sp + f * 8, sp - f * 5 + sn * 5, sp - f * 5 - sn * 5]), Color(1.0, 0.85, 0.3))

func _garage_stats() -> void:
	var st = main.ship.stats
	var lo = main.loadout
	var vp = size
	var x = vp.x - 420
	var y = 70.0
	Ui.segment(self, Rect2(x, y, 440, 50), Ui.INK)
	Ui.text(self, Vector2(x + 26, y + 35), lo.name.to_upper(), 26, Color.WHITE, true)
	y += 62
	var rows = [
		["TOP SPEED", st.top / 40.0], ["ACCEL", st.accel / 40.0], ["GRIP", st.grip / 14.0],
		["BRAKES", st.get("brake", 1.0) / 2.5], ["DRILL", st.drill_tier / 3.0], ["MAGNET", st.magnet / 10.0],
		["SHIELD", st.shield / 260.0], ["HOP", st.jump / 12.0], ["FUEL", st.fuel / 300.0], ["ECONOMY", st.economy],
	]
	Ui.segment(self, Rect2(x, y, 440, rows.size() * 28 + 20), Color(0.03, 0.035, 0.045, 0.85))
	y += 32
	for r in rows:
		Ui.text(self, Vector2(x + 26, y), r[0], 14, Ui.DIM, true)
		_gauge(Rect2(x + 140, y - 11, 250, 10), r[1], Color(0.85, 0.87, 0.9), 20)
		y += 28
