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


func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var aim_target = get_global_mouse_position()
		
		# Raycast from the player to the aim target
		# Draw a line to visualize the aim direction
		var aim_direction = (aim_target - global_position).normalized()
		var aim_length = 1000  # Length of the aim line
		var aim_end = global_position + aim_direction * aim_length

		var aim_line = Line2D.new()
		aim_line.add_point(global_position)
		aim_line.add_point(aim_end)
		aim_line.default_color = Color(1, 0, 0)  # Red color for the aim line
		get_parent().add_child(aim_line)

		for worm in get_tree().get_nodes_in_group("worms"):
			var idx = worm.find_segment_on_line(global_position, aim_end)
			if idx != -1:
				worm.split(idx)
				print("Worm split at segment index: ", idx)

		# Optionally, you can remove the line after a short delay
		await get_tree().create_timer(0.5).timeout
		get_parent().remove_child(aim_line)

