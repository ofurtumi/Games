extends Control

# Row menu in the GT4 manner: the game behind greys out, a title band and
# then each row slides in from the left, one after the other. Up/down picks,
# left/right changes a row's value, Enter confirms, Esc goes back.
#
# show_menu(title, rows, on_back). Row: {label, value (String or Callable),
# action (Callable), left/right (Callable), alt_left/alt_right (Callable,
# with Shift), swatch (Color or Callable), part (a part id: its card shows
# along the bottom while the row is selected), note ({title, text}: a card
# for something that isn't a part), can (bool or Callable: in shops, lit with
# a green edge when you can afford it, greyed out when you can't), actions
# (Array or Callable: see below), hint (a word on the action bar), verb (what
# the bar calls a plain row's action)}. Every menu gets a line under its
# title saying what it's for (BLURBS, by title; set `blurb` to override).
#
# Two kinds of row. A command (action) is a button: pointing at it selects
# it, clicking does it. An item (actions: [{label, can, action}], a part in
# a shop) is something you select with a click; what you can do with it is on
# the action bar along the bottom (Bar.gd), Enter does the first. The bar
# also carries the way back. Long lists scroll. In a hub (Main.hub: an
# outpost, the pit) the tab strip runs along the top: click, or Tab.

const Ui = preload("res://scripts/Ui.gd")
const BACKDROP = preload("res://assets/shaders/menu_backdrop.gdshader")
const Sfx = preload("res://scripts/Sfx.gd")
const PartInfo = preload("res://scripts/PartInfo.gd")
const ShopOverview = preload("res://scripts/ShopOverview.gd")
const StationCRT = preload("res://scripts/StationCRT.gd")
const Bar = preload("res://scripts/Bar.gd")

const ROW_H = 40.0
const ROW_GAP = 6.0
const ROW_W = 520.0
const STAGGER = 0.045
const SLIDE = 0.28

var title = ""
var rows = []
var selected = 0
var on_back: Callable
var t = 0.0
var closing = false
var origin = Vector2(70, 150)
var backdrop: ColorRect
var dim_backdrop = true
var capture: Callable   # when set, the next key press goes here (rebinding)
var wallet: Callable    # shops set this: returns {hold: {...}, bank: {...}}; cleared by show_menu
var blurb = "":         # the line(s) under the title; show_menu picks it from BLURBS
	set(v):
		blurb = v
		_blurb_lines = _wrap(v, ROW_W + 120.0)
var _blurb_lines = []
var overview: Callable   # shops set this: returns ShopOverview data; cleared by show_menu
var overview_mode = "ship"
var crt = {}             # set (after show_menu) to draw this menu as a station's CRT terminal
var main                 # set by Main: the hub's tabs come from it
var bar = Bar.new()
var back_label = ""      # what the bar calls the way back ("BACK"); cleared by show_menu
var scroll = 0           # first row shown
var hover_row = -1
var hover_tab = ""
var _items = false       # the list has items: click selects, the bar acts
var _follow = false      # bring the selected row into view

const BLURB_SIZE = 15
const BLURB_LINE = 20.0

static func _wrap(s: String, width: float) -> Array:
	var out = []
	if s == "":
		return out
	var line = ""
	for word in s.split(" "):
		var trial = word if line == "" else line + " " + word
		if Ui.font(false).get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, BLURB_SIZE).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = trial
	out.append(line)
	return out

# Rows sit lower when the description takes more than one line.
func _rows_top() -> float:
	return origin.y + maxf(0.0, _blurb_lines.size() - 1) * BLURB_LINE + (6.0 if _blurb_lines.size() > 0 else 0.0)

