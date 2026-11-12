extends Control

# Grid ship builder. Left: parts. Top: what the hovered/selected part does,
# with a little demo of it working. Middle: the frame grid, with the cells
# the selected part can go on marked green. Under the grid: rotation and the
# reason a placement doesn't work. The ship turns on the showroom floor to the
# right and rebuilds on every change.
#
# Click a part, click the grid to place it (R or the arrows rotate). Click a
# placed part with nothing selected to pick it up, right-click to scrap it,
# mouse wheel over it to repaint it. Q/E change frame. 1-5 presets, 0 random.
# Saved builds (right): click an empty slot to save into it, click a full one
# to load it, right-click a full one to overwrite it, Delete clears it.

const Parts = preload("res://scripts/Parts.gd")
const Ui = preload("res://scripts/Ui.gd")
const Save = preload("res://scripts/Save.gd")
const PartDemo = preload("res://scripts/PartDemo.gd")
const SubGridEditorScript = preload("res://scripts/SubGridEditor.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const BAND = Rect2(390, 12, 780, 104)
const PartInfo = preload("res://scripts/PartInfo.gd")
const MATS = preload("res://scripts/GtMenu.gd").MATS

var main
var lo = {}
var selected = ""
var rot = 0
var hover = Vector2i(-99, -99)
var t = 0.0
var _ids = []
var hover_list = -1
var hover_slot = -1
var name_edit: LineEdit
var section = "power"
var inspected = -1      # placed part being looked at
var editor              # the open component's sub-grid
var demo: SubViewport
var demo_rect: TextureRect

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	for id in Parts.PARTS:
		_ids.append(id)
	name_edit = LineEdit.new()
	name_edit.max_length = 18
	name_edit.add_theme_font_override("font", Ui.font(true))
	name_edit.add_theme_font_size_override("font_size", 18)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Ui.PAPER
	sb.skew = Vector2(0.25, 0)
	sb.content_margin_left = 16
	name_edit.add_theme_stylebox_override("normal", sb)
	name_edit.add_theme_stylebox_override("focus", sb)
	name_edit.add_theme_color_override("font_color", Ui.INK)
	name_edit.text_changed.connect(func(tx): lo.name = tx; main.loadout.name = tx)
	name_edit.text_submitted.connect(func(_tx): name_edit.release_focus())
	_style_name()
	add_child(name_edit)
	demo = PartDemo.new()
	add_child(demo)
	demo_rect = TextureRect.new()
	demo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	demo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	demo_rect.texture = demo.get_texture()
	demo_rect.position = BAND.position + Vector2(10, 8)
	demo_rect.size = Vector2(144, 88)
	demo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(demo_rect)
	editor = SubGridEditorScript.new()
	add_child(editor)

# The build's name box follows the Interface setting.
var _named_style = ""
func _style_name() -> void:
	if _named_style == Ui.style:
		return
	_named_style = Ui.style
	var term = Ui.style == "terminal"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Ui.T_PANEL if term else Ui.PAPER
	sb.skew = Vector2.ZERO if term else Vector2(0.25, 0)
	sb.content_margin_left = 16
	if term:
		sb.border_color = Ui.T_EDGE
		sb.set_border_width_all(1)
	name_edit.add_theme_stylebox_override("normal", sb)
	name_edit.add_theme_stylebox_override("focus", sb)
	name_edit.add_theme_color_override("font_color", Ui.T_GREEN if term else Ui.INK)
	Ui.begin()
	name_edit.add_theme_font_override("font", Ui.font(true) if term else Ui.font(true))
	Ui.end()

func open(m) -> void:
	main = m
	lo = main.loadout.duplicate(true)
	selected = ""
	inspected = -1
	t = 0.0
	visible = true
	name_edit.text = lo.name

func close() -> void:
	visible = false
	demo.show_part("")
	main.garage_closed()

func _commit() -> void:
	main.equip(lo.duplicate(true), false)

var preview = {}   # stats if the selected part went where the cursor is
var _preview_key = ""

func _process(delta):
	if not visible:
		return
	t += delta
	var key = ""
	if selected != "" and not editor.visible and _part_at(hover) < 0:
		var g = _ghost()
		if Parts.can_place(lo.frame, lo.parts, g, -1, _broken()):
			key = var_to_str(g)
	if key != _preview_key:
		_preview_key = key
		preview = {}
		if key != "":
			var trial = lo.duplicate(true)
			trial.parts.append(_ghost())
			trial.broken = _broken()
			preview = Parts.stats(trial)
	var id = _info_id()
	demo.show_part(id)
	demo_rect.visible = id != ""
	queue_redraw()

# ---------------------------------------------------------------- layout

func _cell_px() -> float:
	var sz = Parts.frame_size(lo.frame)
	return floorf(minf(48.0, 500.0 / maxf(sz.x, sz.y)))

func _grid_origin() -> Vector2:
	var sz = Parts.frame_size(lo.frame)
	var cp = _cell_px()
	return Vector2(410.0 + (540.0 - sz.x * cp) * 0.5, 190.0 + (500.0 - sz.y * cp) * 0.5)

func _cell_at(px: Vector2) -> Vector2i:
	var o = _grid_origin()
	var cp = _cell_px()
	return Vector2i(floori((px.x - o.x) / cp), floori((px.y - o.y) / cp))

func _cell_rect(c: Vector2i) -> Rect2:
	var cp = _cell_px()
	return Rect2(_grid_origin() + Vector2(c) * cp, Vector2(cp, cp))

# Parts in the current section tab.
func _list() -> Array:
	return _ids.filter(func(id): return Parts.SECTION_OF.get(Parts.PARTS[id].kind, "utility") == section)

func _tab_rect(i: int) -> Rect2:
	return Rect2(22 + i * 62, 84, 58, 26)

func _list_rect(i: int) -> Rect2:
	var appear = Ui.ease_out((t - i * 0.03) / 0.25)
	return Rect2(30 - (1.0 - appear) * 400.0, 122 + i * 30, 300, 26)

# Top right: the way out (Esc does the same).
func _done_rect() -> Rect2:
	return Rect2(size.x - 220, 14, 200, 44)

func _frame_rect() -> Rect2:
	return Rect2(430, 132, 500, 38)

func _rot_rects() -> Array:
	return [Rect2(420, 716, 44, 40), Rect2(530, 716, 44, 40)]

func _status_rect() -> Rect2:
	return Rect2(600, 716, 360, 40)

func _paint_rects() -> Array:
	var y = 772.0
	return [Rect2(430, y, 120, 34), Rect2(565, y, 120, 34), Rect2(700, y, 120, 34), Rect2(835, y, 120, 34)]

func _slot_rect(i: int) -> Rect2:
	return Rect2(size.x - 400, 668 + i * 36, 360, 32)

# ---------------------------------------------------------------- input

# Copies of a part not already used in this build.
func _free(id: String) -> int:
	return main.owned().get(id, 0) - Parts.count_parts(lo).get(id, 0)

# Swap to another whole build, if you own the parts for it.
func _try_load(other: Dictionary) -> void:
	var miss = main.missing_parts(other)
	if not miss.is_empty():
		var names = []
		for id in miss:
			names.append("%d %s" % [miss[id], Parts.PARTS[id].name])
		main.notify("MISSING  " + ", ".join(names).to_upper(), Color(1.0, 0.4, 0.3))
		return
	var mc = main.missing_cards(other)
	if not mc.is_empty():
		var names = []
		for id in mc:
			names.append("%d %s" % [mc[id], Parts.NODES[id].name])
		main.notify("MISSING CARDS  " + ", ".join(names).to_upper(), Color(1.0, 0.4, 0.3))
		return
	if Parts.is_locked(Parts.FRAMES[other.frame], main.unlocks()):
		main.notify("YOU DON'T HAVE THE " + Parts.FRAMES[other.frame].name.to_upper() + " YET", Color(1.0, 0.4, 0.3))
		return
	var broken = main.broken_cells(other.frame)
	for p in other.parts:
		if Parts.cells_of(p).any(func(c): return broken.has(c)):
			main.notify("BROKEN SLOTS ON THAT FRAME  -  REPAIR THEM FIRST", Color(1.0, 0.4, 0.3))
			return
	lo = other.duplicate(true)
	name_edit.text = lo.name
	main.equip(lo.duplicate(true), false)

func _broken() -> Dictionary:
	return main.broken_cells(lo.frame)

func _part_at(c: Vector2i) -> int:
	return Parts.occupancy(lo.parts).get(c, -1)

func _ghost() -> Dictionary:
	return {"id": selected, "cell": hover, "rot": rot}

func _slot_click(i: int, button: int) -> void:
	var slots = main.save_data.get("slots", [])
	slots.resize(Save.SLOTS)
	var full = slots[i] != null
	if button == MOUSE_BUTTON_LEFT and full:
		_try_load(Save.clean_loadout(slots[i]))
	elif button == MOUSE_BUTTON_LEFT or (button == MOUSE_BUTTON_RIGHT and full):
		slots[i] = lo.duplicate(true)
		main.save_data.slots = slots
		main.save_game()
		main.notify("SAVED  " + lo.name.to_upper(), Color.WHITE)

func _gui_input(event):
	if event is InputEventMouseMotion:
		hover = _cell_at(event.position)
		hover_list = -1
		hover_slot = -1
		for i in Save.SLOTS:
			if _slot_rect(i).has_point(event.position):
				hover_slot = i
		var lst = _list()
		for i in lst.size():
			if _list_rect(i).has_point(event.position):
				hover_list = _ids.find(lst[i])
	elif event is InputEventMouseButton and event.pressed:
		var pos = event.position
		var c = _cell_at(pos)
		var left = event.button_index == MOUSE_BUTTON_LEFT
		var right = event.button_index == MOUSE_BUTTON_RIGHT
		if left and _done_rect().has_point(pos):
			Sfx.play("ui_back")
			close()
			accept_event()
			return
		if left:
			name_edit.release_focus()
		if left or right:
			for i in Save.SLOTS:
				if _slot_rect(i).has_point(pos):
					_slot_click(i, event.button_index)
					return
			var prs = _paint_rects()
			for i in prs.size():
				if prs[i].has_point(pos):
					_paint(i, 1 if left else -1)
					return
			var rr = _rot_rects()
			if rr[0].has_point(pos) or rr[1].has_point(pos):
				rot = (rot + (3 if rr[0].has_point(pos) else 1)) % 4
				return
			if _frame_rect().has_point(pos):
				_cycle_frame(-1 if pos.x < _frame_rect().get_center().x else 1)
				return
		if left:
			for i in Parts.SECTIONS.size():
				if _tab_rect(i).has_point(pos):
					section = Parts.SECTIONS[i]
					t = 0.0
					return
			var lst = _list()
			for i in lst.size():
				if _list_rect(i).has_point(pos):
					if Parts.is_locked(Parts.PARTS[lst[i]], main.unlocks()):
						return
					if _free(lst[i]) <= 0 and selected != lst[i]:
						# None to hand: where can you get one?
						main.open_order(lst[i])
						return
					# Clicking the selected part again puts it down.
					selected = "" if selected == lst[i] else lst[i]
					return
			# Clicking a placed part opens its sub-grid, selection or not.
			var at = _part_at(c)
			if at < 0 and _broken().has(c):
				main.repair_slot(lo.frame, c)
				return
			if at >= 0:
				inspected = at
				if Parts.sub_size(lo.parts[at].id) != Vector2i.ZERO:
					editor.open(self, at)
			elif selected != "":
				var g = _ghost()
				if Parts.can_place(lo.frame, lo.parts, g, -1, _broken()) and _free(selected) > 0:
					lo.parts.append(g)
					Sfx.play("clunk")
					_commit()
		elif right:
			# Scrap whatever is under the cursor; the selection stays put.
			var idx = _part_at(c)
			if idx >= 0:
				lo.parts.remove_at(idx)
				inspected = -1
				Sfx.play("scrap")
				_commit()
			elif Rect2(Vector2.ZERO, Vector2(Parts.frame_size(lo.frame))).has_point(Vector2(c)):
				selected = ""
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var idx = _part_at(c)
			if idx >= 0:
				var dir = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				var col = _next_color(lo.parts[idx].get("color", null), dir, true)
				if col == null:
					lo.parts[idx].erase("color")
				else:
					lo.parts[idx].color = col
				_commit()
		accept_event()

func _unhandled_key_input(event):
	if not visible or not event.pressed or event.echo or editor.visible or main.menu.visible:
		return
	match event.physical_keycode:
		KEY_R:
			rot = (rot + (3 if event.shift_pressed else 1)) % 4
		KEY_Q:
			_cycle_frame(-1)
		KEY_E:
			_cycle_frame(1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_try_load(Parts.presets()[event.physical_keycode - KEY_1])
		KEY_0:
			_try_load(Parts.random_loadout(main.rng, main.unlocks()))
		KEY_DELETE:
			if hover_slot >= 0:
				var slots = main.save_data.get("slots", [])
				slots.resize(Save.SLOTS)
				slots[hover_slot] = null
				main.save_data.slots = slots
				main.save_game()
		KEY_ESCAPE:
			if selected != "":
				selected = ""
			else:
				close()
		KEY_G:
			close()
		_:
			return
	get_viewport().set_input_as_handled()

func _cycle_frame(dir: int) -> void:
	var keys = Parts.FRAMES.keys().filter(func(f): return not Parts.FRAMES[f].get("hidden", false) and not Parts.is_locked(Parts.FRAMES[f], main.unlocks()))
	lo.frame = keys[(keys.find(lo.frame) + dir + keys.size()) % keys.size()]
	var kept = []
	for p in lo.parts:
		if Parts.can_place(lo.frame, kept, p, -1, _broken()):
			kept.append(p)
	lo.parts = kept
	_commit()

func _next_color(current, dir: int, allow_none: bool):
	var options = Parts.PALETTE.duplicate()
	if allow_none:
		options.push_front(null)
	var i = 0
	for k in options.size():
		if options[k] != null and current != null and options[k].is_equal_approx(current):
			i = k
	return options[(i + dir + options.size()) % options.size()]

func _paint(i: int, dir: int) -> void:
	var paint = lo.paint
	match i:
		0: paint.primary = _next_color(paint.primary, dir, false)
		1: paint.secondary = _next_color(paint.secondary, dir, false)
		2: paint.pattern = Parts.PATTERNS[(Parts.PATTERNS.find(paint.pattern) + dir + Parts.PATTERNS.size()) % Parts.PATTERNS.size()]
		3: paint.glow = _next_color(paint.get("glow", null), dir, true)
	_commit()

# ---------------------------------------------------------------- drawing

func _part_color(p: Dictionary) -> Color:
	if p.has("color"):
		return p.color
	var m = Parts.PARTS[p.id].mech
	return Parts.MECHANICS[m].accent.darkened(0.15) if m != "" else Color(0.62, 0.64, 0.68)

# Tiny glyph per kind so parts read without labels.
func _glyph(r: Rect2, kind: String, facing: Vector2i, col: Color) -> void:
	var c = r.get_center()
	var s = r.size.x * 0.28
	var d = Vector2(facing)
	var n = Vector2(-d.y, d.x)
	match kind:
		"engine":
			draw_circle(c, s, col)
			draw_circle(c, s * 0.5, Color(0, 0, 0, 0.5))
		"thruster":
			draw_colored_polygon(PackedVector2Array([c - d * s, c + d * s + n * s, c + d * s - n * s]), col)
		"drill", "laser", "rocket":
			draw_colored_polygon(PackedVector2Array([c + d * s * 1.3, c - d * s + n * s, c - d * s - n * s]), col)
		"shield":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)
		"fin", "brake":
			draw_line(c, c + d * s * 1.4, col, 4.0)
			draw_line(c - n * s * 0.6, c + n * s * 0.6, col, 3.0)
		"magnet":
			draw_arc(c, s, 0, TAU, 16, col, 3.0)
		"tank":
			draw_rect(Rect2(c - Vector2(s * 0.5, s), Vector2(s, s * 2)), col)
		"charges":
			draw_circle(c + Vector2(-s * 0.5, 0), s * 0.4, col)
			draw_circle(c + Vector2(s * 0.5, 0), s * 0.4, col)
		"hopjet":
			draw_arc(c, s * 0.7, 0, TAU, 12, col, 2.0)
			draw_circle(c, s * 0.25, col)

func _facing(p: Dictionary) -> Vector2i:
	var def = Parts.PARTS[p.id]
	if def.has("exhaust"):
		return Parts.exhaust_of(p)
	if def.get("facing", false):
		return Parts.facing_of(p, Vector2i(1, 0))
	return Parts.facing_of(p, Vector2i(0, -1))

func _draw_part(p: Dictionary, fill: Color, edge: Color) -> void:
	var cells = Parts.cells_of(p)
	var glyph = Color(0, 0, 0, 0.55)
	if Ui.terminal():
		# Phosphor parts: the maker's colour as a faint tint, green edges.
		fill = Color(Ui.T_PANEL.lerp(Color(fill, 1.0), 0.3), fill.a)
		edge = Color(Ui.T_GREEN, edge.a)
		glyph = Color(Ui.T_GREEN, 0.8)
	for c in cells:
		draw_rect(_cell_rect(c).grow(-2), fill)
	for c in cells:
		var r = _cell_rect(c).grow(-2)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cells.has(c + d):
				continue
			var a = r.position
			var b = r.position
			if d.x == 1:
				a = Vector2(r.end.x, r.position.y)
				b = r.end
			elif d.x == -1:
				b = Vector2(r.position.x, r.end.y)
			elif d.y == 1:
				a = Vector2(r.position.x, r.end.y)
				b = r.end
			else:
				b = Vector2(r.end.x, r.position.y)
			draw_line(a, b, edge, 2.0)
	var kind = Parts.PARTS[p.id].kind
	for c in cells:
		_glyph(_cell_rect(c), kind, _facing(p), glyph)
	# Wired: a little node-and-wire mark in the corner.
	if p.has("id") and Parts.sub_size(p.id) != Vector2i.ZERO and not Parts.live_nodes(Parts.sub_of(p)).is_empty():
		var r = _cell_rect(cells[0])
		var a = r.position + Vector2(7, 7)
		draw_line(a, a + Vector2(10, 0), Color.WHITE, 2.0)
		draw_circle(a, 3.5, Color.WHITE)
		draw_circle(a + Vector2(12, 0), 3.5, Color(0.3, 0.55, 1.0))

func _info_id() -> String:
	if hover_list >= 0:
		return "" if Parts.is_locked(Parts.PARTS[_ids[hover_list]], main.unlocks()) else _ids[hover_list]
	var idx = _part_at(hover)
	if idx >= 0:
		return lo.parts[idx].id
	return selected

func _draw():
	Ui.begin()
	_draw_screen()
	Ui.scanlines(self, Rect2(Vector2.ZERO, size))
	Ui.end()

func _draw_screen():
	_style_name()
	if main == null:
		return
	var frame = Parts.frame_cells(lo.frame)
	var sz = Parts.frame_size(lo.frame)
	Ui.segment(self, Rect2(-30, 22, 380, 50), Ui.INK)
	Ui.segment(self, Rect2(-30, 68, 380, 4), Ui.HILITE, 0.0)
	Ui.text(self, Vector2(30, 58), "GARAGE", 30, Color.WHITE, true)
	_draw_info()
	var fr = _frame_rect()
	Ui.segment(self, fr, Ui.PAPER)
	Ui.text(self, fr.position + Vector2(0, 27), "‹   " + Parts.FRAMES[lo.frame].name.to_upper() + "   ›", 20, Ui.INK, true, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x)
	var cp = _cell_px()
	var o = _grid_origin()
	draw_rect(Rect2(o - Vector2(14, 14), Vector2(sz) * cp + Vector2(28, 28)), Color(0.03, 0.035, 0.045, 0.85))
	for y in sz.y:
		for x in sz.x:
			var c = Vector2i(x, y)
			draw_rect(_cell_rect(c).grow(-1), Ui.fill(Color(0.78, 0.8, 0.83)) if frame.has(c) else Color(1, 1, 1, 0.04))
			if frame.has(c) and Ui.terminal():
				draw_rect(_cell_rect(c).grow(-1), Ui.T_EDGE, false, 1.0)
	# Broken slots: scorched, cracked, and a wrench when you point at one.
	var broken = _broken()
	for c in broken:
		var r = _cell_rect(c).grow(-1)
		draw_rect(r, Color(0.2, 0.12, 0.1) if c != hover else Color(0.34, 0.18, 0.12))
		draw_line(r.position + r.size * Vector2(0.2, 0.15), r.position + r.size * Vector2(0.55, 0.5), Color(0.75, 0.3, 0.15), 2.0)
		draw_line(r.position + r.size * Vector2(0.55, 0.5), r.position + r.size * Vector2(0.4, 0.85), Color(0.75, 0.3, 0.15), 2.0)
		draw_line(r.position + r.size * Vector2(0.55, 0.5), r.position + r.size * Vector2(0.85, 0.6), Color(0.75, 0.3, 0.15), 2.0)
	# Where the selected part may go: green on every cell that works as its
	# anchor with the current rotation, a dim red wash on the rest.
	if selected != "":
		for c in frame:
			var ok = Parts.can_place(lo.frame, lo.parts, {"id": selected, "cell": c, "rot": rot}, -1, _broken())
			var r = _cell_rect(c).grow(-1)
			if ok:
				draw_rect(r, Color(0.35, 0.85, 0.4, 0.55))
			elif Parts.occupancy(lo.parts).get(c, -1) < 0:
				draw_rect(r, Color(0.8, 0.2, 0.15, 0.18))
	for p in lo.parts:
		if Parts.PARTS[p.id].has("exhaust"):
			var ex = Parts.exhaust_of(p)
			for c in Parts.cells_of(p):
				var r = _cell_rect(c + ex).grow(-4)
				for k in 4:
					var f = k / 4.0
					draw_line(r.position + Vector2(r.size.x * f, 0), r.position + Vector2(0, r.size.y * f), Color(1, 0.6, 0.2, 0.5), 1.5)
	for p in lo.parts:
		var col = _part_color(p)
		_draw_part(p, col, col.darkened(0.5))
	if inspected >= 0 and inspected < lo.parts.size():
		for c in Parts.cells_of(lo.parts[inspected]):
			draw_rect(_cell_rect(c).grow(-1), Color.WHITE, false, 3.0)
	var err = ""
	var over = _part_at(hover)
	if over >= 0:
		for c in Parts.cells_of(lo.parts[over]):
			draw_rect(_cell_rect(c).grow(-1), Color(0.3, 0.55, 1.0), false, 3.0)
	elif broken.has(hover):
		var free = main.save_data.get("repair_credits", 0)
		err = "click to repair:  " + ("free (%d left)" % free if free > 0 else main._price_text(main.repair_cost(lo.frame)))
	elif selected != "" and Rect2(Vector2.ZERO, Vector2(sz)).has_point(Vector2(hover)):
		var g = _ghost()
		err = Parts.placement_error(lo.frame, lo.parts, g, -1, _broken())
		var ok = err == ""
		_draw_part(g, Color(1, 1, 1, 0.5) if ok else Color(1, 0.2, 0.15, 0.45), Color.WHITE if ok else Color(1, 0.3, 0.2))
	_draw_status(err, over)
	for i in Parts.SECTIONS.size():
		var tr = _tab_rect(i)
		var on = Parts.SECTIONS[i] == section
		Ui.segment(self, tr, Ui.HILITE if on else Color(0.2, 0.22, 0.25, 0.95), 6.0)
		Ui.text(self, tr.position + Vector2(0, 18), Parts.SECTION_NAMES[Parts.SECTIONS[i]], 12, Color.WHITE if on else Color(0.7, 0.72, 0.76), true, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
	var lst = _list()
	for i in lst.size():
		var id = lst[i]
		var def = Parts.PARTS[id]
		var r = _list_rect(i)
		var sel = id == selected
		if Parts.is_locked(def, main.unlocks()):
			# Not found yet: a dark slab, a lock, no name.
			Ui.segment(self, r, Color(0.14, 0.15, 0.17, 0.95), 8.0)
			Ui.text(self, r.position + Vector2(14, 19), "? ? ?", 15, Color(0.4, 0.42, 0.46), true)
			var lc = Vector2(r.end.x - 60, r.position.y + 14)
			draw_rect(Rect2(lc - Vector2(6, 2), Vector2(12, 9)), Color(0.4, 0.42, 0.46))
			draw_arc(lc - Vector2(0, 3), 4, PI, TAU, 8, Color(0.4, 0.42, 0.46), 2.0)
			continue
		var free = _free(id)
		if free <= 0 and not sel:
			Ui.segment(self, r, Color(0.32, 0.34, 0.38, 0.95), 8.0)
		else:
			Ui.segment(self, r, Ui.HILITE if sel else (Color.WHITE if _ids.find(id) == hover_list else Ui.PAPER), 8.0)
		var cnt = "%d / %d" % [maxi(free, 0), main.owned().get(id, 0)]
		Ui.text(self, r.position + Vector2(0, 19), cnt, 13, Color.WHITE if sel else (Color(0.62, 0.64, 0.68) if free <= 0 else Ui.INK), true, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 86)
		draw_rect(Rect2(r.position.x + 2, r.position.y + 4, 4, r.size.y - 8), Parts.MECHANICS[def.mech].accent)
		Ui.text(self, r.position + Vector2(14, 19), def.name, 15, Color.WHITE if sel else Ui.INK, sel)
		var minc = Vector2i(99, 99)
		for sc in def.shape:
			minc = Vector2i(mini(minc.x, sc.x), mini(minc.y, sc.y))
		for sc in def.shape:
			var q = sc - minc
			draw_rect(Rect2(r.end.x - 70 + q.x * 6, r.position.y + 3 + q.y * 6, 5, 5), Color.WHITE if sel else Color(0.3, 0.32, 0.36))
	_draw_slots()
	_draw_repairs()
	var dr = _done_rect()
	Ui.segment(self, dr, Ui.HILITE, 10.0)
	Ui.text(self, dr.position + Vector2(0, 30), "DONE", 20, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, dr.size.x)
	Ui.text(self, dr.position + Vector2(0, 30), "ESC", 11, Color(0.75, 0.82, 1.0), true, HORIZONTAL_ALIGNMENT_RIGHT, dr.size.x - 14)
	var prs = _paint_rects()
	var paint = lo.paint
	var labels = ["HULL", "TRIM", paint.pattern.to_upper(), "GLOW"]
	var swatches = [paint.primary, paint.secondary, null, paint.get("glow", null)]
	for i in prs.size():
		Ui.segment(self, prs[i], Ui.PAPER, 8.0)
		Ui.text(self, prs[i].position + Vector2(12, 23), labels[i], 15, Ui.INK, true)
		if swatches[i] != null:
			draw_rect(Rect2(prs[i].end.x - 34, prs[i].position.y + 8, 18, 18), swatches[i])

# Rotation control + the one line that says what's wrong.
func _draw_status(err: String, over: int = -1) -> void:
	var rr = _rot_rects()
	for i in 2:
		Ui.segment(self, rr[i], Ui.PAPER, 8.0)
		var c = rr[i].get_center()
		draw_arc(c, 10, PI * 0.2, PI * 1.6, 12, Ui.ink(Ui.INK), 3.0)
		var tip = c + Vector2(cos(PI * (1.6 if i == 1 else 0.2)), sin(PI * (1.6 if i == 1 else 0.2))) * 10
		draw_circle(tip, 4, Ui.ink(Ui.INK))
	# Current facing, as an arrow between the buttons.
	var mid = Rect2(470, 716, 56, 40)
	Ui.segment(self, mid, Ui.INK, 8.0)
	var f = Vector2(Parts.rotate(Vector2i(0, -1), rot))
	var n = Vector2(-f.y, f.x)
	var cc = mid.get_center()
	draw_colored_polygon(PackedVector2Array([cc + f * 12, cc - f * 8 + n * 9, cc - f * 8 - n * 9]), Color.WHITE)
	Ui.text(self, Vector2(rr[1].end.x + 6, rr[1].position.y + 26), "R", 13, Ui.DIM, true)
	var sr = _status_rect()
	var st = main.ship.stats
	if err.begins_with("click to repair"):
		Ui.segment(self, sr, Color(0.95, 0.7, 0.2), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), err.to_upper(), 18, Ui.INK, true)
	elif selected != "" and _free(selected) <= 0 and over < 0:
		Ui.segment(self, sr, Color(0.8, 0.12, 0.1), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), "NONE LEFT  -  BUY MORE AT AN OUTPOST", 18, Color.WHITE, true)
	elif over >= 0 and Parts.sub_size(lo.parts[over].id) != Vector2i.ZERO:
		Ui.segment(self, sr, Ui.HILITE, 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), "CLICK TO WIRE " + Parts.PARTS[lo.parts[over].id].name.to_upper(), 18, Color.WHITE, true)
	elif err != "":
		Ui.segment(self, sr, Color(0.8, 0.12, 0.1), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), err.to_upper(), 18, Color.WHITE, true)
	elif not st.can_move:
		Ui.segment(self, sr, Color(0.8, 0.12, 0.1), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), "NO THRUST", 18, Color.WHITE, true)
	elif st.thrust_raw > st.power + 0.1:
		Ui.segment(self, sr, Color(0.95, 0.7, 0.2), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), "POWER LIMITED  %d / %d" % [st.power, st.thrust_raw], 18, Ui.INK, true)
	else:
		Ui.segment(self, sr, Color(0.03, 0.035, 0.045, 0.8), 8.0)

