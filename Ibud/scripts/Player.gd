extends CharacterBody3D

const Data = preload("res://scripts/Data.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")

@export var walk_speed = 1.6
@export var mouse_sensitivity = 0.1
@export var jump_velocity = 3.6
@export var gravity = 12.0
@export var max_fall_speed = 6.0
@export var acceleration = 10.0
@export var deceleration = 12.0
# Fraction of ground acceleration you get in the air, so a swing keeps its
# momentum after you let go.
@export var air_control = 0.3
@export var max_speed = 9.0
@export var pounce_speed = 6.0

# The grapple is a rope: it reels in at reel_speed and never lets you drift
# further from the anchor than the rope is long, so you swing under it and end
# up hanging just below the anchor until you let go. WASD steers the swing.
@export var grapple_max_distance = 12.0
@export var reel_speed = 2.2
@export var rope_min_length = 0.12
@export var swing_gravity = 0.7
@export var swing_steer = 4.0

# Third-person camera: how far behind the spider, how far above its centre,
# and how far right (over the shoulder, so the spider doesn't hide the aim).
@export var camera_distance = 0.32
@export var camera_height = 0.075
@export var camera_shoulder = 0.04
# Length of the spider model.
@export var spider_size = 0.09

const TUNNEL_GUARD_STEP = 0.015

var camera_pivot: Marker3D
var spring_arm: SpringArm3D
var camera: Camera3D
var body_half_height = 0.035

var rotation_y = 0.0
var rotation_x = -12.0

var grapple_point: Vector3 = Vector3.ZERO
var is_grappling: bool = false
var rope_length = 0.0
var web_line: MeshInstance3D

# Set by Game.gd. Everything below still works without it (free roam).
var game = null
var spawn_pos = Vector3.ZERO
var invuln = 0.0
var pounce_time = 0.0
var pounce_cd = 0.0

# Game feel: camera shake, shot recoil, FOV punch, and the walking spider.
var shake = 0.0
var recoil = 0.0
var base_fov = 75.0
var model: Node3D
var legs = []
var gait = 0.0

func _ready():
	camera_pivot = $CameraPivot
	camera = $CameraPivot/Camera3D
	_bake_scale()
	_setup_camera()
	safe_margin = 0.02
	spawn_pos = global_position
	base_fov = camera.fov
	_create_crosshair()
	_create_web_line()
	_create_model()
	_apply_look()

# The scene shrinks the player with a node scale, but move_and_slide() strips
# scale from a CharacterBody3D on the first step. Bake it into the shape.
func _bake_scale():
	var s = scale.x
	var col = $CollisionShape3D
	if not is_equal_approx(s, 1.0):
		scale = Vector3.ONE
		var shape = col.shape.duplicate()
		shape.radius *= s
		shape.height *= s
		col.shape = shape
		for child in camera_pivot.get_children():
			if child is Node3D:
				child.position *= s
	body_half_height = col.shape.height * 0.5
	# The capsule is only the collider now; the spider model is what you see.
	$CollisionShape3D/MeshInstance3D.visible = false

# Pivot sits above the body; the camera hangs off a spring arm behind it so it
# slides in instead of clipping through walls.
func _setup_camera():
	camera_pivot.position = Vector3(0, camera_height, 0)
	spring_arm = SpringArm3D.new()
	var probe = SphereShape3D.new()
	probe.radius = 0.012
	spring_arm.shape = probe
	spring_arm.spring_length = camera_distance
	spring_arm.margin = 0.01
	spring_arm.add_excluded_object(get_rid())
	spring_arm.position = Vector3(camera_shoulder, 0, 0)
	camera_pivot.add_child(spring_arm)
	camera.reparent(spring_arm, false)
	camera.position = Vector3.ZERO
	camera.near = 0.01
	camera.far = 100.0

