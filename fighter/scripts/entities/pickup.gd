class_name Pickup
extends CharacterBody2D
## A weapon lying in the world (or flying through the air after being thrown).

var def: WeaponDef
var state: WeaponState # keeps ammo for guns; null for fresh items / throwables
var count := 1
var arena: Node
var thrown_by: Fighter = null
var no_pick_by: Fighter = null
var no_pick_t := 0.0
var angle := 0.0
var spin := 0.0
var empty_t := 0.0
var clatter_t := 0.0
var chute := false # supply drop: floats down under a parachute
var chute_t := 0.0


func setup(d: WeaponDef, st: WeaponState, a: Node, cnt := -1) -> void:
	def = d
	state = st
	arena = a
	count = cnt if cnt > 0 else d.count


func _ready() -> void:
	collision_layer = Layers.PICKUPS
	collision_mask = Layers.BODY_MASK
	var s := RectangleShape2D.new()
	s.size = Vector2(6, 3)
	var c := CollisionShape2D.new()
	c.shape = s
	c.position = Vector2(0, -1.5)
	add_child(c)
	if thrown_by:
		spin = signf(velocity.x) * 18.0


func is_empty_gun() -> bool:
	return def.kind == "gun" and state != null and state.ammo <= 0


func _physics_process(dt: float) -> void:
	no_pick_t -= dt
	clatter_t -= dt
	if chute:
		chute_t += dt
		velocity.y = minf(velocity.y + 300.0 * dt, 32.0)
		velocity.x = sin(chute_t * 1.7) * 10.0
		angle = sin(chute_t * 1.7) * 0.15
	else:
		velocity.y = minf(velocity.y + 700.0 * dt, 400.0)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * dt)
		spin = move_toward(spin, 0.0, 60.0 * dt)
		if absf(spin) < 1.0:
			angle = lerp_angle(angle, 0.0, 0.3)
	var v_before := velocity
	var was_on_floor := is_on_floor()
	move_and_slide()
	if chute and (is_on_floor() or (chute_t > 0.5 and get_slide_collision_count() > 0)):
		chute = false
		angle = 0.0
		arena.fx.burst(global_position, Color(0.9, 0.9, 0.85), 5, 40.0, 0.4, 60.0, false)
	# Clatter when it lands or hits a wall hard enough.
	if clatter_t <= 0.0 and ((is_on_floor() and not was_on_floor and v_before.y > 90.0)
			or (is_on_wall() and absf(v_before.x) > 90.0) or (is_on_ceiling() and v_before.y < -90.0)):
		clatter_t = 0.12
		Sfx.play("grenade_bounce", global_position, linear_to_db(clampf(v_before.length() / 350.0, 0.3, 1.0)) - 3.0, 0.1)
	angle += spin * dt
	if thrown_by:
		if v_before.length() < 110.0:
			thrown_by = null
		else:
			_check_hits(v_before)
			if get_slide_collision_count() > 0 and v_before.length() > 150.0:
				var col := get_slide_collision(0)
				arena.terrain.damage_cell(arena.terrain.cell_of(col.get_position() - col.get_normal() * 0.5), 6.0)
	if is_empty_gun():
		empty_t += dt
		if empty_t > 4.0:
			queue_free()
	if global_position.y > arena.kill_y:
		queue_free()
	queue_redraw()


func _check_hits(v: Vector2) -> void:
	var r := Rect2(global_position - Vector2(4, 5), Vector2(8, 6))
	for f in arena.fighters:
		if f == thrown_by or not f.alive():
			continue
		if r.intersects(f.hitbox()):
			var dmg := 10.0 + (def.damage * 0.6 if def.kind == "melee" else 0.0)
			f.apply_hit({"dmg": dmg, "kb": v.normalized() * 150.0 + Vector2(0, -60), "src": thrown_by,
				"kind": "thrown", "knockdown": dmg >= 25.0, "stun": 0.35, "from_x": global_position.x})
			velocity = Vector2(-v.x * 0.25, -80.0)
			thrown_by = null
			Sfx.play("punch_heavy" if dmg >= 25.0 else "punch", global_position)
			arena.shake(1.5)
			return


func _draw() -> void:
	if chute:
		# Canopy + lines, swaying with the crate.
		var top := Vector2(sin(chute_t * 1.7) * 2.0, -20.0)
		var w := 9.0
		var pts := PackedVector2Array()
		for i in 9:
			var a := PI + PI * i / 8.0
			pts.append(top + Vector2(cos(a) * w, sin(a) * 5.0))
		pts.append(top + Vector2(w, 1))
		pts.append(top + Vector2(-w, 1))
		draw_colored_polygon(pts, Color(0.92, 0.35, 0.25))
		for i in 3:
			draw_rect(Rect2(top + Vector2(-w + i * 6.0 + 1.0, -2), Vector2(3, 3)), Color(0.98, 0.92, 0.85))
		for sx in [-w + 1.0, w - 1.0]:
			draw_line(top + Vector2(sx, 1), Vector2(sx * 0.3, -4), Color(0.85, 0.85, 0.8, 0.8), -1.0)
	if is_empty_gun() and int(empty_t * 8.0) % 2 == 0 and empty_t > 2.0:
		return
	Art.draw_weapon_centered(self, def, Transform2D(angle, Vector2(0, -2)))
