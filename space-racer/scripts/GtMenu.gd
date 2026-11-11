extends Control

# Row menu in the GT4 manner: the game behind greys out, a title band and
# then each row slides in from the left, one after the other. Up/down picks,
# left/right changes a row's value, Enter confirms, Esc goes back.
#
# show_menu(title, rows, on_back). Row: {label, value (String or Callable),
# action (Callable), left/right (Callable), alt_left/alt_right (Callable,
# with Shift), swatch (Color or Callable)}.

const Ui = preload("res://scripts/Ui.gd")
const BACKDROP = preload("res://assets/shaders/menu_backdrop.gdshader")

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
	return Rect2(x, origin.y + i * (ROW_H + ROW_GAP), w, ROW_H)

func _draw():
	var ta = Ui.ease_out(t / SLIDE)
	var tr = Rect2(-40 + (ta - 1.0) * 700.0, origin.y - 92, ROW_W + 160, 58)
	Ui.segment(self, tr, Ui.INK)
	Ui.segment(self, Rect2(tr.position.x, tr.end.y - 4, tr.size.x, 4), Ui.HILITE, 0)
	Ui.text(self, Vector2(origin.x, tr.position.y + 42), title, 34, Color.WHITE, true)
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

func _activate(i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var r = rows[i]
	if r.has("action"):
		r.action.call()

func _step(dir: int, alt: bool) -> void:
	if rows.is_empty():
		return
	var r = rows[selected]
	var key = ("alt_" if alt else "") + ("left" if dir < 0 else "right")
	if r.has(key):
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
		KEY_DOWN, KEY_S:
			selected = (selected + 1) % maxi(rows.size(), 1)
		KEY_LEFT, KEY_A:
			_step(-1, event.shift_pressed)
		KEY_RIGHT, KEY_D:
			_step(1, event.shift_pressed)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_activate(selected)
		KEY_ESCAPE, KEY_BACKSPACE:
			if not event.echo and on_back.is_valid():
				on_back.call()
		_:
			return
	get_viewport().set_input_as_handled()
