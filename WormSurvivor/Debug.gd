extends Node2D

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				get_tree().quit()
			KEY_F:
				if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

			KEY_R:
				get_tree().reload_current_scene()
			_:
				pass  # Handle other keys if necessary
	
	# Debug input handling, check for click directly on worms
	# if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
	# 	var mouse_position = event.position
	# 	for worm in get_tree().get_nodes_in_group("worms"):
	# 		var idx = worm.find_nearest_segment(mouse_position)
	# 		print(idx)
	# 		if idx != -1:
	# 			worm.split(idx)
