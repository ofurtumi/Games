extends Node2D

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		global_position = get_global_mouse_position()
	if event is InputEventMouseMotion:
		global_position = get_global_mouse_position()	
