class_name Projectiles
extends Node2D
## All bullets in one node: raycast each tick, draw as tracers.

var arena: Node
var bullets: Array = []


## `origin` is the shooter's hand: the bullet first travels origin -> pos instantly,
## so point-blank shots hit someone standing inside the barrel.
func spawn(owner: Fighter, pos: Vector2, vel: Vector2, def: WeaponDef, power := 1.0, origin = null) -> void:
	var ignore := []
	if owner:
		ignore.append(owner.get_rid())
	var b := {"pos": pos, "prev": pos, "vel": vel, "owner": owner, "def": def, "dist": 0.0,
		"power": power, "pierce": def.pierce, "ignore": ignore}
	if origin is Vector2:
		b["pos"] = origin
		var space := get_world_2d().direct_space_state
		var seg := (pos - (origin as Vector2)).length()
		if seg > 0.0 and not _step(b, seg / maxf(vel.length(), 1.0), space, true):
			return
		b["pos"] = pos
		b["prev"] = pos
	bullets.append(b)


func clear() -> void:
	bullets.clear()
	queue_redraw()


func _physics_process(dt: float) -> void:
	if bullets.is_empty():
		return
	var space := get_world_2d().direct_space_state
	var i := bullets.size() - 1
	while i >= 0:
		if not _step(bullets[i], dt, space):
			bullets.remove_at(i)
		i -= 1


func _process(_dt: float) -> void:
	queue_redraw()


func _step(b: Dictionary, dt: float, space: PhysicsDirectSpaceState2D, first := false) -> bool:
	var def: WeaponDef = b["def"]
	if not first:
		b["vel"].y += def.bullet_gravity * dt
	var from: Vector2 = b["pos"]
	var to: Vector2 = from + b["vel"] * dt
	b["prev"] = from
	var q := PhysicsRayQueryParameters2D.create(from, to, Layers.SHOT_MASK, b["ignore"])
	q.hit_from_inside = first # point-blank: target overlapping the shooter
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		b["pos"] = to
		b["dist"] += from.distance_to(to)
		return b["dist"] < def.bullet_range and to.y < arena.kill_y
	var pos: Vector2 = hit["position"]
	b["pos"] = pos
	var col = hit["collider"]
	var power: float = b["power"]
	var vel: Vector2 = b["vel"]
	if col is Fighter:
		var f := col as Fighter
		var connected := f.apply_hit({"dmg": def.damage * power, "kb": vel.normalized() * def.knockback * power,
			"src": b["owner"], "kind": "bullet", "from_x": from.x})
		b["ignore"].append(hit["rid"])
		if not connected:
			return true
		if b["pierce"] > 0:
			b["pierce"] -= 1
			return true
	elif col is Prop:
		(col as Prop).take_damage(def.damage * power, b["owner"], vel.normalized() * def.knockback)
	else:
		var n: Vector2 = hit["normal"]
		var cell: Vector2i = arena.terrain.cell_of(pos - n * 0.5)
		var indestructible: bool = arena.terrain.mats.has(cell) and float(TileMats.LIST[arena.terrain.mats[cell]]["hp"]) < 0.0
		Sfx.play("bullet_hit_metal" if indestructible else "bullet_hit_wall", pos, -5.0, 0.15)
		arena.terrain.damage_cell(cell, def.terrain_damage * power)
		arena.fx.burst(pos, Color(1, 0.85, 0.5), 3, 70.0, 0.15, 200.0, false)
	if not def.explosion.is_empty():
		arena.explode(pos, def.explosion, b["owner"], power)
	return false


func _draw() -> void:
	var f := Engine.get_physics_interpolation_fraction()
	for b in bullets:
		var def: WeaponDef = b["def"]
		var p: Vector2 = (b["prev"] as Vector2).lerp(b["pos"], f)
		if def.bullet_size >= 2.5:
			draw_circle(p, def.bullet_size, def.bullet_color)
			draw_circle(p, def.bullet_size * 0.5, Color.WHITE)
		else:
			var tail: Vector2 = p - (b["vel"] as Vector2).normalized() * 7.0
			draw_line(tail, p, Color(def.bullet_color, 0.35), def.bullet_size)
			draw_line(p - (b["vel"] as Vector2).normalized() * 2.5, p, def.bullet_color.lightened(0.4), def.bullet_size)
