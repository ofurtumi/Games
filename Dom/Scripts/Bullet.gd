extends RigidBody3D


@export var speed = 50.0
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _ready():
	# Add a force to the bullet to move it forward
	var forward = -transform.basis.z
	apply_central_impulse(forward * speed)