# What each menu is for, by title: [match, how ("is", "starts", "ends"), text].
const BLURBS = [
	["PAUSE", "is", "The race is held while you're here."],
	["PIT SHOP", "is", "Stock parts for your ship, paid in credits. Mechanics' specials are only sold at outposts. Spares sell back for half."],
	["ORDER", "starts", "Not sold here. A courier can bring one from an outpost you've been to, for a fee (couriers do get jumped)."],
	["CARDS", "is", "Program cards to wire into your components' sub-grids (select a placed part in the garage, then Wire). Each placed card uses a copy; take it out and it's free again."],
	["MARKET", "is", "Sell materials from your bank for credits. Docking unloads your hold into the bank."],
	["SETTINGS", "is", "Left and right change a setting."],
	["TOW HOME?", "is", "A tow to the last outpost. Everything in your hold is left behind."],
	["PICKUPS", "is", "What goes in your hold. Switch a material off when you have enough of it: drilled rock is dropped, ore is left floating."],
	["CONTROLS", "is", "Pick an action, then press the key you want for it."],
	["RESET SAVE?", "is", "Starts a fresh career. A copy of this save is kept next to it."],
	["ABANDON?", "is", "Drops the contract. Nothing you've done on it is paid."],
	["EXPEDITION", "is", "Paused out in space."],
	["NINE FINGERS", "starts", "A black market. Parts you won't find at the outposts. Spares sell back for half."],
	["CONTRACTS", "ends", "Jobs from this planet. Do them anywhere, three at a time; pick an active one to abandon it."],
	["OUTPOST", "ends", "Docked: your hold is unloaded into the bank, and fuel and shield are topped up."],
	["SHOP", "ends", "Parts for your ship: stock parts plus this outpost's mechanics' own. They go to your garage. Spares sell back for half."],
	["TRADER", "starts", "A travelling trader: swap materials, refuel, or buy the part they're carrying, cheap."],
	["RESULTS", "starts", "Where everyone finished, and what you won."],
	["PRACTICE", "starts", "This run against the track's medal times."],
]

static func blurb_for(menu_title: String) -> String:
	for b in BLURBS:
		var hit = menu_title == b[0] if b[1] == "is" else (menu_title.begins_with(b[0]) if b[1] == "starts" else menu_title.ends_with(b[0]))
		if hit:
			return b[2]
	return ""

const MATS = [["rock", Color(0.7, 0.6, 0.5)], ["metal", Color(1.0, 0.6, 0.25)], ["crystal", Color(0.5, 0.9, 1.0)], ["core", Color(1.0, 0.35, 0.85)]]

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m = ShaderMaterial.new()
	m.shader = BACKDROP
	backdrop.material = m
	add_child(backdrop)
	backdrop.show_behind_parent = true
	visible = false

func show_menu(menu_title: String, menu_rows: Array, back: Callable, keep_selection: bool = false) -> void:
	var animate = not visible or menu_title != title
	title = menu_title
	rows = menu_rows
	wallet = Callable()
	overview = Callable()
	crt = {}
	back_label = ""
	blurb = blurb_for(menu_title)
	on_back = back
	if not keep_selection:
		selected = 0
		scroll = 0
	selected = clampi(selected, 0, maxi(rows.size() - 1, 0))
	_items = rows.any(func(r): return r.has("actions"))
	_follow = true
	hover_row = -1
	if animate:
		t = 0.0
	closing = false
	visible = true
	_fill_bar()
	queue_redraw()

func hide_menu() -> void:
	visible = false

func _process(delta):
	if not visible:
		return
	t += delta
	backdrop.visible = dim_backdrop
	backdrop.material.set_shader_parameter("amount", Ui.ease_out(t / 0.25) * 0.85)
	var most = maxi(rows.size() - _shown(), 0)
	if _follow and size.y > 0.0:
		_follow = false
		scroll = clampi(scroll, selected - _shown() + 1, selected)
	scroll = clampi(scroll, 0, most)
	_fill_bar()
	queue_redraw()

func _val(v):
	return v.call() if v is Callable else v

func _tabs() -> Array:
	return main.hub_tabs() if main != null else []

# How many rows fit between the title and the action bar.
func _shown() -> int:
	if not crt.is_empty():
		return rows.size()
	return maxi(1, int((size.y - Bar.RESERVED - 6.0 - _rows_top() + ROW_GAP) / (ROW_H + ROW_GAP)))

func _row_rect(i: int) -> Rect2:
	if not crt.is_empty():
		return StationCRT.row_rect(size, i)
	return _gt_row_rect(i)

