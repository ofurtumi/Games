extends Control

# Incoming messages on an old green terminal: a sender line, the text typing
# itself out, a blinking cursor, and the replies as [ BRACKETED ] choices.
# Enter or a click skips the typing, then picks the highlighted reply;
# left/right (or the mouse) moves between replies. While it's up nothing
# behind it gets input.
#
# show_message(sender, lines, replies) - replies: [{label, action}].

const Sfx = preload("res://scripts/Sfx.gd")

const GREEN = Color(0.35, 1.0, 0.45)
const DIM = Color(0.2, 0.55, 0.25)
const BG = Color(0.01, 0.03, 0.015, 0.94)
const CPS = 38.0          # characters typed per second
const SIZE = 22

var sender = ""
var text = ""
var replies = []
var selected = 0
var shown = 0.0           # characters typed so far
var t = 0.0
var big = ""              # a large line under the text (GAME OVER)
var _font: Font
var _tick = 0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var f = SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New", "monospace"])
	_font = f

func show_message(from: String, lines: Array, choices: Array, headline: String = "") -> void:
	sender = from
	text = "\n".join(lines)
	replies = choices
	selected = 0
	shown = 0.0
	t = 0.0
	big = headline
	visible = true
	Sfx.play("wire")

func done_typing() -> bool:
	return shown >= text.length()

func close() -> void:
	visible = false

# Skip the typing, or (once it's all there) take the highlighted reply.
func confirm() -> void:
	if not done_typing():
		shown = text.length()
		return
	if replies.is_empty():
		return
	var r = replies[selected]
	Sfx.play("ui_select")
	visible = false
	r.action.call()

func _process(delta):
	if not visible:
		return
	t += delta
	var before = int(shown)
	shown = minf(shown + CPS * delta, text.length())
	if int(shown) != before and text.substr(before, 1) != " ":
		_tick += 1
		if _tick % 2 == 0:
			Sfx.play("tick", -18.0, 2.4)
	queue_redraw()

func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				confirm()
			KEY_LEFT, KEY_A, KEY_UP, KEY_W:
				_move(-1)
			KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S, KEY_TAB:
				_move(1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and done_typing():
		var i = _reply_at(event.position)
		if i >= 0 and i != selected:
			selected = i
			Sfx.play("ui_move")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i = _reply_at(event.position)
		if i >= 0 and done_typing():
			selected = i
		confirm()
		get_viewport().set_input_as_handled()

func _move(d: int) -> void:
	if replies.size() > 1 and done_typing():
		selected = (selected + d + replies.size()) % replies.size()
		Sfx.play("ui_move")

func _box() -> Rect2:
	var w = minf(size.x - 120.0, 900.0)
	return Rect2((size.x - w) * 0.5, size.y * 0.5 - 200.0, w, 400.0)

func _reply_rects() -> Array:
	var b = _box()
	var out = []
	var x = b.position.x + 40.0
	for r in replies:
		var label = "[ " + r.label.to_upper() + " ]"
		var w = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x + 24.0
		out.append(Rect2(x, b.end.y - 76.0, w, 44.0))
		x += w + 24.0
	return out

func _reply_at(p: Vector2) -> int:
	var rr = _reply_rects()
	for i in rr.size():
		if rr[i].has_point(p):
			return i
	return -1

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var b = _box()
	draw_rect(b, BG)
	draw_rect(b, DIM, false, 2.0)
	# Scanlines.
	var y = b.position.y
	while y < b.end.y:
		draw_line(Vector2(b.position.x, y), Vector2(b.end.x, y), Color(0, 0, 0, 0.25), 1.0)
		y += 3.0
	var x = b.position.x + 40.0
	draw_string(_font, Vector2(x, b.position.y + 44.0), "> INCOMING  ::  " + sender.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM)
	draw_line(Vector2(x, b.position.y + 58.0), Vector2(b.end.x - 40.0, b.position.y + 58.0), DIM, 1.0)
	# The typed text, wrapped to the box.
	var typed = text.substr(0, int(shown))
	var lines = _wrap(typed, b.size.x - 80.0)
	var ly = b.position.y + 100.0
	for i in lines.size():
		draw_string(_font, Vector2(x, ly), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, GREEN)
		if i < lines.size() - 1:
			ly += SIZE * 1.45
	var cursor_on = fmod(t, 0.8) < 0.45
	if cursor_on or not done_typing():
		var last = lines[-1] if not lines.is_empty() else ""
		var cx = x + _font.get_string_size(last, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x + 4.0
		draw_rect(Rect2(cx, ly - SIZE * 0.8, SIZE * 0.55, SIZE * 0.95), GREEN)
	if not done_typing():
		return
	if big != "":
		draw_string(_font, Vector2(b.position.x, b.end.y - 120.0), big, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 54, GREEN)
	var rr = _reply_rects()
	for i in replies.size():
		var on = i == selected
		if on:
			draw_rect(rr[i], GREEN)
		draw_string(_font, rr[i].position + Vector2(12, 30), "[ " + replies[i].label.to_upper() + " ]", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, BG if on else GREEN)

# Word wrap that keeps the message's own line breaks.
func _wrap(s: String, width: float) -> Array:
	var out = []
	for para in s.split("\n"):
		var line = ""
		for word in para.split(" "):
			var trial = word if line == "" else line + " " + word
			if _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x > width and line != "":
				out.append(line)
				line = word
			else:
				line = trial
		out.append(line)
	return out
