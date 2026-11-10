extends CharacterBody3D

const Data = preload("res://scripts/Data.gd")

@export var walk_speed = 3.0
@export var mouse_sensitivity = 0.1
@export var jump_velocity = 9.0
@export var fall_velocity = 1.5
@export var gravity = 9.0
@export var game_speed = 15.0
@export var grapple_force = 300.0
@export var grapple_max_distance = 50.0
@export var grapple_move_fraction = 0.2
@export var acceleration = 20.0
@export var deceleration = 15.0
@export var max_speed = 30.0
@export var pounce_speed = 14.0

# World-space size of the (0.05 scaled) capsule and the longest step that
# move_and_slide() is trusted with on its own.
const BODY_HALF_HEIGHT = 0.05
const TUNNEL_GUARD_STEP = 0.02

var camera_pivot: Marker3D
var camera: Camera3D

var rotation_y = 0.0
var rotation_x = 0.0
var air_jumps_left = 0

var grapple_point: Vector3 = Vector3.ZERO
var is_grappling: bool = false
var web_line: MeshInstance3D

# Set by Game.gd. Everything below still works without it (free roam).
var game = null
var spawn_pos = Vector3.ZERO
var invuln = 0.0
var pounce_time = 0.0
var pounce_cd = 0.0

# Game feel: camera shake, shot recoil, FOV punch and the front legs you see.
var shake = 0.0
var recoil = 0.0
var base_fov = 75.0
var legs: Node3D

func _ready():
	camera_pivot = $CameraPivot
	camera = $CameraPivot/Camera3D
	_bake_scale()
	camera_pivot.rotation_degrees.x = clamp(rotation_x, -79.0, 79.0)
	# The spider is tiny, so pull the clip planes in to avoid seeing through walls.
	camera.near = 0.01
	camera.far = 100.0
	safe_margin = 0.05
	spawn_pos = global_position
	base_fov = camera.fov
	_create_crosshair()
	_create_web_line()
	_create_legs()

# The scene shrinks the player with a 0.05 node scale, but move_and_slide()
# strips scale from a CharacterBody3D on the first step: the collision stays
# tiny while the camera pops back up to its unscaled height, 0.75 above the
# body. Bake the scale into the shape and child offsets so both agree.
func _bake_scale():
	var s = scale.x
	if is_equal_approx(s, 1.0):
		return
	scale = Vector3.ONE
	var col = $CollisionShape3D
	var shape = col.shape.duplicate()
	shape.radius *= s
	shape.height *= s
	col.shape = shape
	var body_mesh = $CollisionShape3D/MeshInstance3D
	body_mesh.scale = Vector3.ONE * s
	for child in camera_pivot.get_children():
		if child is Node3D:
			child.position *= s
	camera_pivot.position *= s

func _create_crosshair():
	var canvas = CanvasLayer.new()
	add_child(canvas)

	var h = ColorRect.new()
	h.color = Color.WHITE
	h.anchor_left = 0.5
	h.anchor_right = 0.5
	h.anchor_top = 0.5
	h.anchor_bottom = 0.5
	h.offset_left = -10
	h.offset_right = 10
	h.offset_top = -1
	h.offset_bottom = 1
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(h)

	var v = ColorRect.new()
	v.color = Color.WHITE
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.offset_left = -1
	v.offset_right = 1
	v.offset_top = -10
	v.offset_bottom = 10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(v)

func _create_web_line():
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.006, 0.006, 1.0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.97, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	web_line = MeshInstance3D.new()
	web_line.mesh = mesh
	web_line.material_override = mat
	web_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# top_level so the thread lives in world space.
	web_line.top_level = true
	web_line.visible = false
	add_child(web_line)

# Two front legs at the bottom of the view. They kick back with every shot.
func _create_legs():
	legs = Node3D.new()
	camera.add_child(legs)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.13, 0.1)
	mat.roughness = 1.0
	for side in [-1.0, 1.0]:
		var upper = BoxMesh.new()
		upper.size = Vector3(0.0035, 0.0035, 0.035)
		var a = MeshInstance3D.new()
		a.mesh = upper
		a.material_override = mat
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.position = Vector3(0.021 * side, -0.015, -0.0325)
		a.rotation_degrees = Vector3(18, -24 * side, 0)
		legs.add_child(a)
		var tip = BoxMesh.new()
		tip.size = Vector3(0.0025, 0.0025, 0.0225)
		var b = MeshInstance3D.new()
		b.mesh = tip
		b.material_override = mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = Vector3(0.012 * side, -0.0135, -0.056)
		b.rotation_degrees = Vector3(-22, -30 * side, 0)
		legs.add_child(b)

func add_shake(amount: float):
	shake = minf(maxf(shake, amount), 3.0)

func on_fired():
	recoil = 1.6
	legs.position.z = 0.011

func _stat(key: String, fallback):
	if game == null:
		return fallback
	return game.st.get(key, fallback)

func reset_to_spawn():
	global_position = spawn_pos
	velocity = Vector3.ZERO
	is_grappling = false
	invuln = 1.0
	pounce_time = 0.0
	pounce_cd = 0.0

