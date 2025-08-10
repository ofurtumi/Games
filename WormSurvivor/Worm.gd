extends Node2D

var worm_scene: PackedScene = preload("res://Worm.tscn")
@export var Speed: float = 100.0
@export var Segments: int = 64
@export var Target: CharacterBody2D
@export var Positions: Array[Vector2] = []
var last_target: Vector2
var line: Line2D

func _init():
	if Segments <= 1:
		queue_free()
		return

func _ready():
	add_to_group("worms")
	# Initialize the Target to the current position
	if (!Target):
		print("No Target")
	
	line = $Line2D
	# Set the number of Segments for the worm
	if Positions.size() == 0:
		Positions.resize(Segments)
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

func split(segment_index: int = 5):
	var should_split = segment_index != 0 and segment_index < Segments - 1
	print("Segment index: %s, Should split: %s, Segments: %s" % [segment_index, should_split, Segments])
	if should_split:
		for i in range(Segments):
			Positions[i] = line.get_point_position(i)

		var back_worm = worm_scene.instantiate()
		back_worm.set_script(load("res://Worm.gd"))
		back_worm.Positions = Positions.slice(segment_index + 1, Segments)
		back_worm.Positions.reverse()
		back_worm.Segments = back_worm.Positions.size()
		back_worm.Target = Target
		back_worm.Speed = 1.15 * Speed
		
		# Remove points between the split point and the end
		for i in range(Segments - segment_index):
			line.remove_point(Segments - 1 - i)

		Segments = segment_index
		Speed *= 1.15


		get_parent().add_child(back_worm)
	elif segment_index == 0:
		Segments -= 1
		line.remove_point(0)
	else:
		print('removing last segment')
		Segments -= 1
		line.remove_point(Segments)

	if Segments <= 1:
		queue_free()  # Remove the worm if no segments left

func find_nearest_segment(pos: Vector2) -> int:
	var nearest_index = -1
	var nearest_distance = float(INF)
	for i in range(Segments):
		var segment_position = line.get_point_position(i)
		var distance = segment_position.distance_to(pos)
		if distance <= 10.0 and distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	return nearest_index


func find_segment_on_line(line_start: Vector2, line_end: Vector2, threshold: float = 10.0) -> int:
	var nearest_index = -1
	var nearest_distance = float(INF)
	for i in range(Segments):
		var seg_pos = line.get_point_position(i)
		var dist = distance_to_segment(seg_pos, line_start, line_end)
		if dist <= threshold and dist < nearest_distance:
			nearest_distance = dist
			nearest_index = i
	return nearest_index

func distance_to_segment(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab = seg_b - seg_a
	var t = ((point - seg_a).dot(ab)) / ab.length_squared()
	t = clamp(t, 0, 1)
	var closest = seg_a + ab * t
	return point.distance_to(closest)
