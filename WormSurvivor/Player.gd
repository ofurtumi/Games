extends CharacterBody2D


const SPEED = 30.0

func _physics_process(delta):
	var direction = Vector2.ZERO
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		direction.x += 1

	if direction.length() > 0:
		direction = direction.normalized()
		velocity = direction * SPEED * delta * 1000
	else:
		# If no input, slowly decelerate to stop
		velocity = velocity.move_toward(Vector2.ZERO, SPEED * delta * 1000)

	move_and_slide()