func _process(delta):
	shake = move_toward(shake, 0.0, delta * 9.0)
	recoil = lerpf(recoil, 0.0, clampf(14.0 * delta, 0.0, 1.0))
	camera.rotation_degrees = Vector3(recoil + randf_range(-1.0, 1.0) * shake, randf_range(-1.0, 1.0) * shake, randf_range(-1.0, 1.0) * shake * 0.5)
	camera.fov = lerpf(camera.fov, base_fov, clampf(7.0 * delta, 0.0, 1.0))
	legs.position.z = lerpf(legs.position.z, 0.0, clampf(12.0 * delta, 0.0, 1.0))
	if not is_grappling:
		web_line.visible = false
		return
	var from = global_position + Vector3.DOWN * 0.02
	var dir = grapple_point - from
	var length = dir.length()
	if length < 0.01:
		web_line.visible = false
		return
	dir /= length
	var up = Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	var b = Basis.looking_at(dir, up)
	b.z *= length
	web_line.global_transform = Transform3D(b, from + dir * length * 0.5)
	web_line.visible = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	invuln -= delta
	pounce_time -= delta
	pounce_cd -= delta

	var x = 0
	var z = 0

	if Input.is_action_pressed("move_forward"): z -= 1
	if Input.is_action_pressed("move_backward"): z += 1
	if Input.is_action_pressed("move_left"): x -= 1
	if Input.is_action_pressed("move_right"): x += 1

	# A release that happened while a menu was open never reaches _input.
	if is_grappling and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		is_grappling = false

	var dir = Vector2(x, z)
	var target_x = 0.0
	var target_z = 0.0
	if dir.length() > 0 and not is_grappling:
		dir = dir.normalized() * walk_speed * _stat("speed", 1.0)
		var angle_rad = deg_to_rad(rotation_y)
		target_x = dir.y * sin(angle_rad) + dir.x * cos(angle_rad)
		target_z = dir.y * cos(angle_rad) - dir.x * sin(angle_rad)

	# Gravity and jumping
	if is_on_floor() and pounce_time <= 0.0:
		air_jumps_left = _stat("extra_jumps", 1)
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity # min(9, roundf(jump_velocity * delta * game_speed))
	else:
		if velocity.y > -gravity:
			velocity.y -= fall_velocity * delta * game_speed
		if air_jumps_left > 0 and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			air_jumps_left -= 1


	if is_grappling:
		var to_point = grapple_point - global_position
		var distance = to_point.length()
		if distance < 1.5:
			is_grappling = false
		else:
			var force = grapple_force * _stat("grapple_force", 1.0) * (distance / grapple_max_distance)
			velocity += (to_point / distance) * force * delta

	velocity = velocity.limit_length(max_speed)
	_move_guarded(delta)
	if not is_grappling:
		var rate = acceleration if Vector2(target_x, target_z).length() > 0 else deceleration
		velocity.x = move_toward(velocity.x, target_x, rate * delta)
		velocity.z = move_toward(velocity.z, target_z, rate * delta)

	if game != null:
		var p = global_position
		var lo = Data.WORLD_MIN
		var hi = Data.WORLD_MAX
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			reset_to_spawn()

# move_and_slide() with a guard against tunnelling. The spider is only 0.1
# units tall, so one physics step at speed can carry it clean through a floor
# or wall face. A ray along the motion spots the surface first and the step
# is shortened so the body arrives next to it instead of beyond it.
func _move_guarded(delta):
	var motion = velocity * delta
	var dist = motion.length()
	if dist < TUNNEL_GUARD_STEP:
		move_and_slide()
		return
	var dir = motion / dist
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + dir * (dist + BODY_HALF_HEIGHT))
	query.exclude = [ get_rid() ]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		move_and_slide()
		return
	var full = velocity
	var allowed = maxf(global_position.distance_to(hit.position) - BODY_HALF_HEIGHT, 0.0) + TUNNEL_GUARD_STEP
	velocity = dir * (minf(allowed, dist) / delta)
	move_and_slide()
	# Keep the momentum the shortened step threw away, minus what the
	# surfaces we actually touched take out of it.
	velocity = full
	for i in get_slide_collision_count():
		velocity = velocity.slide(get_slide_collision(i).get_normal())

func _input(event):
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x = clamp(rotation_x - event.relative.y * mouse_sensitivity, -79.0, 79.0)
		rotation_degrees.y = rotation_y
		camera_pivot.rotation_degrees.x = rotation_x

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			try_start_grapple()
		else:
			is_grappling = false

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SHIFT:
				try_pounce()
			KEY_Q:
				if game != null:
					game.try_burst()
			KEY_E:
				if game != null:
					game.interact()

func try_start_grapple():
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0
	var space_state = get_world_3d().direct_space_state
	var reach = grapple_max_distance * _stat("grapple_range", 1.0)
	var from = camera.project_ray_origin(screen_center)
	var to = from + camera.project_ray_normal(screen_center) * reach
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [ get_rid() ]

	var result = space_state.intersect_ray(query)
	if result:
		grapple_point = result.position
		is_grappling = true
		if game != null:
			game.sfx.play("grapple")

# Short dash in the look direction that bites everything it passes through.
func try_pounce():
	if pounce_cd > 0.0:
		return
	var dir = -camera.global_transform.basis.z.normalized()
	velocity = dir * pounce_speed
	is_grappling = false
	pounce_time = 0.3
	pounce_cd = _stat("pounce_cd", 2.5)
	invuln = maxf(invuln, 0.35)
	camera.fov = base_fov + 14.0
	if game != null:
		game.on_pounce_start()
