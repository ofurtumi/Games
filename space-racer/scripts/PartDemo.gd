extends SubViewport

# Little looping demo of one component for the garage: the part on a plate,
# turning slowly, doing its thing (flames, spinning bits, beams, rockets,
# flaps, bubbles, hops). Rendered into its own world.

const Parts = preload("res://scripts/Parts.gd")
const ShipBuilder = preload("res://scripts/ShipBuilder.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")

var root3d: Node3D
var model: Node3D
var rig = {}
var part_id = ""
var t = 0.0
var cam: Camera3D
var fxs = []      # transient bits: {node, vel, life}
var _cd = 0.0
var _focus = Vector3.ZERO

func _ready():
	own_world_3d = true
	transparent_bg = false
	size = Vector2i(320, 200)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root3d = Node3D.new()
	add_child(root3d)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.065, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we = WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3d.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35.0
	root3d.add_child(cam)

func show_part(id: String) -> void:
	if id == part_id:
		return
	part_id = id
	if model != null:
		model.queue_free()
		model = null
	for f in fxs:
		f.node.queue_free()
	fxs.clear()
	if id == "":
		return
	var lo = Parts.demo_loadout(id)
	model = ShipBuilder.build(lo, Parts.stats(lo))
	root3d.add_child(model)
	rig = model.get_meta("rig")
	var p = lo.parts[0]
	_focus = Vector3.ZERO
	for c in Parts.cells_of(p):
		_focus += Parts.cell_pos(lo.frame, c)
	_focus /= Parts.cells_of(p).size()
	t = 0.0

func _process(delta):
	if model == null:
		return
	t += delta
	var kind = Parts.PARTS[part_id].kind
	model.rotation.y = sin(t * 0.5) * 0.6
	model.position.y = 0.0
	rig.shield.visible = kind == "shield"
	for f in rig.flames:
		f.scale = Vector3(1, 1, 0.05)
	match kind:
		"thruster", "tank", "engine":
			var k = 0.5 + 0.5 * sin(t * 2.0)
			for f in rig.flames:
				f.scale = Vector3(1, 1, 0.2 + k * 1.2 + randf() * 0.1)
		"fin":
			model.rotation.y = sin(t * 1.4) * 0.5
			model.rotation.z = -sin(t * 1.4) * 0.3
		"brake":
			for b in rig.brakes:
				b.rotation.x = deg_to_rad(65.0) * clampf(sin(t * 2.0) * 1.5, 0.0, 1.0)
		"shield":
			rig.shield.material_override.set_shader_parameter("strength", 0.25)
			rig.shield.material_override.set_shader_parameter("hit", maxf(0.0, sin(t * 3.0)) ** 8)
		"hopjet":
			model.position.y = absf(sin(t * 2.2)) * 0.6
		"laser":
			_cd -= delta
			if fmod(t, 2.0) < 1.2 and _cd <= 0.0:
				_cd = 0.05
				_spawn_bit(Color(0.5, 1.0, 0.5), 18.0, 0.15, 0.05)
		"rocket":
			_cd -= delta
			if _cd <= 0.0:
				_cd = 0.9
				_spawn_bit(Color(0.9, 0.9, 0.85), 7.0, 0.8, 0.12)
		"magnet":
			_cd -= delta
			if _cd <= 0.0:
				_cd = 0.4
				var a = randf() * TAU
				var node = MeshKit.part(root3d, MeshKit.box(Vector3.ONE * 0.12), MeshKit.mat(Color(1.0, 0.6, 0.25), 0.4), _focus + Vector3(cos(a) * 1.6, 0.3, sin(a) * 1.6))
				fxs.append({"node": node, "vel": -Vector3(cos(a), 0, sin(a)) * 1.6, "life": 1.0})
		"charges":
			_cd -= delta
			if _cd <= 0.0:
				_cd = 1.2
				var node = MeshKit.part(root3d, MeshKit.cyl(0.08, 0.08, 0.25, 6), MeshKit.mat(Color(0.8, 0.15, 0.1)), model.to_global(_focus) + Vector3(0, 0.3, 0))
				fxs.append({"node": node, "vel": Vector3(0, -0.3, -1.0), "life": 1.0})
	for sp in rig.spinners:
		sp[0].rotate_object_local(sp[1], sp[2] * delta * (2.5 if kind == "drill" else 1.0))
	var keep = []
	for f in fxs:
		f.life -= delta
		f.node.position += f.vel * delta
		if f.life <= 0.0:
			f.node.queue_free()
		else:
			keep.append(f)
	fxs = keep
	var span = 1
	for c in Parts.PARTS[part_id].shape:
		span = maxi(span, maxi(absi(c.x), absi(c.y)) * 2 + 1)
	var reach = span * Parts.CELL * 1.6 + 1.1
	var fw = model.to_global(_focus)
	cam.position = fw + Vector3(0, reach * 0.6, reach * 0.95)
	cam.look_at(fw, Vector3.UP)

# Beam segments / rockets leaving the part along its facing.
func _spawn_bit(color: Color, speed: float, life: float, size_: float) -> void:
	var dir = model.global_transform.basis * Vector3(0, 0, 1)
	var start = model.to_global(_focus + Vector3(0, 0.25, 0.5))
	var node = MeshKit.part(root3d, MeshKit.box(Vector3(size_, size_, size_ * 4.0)), MeshKit.add_mat(Color(color.r, color.g, color.b, 0.9)) if color.g > 0.95 else MeshKit.mat(color), start)
	node.look_at(start + dir, Vector3.UP)
	fxs.append({"node": node, "vel": dir * speed, "life": life})