func _create_crosshair():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	for horizontal in [true, false]:
		var r = ColorRect.new()
		r.color = Color.WHITE
		r.anchor_left = 0.5
		r.anchor_right = 0.5
		r.anchor_top = 0.5
		r.anchor_bottom = 0.5
		r.offset_left = -8 if horizontal else -1
		r.offset_right = 8 if horizontal else 1
		r.offset_top = -1 if horizontal else -8
		r.offset_bottom = 1 if horizontal else 8
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(r)

func _create_web_line():
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.005, 0.005, 1.0)
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

func _create_model():
	model = MeshKit.build_spider(spider_size)
	# MeshKit builds facing +Z; the player looks down -Z. Feet on the floor.
	model.rotation_degrees.y = 180.0
	model.position.y = -body_half_height + spider_size * 0.14
	add_child(model)
	legs = model.get_meta("legs")

func add_shake(amount: float):
	shake = minf(maxf(shake, amount), 3.0)

func on_fired():
	recoil = 1.2

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

# Where the crosshair is pointing: the camera ray, started level with the
# spider so nothing between the camera and the spider gets in the way.
func aim_ray() -> Array:
	var from = camera.global_position
	var dir = -camera.global_basis.z.normalized()
	from += dir * maxf(0.0, (global_position - from).dot(dir))
	return [from, dir]

func _process(delta):
	shake = move_toward(shake, 0.0, delta * 9.0)
	recoil = lerpf(recoil, 0.0, clampf(14.0 * delta, 0.0, 1.0))
	camera.rotation_degrees = Vector3(recoil + randf_range(-1.0, 1.0) * shake, randf_range(-1.0, 1.0) * shake, randf_range(-1.0, 1.0) * shake * 0.5)
	camera.fov = lerpf(camera.fov, base_fov, clampf(7.0 * delta, 0.0, 1.0))
	_animate_legs(delta)
	if not is_grappling:
		web_line.visible = false
		return
	var from = global_position
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

# Alternating gait: legs swing faster the faster the spider walks.
func _animate_legs(delta):
	var flat_speed = Vector2(velocity.x, velocity.z).length()
	var walking = is_on_floor() and flat_speed > 0.05
	if walking:
		gait += delta * (6.0 + flat_speed * 10.0)
	var amount = clampf(flat_speed / walk_speed, 0.0, 1.0) if walking else 0.0
	# Tuck the legs in while airborne or swinging.
	var tuck = 0.0 if is_on_floor() else 0.35
	for i in legs.size():
		var leg = legs[i]
		var phase = gait + (PI if (i % 2 == 0) == (i < 4) else 0.0)
		leg.rotation.y = leg.get_meta("base_y") + sin(phase) * 0.35 * amount
		leg.rotation.z = lerpf(leg.rotation.z, tuck + maxf(0.0, cos(phase)) * 0.25 * amount, clampf(12.0 * delta, 0.0, 1.0))

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
		release_grapple()

	# Input direction in world space, relative to where the camera faces.
	var wish = Vector3.ZERO
	if x != 0 or z != 0:
		var angle_rad = deg_to_rad(rotation_y)
		var d = Vector2(x, z).normalized()
		wish = Vector3(d.y * sin(angle_rad) + d.x * cos(angle_rad), 0.0, d.y * cos(angle_rad) - d.x * sin(angle_rad))
	var target = wish * walk_speed * _stat("speed", 1.0)
	var on_floor = is_on_floor()

	if on_floor and pounce_time <= 0.0 and not is_grappling:
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		var g = gravity * _stat("air_gravity", 1.0)
		if is_grappling:
			g *= swing_gravity
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)

	if is_grappling:
		if Input.is_action_just_pressed("jump"):
			# Jump off the thread with a little hop.
			release_grapple()
			velocity.y = maxf(velocity.y, 0.0) + jump_velocity * 0.6
		else:
			_swing(delta, wish)

	velocity = velocity.limit_length(max_speed)
	_move_guarded(delta)
	if not is_grappling and pounce_time <= 0.0:
		var rate = acceleration if target != Vector3.ZERO else deceleration
		if not is_on_floor():
			rate *= air_control
		velocity.x = move_toward(velocity.x, target.x, rate * delta)
		velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if game != null:
		var p = global_position
		var lo = Data.WORLD_MIN
		var hi = Data.WORLD_MAX
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			reset_to_spawn()

