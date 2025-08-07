extends Node2D

var worm_scene: PackedScene = preload("res://Worm.tscn")
@export var Speed: float = 100.0
@export var Segments: int = 64
@export var Target: CharacterBody2D
@export var Positions: Array[Vector2] = []
var last_target: Vector2
var line: Line2D

func _ready():
	# Initialize the Target to the current position
	if (!Target):
		print("No Target")
	
	line = $Line2D
	# Set the number of Segments for the worm
	if Positions.size() == 0:
		Positions.resize(Segments)
		print(Positions.size())
		Positions.fill(Vector2.ZERO)

	for i in range(Segments):
		# Initialize the worm's Segments
		line.add_point(Positions[i])

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var head = line.get_point_position(0)
	if (head - Target.position).length() > 1.0:
		# Update the line Segments
		update_segments(delta, head)

func update_segments(delta, head):
	var direction = (Target.position - head).normalized()
	for i in range(Segments):
		if i == 0:
			# The first point is always at the worm's head
			line.set_point_position(i, head + direction * Speed * delta)
		else:
			# For subsequent points, follow the previous point
			var prev_point = line.get_point_position(i - 1)
			var current_point = line.get_point_position(i)
			var new_position = prev_point.lerp(current_point, 0.9)  # Smoothly follow the previous point
			line.set_point_position(i, new_position)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			# Split the worm when space is pressed
			split(25)  # Example: split at segment index 25

func split(segment_index: int = 5):
	var should_split = segment_index != 0 and segment_index < Segments
	if should_split:
		for i in range(Segments):
			Positions[i] = line.get_point_position(i)

		var back_worm = worm_scene.instantiate()
		back_worm.set_script(load("res://Worm.gd"))
		back_worm.Positions = Positions.slice(Segments - segment_index, Segments)
		back_worm.Positions.reverse()
		back_worm.Segments = segment_index
		back_worm.Target = Target
		back_worm.Speed = 0.75 * Speed
		
		# Remove points between the split point and the end
		for i in range(segment_index):
			line.remove_point(Segments - 1 - i)

		Segments = Segments - segment_index
		Speed *= 1.125


		print(back_worm.Positions.size(), ' ', back_worm.Segments)
		get_parent().add_child(back_worm)
