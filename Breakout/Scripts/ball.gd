extends Area2D

const HEADING = Vector2(-0.5,1)
const SPEED = 5;
var direction = HEADING * SPEED
var angle = 0;
var paddle_width = 1

func _ready():
	paddle_width = get_node("/root/Board/Paddle/CollisionShape2D").shape.get_rect().size.x
	print(rad_to_deg(get_angle_to(direction.normalized())) - 90)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	position += direction

func _on_body_entered(body):
	# var dist = body.position.x - position.x
	# angle = (dist / paddle_width) * -45
	# direction.y = -direction.y
	# direction = -HEADING
	# direction = direction.rotated(deg_to_rad(angle))
	angle = round(rad_to_deg(get_angle_to(direction.normalized())) - 90)
	var dot = rad_to_deg(direction.normalized().dot(Vector2(1,0)))
	direction = direction.rotated(dot)
	print(dot)

func _on_area_entered(area):
	
	# print(area)
	direction.y = -direction.y