func _draw_info() -> void:
	PartInfo.draw(self, BAND, _info_id(), 166.0)

# Bottom left: what's in the bank, and what it buys in repairs on this frame.
func _draw_repairs() -> void:
	var bank = main.inventory
	var broken = _broken().size()
	var h = 74.0 + (96.0 if broken > 0 else 0.0)
	var r = Rect2(-20, size.y - h - 24.0, 390, h)
	Ui.segment(self, r, Color(0.03, 0.035, 0.045, 0.88), 10.0)
	Ui.segment(self, Rect2(r.position.x, r.end.y - 4, r.size.x, 4), Ui.HILITE, 0.0)
	var y = r.position.y + 32.0
	Ui.text(self, Vector2(30, y), "BANK", 14, Ui.DIM, true)
	var x = 92.0
	for m in MATS:
		draw_rect(Rect2(x, y - 12, 12, 12), m[1])
		Ui.text(self, Vector2(x + 17, y), str(bank.get(m[0], 0)), 18, Color.WHITE, true)
		x += 68.0
	if broken == 0:
		Ui.text(self, Vector2(30, y + 30), "NO BROKEN SLOTS", 14, Ui.DIM, true)
		return
	var free = main.save_data.get("repair_credits", 0)
	var cost = main.repair_cost(lo.frame)
	var can = main.repairs_affordable(lo.frame)
	y += 32.0
	Ui.text(self, Vector2(30, y), "BROKEN SLOTS", 14, Ui.DIM, true)
	Ui.text(self, Vector2(30, y), str(broken), 16, Color(1.0, 0.55, 0.35), true, HORIZONTAL_ALIGNMENT_RIGHT, 310)
	y += 26.0
	Ui.text(self, Vector2(30, y), "NEXT REPAIR", 14, Ui.DIM, true)
	var next = "FREE  (%d LEFT)" % free if free > 0 else main._price_text(cost).to_upper()
	var ok = free > 0 or main.can_afford(cost)
	Ui.text(self, Vector2(30, y), next, 16, Color(0.5, 1.0, 0.6) if ok else Color(1.0, 0.4, 0.3), true, HORIZONTAL_ALIGNMENT_RIGHT, 310)
	y += 26.0
	Ui.text(self, Vector2(30, y), "YOU CAN REPAIR", 14, Ui.DIM, true)
	Ui.text(self, Vector2(30, y), "%d / %d" % [can, broken], 16, Color.WHITE if can > 0 else Color(1.0, 0.4, 0.3), true, HORIZONTAL_ALIGNMENT_RIGHT, 310)

func _draw_slots() -> void:
	var slots = main.save_data.get("slots", [])
	var x = size.x - 400
	name_edit.position = Vector2(x, 626)
	name_edit.size = Vector2(360, 34)
	for i in Save.SLOTS:
		var r = _slot_rect(i)
		var lo_i = slots[i] if i < slots.size() else null
		var hot = i == hover_slot
		Ui.segment(self, r, (Color.WHITE if hot else Ui.PAPER) if lo_i != null else Color(0.2, 0.22, 0.25, 0.9), 8.0)
		Ui.text(self, r.position + Vector2(14, 22), str(i + 1), 15, Ui.DIM, true)
		if lo_i != null:
			Ui.text(self, r.position + Vector2(40, 22), str(lo_i.get("name", "")).to_upper(), 16, Ui.INK, true)
			Ui.text(self, r.position + Vector2(40, 22), Parts.FRAMES.get(lo_i.get("frame", ""), {"name": ""}).name, 13, Ui.DIM, false, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 56)
		else:
			Ui.text(self, r.position + Vector2(40, 22), "+ SAVE", 15, Color(0.6, 0.63, 0.68), true)

