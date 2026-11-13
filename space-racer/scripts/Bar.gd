extends RefCounted

# What every menu, the garage and the wiring editor share.
#
# The action bar along the bottom: what's selected on the left, then what you
# can do with it as numbered buttons (click one, press its number, or Enter
# for the first you can do), and the way back on the right (Esc). A screen
# fills it in every frame:
#   fill(title, actions, back, hint)
#   actions: [{label, can (bool or Callable, default true), action (Callable)}]
#   back:    {label, action}, or {} when there's no way back
# A greyed-out action still runs when pressed, so it can say why not.
#
# The tab strip along the top (static: tab_at / draw_tabs), for the screens
# that sit side by side in one place (an outpost, the pit lane).
#   tabs: [[id, label], ...]

const Ui = preload("res://scripts/Ui.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const H = 52.0
const RESERVED = 72.0   # screens keep this much clear at the bottom
const TABS_H = 46.0     # and this much at the top when there are tabs

var title = ""
var hint = ""
var actions = []
var back = {}
var hover = -1          # the action under the mouse; -2 the back button

func fill(new_title: String, new_actions: Array, new_back: Dictionary = {}, new_hint: String = "") -> void:
	title = new_title
	actions = new_actions
	back = new_back
	hint = new_hint

static func _can(a: Dictionary) -> bool:
	var c = a.get("can", true)
	return c.call() if c is Callable else c != false

func strip(size: Vector2) -> Rect2:
	return Rect2(0, size.y - H - 12.0, size.x, H)

func _back_rect(size: Vector2) -> Rect2:
	if back.is_empty():
		return Rect2(size.x, 0, 0, 0)
	var w = 76.0 + Ui.measure(back.label, 16, true)
	return Rect2(size.x - w - 26.0, strip(size).position.y + 9.0, w, H - 18.0)

# The title gives way when the buttons wouldn't fit beside it.
func _title_shown(size: Vector2) -> bool:
	return title != "" and _buttons(size, true)[1] <= _back_rect(size).position.x - 12.0

# [rects, where they end]
func _buttons(size: Vector2, with_title: bool) -> Array:
	var x = 30.0 + (Ui.measure(title, 18, true) + 30.0 if with_title else 0.0)
	var y = strip(size).position.y + 9.0
	var out = []
	for a in actions:
		var w = 56.0 + Ui.measure(a.label, 16, true)
		out.append(Rect2(x, y, w, H - 18.0))
		x += w + 16.0
	return [out, x - 16.0]

func _rects(size: Vector2) -> Array:
	return _buttons(size, _title_shown(size))[0]

func at(size: Vector2, pos: Vector2) -> int:
	var rr = _rects(size)
	for i in rr.size():
		if rr[i].has_point(pos):
			return i
	return -2 if _back_rect(size).has_point(pos) else -1

func motion(size: Vector2, pos: Vector2) -> void:
	hover = at(size, pos)

# A left click: true if the bar took it.
func click(size: Vector2, pos: Vector2) -> bool:
	var i = at(size, pos)
	if i == -1:
		return strip(size).has_point(pos)
	run(i)
	return true

# The first action you can do right now (Enter), else the first.
func primary() -> int:
	for i in actions.size():
		if _can(actions[i]):
			return i
	return 0 if not actions.is_empty() else -1

func run(i: int) -> void:
	if i == -2 and not back.is_empty():
		Sfx.play("ui_back")
		back.action.call()
	elif i >= 0 and i < actions.size():
		Sfx.play("ui_select", -4.0)
		actions[i].action.call()

# Number keys and Enter. True if it was one of ours.
func key(event: InputEventKey) -> bool:
	var k = event.physical_keycode
	if k >= KEY_1 and k <= KEY_9 and not event.shift_pressed:
		if k - KEY_1 < actions.size():
			run(k - KEY_1)
		return true
	if k in [KEY_ENTER, KEY_KP_ENTER] and primary() >= 0:
		run(primary())
		return true
	return false

func draw(ci: CanvasItem, size: Vector2) -> void:
	var s = strip(size)
	Ui.segment(ci, Rect2(-20, s.position.y, size.x + 40, H), Color(0.03, 0.035, 0.045, 0.94), 0.0)
	Ui.segment(ci, Rect2(-20, s.position.y, size.x + 40, 3), Ui.HILITE, 0.0)
	var with_title = _title_shown(size)
	if with_title:
		Ui.text(ci, Vector2(30, s.position.y + 33), title, 18, Color.WHITE, true)
	var bb = _buttons(size, with_title)
	for i in bb[0].size():
		var r = bb[0][i]
		var ok = _can(actions[i])
		var hot = i == hover
		Ui.segment(ci, r, Ui.HILITE if hot else (Ui.PAPER if ok else Color(0.32, 0.34, 0.38)), 8.0)
		var chip = Rect2(r.position.x + 10, r.position.y + 7, 22, r.size.y - 14)
		Ui.segment(ci, chip, Ui.INK, 0.0)
		Ui.text(ci, chip.position + Vector2(0, 15), str(i + 1), 13, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x)
		Ui.text(ci, Vector2(r.position.x + 42, r.position.y + 23), actions[i].label, 16,
			Color.WHITE if hot else (Ui.INK if ok else Color(0.62, 0.64, 0.68)), true)
	var br = _back_rect(size)
	if hint != "":
		var hx = maxf(bb[1] + (30.0 if not bb[0].is_empty() else 0.0), 30.0)
		if hx + Ui.measure(hint, 14, true) < br.position.x - 12.0:
			Ui.text(ci, Vector2(hx, s.position.y + 32), hint, 14, Ui.DIM, true)
	if not back.is_empty():
		var hot = hover == -2
		Ui.segment(ci, br, Ui.HILITE if hot else Color(0.2, 0.22, 0.25, 0.95), 8.0)
		Ui.text(ci, Vector2(br.position.x + 14, br.position.y + 22), "ESC", 12, Color(0.75, 0.82, 1.0) if hot else Ui.DIM, true)
		Ui.text(ci, Vector2(br.position.x + 58, br.position.y + 23), back.label, 16, Color.WHITE, true)

# ---------------------------------------------------------------- tabs

static func tab_rects(tabs: Array) -> Array:
	var out = []
	var x = 22.0
	for t in tabs:
		var w = Ui.measure(t[1], 15, true) + 34.0
		out.append(Rect2(x, 8, w, 30))
		x += w + 12.0
	return out

# The id of the tab at `pos`, or "".
static func tab_at(tabs: Array, pos: Vector2) -> String:
	var rr = tab_rects(tabs)
	for i in rr.size():
		if rr[i].has_point(pos):
			return tabs[i][0]
	return ""

static func draw_tabs(ci: CanvasItem, size: Vector2, tabs: Array, current: String, hover_id: String = "") -> void:
	if tabs.is_empty():
		return
	Ui.segment(ci, Rect2(-20, -4, size.x + 40, TABS_H), Color(0.03, 0.035, 0.045, 0.94), 0.0)
	var rr = tab_rects(tabs)
	for i in tabs.size():
		var on = tabs[i][0] == current
		var hot = tabs[i][0] == hover_id
		Ui.segment(ci, rr[i], Ui.HILITE if on else Color(0.2, 0.22, 0.25, 0.95), 6.0)
		Ui.text(ci, rr[i].position + Vector2(0, 21), tabs[i][1], 15, Color.WHITE if on or hot else Color(0.7, 0.72, 0.76), true, HORIZONTAL_ALIGNMENT_CENTER, rr[i].size.x)
		if hot and not on:
			ci.draw_rect(Rect2(rr[i].position.x, rr[i].end.y - 3, rr[i].size.x, 3), Ui.fill(Ui.HILITE))
	if tabs.size() > 1:
		Ui.text(ci, Vector2(size.x - 230, 29), "TAB  NEXT", 12, Ui.DIM, true, HORIZONTAL_ALIGNMENT_RIGHT, 200)
