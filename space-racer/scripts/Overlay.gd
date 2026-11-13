extends Control

# Top-most layer: the red flash and the big banner when you die, and the
# short banners (Main.notify), which have to show over menus and the garage
# too: a shop says what it sold you there.

const Ui = preload("res://scripts/Ui.gd")
const Bar = preload("res://scripts/Bar.gd")

var main

var flash = 0.0
var title = ""
var sub = ""
var t_banner = 0.0
var accent = Color(0.85, 0.12, 0.08)
var count = -1          # 3, 2, 1, 0 = GO
var count_t = 0.0
var fade = 0.0          # 0..1 black over everything (scene cuts)

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_death(big: String, small: String) -> void:
	flash = 0.85
	title = big
	sub = small
	accent = Color(0.85, 0.12, 0.08)
	t_banner = 3.2

func show_count(n: int) -> void:
	count = n
	count_t = 0.0

func show_banner(big: String, small: String, color: Color) -> void:
	title = big
	sub = small
	accent = color
	t_banner = 3.2

# Runs on real time so slow motion doesn't drag it out.
func tick(real_dt: float) -> void:
	flash = maxf(0.0, flash - real_dt * 1.4)
	t_banner = maxf(0.0, t_banner - real_dt)
	if count >= 0:
		count_t += real_dt
		if count == 0 and count_t > 0.9:
			count = -1
	queue_redraw()

func _draw():
	var vp = size
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, clampf(fade, 0.0, 1.0)))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.9, 0.1, 0.05, flash * 0.55))
	if count >= 0:
		# Each number punches in big and settles.
		var k = Ui.ease_out(count_t / 0.25)
		var sz = int(lerpf(260.0, 170.0, k))
		var go = count == 0
		var txt = "GO" if go else str(count)
		var col = Color(0.45, 1.0, 0.5) if go else Color.WHITE
		var a = clampf(1.0 - (count_t - 0.6) / 0.3, 0.0, 1.0) if go else 1.0
		var band = Rect2(-40, vp.y * 0.5 - 110, vp.x + 80, 200)
		Ui.segment(self, band, Color(0.02, 0.02, 0.03, 0.55 * a), 40.0)
		Ui.text(self, Vector2(0, vp.y * 0.5 + sz * 0.33), txt, sz, Color(col, a), true, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_draw_notes(vp)
	if t_banner <= 0.0:
		return
	var age = 3.2 - t_banner
	var slide = Ui.ease_out(age / 0.35)
	var a = clampf(t_banner / 0.5, 0.0, 1.0)
	var h = 120.0
	var y = vp.y * 0.38
	var r = Rect2(-60 + (1.0 - slide) * -vp.x, y, vp.x + 120, h)
	Ui.segment(self, r, Color(0.02, 0.02, 0.03, 0.88 * a), 30.0)
	Ui.segment(self, Rect2(r.position.x, r.position.y, r.size.x, 6), Color(accent, a), 0.0)
	Ui.segment(self, Rect2(r.position.x, r.end.y - 6, r.size.x, 6), Color(accent, a), 0.0)
	Ui.text(self, Vector2(0, y + 74), title, 64, Color(1, 1, 1, a), true, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	Ui.text(self, Vector2(0, y + 106), sub, 18, Color(0.9, 0.75, 0.7, a), true, HORIZONTAL_ALIGNMENT_CENTER, vp.x)

# Main.notify's banners: down from a quarter of the way while you're flying,
# stacked up from the action bar while a menu or the garage is open. Held
# back while the countdown is up.
func _draw_notes(vp: Vector2) -> void:
	if main == null or main.countdown > 0.0:
		return
	var in_menu = main.menu_open()
	var ny = vp.y - Bar.RESERVED - 50.0 if in_menu else vp.y * 0.24
	for msg in main.messages:
		var slide = Ui.ease_out((2.2 - msg.t) / 0.25)
		var a = clampf(msg.t / 0.3, 0.0, 1.0)
		var w = 560.0
		var r = Rect2((vp.x - w) * 0.5 + (1.0 - slide) * -300.0, ny, w, 42)
		Ui.segment(self, r, Color(0.03, 0.035, 0.045, (0.95 if in_menu else 0.8) * a))
		Ui.segment(self, Rect2(r.position.x, r.end.y - 3, w, 3), Color(msg.color, a), 0.0)
		Ui.text(self, Vector2(r.position.x, r.position.y + 29), msg.text, 22, Color(1, 1, 1, a), true, HORIZONTAL_ALIGNMENT_CENTER, w)
		ny += -50.0 if in_menu else 50.0
