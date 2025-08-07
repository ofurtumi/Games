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
