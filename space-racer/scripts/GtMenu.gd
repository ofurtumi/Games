extends Control

# Row menu in the GT4 manner: the game behind greys out, a title band and
# then each row slides in from the left, one after the other. Up/down picks,
# left/right changes a row's value, Enter confirms, Esc goes back.
#
# show_menu(title, rows, on_back). Row: {label, value (String or Callable),
# action (Callable), left/right (Callable), alt_left/alt_right (Callable,
# with Shift), swatch (Color or Callable), part (a part id: its card shows
# along the bottom while the row is selected), note ({title, text}: a card
# for something that isn't a part)}. Every menu gets a line under its title
# saying what it's for (BLURBS, by title; set `blurb` to override).

const Ui = preload("res://scripts/Ui.gd")
const BACKDROP = preload("res://assets/shaders/menu_backdrop.gdshader")
const Sfx = preload("res://scripts/Sfx.gd")
const PartInfo = preload("res://scripts/PartInfo.gd")
const ShopOverview = preload("res://scripts/ShopOverview.gd")

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
	["PIT SHOP", "is", "Stock parts for your ship, paid in credits. Mechanics' specials are only sold at outposts."],
	["SELL", "is", "Parts your current build isn't using, sold back for half what they cost."],
	["CARDS", "is", "Program cards to wire into your components' sub-grids (click a placed part in the garage). Each placed card uses a copy; take it out and it's free again."],
	["MARKET", "is", "Sell materials from your bank for credits. Docking unloads your hold into the bank."],
	["SOUND", "is", "Volume from 0 to 10. Left and right to change."],
	["CONTROLS", "is", "Pick an action, then press the key you want for it."],
	["RESET SAVE?", "is", "Starts a fresh career. A copy of this save is kept next to it."],
	["ABANDON?", "is", "Drops the contract. Nothing you've done on it is paid."],
	["EXPEDITION", "is", "Paused out in space."],
	["NINE FINGERS", "is", "A black market. Program cards and parts you won't find at the outposts."],
	["CONTRACTS", "ends", "Jobs from this planet. Do them anywhere, three at a time; pick an active one to abandon it."],
	["OUTPOST", "ends", "Docked: your hold is unloaded into the bank, and fuel and shield are topped up."],
	["SHOP", "ends", "Parts for your ship: stock parts plus this outpost's mechanics' own. They go to your garage."],
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
	blurb = blurb_for(menu_title)
	on_back = back
	if not keep_selection:
		selected = 0
	selected = clampi(selected, 0, maxi(rows.size() - 1, 0))
	if animate:
		t = 0.0
	closing = false
	visible = true
	queue_redraw()

func hide_menu() -> void:
	visible = false

func _process(delta):
	if not visible:
		return
	t += delta
	backdrop.visible = dim_backdrop
	backdrop.material.set_shader_parameter("amount", Ui.ease_out(t / 0.25) * 0.85)
	queue_redraw()

func _val(v):
	return v.call() if v is Callable else v

func _row_rect(i: int) -> Rect2:
	var appear = Ui.ease_out((t - 0.12 - i * STAGGER) / SLIDE)
	var x = origin.x - (1.0 - appear) * (ROW_W + origin.x + 60.0)
	var w = ROW_W + (24.0 if i == selected else 0.0)
	return Rect2(x, _rows_top() + i * (ROW_H + ROW_GAP), w, ROW_H)

func _draw():
	var ta = Ui.ease_out(t / SLIDE)
	if title != "":
		var tr = Rect2(-40 + (ta - 1.0) * 700.0, origin.y - 92, ROW_W + 160, 58)
		Ui.segment(self, tr, Ui.INK)
		Ui.segment(self, Rect2(tr.position.x, tr.end.y - 4, tr.size.x, 4), Ui.HILITE, 0)
		Ui.text(self, Vector2(origin.x, tr.position.y + 42), title, 34, Color.WHITE, true)
		for li in _blurb_lines.size():
			Ui.text(self, Vector2(origin.x + (ta - 1.0) * 700.0, origin.y - 10 + li * BLURB_LINE), _blurb_lines[li], BLURB_SIZE, Color(0.82, 0.85, 0.9), false)
	for i in rows.size():
		var r = rows[i]
		var rr = _row_rect(i)
		var sel = i == selected
		Ui.segment(self, Rect2(rr.position + Vector2(4, 4), rr.size), Color(0, 0, 0, 0.35))
		Ui.segment(self, rr, Ui.HILITE if sel else Ui.PAPER)
		var ink = Color.WHITE if sel else Ui.INK
		Ui.text(self, rr.position + Vector2(18, 27), r.label, 20, ink, sel)
		var value = _val(r.get("value", ""))
		var vx = rr.end.x - 20
		if value != "":
			var shown = value
			if sel and (r.has("left") or r.has("right")):
				shown = "‹  %s  ›" % value
			Ui.text(self, Vector2(rr.position.x + 170, rr.position.y + 27), shown, 18, ink if sel else Color(0.25, 0.27, 0.3), false, HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 190)
			vx = rr.position.x + 150
		var sw = _val(r.get("swatch", null))
		if sw != null:
			var sq = Rect2(rr.end.x - 46, rr.position.y + 10, 20, 20)
			if value != "":
				sq.position.x = rr.position.x + 150 - 4
			draw_rect(sq, sw)
			draw_rect(sq, ink, false, 1.5)
	if wallet.is_valid():
		_draw_wallet(wallet.call(), ta)
	if overview.is_valid():
		var bw3 = minf(size.x - ROW_W - origin.x - 70.0, 900.0)
		var top3 = origin.y + 160.0
		var data = overview.call()
		data.selected = rows[selected].get("part", "") if selected < rows.size() else ""
		ShopOverview.draw(self, Rect2(size.x - bw3 + (1.0 - ta) * 1000.0, top3, bw3 + 20.0, minf(size.y - top3 - 30.0, 440.0)), data, overview_mode)
	if selected < rows.size() and rows[selected].has("note") and not rows[selected].has("part"):
		var bw2 = minf(size.x - ROW_W - origin.x - 70.0, 900.0)
		var band2 = Rect2(size.x - bw2 + (1.0 - ta) * 1000.0, origin.y + 40.0, bw2 + 20.0, 84)
		var nt = rows[selected].note
		Ui.segment(self, band2, Color(0.03, 0.035, 0.045, 0.9), 10.0)
		Ui.segment(self, Rect2(band2.position, Vector2(band2.size.x, 4)), Ui.HILITE, 0.0)
		Ui.text(self, band2.position + Vector2(36, 32), nt.title.to_upper(), 22, Color.WHITE, true)
		Ui.text(self, band2.position + Vector2(36, 60), nt.text, 15, Color(0.85, 0.87, 0.9))
	if selected < rows.size() and rows[selected].has("part"):
		# Right side, under the wallet, clear of the rows however long the list.
		var bw = minf(size.x - ROW_W - origin.x - 70.0, 900.0)
		var band = Rect2(size.x - bw + (1.0 - ta) * 1000.0, origin.y + 40.0, bw + 20.0, 104)
		PartInfo.draw(self, band, rows[selected].part, 36.0)