func _gt_row_rect(i: int) -> Rect2:
	var k = i - scroll
	var appear = Ui.ease_out((t - 0.12 - k * STAGGER) / SLIDE)
	var x = origin.x - (1.0 - appear) * (ROW_W + origin.x + 60.0)
	var w = ROW_W + (24.0 if i == selected else 0.0)
	return Rect2(x, _rows_top() + k * (ROW_H + ROW_GAP), w, ROW_H)

# The row under `pos` (-1: none), among the ones on screen.
func _row_at(pos: Vector2) -> int:
	for i in range(scroll, mini(rows.size(), scroll + _shown())):
		if _row_rect(i).grow(3).has_point(pos):
			return i
	return -1

# Right column (shops): the part card, then the overview panel under it.
func _side_w() -> float:
	return minf(size.x - ROW_W - origin.x - 70.0, 900.0)

func _overview_rect() -> Rect2:
	var top = origin.y + 160.0
	return Rect2(size.x - _side_w(), top, _side_w() + 20.0, minf(size.y - top - Bar.RESERVED - 10.0, 440.0))

# What the action bar says for the selected row.
func _fill_bar() -> void:
	var r = rows[selected] if selected < rows.size() else {}
	var acts = []
	if r.has("actions"):
		acts = _val(r.actions)
	elif r.has("left") and r.has("right"):
		acts = [{"label": "‹  PREV", "action": r.left}, {"label": "NEXT  ›", "action": r.right}]
	elif r.has("action"):
		acts = [{"label": r.get("verb", "SELECT"), "action": r.action}]
	var back = {}
	if on_back.is_valid():
		var in_hub = main != null and main.hub != "" and on_back == main.hub_back
		back = {"label": back_label if back_label != "" else (main.hub_back_label() if in_hub else "BACK"), "action": on_back}
	bar.fill(str(r.get("label", "")).to_upper(), acts, back, r.get("hint", ""))

func _draw():
	Ui.begin()
	if Ui.terminal() and dim_backdrop and crt.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.T_BG, 0.82))
	_draw_screen()
	Bar.draw_tabs(self, size, _tabs(), main.hub_tab if main != null else "", hover_tab)
	bar.draw(self, size)
	Ui.scanlines(self, Rect2(Vector2.ZERO, size))
	Ui.end()

