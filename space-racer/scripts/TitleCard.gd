extends Control

# The title screen's logo and the dark wedge behind its menu. The menu itself
# is the shared GtMenu; the ship laps the current track behind it.

const Ui = preload("res://scripts/Ui.gd")

var t = 0.0

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta):
	if visible:
		t += delta
		queue_redraw()

func _draw():
	var vp = size
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(700, 0), Vector2(540, vp.y), Vector2(0, vp.y)]), Color(0.0, 0.0, 0.02, 0.5))
	var a = Ui.ease_out(t / 0.5)
	var w = 720.0
	var x = vp.x - w - 40.0 + (1.0 - a) * 900.0
	var y = 70.0
	Ui.segment(self, Rect2(x + 8, y + 8, w, 128), Color(0, 0, 0, 0.4), 34.0)
	Ui.segment(self, Rect2(x, y, w, 128), Ui.INK, 34.0)
	Ui.segment(self, Rect2(x - 10, y + 128, w, 9), Ui.HILITE, 0.0)
	Ui.segment(self, Rect2(x + 40, y + 142, 220, 5), Color(0.85, 0.15, 0.12), 0.0)
	Ui.text(self, Vector2(x + 44, y + 98), "SPACE RACER", 92, Color.WHITE, true)
	Ui.text(self, Vector2(x + 44, y + 186), "BUILD   ·   MINE   ·   RACE", 18, Color(0.85, 0.87, 0.92), true)
