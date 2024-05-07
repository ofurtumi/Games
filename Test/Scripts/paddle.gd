extends CharacterBody2D


const SPEED = 1400.0
@export var invert = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
# var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")



func _physics_process(delta):
	var direction = Input.get_axis("ui_left", "ui_right")
	if invert:
		direction = -direction
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
