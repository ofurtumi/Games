extends Control

# The run's skill tree, drawn as a spider web. Spokes run out from the core;
# the rings are the spiral threads. Only rings 2 and 4 carry thread nodes, so
# those are the only places you can cross from one spoke to the next.
# Hover a node to read it, click to spin it with a web point.

const Data = preload("res://scripts/Data.gd")

const RING_STEP = 49.0
const RING_BASE = 28.0
const LABEL_RADIUS = 302.0

var game = null
var hovered = ""

var info_points: Label
var info_name: Label
var info_desc: Label
var info_status: Label

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box = VBoxContainer.new()
	box.position = Vector2(28, 28)
	box.custom_minimum_size = Vector2(300, 0)
	box.size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(_label("THE WEB", 34, Color(0.92, 0.95, 1.0)))
	info_points = _label("", 20, Color(0.75, 0.95, 1.0))
	box.add_child(info_points)
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	box.add_child(gap)
	info_name = _label("", 22)
	box.add_child(info_name)
	info_desc = _label("", 16)
	box.add_child(info_desc)
	info_status = _label("", 15, Color(0.75, 0.75, 0.75))
	box.add_child(info_status)
	var gap2 = Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	box.add_child(gap2)
	box.add_child(_label("Each spoke is its own craft. The thread nodes on rings 2 and 4 join two neighbouring spokes: take one to cross over.\n\nEarn web points by levelling up, finding sugar caches and at the nest.\n\n[Tab] or [Esc] to close", 14, Color(0.7, 0.7, 0.75)))

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(300, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func open(g):
	game = g
	_refresh_info()
	queue_redraw()

func _process(_delta):
	if visible:
		queue_redraw()

# --- layout ----------------------------------------------------------------------

func _center() -> Vector2:
	return Vector2(size.x * 0.5 + 110.0, size.y * 0.5 + 8.0)

func _angle(i: int) -> float:
	return deg_to_rad(-120.0 + 60.0 * i)

func _ring_point(i: int, r: float) -> Vector2:
	var a = _angle(i % Data.WEB_SPOKES.size())
	return _center() + Vector2(cos(a), sin(a)) * (RING_BASE + r * RING_STEP)

func _pos(id: String) -> Vector2:
	var n = game.web[id]
	match n["kind"]:
		"core":
			return _center()
		"thread":
			# Middle of the straight ring thread between two spokes.
			return (_ring_point(n["spoke"], n["ring"]) + _ring_point(n["spoke"] + 1, n["ring"])) * 0.5
	return _ring_point(n["spoke"], n["ring"])

func _node_radius(id: String) -> float:
	match game.web[id]["kind"]:
		"core":
			return 15.0
		"capstone":
			return 13.0
		"thread":
			return 8.5
	return 10.0

func _node_at(p: Vector2) -> String:
	if game == null:
		return ""
	for id in game.web:
		if _pos(id).distance_to(p) <= _node_radius(id) + 5.0:
			return id
	return ""

# --- drawing ---------------------------------------------------------------------

func _link_color(a: String, b: String, color: Color) -> Array:
	var oa = game.web_owned.has(a)
	var ob = game.web_owned.has(b)
	if oa and ob:
		return [color, 3.0]
	if oa or ob:
		return [Color(color, 0.45), 2.0]
	return [Color(0.6, 0.62, 0.7, 0.22), 1.5]

func _draw():
	if game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04, 0.8))
	var n = Data.WEB_SPOKES.size()
	var t = Time.get_ticks_msec() / 1000.0
	# Decorative spiral threads between the real ones.
	for k in range(2, Data.WEB_RINGS * 2 + 2):
		var r = k * 0.5
		if is_equal_approx(r, roundf(r)) and Data.WEB_THREAD_RINGS.has(int(r)):
			continue
		var pts = PackedVector2Array()
		for i in n + 1:
			pts.append(_ring_point(i, r))
		draw_polyline(pts, Color(0.7, 0.72, 0.8, 0.1 if r != roundf(r) else 0.16), 1.0, true)
	# Rings 2 and 4: real threads that run through the thread nodes.
	for r in Data.WEB_THREAD_RINGS:
		for i in n:
			var tid = "thread_%d_%d" % [r, i]
			var mid = _pos(tid)
			var a_id = "%s_%d" % [Data.WEB_SPOKES[i]["id"], r]
			var b_id = "%s_%d" % [Data.WEB_SPOKES[(i + 1) % n]["id"], r]
			var ca = _link_color(a_id, tid, Color(0.9, 0.9, 0.95))
			var cb = _link_color(b_id, tid, Color(0.9, 0.9, 0.95))
			draw_line(_pos(a_id), mid, ca[0], ca[1], true)
			draw_line(mid, _pos(b_id), cb[0], cb[1], true)
	# Spokes.
	for i in n:
		var spoke = Data.WEB_SPOKES[i]
		var prev = "core"
		for r in range(1, Data.WEB_RINGS + 1):
			var id = "%s_%d" % [spoke["id"], r]
			var c = _link_color(prev, id, spoke["color"])
			draw_line(_pos(prev), _pos(id), c[0], c[1], true)
			prev = id
		# Spoke name and progress past the outer ring.
		var taken = 0
		for r in range(1, Data.WEB_RINGS + 1):
			if game.web_owned.has("%s_%d" % [spoke["id"], r]):
				taken += 1
		var a = _angle(i)
		var label = "%s  %d/%d" % [spoke["name"], taken, Data.WEB_RINGS]
		var lp = _center() + Vector2(cos(a), sin(a)) * LABEL_RADIUS
		# Side spokes: push the label out past the end so it clears the node.
		var w = get_theme_default_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		lp.x += signf(cos(a)) * maxf(0.0, w * 0.5 - 4.0) * absf(cos(a))
		_draw_centered(label, lp + Vector2(0, 6), 17, spoke["color"])
	# Nodes.
	var pulse = 0.5 + 0.5 * sin(t * 4.0)
	for id in game.web:
		var node = game.web[id]
		var p = _pos(id)
		var rad = _node_radius(id)
		var col: Color = node["color"]
		if game.web_owned.has(id):
			draw_circle(p, rad, col)
			draw_arc(p, rad, 0.0, TAU, 24, Color.WHITE, 1.5, true)
		elif game.web_reachable(id):
			draw_circle(p, rad, Color(0.06, 0.06, 0.08))
			var a = 0.55 + 0.45 * pulse if game.web_points > 0 else 0.5
			draw_arc(p, rad, 0.0, TAU, 24, Color(col, a), 2.5, true)
		else:
			draw_circle(p, rad, Color(0.11, 0.11, 0.13))
			draw_arc(p, rad, 0.0, TAU, 24, Color(0.5, 0.5, 0.55, 0.4), 1.0, true)
		if id == hovered:
			draw_arc(p, rad + 4.0, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 1.5, true)
	_draw_centered("core", _center() + Vector2(0, 5), 12, Color(0.1, 0.1, 0.1))

