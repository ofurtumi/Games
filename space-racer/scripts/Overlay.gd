extends Control

# Top-most layer: the red flash and the big banner when you die.

const Ui = preload("res://scripts/Ui.gd")

var flash = 0.0
var title = ""
var sub = ""
var t_banner = 0.0
var accent = Color(0.85, 0.12, 0.08)

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_death(big: String, small: String) -> void:
	flash = 0.85
	title = big
	sub = small
	accent = Color(0.85, 0.12, 0.08)
	t_banner = 3.2

func show_banner(big: String, small: String, color: Color) -> void:
	title = big
	sub = small
	accent = color
	t_banner = 3.2

# Runs on real time so slow motion doesn't drag it out.
func tick(real_dt: float) -> void:
	flash = maxf(0.0, flash - real_dt * 1.4)
	t_banner = maxf(0.0, t_banner - real_dt)
	queue_redraw()

func _draw():
	var vp = size
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.9, 0.1, 0.05, flash * 0.55))
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
