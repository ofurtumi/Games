extends Control

# Grid ship builder. Left: parts. Top: what the hovered/selected part does,
# with a little demo of it working. Middle: the frame grid, with the cells
# the selected part can go on marked green, and under it the reason a
# placement doesn't work. The ship turns on the showroom floor to the right
# and rebuilds on every change. It's a tab of its hub (Main.hub): the tab
# strip runs along the top.
#
# Everything is select, then act: click a part in the list, a part on the
# ship, a broken slot or a saved build, and the action bar along the bottom
# (Bar.gd) lists what you can do with it: click a button, press its number,
# or Enter for the first. With a part from the list selected, clicking a
# free cell places it. Shortcuts: R rotates, right-click scraps a placed
# part, mouse wheel repaints it, a double click wires it, Delete scraps or
# clears, Q/E change frame, Esc drops the selection and then leaves.
# Shift+1-5 load the preset builds, Shift+0 a random one.

const Parts = preload("res://scripts/Parts.gd")
const Ui = preload("res://scripts/Ui.gd")
const Save = preload("res://scripts/Save.gd")
const PartDemo = preload("res://scripts/PartDemo.gd")
const SubGridEditorScript = preload("res://scripts/SubGridEditor.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const BAND = Rect2(390, 52, 780, 104)
const GRID = Rect2(410, 210, 540, 460)   # the frame grid sits in the middle of this
const PartInfo = preload("res://scripts/PartInfo.gd")
const Bar = preload("res://scripts/Bar.gd")
const MATS = preload("res://scripts/GtMenu.gd").MATS

var main
var lo = {}
var selected = ""       # a part from the list, ready to place
var rot = 0
var hover = Vector2i(-99, -99)
var t = 0.0
var _ids = []
var hover_list = -1
var hover_slot = -1
var name_edit: LineEdit
var section = "power"
var inspected = -1      # the placed part selected
var sel_slot = -1       # the saved build selected
var sel_broken = null   # the broken slot selected (Vector2i)
var carry = {}          # a placed part picked up to move: it goes back if you let go
var bar = Bar.new()
var hover_tab = ""
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
	carry = {}
	_deselect()
	t = 0.0
	visible = true
	name_edit.text = lo.name

# Shut the garage (Main's hub decides where you go next).
func close() -> void:
	if editor.visible:
		editor.close()
	_put_back()
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
	_fill_bar()
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
	return floorf(minf(48.0, GRID.size.y / maxf(sz.x, sz.y)))

func _grid_origin() -> Vector2:
	var sz = Parts.frame_size(lo.frame)
	var cp = _cell_px()
	return GRID.position + (GRID.size - Vector2(sz) * cp) * 0.5

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
	return Rect2(22 + i * 62, 58, 58, 26)

func _list_rect(i: int) -> Rect2:
	var appear = Ui.ease_out((t - i * 0.03) / 0.25)
	return Rect2(30 - (1.0 - appear) * 400.0, 96 + i * 30, 300, 26)

func _frame_rect() -> Rect2:
	return Rect2(430, 166, 500, 34)

# Which way a part from the list will face, then the one line that says
# what's wrong.
func _facing_rect() -> Rect2:
	return Rect2(430, 684, 48, 40)

func _status_rect() -> Rect2:
	return Rect2(492, 684, 468, 40)

func _paint_rects() -> Array:
	var y = 738.0
	return [Rect2(430, y, 120, 34), Rect2(565, y, 120, 34), Rect2(700, y, 120, 34), Rect2(835, y, 120, 34)]

func _slot_rect(i: int) -> Rect2:
	return Rect2(size.x - 400, 632 + i * 32, 360, 28)

# ---------------------------------------------------------------- selection

# One thing is selected at a time: a part from the list (to place), a placed
# part, a broken slot or a saved build.
func _deselect() -> void:
	_put_back()
	selected = ""
	inspected = -1
	sel_slot = -1
	sel_broken = null

# Let go of a part picked up to move: back where it was.
func _put_back() -> void:
	if carry.is_empty():
		return
	lo.parts.append(carry)
	carry = {}
	_commit()

func pick_part(id: String) -> void:
	_deselect()
	selected = id
	section = Parts.SECTION_OF.get(Parts.PARTS[id].kind, "utility")

func pick_placed(idx: int) -> void:
	_deselect()
	inspected = idx if idx >= 0 and idx < lo.parts.size() else -1

func _slots() -> Array:
	var slots = main.save_data.get("slots", [])
	slots.resize(Save.SLOTS)
	return slots

# What the action bar offers for the selection.
func _fill_bar() -> void:
	var acts = []
	var title = ""
	var hint = ""
	var back = {"label": "DESELECT", "action": _deselect}
	if selected != "":
		var id = selected
		title = "%s  %d / %d" % [Parts.PARTS[id].name.to_upper(), maxi(_free(id), 0), main.owned().get(id, 0)]
		acts.append({"label": "ROTATE (R)", "action": func(): rot = (rot + 1) % 4})
		if carry.is_empty():
			acts.append_array(_trade_actions(id))
			back.label = "PUT DOWN"
			hint = "CLICK A GREEN CELL TO PLACE IT" if _free(id) > 0 else "NONE SPARE"
		else:
			back.label = "PUT BACK"
			hint = "CLICK A GREEN CELL TO MOVE IT THERE"
	elif inspected >= 0 and inspected < lo.parts.size():
		var idx = inspected
		title = Parts.PARTS[lo.parts[idx].id].name.to_upper()
		if Parts.sub_size(lo.parts[idx].id) != Vector2i.ZERO:
			acts.append({"label": "WIRE", "action": func(): editor.open(self, idx)})
		acts.append({"label": "MOVE", "action": func(): _pick_up(idx)})
		acts.append({"label": "TURN (R)", "action": func(): _turn(idx)})
		acts.append({"label": "REPAINT", "action": func(): _repaint(idx, 1)})
		acts.append({"label": "SCRAP (DEL)", "action": func(): _scrap(idx)})
	elif sel_broken != null and _broken().has(sel_broken):
		var free = main.save_data.get("repair_credits", 0)
		var cost = main.repair_cost(lo.frame)
		title = "BROKEN SLOT"
		acts.append({"label": "REPAIR  ·  " + ("FREE (%d LEFT)" % free if free > 0 else main._price_text(cost).to_upper()),
			"can": free > 0 or main.can_afford(cost), "action": _repair})
		hint = "%d BROKEN" % _broken().size()
	elif sel_slot >= 0:
		var i = sel_slot
		var saved = _slots()[i]
		if saved != null:
			title = "BUILD %d  %s" % [i + 1, str(saved.get("name", "")).to_upper()]
			acts.append({"label": "LOAD", "action": func(): _try_load(Save.clean_loadout(_slots()[i]))})
			acts.append({"label": "OVERWRITE", "action": func(): _save_slot(i)})
			acts.append({"label": "CLEAR (DEL)", "action": func(): _clear_slot(i)})
		else:
			title = "BUILD %d  EMPTY" % (i + 1)
			acts.append({"label": "SAVE THIS BUILD HERE", "action": func(): _save_slot(i)})
	else:
		hint = "SELECT A PART IN THE LIST OR ON YOUR SHIP, A BROKEN SLOT, OR A SAVED BUILD"
		back = {"label": main.hub_back_label(), "action": main.hub_back}
	bar.fill(title, acts, back, hint)

# Buy / order / sell for a part from the list.
func _trade_actions(id: String) -> Array:
	var out = []
	var pr = Parts.credit_price(id)
	if main.sold_here(id):
		out.append({"label": "BUY 1  ·  " + main._price_text(pr).to_upper(), "can": func(): return main.can_afford(pr),
			"action": func(): main.buy_part(id)})
	elif main.can_order(id):
		out.append({"label": "ORDER BY COURIER", "action": func(): main.open_order(id)})
	else:
		out.append({"label": "NOT SOLD HERE", "can": false,
			"action": func(): main.notify(main.where_sold(id), Color(1.0, 0.82, 0.25), "shop")})
	if _free(id) > 0:
		out.append({"label": "SELL 1  ·  +" + main._price_text(main.MiningScript.sell_price(id)).to_upper(),
			"action": func(): main.sell_part(id)})
	return out

func _pick_up(idx: int) -> void:
	var p = lo.parts[idx]
	lo.parts.remove_at(idx)
	pick_part(p.id)
	carry = p
	rot = p.get("rot", 0)
	Sfx.play("clunk", -4.0, 1.3)
	_commit()

# Turn a placed part where it sits, to the next way round that fits.
func _turn(idx: int) -> void:
	var p = lo.parts[idx]
	for k in range(1, 4):
		var q = p.duplicate(true)
		q.rot = (p.get("rot", 0) + k) % 4
		if Parts.can_place(lo.frame, lo.parts, q, idx, _broken()):
			lo.parts[idx] = q
			Sfx.play("clunk", -4.0, 1.3)
			_commit()
			return
	main.notify("NO ROOM TO TURN IT THERE", Color(1.0, 0.4, 0.3), "garage")

func _repaint(idx: int, dir: int) -> void:
	var col = _next_color(lo.parts[idx].get("color", null), dir, true)
	if col == null:
		lo.parts[idx].erase("color")
	else:
		lo.parts[idx].color = col
	_commit()

func _scrap(idx: int) -> void:
	lo.parts.remove_at(idx)
	inspected = -1
	Sfx.play("scrap")
	_commit()

# Repair the selected slot and move on to the nearest one still broken, so
# Enter (or the button) works down the lot.
func _repair() -> void:
	var c = sel_broken
	if not main.repair_slot(lo.frame, c):
		return
	sel_broken = null
	for b in _broken():
		if sel_broken == null or (b - c).length_squared() < (sel_broken - c).length_squared():
			sel_broken = b

func _save_slot(i: int) -> void:
	var slots = _slots()
	slots[i] = lo.duplicate(true)
	main.save_data.slots = slots
	main.save_game()
	Sfx.play("clunk")
	main.notify("SAVED  " + lo.name.to_upper(), Color.WHITE, "garage")

func _clear_slot(i: int) -> void:
	var slots = _slots()
	slots[i] = null
	main.save_data.slots = slots
	main.save_game()
	Sfx.play("scrap")

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
	carry = {}
	_deselect()
	lo = other.duplicate(true)
	name_edit.text = lo.name
	main.equip(lo.duplicate(true), false)
	main.notify("LOADED  " + lo.name.to_upper(), Color.WHITE, "garage")

func _broken() -> Dictionary:
	return main.broken_cells(lo.frame)

func _part_at(c: Vector2i) -> int:
	return Parts.occupancy(lo.parts).get(c, -1)

# The part that would go down under the cursor (a moved part keeps its
# wiring and paint).
func _ghost() -> Dictionary:
	if not carry.is_empty():
		var g = carry.duplicate(true)
		g.cell = hover
		g.rot = rot
		return g
	return {"id": selected, "cell": hover, "rot": rot}

func _gui_input(event):
	if event is InputEventMouseMotion:
		hover = _cell_at(event.position)
		bar.motion(size, event.position)
		hover_tab = Bar.tab_at(main.hub_tabs(), event.position)
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
		accept_event()
		if left:
			name_edit.release_focus()
			var tab = Bar.tab_at(main.hub_tabs(), pos)
			if tab != "":
				Sfx.play("ui_move")
				main.hub_show(tab)
				return
			if bar.click(size, pos):
				return
		if left or right:
			var prs = _paint_rects()
			for i in prs.size():
				if prs[i].has_point(pos):
					_paint(i, 1 if left else -1)
					return
			if _frame_rect().has_point(pos):
				_cycle_frame(-1 if pos.x < _frame_rect().get_center().x else 1)
				return
		if left:
			for i in Save.SLOTS:
				if _slot_rect(i).has_point(pos):
					_deselect()
					sel_slot = i
					Sfx.play("ui_move", -6.0)
					return
			for i in Parts.SECTIONS.size():
				if _tab_rect(i).has_point(pos):
					section = Parts.SECTIONS[i]
					t = 0.0
					return
			var lst = _list()
			for i in lst.size():
				if _list_rect(i).has_point(pos):
					# Select it, spare or not: the bar says how to get one.
					if not Parts.is_locked(Parts.PARTS[lst[i]], main.unlocks()) and selected != lst[i]:
						pick_part(lst[i])
						Sfx.play("ui_move", -6.0)
					return
			var at = _part_at(c)
			if at >= 0:
				pick_placed(_part_at(c))
				Sfx.play("ui_move", -6.0)
				if event.double_click and Parts.sub_size(lo.parts[inspected].id) != Vector2i.ZERO:
					editor.open(self, inspected)
			elif _broken().has(c):
				_deselect()
				sel_broken = c
				Sfx.play("ui_move", -6.0)
			elif selected != "" and Parts.frame_cells(lo.frame).has(c):
				var g = _ghost()
				if Parts.can_place(lo.frame, lo.parts, g, -1, _broken()) and _free(selected) > 0:
					lo.parts.append(g)
					Sfx.play("clunk")
					if not carry.is_empty():
						# Moved: it's the selection again, where it now sits.
						carry = {}
						selected = ""
						inspected = lo.parts.size() - 1
					_commit()
			else:
				_deselect()
		elif right:
			# Scrap whatever is under the cursor; the selection stays put.
			var idx = _part_at(c)
			if idx >= 0:
				var keep = inspected
				_scrap(idx)
				inspected = keep - 1 if keep > idx else (keep if keep < idx else -1)
			else:
				_deselect()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var idx = _part_at(c)
			if idx >= 0:
				_repaint(idx, 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)

func _unhandled_key_input(event):
	if not visible or not event.pressed or event.echo or editor.visible or main.menu.visible:
		return
	if bar.key(event):
		get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_TAB:
			Sfx.play("ui_move")
			main.hub_step(-1 if event.shift_pressed else 1)
		KEY_R:
			if inspected >= 0 and inspected < lo.parts.size():
				_turn(inspected)
			else:
				rot = (rot + (3 if event.shift_pressed else 1)) % 4
		KEY_Q:
			_cycle_frame(-1)
		KEY_E:
			_cycle_frame(1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_try_load(Parts.presets()[event.physical_keycode - KEY_1])
		KEY_0:
			if event.shift_pressed:
				_try_load(Parts.random_loadout(main.rng, main.unlocks()))
		KEY_DELETE, KEY_BACKSPACE:
			if inspected >= 0 and inspected < lo.parts.size():
				_scrap(inspected)
			elif sel_slot >= 0 and _slots()[sel_slot] != null:
				_clear_slot(sel_slot)
		KEY_ESCAPE:
			if selected != "" or inspected >= 0 or sel_slot >= 0 or sel_broken != null:
				_deselect()
			else:
				Sfx.play("ui_back")
				main.hub_back()
		KEY_G:
			main.hub_back()
		_:
			return
	get_viewport().set_input_as_handled()

func _cycle_frame(dir: int) -> void:
	_put_back()
	var keys = Parts.FRAMES.keys().filter(func(f): return not Parts.FRAMES[f].get("hidden", false) and not Parts.is_locked(Parts.FRAMES[f], main.unlocks()))
	lo.frame = keys[(keys.find(lo.frame) + dir + keys.size()) % keys.size()]
	var kept = []
	for p in lo.parts:
		if Parts.can_place(lo.frame, kept, p, -1, _broken()):
			kept.append(p)
	lo.parts = kept
	inspected = -1
	sel_broken = null
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
	if selected == "" and inspected >= 0 and inspected < lo.parts.size():
		return lo.parts[inspected].id
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
	_draw_info()
	var fr = _frame_rect()
	Ui.segment(self, fr, Ui.PAPER)
	Ui.text(self, fr.position + Vector2(0, 24), "‹   " + Parts.FRAMES[lo.frame].name.to_upper() + "   ›", 20, Ui.INK, true, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x)
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
		draw_rect(r, Color(0.2, 0.12, 0.1) if c != hover and c != sel_broken else Color(0.34, 0.18, 0.12))
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
	if sel_broken != null and broken.has(sel_broken):
		draw_rect(_cell_rect(sel_broken).grow(-1), Color(0.95, 0.7, 0.2), false, 3.0)
	var err = ""
	var over = _part_at(hover)
	if over >= 0:
		for c in Parts.cells_of(lo.parts[over]):
			draw_rect(_cell_rect(c).grow(-1), Color(0.3, 0.55, 1.0), false, 3.0)
	elif broken.has(hover):
		var free = main.save_data.get("repair_credits", 0)
		err = "broken slot  -  repair:  " + ("free (%d left)" % free if free > 0 else main._price_text(main.repair_cost(lo.frame)))
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
	var prs = _paint_rects()
	var paint = lo.paint
	var labels = ["HULL", "TRIM", paint.pattern.to_upper(), "GLOW"]
	var swatches = [paint.primary, paint.secondary, null, paint.get("glow", null)]
	for i in prs.size():
		Ui.segment(self, prs[i], Ui.PAPER, 8.0)
		Ui.text(self, prs[i].position + Vector2(12, 23), labels[i], 15, Ui.INK, true)
		if swatches[i] != null:
			draw_rect(Rect2(prs[i].end.x - 34, prs[i].position.y + 8, 18, 18), swatches[i])
	Bar.draw_tabs(self, size, main.hub_tabs(), main.hub_tab, hover_tab)
	bar.draw(self, size)

# Which way the part will face + the one line that says what's wrong.
func _draw_status(err: String, over: int = -1) -> void:
	var mid = _facing_rect()
	Ui.segment(self, mid, Ui.INK, 8.0)
	var f = Vector2(Parts.rotate(Vector2i(0, -1), rot))
	var n = Vector2(-f.y, f.x)
	var cc = mid.get_center()
	draw_colored_polygon(PackedVector2Array([cc + f * 12, cc - f * 8 + n * 9, cc - f * 8 - n * 9]), Ui.ink(Color.WHITE) if selected != "" else Ui.ink(Ui.DIM))
	var sr = _status_rect()
	var st = main.ship.stats
	if err.begins_with("broken slot  -  repair"):
		Ui.segment(self, sr, Color(0.95, 0.7, 0.2), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), err.to_upper(), 18, Ui.INK, true)
	elif selected != "" and _free(selected) <= 0 and over < 0:
		Ui.segment(self, sr, Color(0.8, 0.12, 0.1), 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), "NONE SPARE  -  SEE THE ACTIONS BELOW", 18, Color.WHITE, true)
	elif over >= 0 and over != inspected:
		Ui.segment(self, sr, Ui.HILITE, 8.0)
		Ui.text(self, sr.position + Vector2(18, 27), "CLICK TO SELECT " + Parts.PARTS[lo.parts[over].id].name.to_upper(), 18, Color.WHITE, true)
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
	var r = Rect2(-20, size.y - h - Bar.RESERVED - 6.0, 390, h)
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
	Ui.text(self, Vector2(x + 4, 584), "THIS BUILD", 12, Ui.DIM, true)
	Ui.text(self, Vector2(x + 4, 584), "SAVED BUILDS BELOW", 12, Ui.DIM, true, HORIZONTAL_ALIGNMENT_RIGHT, 352)
	name_edit.position = Vector2(x, 592)
	name_edit.size = Vector2(360, 32)
	for i in Save.SLOTS:
		var r = _slot_rect(i)
		var lo_i = slots[i] if i < slots.size() else null
		var on = i == sel_slot
		var hot = i == hover_slot
		Ui.segment(self, r, Ui.HILITE if on else ((Color.WHITE if hot else Ui.PAPER) if lo_i != null else Color(0.2, 0.22, 0.25, 0.9)), 8.0)
		if hot and not on:
			draw_rect(Rect2(r.position.x, r.position.y, 4, r.size.y), Ui.ink(Color.WHITE) if Ui.terminal() else Ui.HILITE)
		Ui.text(self, r.position + Vector2(14, 20), str(i + 1), 15, Color.WHITE if on else Ui.DIM, true)
		if lo_i != null:
			Ui.text(self, r.position + Vector2(40, 20), str(lo_i.get("name", "")).to_upper(), 16, Color.WHITE if on else Ui.INK, true)
			Ui.text(self, r.position + Vector2(40, 20), Parts.FRAMES.get(lo_i.get("frame", ""), {"name": ""}).name, 13, Color.WHITE if on else Ui.DIM, false, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 56)
		else:
			Ui.text(self, r.position + Vector2(40, 20), "EMPTY", 15, Color.WHITE if on else Color(0.6, 0.63, 0.68), true)
