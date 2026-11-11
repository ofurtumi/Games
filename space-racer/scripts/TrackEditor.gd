extends Control

# Top-down blueprint editor. The map is the planet's block grid; the track is
# a loop of control nodes you drag around. Features (gates, pads, mines,
# barriers) snap to the road. The right panel is the blueprint: layout rules
# and the material checklist. Build is allowed once both are green (or in
# sandbox mode, which ignores materials).
#
# Nodes tool: drag a node; click the road to add a node there; right-click a
# node to delete it; mouse wheel over a node widens or narrows the road there.
# Feature tools: click the road to place, right-click any feature to remove.

const Track = preload("res://scripts/Track.gd")

const PANEL_W = 400.0
const BG = Color(0.05, 0.055, 0.065)
const PANEL = Color(0.09, 0.1, 0.12)
const DIM = Color(0.6, 0.65, 0.72)
const OK = Color(0.45, 0.9, 0.45)
const BAD = Color(1.0, 0.4, 0.35)
const MAT_COLORS = {"rock": Color(0.7, 0.6, 0.5), "metal": Color(1.0, 0.6, 0.25), "crystal": Color(0.5, 0.9, 1.0)}
const TOOLS = [
	["nodes", "Nodes"], ["gate", "Gate"], ["pad", "Boost pad"],
	["mine", "Mine"], ["barrier", "Barrier"], ["half", "Half barrier"],
	["wall", "Wall"], ["ramp", "Ramp"],
]

var main
var bp = {}
var line = PackedVector3Array()
var hws = PackedFloat32Array()
var check = {"ok": true, "errors": [], "bad": []}
var need = {}
var tool = "nodes"
var sandbox = false
var drag = -1
var hover = -1
var map_tex: ImageTexture
var font: Font
var tool_buttons = {}
var build_button: Button
var sandbox_button: Button

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	visible = false
	theme = _theme()
	var box = VBoxContainer.new()
	box.name = "Buttons"
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var tools = GridContainer.new()
	tools.columns = 3
	box.add_child(tools)
	for t in TOOLS:
		var b = _button(t[1], func(): _set_tool(t[0]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(118, 30)
		tools.add_child(b)
		tool_buttons[t[0]] = b
	var row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("Auto-generate", _auto))
	row.add_child(_button("Clear features", _clear_features))
	row.add_child(_button("Revert", func(): open(main)))
	var row2 = HBoxContainer.new()
	box.add_child(row2)
	sandbox_button = _button("Sandbox: off", _toggle_sandbox)
	row2.add_child(sandbox_button)
	build_button = _button("BUILD TRACK", _build)
	build_button.custom_minimum_size = Vector2(160, 36)
	row2.add_child(build_button)
	row2.add_child(_button("Close", close))
	_set_tool("nodes")

# Buttons in the shared look: pale slabs, blue when pressed or toggled on.
func _theme() -> Theme:
	const Ui = preload("res://scripts/Ui.gd")
	var th = Theme.new()
	th.default_font = Ui.font(true)
	th.default_font_size = 16
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = {"normal": Ui.PAPER, "hover": Color(1, 1, 1), "pressed": Ui.HILITE, "hover_pressed": Ui.HILITE, "disabled": Color(0.35, 0.37, 0.4)}[state]
		sb.skew = Vector2(0.25, 0)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		th.set_stylebox(state, "Button", sb)
	th.set_color("font_color", "Button", Ui.INK)
	th.set_color("font_hover_color", "Button", Ui.INK)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.6, 0.62, 0.66))
	return th

