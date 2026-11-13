class_name Prop
extends CharacterBody2D
## Furniture-ish physics objects: crates (break, may drop loot) and barrels (explode).

var kind := "crate"
var hp := 30.0
var arena: Node
var size := Vector2(8, 8)
var flash := 0.0
var dead := false
var net_id := 0
var puppet := false # online client: drawn only (still blocks cosmetic bullets)


func setup(k: String, a: Node) -> void:
	kind = k
	arena = a
	if kind == "barrel":
		hp = 14.0
		size = Vector2(7, 9)


func _ready() -> void:
	collision_layer = Layers.PROPS
	collision_mask = Layers.BODY_MASK
	var s := RectangleShape2D.new()
	s.size = size
	var c := CollisionShape2D.new()
	c.shape = s
	c.position = Vector2(0, -size.y / 2.0)
	add_child(c)
	if puppet:
		set_physics_process(false)


func rect() -> Rect2:
	return Rect2(global_position - Vector2(size.x / 2.0, size.y), size)


func _physics_process(dt: float) -> void:
	flash = maxf(0.0, flash - dt)
	velocity.y = minf(velocity.y + 900.0 * dt, 420.0)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * dt)
	move_and_slide()
	if global_position.y > arena.kill_y:
		queue_free()
	if flash > 0.0:
		queue_redraw()


func take_damage(amount: float, src: Fighter = null, kb := Vector2.ZERO) -> void:
	if dead:
		return
	hp -= amount
	velocity += kb * 0.3
	flash = 0.08
	queue_redraw()
	if hp <= 0.0:
		destroy(src)
	elif amount >= 1.0:
		Sfx.play("bullet_hit_metal" if kind == "barrel" else "bullet_hit_wall", global_position + Vector2(0, -size.y / 2.0),
			-4.0, 0.15)


func destroy(src: Fighter) -> void:
	if dead:
		return
	dead = true
	var c := global_position + Vector2(0, -size.y / 2.0)
	if kind == "barrel":
		arena.queue_explosion(c, {"radius": 34.0, "damage": 70.0, "terrain_damage": 100.0, "knockback": 260.0}, src, 0.08)
	else:
		Sfx.play("wood_break", c)
		arena.fx.debris(c, Color(0.62, 0.42, 0.22), 10)
		if arena.rng.randf() < 0.4:
			var d := Items.pick_random(arena.rng)
			if d:
				arena.spawn_pickup(d, null, c, Vector2(0, -120), null)
	queue_free()


func _draw() -> void:
	var tex := Art.prop(kind)
	var sz := tex.get_size()
	draw_texture(tex, Vector2(-sz.x / 2.0, -sz.y + 1.0), Color(4, 4, 4) if flash > 0.0 else Color.WHITE)
