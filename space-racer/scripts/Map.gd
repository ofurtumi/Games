extends Control

# The expedition map (M). Space you've flown through is lit; the rest is fog.
# Outposts, fuel depots and traders you haven't been near yet show only as
# pulsing amber signals; once you've been close they're dots with names.
# Found wrecks/hulls/the market show as dots too. Pan with WASD / arrows /
# drag, zoom with the wheel, close with M or Esc. The game waits while it's up.

const Ui = preload("res://scripts/Ui.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const SIGNAL = Color(1.0, 0.75, 0.25)
const FOG = Color(0.012, 0.014, 0.022)
const LIT = Color(0.07, 0.095, 0.15)
const PAN = 700.0           # screen px per second

var mining
var centre = Vector2.ZERO   # world point at the middle of the screen
var zoom = 0.45             # screen px per metre
var t = 0.0
var _drag = false
var _labels = []            # label rects placed this frame, so they don't stack

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(m) -> void:
	mining = m
	centre = m.miner.pos
	visible = true
	Sfx.play("ui_select")

func close() -> void:
	visible = false
	_drag = false
	Sfx.play("ui_back")

func to_screen(w: Vector2) -> Vector2:
	return size * 0.5 + Vector2(w.x - centre.x, centre.y - w.y) * zoom

func to_world(s: Vector2) -> Vector2:
	var d = (s - size * 0.5) / zoom
	return centre + Vector2(d.x, -d.y)

func _process(delta):
	if not visible:
		return
	t += delta
	var dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y -= 1.0
	centre += dir * PAN / zoom * delta
	queue_redraw()

func _close_rect() -> Rect2:
	return Rect2(size.x - 190, size.y - 58, 170, 40)

func zoom_by(k: float, about: Vector2) -> void:
	var before = to_world(about)
	zoom = clampf(zoom * k, 0.08, 3.0)
	centre += before - to_world(about)

func _input(event):
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_TAB] or event.is_action("map"):
			close()
		elif event.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]:
			zoom_by(1.25, size * 0.5)
		elif event.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_by(0.8, size * 0.5)
		elif event.physical_keycode == KEY_SPACE:
			centre = mining.miner.pos
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _close_rect().has_point(event.position):
			close()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		centre += Vector2(-event.relative.x, event.relative.y) / zoom
		get_viewport().set_input_as_handled()

func _draw():
	Ui.begin()
	_draw_screen()
	Ui.scanlines(self, Rect2(Vector2.ZERO, size))
	Ui.end()

