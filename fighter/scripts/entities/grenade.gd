class_name Grenade
extends Node2D
## Thrown explosive. Custom grid physics (bounces off tiles) so it never tunnels.

var def: WeaponDef
var thrower: Fighter
var arena: Node
var vel := Vector2.ZERO
var fuse := 2.5
var age := 0.0
var stuck_to: Node2D = null
var stuck_offset := Vector2.ZERO
var stuck_cell := Vector2i(-9999, -9999)
var resting := false
var done := false
var bounce_snd_t := 0.0


func setup(d: WeaponDef, who: Fighter, a: Node, v: Vector2) -> void:
	def = d
	thrower = who
	arena = a
	vel = v
	fuse = d.fuse
	if d.cursed and who:
		stick_to(who)


func _ready() -> void:
	if not def.cursed:
		Sfx.play("throw", global_position, -4.0)
	if not def.impact:
		Sfx.play("grenade_pin", global_position, -2.0)


func stick_to(n: Node2D) -> void:
	stuck_to = n
	stuck_offset = global_position - n.global_position
	stuck_offset.x = clampf(stuck_offset.x, -3, 3)
	stuck_offset.y = clampf(stuck_offset.y, -14, -4)
	vel = Vector2.ZERO
	_stick_sound()


func _stick_sound() -> void:
	if is_inside_tree():
		Sfx.play("grenade_bounce", global_position, -5.0)


## Hit by a melee swing: send it flying.
func bat(v: Vector2, by: Fighter) -> void:
	if stuck_to:
		return
	vel = v
	resting = false
	stuck_cell = Vector2i(-9999, -9999)
	thrower = by


func _solid(p: Vector2, moving_down: bool) -> bool:
	var t: Terrain = arena.terrain
	if t.is_solid_at(p):
		return true
	return moving_down and t.is_platform_at(p) and fmod(p.y, Terrain.TILE) < 4.0


func _physics_process(dt: float) -> void:
	age += dt
	fuse -= dt
	bounce_snd_t -= dt
	if fuse <= 0.0:
		detonate()
		return
	if stuck_to:
		if is_instance_valid(stuck_to) and not (stuck_to is Fighter and stuck_to.gibbed):
			global_position = stuck_to.global_position + Vector2(stuck_offset.x * (stuck_to.facing if stuck_to is Fighter else 1), stuck_offset.y)
		else:
			stuck_to = null
	elif stuck_cell.x != -9999:
		if not arena.terrain.is_solid(stuck_cell):
			stuck_cell = Vector2i(-9999, -9999)
	else:
		_move(dt)
	if global_position.y > arena.kill_y:
		queue_free()
	queue_redraw()


func _move(dt: float) -> void:
	vel.y = minf(vel.y + 600.0 * dt, 400.0)
	var hit := false
	var speed := vel.length()
	var nx := global_position.x + vel.x * dt
	if _solid(Vector2(nx, global_position.y), false):
		hit = true
		if def.sticky:
			stuck_cell = arena.terrain.cell_of(Vector2(nx, global_position.y))
			_stick_sound()
			return
		vel.x *= -0.45
	else:
		global_position.x = nx
	var ny := global_position.y + vel.y * dt
	if _solid(Vector2(global_position.x, ny), vel.y > 0.0):
		if absf(vel.y) > 40.0:
			hit = true
		if def.sticky:
			stuck_cell = arena.terrain.cell_of(Vector2(global_position.x, ny))
			_stick_sound()
			return
		vel.y *= -0.4
		vel.x *= 0.7
		if absf(vel.y) < 30.0:
			vel.y = 0.0
	else:
		global_position.y = ny
	# Fighters
	if age > 0.12 or thrower == null:
		var r := Rect2(global_position - Vector2(2, 2), Vector2(4, 4))
		for f in arena.fighters:
			if f.alive() and (f != thrower or age > 0.4) and r.intersects(f.hitbox()):
				if def.sticky:
					stick_to(f)
					return
				if def.impact:
					detonate()
					return
				if vel.length() > 120.0:
					vel *= -0.3
	# Props
	for p in arena.props():
		if p.rect().has_point(global_position):
			if def.sticky:
				stick_to(p)
				return
			hit = true
			vel.x *= -0.4
	if hit and def.impact:
		detonate()
	elif hit and speed > 50.0 and bounce_snd_t <= 0.0:
		bounce_snd_t = 0.08
		Sfx.play("grenade_bounce", global_position, linear_to_db(clampf(speed / 300.0, 0.25, 1.0)))


func detonate() -> void:
	if done:
		return
	done = true
	# The explosion sound itself belongs in Arena.explode (shared by barrels and explosive bullets).
	if not def.explosion.is_empty():
		arena.explode(global_position, def.explosion, thrower)
	if def.impact:
		Sfx.play("glass_break", global_position, -2.0)
	if not def.fire.is_empty():
		Sfx.play("fire_loop_short", global_position)
		var n := int(def.fire.get("count", 10))
		for i in n:
			var v := Vector2(arena.rng.randf_range(-110, 110), arena.rng.randf_range(-160, -40))
			arena.fx.spawn_flame(global_position + Vector2(0, -2), v, thrower,
				float(def.fire.get("dps", 25)), float(def.fire.get("duration", 4.0)))
	queue_free()


func _draw() -> void:
	var a := 0.0 if stuck_to or stuck_cell.x != -9999 else age * vel.x * 0.05
	Art.draw_weapon(self, def, Transform2D(a, Vector2.ZERO))
	var blink_rate := 4.0 if fuse > 1.0 else 12.0
	if int(age * blink_rate) % 2 == 0 and not def.impact:
		draw_rect(Rect2(-0.5, -3, 1, 1), Color(1, 0.2, 0.2))