func _draw_centered(text: String, p: Vector2, font_size: int, color: Color):
	var font = get_theme_default_font()
	var w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at = p - Vector2(w * 0.5, 0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

# --- info + input ----------------------------------------------------------------

func _refresh_info():
	if game == null:
		return
	info_points.text = "Web points: %d" % game.web_points
	if hovered == "" or not game.web.has(hovered):
		info_name.text = "Hover a node"
		info_name.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		info_desc.text = ""
		info_status.text = ""
		return
	var node = game.web[hovered]
	info_name.text = node["name"]
	info_name.add_theme_color_override("font_color", node["color"])
	var where = ""
	match node["kind"]:
		"thread":
			where = "Thread between %s and %s" % [Data.WEB_SPOKES[node["spoke"]]["name"], Data.WEB_SPOKES[(node["spoke"] + 1) % Data.WEB_SPOKES.size()]["name"]]
		"spoke", "capstone":
			where = "%s, ring %d" % [Data.WEB_SPOKES[node["spoke"]]["name"], node["ring"]]
	info_desc.text = node["desc"] if where == "" else "%s\n%s" % [node["desc"], where]
	if game.web_owned.has(hovered):
		info_status.text = "Spun."
	elif not game.web_reachable(hovered):
		info_status.text = "Needs a neighbouring node first."
	elif game.web_points <= 0:
		info_status.text = "No web points left."
	else:
		info_status.text = "Click to spin it (1 web point)."

func _gui_input(event):
	if game == null:
		return
	if event is InputEventMouseMotion:
		var h = _node_at(event.position)
		if h != hovered:
			hovered = h
			_refresh_info()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id = _node_at(event.position)
		if id != "":
			game.web_take(id)
		accept_event()
