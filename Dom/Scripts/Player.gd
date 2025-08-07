extends CharacterBody3D

@export var walk_speed = 5.0
@export var mouse_sensitivity = 0.1
@export var jump_velocity = 2.0
@export var fall_velocity = 3.0
@export var gravity = 9.0
@export var game_speed = 15.0

@export var bullet_scene: PackedScene

var camera_pivot: Marker3D

var rotation_y = 0.0
var rotation_x = 0.0
var double_jump_available = false

func _ready():
	camera_pivot = $CameraPivot
	# Set the initial rotation of the camera
	camera_pivot.rotation_degrees.x = clamp(rotation_x, -79.0, 79.0)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var x = 0
	var z = 0

	if Input.is_action_pressed("move_forward"): z -= 1
	if Input.is_action_pressed("move_backward"): z += 1
	if Input.is_action_pressed("move_left"): x -= 1
	if Input.is_action_pressed("move_right"): x += 1


	var dir = Vector2(x, z)
	if dir.length() > 0:
		dir = dir.normalized() * walk_speed
		var angle_rad = deg_to_rad(rotation_y)
		velocity.x = dir.y * sin(angle_rad) + dir.x * cos(angle_rad)
		velocity.z = dir.y * cos(angle_rad) - dir.x * sin(angle_rad)

	# Gravity and jumping
	if not is_on_floor():
		if velocity.y <= -gravity:
			velocity.y = -gravity
		else: 
			velocity.y -= fall_velocity * delta * game_speed
		if double_jump_available and Input.is_action_just_pressed("jump"):
			velocity.y = roundf(jump_velocity * delta * game_speed)
			double_jump_available = false
	else:
		double_jump_available = true
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = roundf(jump_velocity * delta * game_speed)


	move_and_slide()
	velocity.x = lerp(velocity.x, 0.0, 0.2)
	velocity.z = lerp(velocity.z, 0.0, 0.2)

func _input(event):
	if event is InputEventMouseMotion:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_degrees.y = rotation_y
		camera_pivot.rotation_degrees.x = clamp(rotation_x, -79.0, 79.0)

	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		shoot_ray(event)

func shoot_ray(event):
	var space_state = get_world_3d().direct_space_state
	var camera3d = $CameraPivot/Camera3D
	var from = camera3d.project_ray_origin(event.position)
	var to = from + camera3d.project_ray_normal(event.position) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true

	var result = space_state.intersect_ray(query)
	
	var collider = result.get("collider")
	if collider && collider.is_in_group('Target'):
		collider.queue_free()

	line(from, to, Color.RED, 10)

func shoot():
	var bullet = bullet_scene.instantiate()
	bullet.position = position
	bullet.position.z -= 2
	bullet.position.y += 1
	bullet.rotation = $CameraPivot/FirePoint.global_rotation
	add_sibling(bullet)

func line(pos1: Vector3, pos2: Vector3, color = Color.WHITE_SMOKE, persist_ms = 0):
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(pos1)
	immediate_mesh.surface_add_vertex(pos2)
	immediate_mesh.surface_end()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return await final_cleanup(mesh_instance, persist_ms)

func final_cleanup(mesh_instance: MeshInstance3D, persist_ms: float):
	get_tree().get_root().add_child(mesh_instance)
	if persist_ms == 1:
		await get_tree().physics_frame
		mesh_instance.queue_free()
	elif persist_ms > 0:
		await get_tree().create_timer(persist_ms).timeout
		mesh_instance.queue_free()
	else:
		return mesh_instance
