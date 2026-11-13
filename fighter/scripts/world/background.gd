extends Node2D
## Parallax night city behind the map. Layers scroll slower than the world.

var size := Vector2(480, 272)
var top := Color(0.05, 0.05, 0.12)
var bottom := Color(0.24, 0.13, 0.24)


func _ready() -> void:
	z_index = -20


func _process(_dt: float) -> void:
	queue_redraw()


static func _h(i: int, salt: int) -> float:
	var v := sin(i * 127.1 + salt * 311.7) * 43758.5453
	return v - floorf(v)


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vs := get_viewport_rect().size / cam.zoom
	var center := cam.get_screen_center_position()
	var view := Rect2(center - vs / 2.0, vs).grow(4.0)
	# Sky: vertical gradient over the visible area, stepped for a pixel look.
	var bands := 16
	for i in bands:
		var y0 := view.position.y + view.size.y * i / bands
		draw_rect(Rect2(view.position.x, y0, view.size.x, view.size.y / bands + 1.0), top.lerp(bottom, float(i) / (bands - 1)))
	# Stars (almost fixed to the screen)
	for i in 90:
		var p := Vector2(_h(i, 1), _h(i, 2)) * Vector2(vs.x, vs.y * 0.7)
		var sp := view.position + p + Vector2(fposmod(-center.x * 0.03, vs.x), 0)
		sp.x = view.position.x + fposmod(sp.x - view.position.x, vs.x)
		draw_rect(Rect2(sp.round(), Vector2.ONE), Color(1, 1, 1, 0.2 + _h(i, 3) * 0.6))
	draw_circle(view.position + Vector2(vs.x * 0.8, vs.y * 0.18), 10, Color(0.95, 0.9, 0.75, 0.9))
	# Skyline layers: far -> near. factor = how much they move with the camera (1 = glued).
	var ground := size.y
	for layer in 3:
		var factor: float = [0.85, 0.7, 0.5][layer]
		var col: Color = [Color(0.12, 0.09, 0.18), Color(0.1, 0.07, 0.15), Color(0.07, 0.05, 0.11)][layer]
		var spacing: float = [26.0, 34.0, 44.0][layer]
		var hmax: float = [150.0, 120.0, 90.0][layer] + size.y * 0.15
		var shift := center * factor
		var base_y := ground + (center.y - size.y / 2.0) * factor * 0.3 + layer * 10.0
		var i0 := int(floorf((view.position.x - shift.x) / spacing)) - 2
		var i1 := int(ceilf((view.end.x - shift.x) / spacing)) + 2
		for i in range(i0, i1):
			var w := spacing * (0.6 + _h(i, layer * 7 + 4) * 0.7)
			var h := 30.0 + _h(i, layer * 7 + 5) * hmax
			var x := shift.x + i * spacing
			var r := Rect2(roundf(x), roundf(base_y - h), roundf(w), h + 400.0)
			draw_rect(r, col)
			if _h(i, layer * 7 + 6) < 0.25:
				draw_rect(Rect2(r.position.x + w * 0.4, r.position.y - 8, 2, 8), col)
			if layer == 0:
				continue
			var lit := Color(0.95, 0.8, 0.4, 0.35 if layer == 1 else 0.5)
			var wy := r.position.y + 4.0
			var row := 0
			while wy < base_y - 4.0 and row < 30:
				var wx := r.position.x + 3.0
				var colm := 0
				while wx < r.end.x - 3.0:
					if _h(i * 31 + row * 7 + colm, layer + 9) < 0.16:
						draw_rect(Rect2(wx, wy, 2, 2), lit)
					wx += 5.0
					colm += 1
				wy += 6.0
				row += 1
