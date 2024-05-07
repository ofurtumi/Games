extends Area2D

const SPEED = 25
var direction = Vector2(0.2,1)


func _ready():
	print('Instantiated...')


func _physics_process(delta):
	position += direction.normalized() * SPEED



func _on_body_entered(body):
	print('Direction flipped')
	direction.x += randf_range(-0.2, 0.2)
	direction.y = -direction.y
