extends Node3D

# One MultiMesh of little cubes for every particle in the game: rock debris,
# sparks, explosions, nanobots. Oldest particles get recycled first.

const MeshKit = preload("res://scripts/MeshKit.gd")
const MAX = 1500

var mm: MultiMesh
var pos = PackedVector3Array()
var vel = PackedVector3Array()
var life = PackedFloat32Array()
var max_life = PackedFloat32Array()
var size = PackedFloat32Array()
var grav = PackedFloat32Array()
var spin = PackedVector3Array()
var next = 0
var alive = {}
var floor_enabled = true

func _ready():
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = MeshKit.box(Vector3.ONE)
	mm.instance_count = MAX
	pos.resize(MAX)
	vel.resize(MAX)
	spin.resize(MAX)
	life.resize(MAX)
	max_life.resize(MAX)
	size.resize(MAX)
	grav.resize(MAX)
	for i in MAX:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	var node = MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = MeshKit.block_mat()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func spawn(p: Vector3, v: Vector3, color: Color, glow: float, sz: float, lifetime: float, gravity: float = 18.0) -> void:
	var i = next
	next = (next + 1) % MAX
	pos[i] = p
	vel[i] = v
	life[i] = lifetime
	max_life[i] = lifetime
	size[i] = sz
	grav[i] = gravity
	spin[i] = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	mm.set_instance_color(i, color)
	mm.set_instance_custom_data(i, Color(glow, 0, 0, 0))
	alive[i] = true

func burst(p: Vector3, color: Color, count: int, speed: float, glow: float = 0.0, sz: float = 0.22, lifetime: float = 0.8, gravity: float = 18.0) -> void:
	for k in count:
		var dir = Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		spawn(p, dir * speed * randf_range(0.4, 1.0), color, glow, sz * randf_range(0.6, 1.2), lifetime * randf_range(0.6, 1.1), gravity)

func _process(delta):
	var dead = []
	for i in alive:
		life[i] -= delta
		if life[i] <= 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			dead.append(i)
			continue
		var v = vel[i]
		var p = pos[i]
		v.y -= grav[i] * delta
		v *= 1.0 - 1.5 * delta
		p += v * delta
		if floor_enabled and p.y < size[i] * 0.5:
			p.y = size[i] * 0.5
			v = Vector3(v.x * 0.7, absf(v.y) * 0.3, v.z * 0.7)
		vel[i] = v
		pos[i] = p
		var t = life[i] / max_life[i]
		var s = size[i] * clampf(t * 1.5, 0.0, 1.0)
		var age = max_life[i] - life[i]
		var bs = Basis.from_euler(spin[i] * age).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(bs, p))
	for i in dead:
		alive.erase(i)
