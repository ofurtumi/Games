class_name ArenaCamera
extends Camera2D
## Single player (one human vs bots): follows the human with look-ahead, like Superfighters.
## Multiplayer: frames every living fighter, zooming out down to MIN_ZOOM on big maps.
## Always clamped to the map.

const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.0

var arena: Node
var trauma := 0.0
var target_pos := Vector2.ZERO
var target_zoom := 1.0
var look := Vector2.ZERO
var punch_z := 1.0 # extra zoom for dramatic moments (final kill)


func punch(amount: float) -> void:
	punch_z = amount


func add_shake(amount: float) -> void:
	trauma = minf(trauma + amount, 14.0)


func snap() -> void:
	_compute()
	global_position = target_pos
	zoom = Vector2.ONE * target_zoom
	reset_physics_interpolation()


func _humans() -> Array:
	return arena.fighters.filter(func(f): return not f.source.is_bot and not f.source.remote and not (f.source is ScriptedSource))


func _compute() -> void:
	var view := get_viewport_rect().size
	var map: Vector2 = arena.terrain.pixel_size()
	var fit := minf(MAX_ZOOM, maxf(view.x / maxf(map.x, 1.0), view.y / maxf(map.y, 1.0)))
	var humans := _humans()
	var c := map / 2.0
	if humans.size() == 1:
		# Follow mode
		var h: Fighter = humans[0]
		var focus: Fighter = h
		if not h.alive() and h.last_hitter and h.last_hitter.alive():
			focus = h.last_hitter
		var want := Vector2(focus.facing * 36.0 + focus.velocity.x * 0.15, focus.velocity.y * 0.08)
		look = look.lerp(want, 0.04)
		c = focus.center() + look + Vector2(0, -12)
		target_zoom = maxf(fit, MAX_ZOOM)
	else:
		var pts: Array = []
		for f in (humans if not humans.is_empty() else arena.fighters):
			if f.alive():
				pts.append(f.center())
		if pts.is_empty():
			pts.append(map / 2.0)
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		box = box.grow(70.0)
		target_zoom = clampf(minf(view.x / box.size.x, view.y / box.size.y), maxf(fit, MIN_ZOOM), MAX_ZOOM)
		c = box.get_center()
	var half := view / target_zoom / 2.0
	c.x = map.x / 2.0 if half.x * 2.0 >= map.x else clampf(c.x, half.x, map.x - half.x)
	c.y = map.y / 2.0 if half.y * 2.0 >= map.y else clampf(c.y, half.y, map.y - half.y)
	target_pos = c


func _physics_process(dt: float) -> void:
	if arena.terrain == null:
		return
	_compute()
	global_position = global_position.lerp(target_pos, 1.0 - exp(-dt * 7.0))
	punch_z = lerpf(punch_z, 1.0, 1.0 - exp(-dt * 1.2))
	zoom = zoom.lerp(Vector2.ONE * target_zoom * punch_z, 1.0 - exp(-dt * 3.0))
	trauma = maxf(0.0, trauma - dt * 25.0)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * trauma * 0.5


## Visible world rectangle.
func view_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(get_screen_center_position() - size / 2.0, size)