# What you can spend, top right: hold and bank, a chip and a count per ore.
func _draw_wallet(w: Dictionary, ta: float) -> void:
	var x0 = size.x - 470 + (1.0 - ta) * 500.0
	var parts = [["HOLD", w.get("hold")], ["BANK", w.get("bank")]].filter(func(p): return p[1] != null)
	var cr = w.get("bank", {}).get("credits", 0)
	var h = 24 + parts.size() * 40 + 40
	var y = origin.y + 12 - h
	Ui.segment(self, Rect2(x0, y, 520, h), Ui.INK)
	Ui.segment(self, Rect2(x0, y + h - 4, 520, 4), Ui.HILITE, 0)
	var line = 0
	for part in parts:
		var ly = y + 40 + line * 40
		Ui.text(self, Vector2(x0 + 30, ly), part[0], 16, Ui.DIM, true)
		var cx = x0 + 100
		for m in MATS:
			draw_rect(Rect2(cx, ly - 13, 12, 12), m[1])
			Ui.text(self, Vector2(cx + 18, ly), str(part[1].get(m[0], 0)), 20, Color.WHITE, true)
			cx += 82
		line += 1
	var cy = y + 40 + line * 40
	Ui.text(self, Vector2(x0 + 30, cy), "CREDITS", 16, Ui.DIM, true)
	Ui.text(self, Vector2(x0 + 118, cy), "%d cr" % cr, 22, Color(1.0, 0.82, 0.25), true)

func _activate(i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var r = rows[i]
	if r.has("action"):
		Sfx.play("ui_select")
		r.action.call()

func _step(dir: int, alt: bool) -> void:
	if rows.is_empty():
		return
	var r = rows[selected]
	var key = ("alt_" if alt else "") + ("left" if dir < 0 else "right")
	if r.has(key):
		Sfx.play("ui_move")
		r[key].call()
	elif not alt and r.has("action") and dir > 0 and not r.has("left"):
		pass

func _gui_input(event):
	if capture.is_valid() and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var cb = capture
		capture = Callable()
		cb.call(1000 + event.button_index)
		accept_event()
		return
	if event is InputEventMouseMotion:
		for i in rows.size():
			if _row_rect(i).grow(4).has_point(event.position):
				if selected != i:
					Sfx.play("ui_move", -6.0)
				selected = i
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in rows.size():
				if _row_rect(i).has_point(event.position):
					selected = i
					if rows[i].has("right") and not rows[i].has("action"):
						_step(1, event.shift_pressed)
					else:
						_activate(i)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if on_back.is_valid():
				on_back.call()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_step(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, event.shift_pressed)
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
	match event.physical_keycode:
		KEY_UP, KEY_W:
			selected = (selected - 1 + rows.size()) % maxi(rows.size(), 1)
			Sfx.play("ui_move")
		KEY_DOWN, KEY_S:
			selected = (selected + 1) % maxi(rows.size(), 1)
			Sfx.play("ui_move")
		KEY_LEFT, KEY_A:
			_step(-1, event.shift_pressed)
		KEY_RIGHT, KEY_D:
			_step(1, event.shift_pressed)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_activate(selected)
		KEY_TAB:
			if overview.is_valid() and not event.echo:
				overview_mode = "parts" if overview_mode == "ship" else "ship"
				Sfx.play("ui_move")
		KEY_ESCAPE, KEY_BACKSPACE:
			if not event.echo and on_back.is_valid():
				Sfx.play("ui_back")
				on_back.call()
		_:
			return
	get_viewport().set_input_as_handled()