func _button(text: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func open(m) -> void:
	main = m
	bp = main.track.blueprint.duplicate(true)
	bp.widths = Track.widths_of(bp)
	_refresh_map()
	_recompute()
	visible = true
	_layout()

func close() -> void:
	visible = false
	main.editor_closed()

func _set_tool(t: String) -> void:
	tool = t
	for k in tool_buttons:
		tool_buttons[k].button_pressed = k == t

func _toggle_sandbox() -> void:
	sandbox = not sandbox
	sandbox_button.text = "Sandbox: " + ("on" if sandbox else "off")
	_recompute()

func _auto() -> void:
	bp = Track.auto_blueprint(randi() % 100000, main.terrain)
	bp.widths = Track.widths_of(bp)
	_recompute()

func _clear_features() -> void:
	bp.features = bp.features.filter(func(f): return f.type == "gate")
	_recompute()

func _build() -> void:
	if not _can_build():
		return
	if not sandbox:
		for m in need:
			main.inventory[m] = main.inventory.get(m, 0) - need[m]
	visible = false
	main.build_blueprint(bp)

func _can_build() -> bool:
	if not check.ok:
		return false
	if sandbox:
		return true
	for m in need:
		if main.inventory.get(m, 0) < need[m]:
			return false
	return true

func _recompute() -> void:
	var lay = Track.layout(bp)
	line = lay.pts
	hws = lay.hw
	check = Track.validate(bp, main.terrain, lay)
	need = Track.cost(bp, lay)
	if build_button:
		build_button.disabled = not _can_build()
	queue_redraw()

func _refresh_map() -> void:
	var t = main.terrain
	var img = Image.create(t.w, t.h, false, Image.FORMAT_RGB8)
	for j in t.h:
		for i in t.w:
			var k = t.get_kind(Vector2i(i, j))
			var c = t.planet.ground if k == t.EMPTY else t.kind_color(k)
			if k != t.EMPTY and k != t.ORE_A and k != t.ORE_B:
				c = c.darkened(0.25)
			img.set_pixel(i, j, c)
	map_tex = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- layout

func _map_rect() -> Rect2:
	var s = minf(size.y - 40.0, size.x - PANEL_W - 60.0)
	return Rect2((size.x - s - PANEL_W - 20.0) * 0.5, (size.y - s) * 0.5, s, s)

func _to_px(p: Vector3) -> Vector2:
	var t = main.terrain
	var r = _map_rect()
	return r.position + Vector2((p.x / t.cell + t.w * 0.5) / t.w, (p.z / t.cell + t.h * 0.5) / t.h) * r.size

func _to_world(px: Vector2) -> Vector3:
	var t = main.terrain
	var r = _map_rect()
	var f = (px - r.position) / r.size
	return Vector3((f.x * t.w - t.w * 0.5) * t.cell, 0.0, (f.y * t.h - t.h * 0.5) * t.cell)

func _px_per_m() -> float:
	return _map_rect().size.x / (main.terrain.w * main.terrain.cell)

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_layout()

func _layout() -> void:
	if has_node("Buttons"):
		var r = _map_rect()
		var b = $Buttons
		b.position = Vector2(r.end.x + 30, r.position.y + 50)
		b.size.x = PANEL_W - 20

# ---------------------------------------------------------------- input

func _nearest_node(px: Vector2, radius: float) -> int:
	var best = -1
	var best_d = radius
	for k in bp.nodes.size():
		var d = _to_px(bp.nodes[k]).distance_to(px)
		if d < best_d:
			best_d = d
			best = k
	return best

# Nearest centreline sample to a screen point, and whether it's on the road.
func _road_hit(px: Vector2) -> Dictionary:
	var w = _to_world(px)
	var best = 0
	var best_d = INF
	for i in line.size():
		var d = line[i].distance_squared_to(w)
		if d < best_d:
			best_d = d
			best = i
	var lateral = (w - line[best]).dot(Track.side_of(line, best))
	return {"idx": best, "on": sqrt(best_d) < hws[best] + 1.5, "offset": clampf(lateral / hws[best], -0.8, 0.8)}

func _feature_px(f: Dictionary) -> Vector2:
	var i = int(fposmod(f.u, 1.0) * line.size()) % line.size()
	return _to_px(line[i] + Track.side_of(line, i) * f.offset * hws[i])

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if not _map_rect().has_point(event.position):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_click(event.position)
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var k = _nearest_node(event.position, 16.0)
			if k >= 0:
				var d = 0.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.5
				bp.widths[k] = clampf(bp.widths[k] + d, Track.MIN_HW, Track.MAX_HW)
				_recompute()
		accept_event()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if drag >= 0:
			drag = -1
			_recompute()
	elif event is InputEventMouseMotion:
		if drag >= 0:
			var lim = main.terrain.w * 0.5 * main.terrain.cell - 2.0
			var p = _to_world(event.position)
			bp.nodes[drag] = Vector3(clampf(p.x, -lim, lim), 0.0, clampf(p.z, -lim, lim))
			_recompute()
		else:
			var h = _nearest_node(event.position, 12.0)
			if h != hover:
				hover = h
				queue_redraw()

func _click(px: Vector2) -> void:
	if tool == "nodes":
		var k = _nearest_node(px, 12.0)
		if k >= 0:
			drag = k
			return
		var hit = _road_hit(px)
		if hit.on:
			_insert_node(_to_world(px))
		return
	var hit = _road_hit(px)
	if not hit.on:
		return
	var u = hit.idx / float(line.size())
	match tool:
		"gate": bp.features.append({"type": "gate", "u": u, "offset": 0.0, "width": 1.0})
		"pad": bp.features.append({"type": "pad", "u": u, "offset": 0.0, "width": 1.0})
		"mine": bp.features.append({"type": "mine", "u": u, "offset": hit.offset, "width": 1.0})
		"barrier": bp.features.append({"type": "barrier", "u": u, "offset": 0.0, "width": 1.0})
		"half": bp.features.append({"type": "barrier", "u": u, "offset": clampf(hit.offset, -0.5, 0.5), "width": 0.5})
		"wall": bp.features.append({"type": "wall", "u": u, "offset": 0.0, "width": 1.0})
		"ramp": bp.features.append({"type": "ramp", "u": u, "offset": clampf(hit.offset, -0.5, 0.5), "width": 0.5})
	_recompute()

# New node goes between the pair of neighbours it lengthens the loop least.
func _insert_node(p: Vector3) -> void:
	var n = bp.nodes.size()
	var best = 0
	var best_cost = INF
	for k in n:
		var a = bp.nodes[k]
		var b = bp.nodes[(k + 1) % n]
		var c = a.distance_to(p) + p.distance_to(b) - a.distance_to(b)
		if c < best_cost:
			best_cost = c
			best = k
	bp.nodes.insert(best + 1, p)
	bp.widths.insert(best + 1, (bp.widths[best] + bp.widths[(best + 1) % n]) * 0.5)
	drag = best + 1
	_recompute()

func _right_click(px: Vector2) -> void:
	if tool == "nodes":
		var k = _nearest_node(px, 12.0)
		if k >= 0 and bp.nodes.size() > 4:
			bp.nodes.remove_at(k)
			bp.widths.remove_at(k)
			_recompute()
			return
	var best = -1
	var best_d = 14.0
	for i in bp.features.size():
		var d = _feature_px(bp.features[i]).distance_to(px)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		bp.features.remove_at(best)
		_recompute()

# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, sz: int, color: Color = Color.WHITE, align = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1) -> void:
	draw_string(font, pos, s, align, width, sz, color)

func _draw():
	if main == null or line.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var r = _map_rect()
	draw_texture_rect(map_tex, r, false)
	var ppm = _px_per_m()
	var pts = PackedVector2Array()
	for p in line:
		pts.append(_to_px(p))
	pts.append(pts[0])
	var road_col = Color(0.14, 0.14, 0.17) if check.ok else Color(0.35, 0.1, 0.1)
	var n_l = line.size()
	for i in n_l:
		var j = (i + 1) % n_l
		var si = Track.side_of(line, i)
		var sj = Track.side_of(line, j)
		draw_colored_polygon(PackedVector2Array([
			_to_px(line[i] + si * hws[i]), _to_px(line[j] + sj * hws[j]),
			_to_px(line[j] - sj * hws[j]), _to_px(line[i] - si * hws[i])]), road_col)
	draw_polyline(pts, main.terrain.planet.line.darkened(0.2), 1.5)
	# Direction arrows.
	for k in 8:
		var i = int(line.size() * (k + 0.5) / 8.0)
		var a = _to_px(line[i])
		var b = _to_px(line[(i + 3) % line.size()])
		var d = (b - a).normalized()
		var n = Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([a + d * 7, a - d * 5 + n * 5, a - d * 5 - n * 5]), Color(1, 1, 1, 0.5))
	# Start/finish.
	var s0 = Track.side_of(line, 0) * hws[0]
	draw_line(_to_px(line[0] + s0), _to_px(line[0] - s0), Color.WHITE, 4.0)
	for f in bp.features:
		var i = int(fposmod(f.u, 1.0) * line.size()) % line.size()
		var sd = Track.side_of(line, i)
		match f.type:
			"gate":
				draw_line(_to_px(line[i] + sd * hws[i]), _to_px(line[i] - sd * hws[i]), Color(0.4, 0.6, 1.0), 3.0)
			"pad":
				var c = _feature_px(f)
				var t = (line[(i + 1) % line.size()] - line[i]).normalized()
				var d = Vector2(t.x, t.z)
				var nn = Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([c + d * 8, c - d * 5 + nn * 6, c - d * 5 - nn * 6]), Color(0.3, 1.0, 0.6))
			"mine":
				draw_circle(_feature_px(f), 4.5, Color(1.0, 0.25, 0.2))
			"barrier", "wall", "ramp":
				var c3 = line[i] + sd * f.offset * hws[i]
				var hw = f.width * hws[i]
				var col = {"barrier": Color(0.95, 0.8, 0.2), "wall": Color(0.6, 0.65, 0.72), "ramp": Color(0.85, 0.55, 0.15)}[f.type]
				draw_line(_to_px(c3 + sd * hw), _to_px(c3 - sd * hw), col, 4.0 if f.type != "ramp" else 7.0)
	for p in check.bad:
		draw_arc(_to_px(p), 12.0, 0, TAU, 20, BAD, 2.0)
	for k in bp.nodes.size():
		var c = _to_px(bp.nodes[k])
		var col = Color(1.0, 0.85, 0.3) if k == hover or k == drag else Color.WHITE
		draw_circle(c, 7.0, Color(0, 0, 0, 0.6))
		draw_circle(c, 5.0, col)
	# Ship position for reference.
	draw_circle(_to_px(main.ship.position), 4.0, Color(0.3, 0.9, 1.0))

	# Blueprint panel.
	var px = r.end.x + 20
	var panel = Rect2(px, r.position.y, PANEL_W, r.size.y)
	draw_rect(panel, PANEL)
	var x = px + 10
	_text(Vector2(x, r.position.y + 32), "TRACK BLUEPRINT", 22)
	var y = r.position.y + 290
	var gates = 1
	var counts = {"pad": 0, "mine": 0, "barrier": 0, "wall": 0, "ramp": 0}
	for f in bp.features:
		if f.type == "gate":
			gates += 1
		else:
			counts[f.type] += 1
	_text(Vector2(x, y), "%dm   %d gates   %d pads   %d mines   %d barriers   %d walls   %d ramps" % [line.size() * Track.STEP, gates, counts.pad, counts.mine, counts.barrier, counts.wall, counts.ramp], 12, DIM)
	y += 34
	_text(Vector2(x, y), "MATERIALS", 13, DIM)
	_text(Vector2(x, y), "have / need", 13, DIM, HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 20)
	y += 24
	for m in ["rock", "metal", "crystal"]:
		var have = main.inventory.get(m, 0)
		var n = need.get(m, 0)
		var ok = have >= n or sandbox
		draw_rect(Rect2(x, y - 12, 12, 12), MAT_COLORS[m])
		_text(Vector2(x + 20, y), m, 16)
		_text(Vector2(x, y), "%d / %d" % [have, n], 16, OK if ok else BAD, HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 44)
		_text(Vector2(x, y), "✓" if ok else "✗", 16, OK if ok else BAD, HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 20)
		y += 26
	y += 14
	_text(Vector2(x, y), "RULES", 13, DIM)
	y += 24
	if check.errors.is_empty():
		_text(Vector2(x, y), "✓ Layout is buildable", 15, OK)
		y += 22
	for e in check.errors:
		_text(Vector2(x, y), "✗ " + e, 15, BAD)
		y += 22