func _draw_screen():
	if not crt.is_empty():
		StationCRT.draw(self, size, crt, rows, selected, t, _val)
		return
	var ta = Ui.ease_out(t / SLIDE)
	if title != "":
		var tr = Rect2(-40 + (ta - 1.0) * 700.0, origin.y - 92, ROW_W + 160, 58)
		Ui.segment(self, tr, Ui.INK)
		Ui.segment(self, Rect2(tr.position.x, tr.end.y - 4, tr.size.x, 4), Ui.HILITE, 0)
		Ui.text(self, Vector2(origin.x, tr.position.y + 42), title, 34, Color.WHITE, true)
		for li in _blurb_lines.size():
			Ui.text(self, Vector2(origin.x + (ta - 1.0) * 700.0, origin.y - 10 + li * BLURB_LINE), _blurb_lines[li], BLURB_SIZE, Color(0.82, 0.85, 0.9), false)
	var last = mini(rows.size(), scroll + _shown())
	for i in range(scroll, last):
		var r = rows[i]
		var rr = _row_rect(i)
		var sel = i == selected
		Ui.segment(self, Rect2(rr.position + Vector2(4, 4), rr.size), Color(0, 0, 0, 0.35))
		var can = _val(r.get("can", null))
		var fill = Ui.HILITE if sel else Ui.PAPER
		var ink = Color.WHITE if sel else Ui.INK
		if can == false:
			fill = Color(0.3, 0.36, 0.5) if sel else Color(0.52, 0.54, 0.58)
			ink = Color(0.85, 0.87, 0.9) if sel else Color(0.3, 0.32, 0.36)
		Ui.segment(self, rr, fill)
		if i == hover_row and not sel:
			# Pointed at, not selected (item lists): an edge.
			draw_rect(Rect2(rr.position.x, rr.position.y, 4, rr.size.y), Ui.ink(Color.WHITE) if Ui.terminal() else Ui.HILITE)
		if can == true:
			Ui.segment(self, Rect2(rr.position.x + 6, rr.position.y + 6, 6, rr.size.y - 12), Color(0.35, 0.95, 0.45), 2.0)
		Ui.text(self, rr.position + Vector2(18, 27), r.label, 20, ink, sel)
		var value = _val(r.get("value", ""))
		if value != "":
			var shown = value
			if sel and (r.has("left") or r.has("right")):
				shown = "‹  %s  ›" % value
			Ui.text(self, Vector2(rr.position.x + 170, rr.position.y + 27), shown, 18, ink if sel else Color(0.25, 0.27, 0.3), false, HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 190)
		var sw = _val(r.get("swatch", null))
		if sw != null:
			var sq = Rect2(rr.end.x - 46, rr.position.y + 10, 20, 20)
			if value != "":
				sq.position.x = rr.position.x + 150 - 4
			draw_rect(sq, sw)
			draw_rect(sq, ink, false, 1.5)
	# More rows than fit: a scroll rail beside the list.
	if rows.size() > _shown():
		var top = _rows_top()
		var h = _shown() * (ROW_H + ROW_GAP) - ROW_GAP
		var x = origin.x - 30.0 + (ta - 1.0) * 700.0
		draw_rect(Rect2(x, top, 5, h), Color(1, 1, 1, 0.1))
		var k = h / rows.size()
		draw_rect(Rect2(x, top + scroll * k, 5, _shown() * k), Ui.ink(Color.WHITE))
	if wallet.is_valid():
		_draw_wallet(wallet.call(), ta)
	if overview.is_valid():
		var data = overview.call()
		data.selected = rows[selected].get("part", "") if selected < rows.size() else ""
		var orect = _overview_rect()
		orect.position.x += (1.0 - ta) * 1000.0
		ShopOverview.draw(self, orect, data, overview_mode)
	if selected < rows.size() and rows[selected].has("note") and not rows[selected].has("part"):
		var band2 = Rect2(size.x - _side_w() + (1.0 - ta) * 1000.0, origin.y + 40.0, _side_w() + 20.0, 84)
		var nt = rows[selected].note
		Ui.segment(self, band2, Color(0.03, 0.035, 0.045, 0.9), 10.0)
		Ui.segment(self, Rect2(band2.position, Vector2(band2.size.x, 4)), Ui.HILITE, 0.0)
		Ui.text(self, band2.position + Vector2(36, 32), nt.title.to_upper(), 22, Color.WHITE, true)
		Ui.text(self, band2.position + Vector2(36, 60), nt.text, 15, Color(0.85, 0.87, 0.9))
	if selected < rows.size() and rows[selected].has("part"):
		# Right side, under the wallet, clear of the rows however long the list.
		var band = Rect2(size.x - _side_w() + (1.0 - ta) * 1000.0, origin.y + 40.0, _side_w() + 20.0, 104)
		PartInfo.draw(self, band, rows[selected].part, 36.0)

# What you can spend, top right: hold and bank, a chip and a count per ore.
func _draw_wallet(w: Dictionary, ta: float) -> void:
	var x0 = size.x - 470 + (1.0 - ta) * 500.0
	var parts = [["HOLD", w.get("hold")], ["BANK", w.get("bank")]].filter(func(p): return p[1] != null)
	var cr = w.get("bank", {}).get("credits", 0)
	var h = 20 + parts.size() * 36 + 36
	# Above the part card, and under the tab strip when there is one.
	var y = maxf(origin.y + 30 - h, Bar.TABS_H + 4.0 if not _tabs().is_empty() else 0.0)
	Ui.segment(self, Rect2(x0, y, 520, h), Ui.INK)
	Ui.segment(self, Rect2(x0, y + h - 4, 520, 4), Ui.HILITE, 0)
	var line = 0
	for part in parts:
		var ly = y + 34 + line * 36
		Ui.text(self, Vector2(x0 + 30, ly), part[0], 16, Ui.DIM, true)
		var cx = x0 + 100
		for m in MATS:
			draw_rect(Rect2(cx, ly - 13, 12, 12), m[1])
			Ui.text(self, Vector2(cx + 18, ly), str(part[1].get(m[0], 0)), 20, Color.WHITE, true)
			cx += 82
		line += 1
	var cy = y + 34 + line * 36
	Ui.text(self, Vector2(x0 + 30, cy), "CREDITS", 16, Ui.DIM, true)
	Ui.text(self, Vector2(x0 + 118, cy), "%d cr" % cr, 22, Color(1.0, 0.82, 0.25), true)