func _swing(delta, wish: Vector3):
	var to_point = grapple_point - global_position
	var distance = to_point.length()
	if distance < 0.001:
		return
	var dir = to_point / distance
	var reel = reel_speed * _stat("reel", 1.0) * _stat("grapple_force", 1.0)
	rope_length = maxf(rope_min_length, minf(rope_length, distance) - reel * delta)
	velocity += wish * swing_steer * delta
	var inward = velocity.dot(dir)
	if distance > rope_length:
		# The rope can't stretch: we must be closing in at least fast enough
		# to take up the slack the reel just made.
		var need = minf((distance - rope_length) / delta * 0.5, reel * 1.5)
		if inward < need:
			velocity += dir * (need - inward)
	elif distance < rope_length + 0.3 and inward > reel:
		# Don't slam past the anchor at the end of the reel.
		velocity -= dir * (inward - reel)

func release_grapple():
	if not is_grappling:
		return
	is_grappling = false
	var sling = _stat("sling", 0.0)
	if sling > 0.0 and velocity.length() > 0.5:
		velocity += velocity.normalized() * 1.8 * sling + Vector3.UP * 0.8 * sling

# move_and_slide() with a guard against tunnelling. The spider is tiny, so one
# physics step at speed can carry it clean through a floor or wall face. A ray
# along the motion spots the surface first and the step is shortened so the
# body arrives next to it instead of beyond it.
func _move_guarded(delta):
	var motion = velocity * delta
	var dist = motion.length()
	if dist < TUNNEL_GUARD_STEP:
		move_and_slide()
		return
	var dir = motion / dist
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + dir * (dist + body_half_height))
	query.exclude = [ get_rid() ]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		move_and_slide()
		return
	var full = velocity
	var allowed = maxf(global_position.distance_to(hit.position) - body_half_height, 0.0) + TUNNEL_GUARD_STEP
	velocity = dir * (minf(allowed, dist) / delta)
	move_and_slide()
	# Keep the momentum the shortened step threw away, minus what the
	# surfaces we actually touched take out of it.
	velocity = full
	for i in get_slide_collision_count():
		velocity = velocity.slide(get_slide_collision(i).get_normal())

func _apply_look():
	rotation_degrees.y = rotation_y
	camera_pivot.rotation_degrees.x = rotation_x

func _input(event):
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotation_y -= event.screen_relative.x * mouse_sensitivity
		rotation_x = clamp(rotation_x - event.screen_relative.y * mouse_sensitivity, -75.0, 50.0)
		_apply_look()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			try_start_grapple()
		else:
			release_grapple()

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
	var aim = aim_ray()
	var reach = grapple_max_distance * _stat("grapple_range", 1.0)
	var query = PhysicsRayQueryParameters3D.create(aim[0], aim[0] + aim[1] * reach)
	query.exclude = [ get_rid() ]
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		grapple_point = result.position
		is_grappling = true
		rope_length = global_position.distance_to(grapple_point)
		if game != null:
			game.sfx.play("grapple")

# Short dash in the look direction that bites everything it passes through.
func try_pounce():
	if pounce_cd > 0.0:
		return
	var dir = -camera.global_transform.basis.z.normalized()
	velocity = dir * pounce_speed * _stat("pounce_speed", 1.0)
	is_grappling = false
	pounce_time = 0.35
	pounce_cd = _stat("pounce_cd", 2.5)
	invuln = maxf(invuln, 0.4)
	camera.fov = base_fov + 10.0
	if game != null:
		game.on_pounce_start()
