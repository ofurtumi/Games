extends CharacterBody3D

@export var walk_speed = 5.0
@export var mouse_sensitivity = 0.1
@export var jump_velocity = 9.0
@export var fall_velocity = 1.5
@export var gravity = 9.0
@export var game_speed = 15.0
@export var grapple_force = 500.0
@export var grapple_max_distance = 50.0
@export var grapple_move_fraction = 0.2

var camera_pivot: Marker3D
var camera: Camera3D

var rotation_y = 0.0
var rotation_x = 0.0
var double_jump_available = false

var grapple_point: Vector3 = Vector3.ZERO
var is_grappling: bool = false

func _ready():
	camera_pivot = $CameraPivot
	camera = $CameraPivot/Camera3D
	camera_pivot.rotation_degrees.x = clamp(rotation_x, -79.0, 79.0)
	_create_crosshair()

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
	canvas.add_child(v)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	var x = 0
	var z = 0

	if Input.is_action_pressed("move_forward"): z -= 1
	if Input.is_action_pressed("move_backward"): z += 1
	if Input.is_action_pressed("move_left"): x -= 1
	if Input.is_action_pressed("move_right"): x += 1


	var dir = Vector2(x, z)
	if dir.length() > 0:
		var speed = walk_speed * (grapple_move_fraction if is_grappling else 1.0)
		dir = dir.normalized() * speed
		var angle_rad = deg_to_rad(rotation_y)
		velocity.x = dir.y * sin(angle_rad) + dir.x * cos(angle_rad)
		velocity.z = dir.y * cos(angle_rad) - dir.x * sin(angle_rad)

	# Gravity and jumping
	if is_on_floor():
		double_jump_available = true
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity # min(9, roundf(jump_velocity * delta * game_speed))
	else:
		if velocity.y > -gravity:
			velocity.y -= fall_velocity * delta * game_speed
		if double_jump_available and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

			double_jump_available = false


	if is_grappling:
		var to_point = grapple_point - global_position
		var distance = to_point.length()
		if distance < 1.5:
			is_grappling = false
		else:
			var force = grapple_force * (distance / grapple_max_distance)
			velocity += (to_point / distance) * force * delta

	move_and_slide()
	velocity.x = lerp(velocity.x, 0.0, 1.0 - pow(0.8, delta * 60)) # maybe break 60 out into a variable for tuning
	velocity.z = lerp(velocity.z, 0.0, 1.0 - pow(0.8, delta * 60)) # maybe break 60 out into a variable for tuning

func _input(event):
	if event is InputEventMouseMotion:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_degrees.y = rotation_y
		camera_pivot.rotation_degrees.x = clamp(rotation_x, -79.0, 79.0)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			try_start_grapple()
		else:
			is_grappling = false

func try_start_grapple():
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0
	var space_state = get_world_3d().direct_space_state
	var from = camera.project_ray_origin(screen_center)
	var to = from + camera.project_ray_normal(screen_center) * grapple_max_distance
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [ self ]

	var result = space_state.intersect_ray(query)
	if result:
		grapple_point = result.position
		is_grappling = true