func _draw_screen():
	_labels = []
	draw_rect(Rect2(Vector2.ZERO, size), FOG)
	if mining == null:
		return
	# Explored space.
	var cs = mining.EXPLORE_CELL
	var px = cs * zoom
	for c in mining.explored():
		var p = to_screen(Vector2(c.x * cs, (c.y + 1) * cs))
		if p.x > size.x or p.y > size.y or p.x + px < 0 or p.y + px < 0:
			continue
		draw_rect(Rect2(p, Vector2(px + 0.5, px + 0.5)), LIT)
	# Planets: outlines, named once you've been to them.
	for i in mining.planets.size():
		var pl = mining.planets[i]
		var c = to_screen(pl.centre)
		var r = pl.def.radius * zoom
		var col = pl.terrain.planet.rock.lightened(0.25)
		draw_circle(c, r, Color(col, 0.25))
		draw_arc(c, r, 0, TAU, 48, Color(col, 0.8), 2.0)
		if mining.seen("planet:%d" % i):
			Ui.text(self, c + Vector2(-100, 6), pl.def.name.to_upper(), 18, col.lightened(0.3), true, HORIZONTAL_ALIGNMENT_CENTER, 200)
			_labels.append(Rect2(c + Vector2(-50, -12), Vector2(100, 22)))
	# Found sites.
	for s in mining.sites:
		if s.found and not s.done:
			_dot(s.pos, mining.SITE_COLORS[s.type], mining._site_label(s), 5.0)
	# Outposts, depots, traders: signals until you've been near.
	for i in mining.outposts.size():
		var o = mining.outposts[i]
		if mining.seen("outpost:%d" % i):
			_dot(o.pad, mining.Parts.MECHANICS[mining.PLANETS[o.planet].mech].accent, mining.PLANETS[o.planet].name.to_upper() + " OUTPOST", 7.0)
		else:
			_signal(o.pad, 0.0)
	for i in mining.depots.size():
		if mining.seen("depot:%d" % i):
			_dot(mining.depots[i], Color(0.3, 1.0, 0.4), "DEPOT", 6.0)
		else:
			_signal(mining.depots[i], 0.7)
	for tr in mining.traders.traders:
		if mining.seen("trader:" + tr.name):
			_dot(tr.pos, Color(0.6, 0.85, 1.0), "TRADER " + tr.name, 5.0)
		else:
			_signal(tr.pos, 1.3)
	# Your couriers, in flight.
	for o in mining.couriers.orders():
		if o.state == "flying":
			_dot(o.pos, Color(1.0, 0.82, 0.25), "COURIER  " + mining.Parts.PARTS[o.part].name.to_upper(), 4.0)
	# You.
	var me = to_screen(mining.miner.pos)
	var f = Vector2(cos(mining.miner.heading), -sin(mining.miner.heading))
	var n = Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([me + f * 13, me - f * 8 + n * 8, me - f * 8 - n * 8]), Color.WHITE)
	draw_arc(me, 18 + 4 * sin(t * 4.0), 0, TAU, 24, Color(1, 1, 1, 0.35), 1.5)
	# Title and keys.
	Ui.segment(self, Rect2(-30, 22, 330, 50), Ui.INK)
	Ui.segment(self, Rect2(-30, 68, 330, 4), Ui.HILITE, 0.0)
	Ui.text(self, Vector2(30, 58), "MAP", 30, Color.WHITE, true)
	var keys = "WASD / DRAG  MOVE    WHEEL  ZOOM    SPACE  YOU    M  CLOSE"
	Ui.segment(self, Rect2(size.x * 0.5 - 380, size.y - 52, 760, 34), Color(0.03, 0.035, 0.045, 0.85), 8.0)
	Ui.text(self, Vector2(size.x * 0.5 - 380, size.y - 29), keys, 14, Ui.DIM, true, HORIZONTAL_ALIGNMENT_CENTER, 760)
	var cr = _close_rect()
	Ui.segment(self, cr, Ui.HILITE, 8.0)
	Ui.text(self, cr.position + Vector2(0, 27), "CLOSE", 18, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	draw_arc(Vector2(size.x - 250, 52), 7, 0, TAU, 16, SIGNAL, 2.0)
	Ui.text(self, Vector2(size.x - 234, 57), "SIGNAL - NOT VISITED", 13, SIGNAL, true)

func _dot(w: Vector2, col: Color, label: String, r: float) -> void:
	var p = to_screen(w)
	if not Rect2(Vector2.ZERO, size).grow(40).has_point(p):
		return
	draw_circle(p, r, col)
	# Slide the name down past any label already there.
	var lw = Ui.font(true).get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var at = Rect2(p + Vector2(r + 6, -9), Vector2(lw, 16))
	for k in 6:
		if not _labels.any(func(o): return o.intersects(at)):
			break
		at.position.y += 17
	_labels.append(at)
	if at.position.y > p.y - 9 + 1:
		draw_line(p, at.position + Vector2(-2, 8), Color(col, 0.5), 1.0)
	Ui.text(self, at.position + Vector2(0, 14), label, 14, col, true)

func _signal(w: Vector2, phase: float) -> void:
	var p = to_screen(w)
	if not Rect2(Vector2.ZERO, size).grow(40).has_point(p):
		return
	var k = fmod(t * 0.8 + phase, 1.0)
	draw_arc(p, 6 + 22 * k, 0, TAU, 24, Color(SIGNAL, 1.0 - k), 2.0)
	draw_circle(p, 3.5, SIGNAL)
	Ui.text(self, p + Vector2(10, 5), "?", 14, SIGNAL, true)