# Enter, or a click on a command row: do the row's thing (for an item, the
# first action on the bar).
func _activate(i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var r = rows[i]
	if r.has("actions"):
		_fill_bar()
		if bar.primary() >= 0:
			bar.run(bar.primary())
	elif r.has("action"):
		Sfx.play("ui_select")
		r.action.call()
	elif r.has("right"):
		_step(1, false)

func _step(dir: int, alt: bool) -> void:
	if rows.is_empty():
		return
	var r = rows[selected]
	var key = ("alt_" if alt else "") + ("left" if dir < 0 else "right")
	if r.has(key):
		Sfx.play("ui_move")
		r[key].call()

func _toggle_overview() -> void:
	overview_mode = "parts" if overview_mode == "ship" else "ship"
	Sfx.play("ui_move")

func _gui_input(event):
	if capture.is_valid() and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var cb = capture
		capture = Callable()
		cb.call(1000 + event.button_index)
		accept_event()
		return
	if event is InputEventMouseMotion:
		bar.motion(size, event.position)
		hover_tab = Bar.tab_at(_tabs(), event.position)
		hover_row = _row_at(event.position)
		# Commands follow the pointer; items wait for a click.
		if hover_row >= 0 and not _items and selected != hover_row:
			Sfx.play("ui_move", -6.0)
			selected = hover_row
	elif event is InputEventMouseButton and event.pressed:
		var pos = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			var tab = Bar.tab_at(_tabs(), pos)
			if tab != "":
				Sfx.play("ui_move")
				main.hub_show(tab)
			elif bar.click(size, pos):
				pass
			elif overview.is_valid() and ShopOverview.tab_at(_overview_rect(), pos) != "":
				overview_mode = ShopOverview.tab_at(_overview_rect(), pos)
				Sfx.play("ui_move")
			else:
				var i = _row_at(pos)
				if i >= 0:
					var was = selected
					selected = i
					if rows[i].has("actions"):
						if event.double_click:
							_activate(i)
						elif was != i:
							Sfx.play("ui_move", -6.0)
					else:
						_activate(i)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if on_back.is_valid():
				Sfx.play("ui_back")
				on_back.call()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up = event.button_index == MOUSE_BUTTON_WHEEL_UP
			var i = _row_at(pos)
			if i >= 0 and (rows[i].has("left") or rows[i].has("right")):
				selected = i
				_step(1 if up else -1, event.shift_pressed)
			else:
				scroll += -1 if up else 1
		accept_event()

func _unhandled_key_input(event):
	if not visible or not event.pressed:
		return
	if capture.is_valid():
		if not event.echo:
			var cb = capture
			capture = Callable()
			cb.call(event.physical_keycode)
		get_viewport().set_input_as_handled()
		return
	var k = event.physical_keycode
	match k:
		KEY_UP, KEY_W:
			selected = (selected - 1 + rows.size()) % maxi(rows.size(), 1)
			_follow = true
			Sfx.play("ui_move")
		KEY_DOWN, KEY_S:
			selected = (selected + 1) % maxi(rows.size(), 1)
			_follow = true
			Sfx.play("ui_move")
		KEY_LEFT, KEY_A:
			_step(-1, event.shift_pressed)
		KEY_RIGHT, KEY_D:
			_step(1, event.shift_pressed)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_activate(selected)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			if not event.echo:
				_fill_bar()
				bar.run(k - KEY_1)
		KEY_TAB:
			if not event.echo and _tabs().size() > 1:
				Sfx.play("ui_move")
				main.hub_step(-1 if event.shift_pressed else 1)
		KEY_V:
			if overview.is_valid() and not event.echo:
				_toggle_overview()
		KEY_ESCAPE, KEY_BACKSPACE:
			if not event.echo and on_back.is_valid():
				Sfx.play("ui_back")
				on_back.call()
		_:
			return
	get_viewport().set_input_as_handled()
