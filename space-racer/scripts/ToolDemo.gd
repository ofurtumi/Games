extends SubViewport

# Live test range for a tool's wiring, shown in the sub-grid editor. Runs the
# real Weapons code against a small world: a rock wall with a lava pocket and
# a few target dummies, fired every couple of seconds and reset now and then.
# Top-down, points are (x, z); the tool sits at the origin facing +z.

const Parts = preload("res://scripts/Parts.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const WeaponsScript = preload("res://scripts/Weapons.gd")
const FxScript = preload("res://scripts/Fx.gd")

var root3d: Node3D
var fx
var weapons
var cam: Camera3D
var world
var rock = {}        # Vector2i -> {node, hp, lava}
var targets = []     # {pos, node, down}
var stats = {}
var t = 0.0
var _fire_t = 0.0
var _reset_t = 0.0
var _key = ""
var _rock_mat: Material
var _lava_mat: Material
var _target_mat: Material
var host
var ship: Node3D

# --- the tiny world Weapons talks to -----------------------------------------

class DemoWorld:
	var demo
	func _init(d):
		demo = d
	func up() -> Vector3:
		return Vector3.UP
	func to3(p: Vector2, h: float) -> Vector3:
		return Vector3(p.x, h, p.y)
	func _c(p: Vector2) -> Vector2i:
		return Vector2i(floori(p.x), floori(p.y))
	func solid(p: Vector2) -> bool:
		return demo.rock.has(_c(p))
	func hit(p: Vector2, amount: float, _tier: int) -> int:
		var c = _c(p)
		if not demo.rock.has(c) or demo.rock[c].lava:
			return -1
		demo.rock[c].hp -= amount
		if demo.rock[c].hp <= 0.0:
			demo.break_cell(c)
			return 1
		return 0
	func blast(p: Vector2, r: float, _tier: int) -> void:
		for c in demo.rock.keys():
			if Vector2(c.x + 0.5, c.y + 0.5).distance_to(p) < r and not demo.rock[c].lava:
				demo.break_cell(c)
		demo.fx.burst(Vector3(p.x, 0.6, p.y), Color(1.0, 0.55, 0.15), 24, 8.0, 1.2, 0.18, 0.5, 6.0)
		touch(p, r)
	func touch(p: Vector2, r: float) -> bool:
		var any = false
		for tg in demo.targets:
			if tg.down <= 0.0 and tg.pos.distance_to(p) < r + 0.5:
				tg.down = 1.5
				tg.node.visible = false
				demo.fx.burst(Vector3(tg.pos.x, 0.6, tg.pos.y), Color(1.0, 0.3, 0.25), 14, 6.0, 1.2, 0.12, 0.4, 6.0)
				any = true
		return any
	func target(p: Vector2, r: float):
		var best = null
		var bd = r
		for tg in demo.targets:
			if tg.down <= 0.0 and tg.pos.distance_to(p) < bd:
				bd = tg.pos.distance_to(p)
				best = tg.pos
		return best
	func pull(_p: Vector2, _r: float, _k: float) -> void:
		pass
	func quench(p: Vector2, r: float) -> void:
		for c in demo.rock.keys():
			if demo.rock[c].lava and Vector2(c.x + 0.5, c.y + 0.5).distance_to(p) < r:
				demo.rock[c].lava = false
				demo.rock[c].node.material_override = demo._rock_mat
	func burst(p: Vector2, c: Color, n: int, speed: float, h: float) -> void:
		demo.fx.burst(Vector3(p.x, h, p.y), c, n, speed, 1.2, 0.12, 0.5, 4.0)
	func spark(p: Vector2, c: Color, h: float) -> void:
		demo.fx.spawn(Vector3(p.x, h, p.y), Vector3(randf_range(-3, 3), 4.0, randf_range(-3, 3)), c, 1.2, 0.08, 0.3)
	func smoke(p: Vector2, h: float) -> void:
		demo.fx.spawn(Vector3(p.x, h, p.y), Vector3(0, 1.0, 0), Color(0.35, 0.35, 0.35), 0.0, 0.18, 0.5, -1.0)
	func swirl(p: Vector2, a: float, h: float) -> void:
		var q = p + Vector2(cos(a), sin(a)) * 4.0
		demo.fx.spawn(Vector3(q.x, h, q.y), Vector3(-cos(a) * 4.0 - sin(a) * 3.0, 0.0, -sin(a) * 4.0 + cos(a) * 3.0), Color(0.7, 0.5, 1.0), 1.2, 0.1, 0.6, 0.0)

# --- the stand-in ship Weapons fires from ------------------------------------

class DemoHost:
	var pos = Vector2.ZERO
	func pos2() -> Vector2:
		return pos
	func vel2() -> Vector2:
		return Vector2.ZERO
	func l2w(_local: Vector3) -> Vector2:
		return pos + Vector2(0, 0.8)
	func d2w(d: Vector3) -> Vector2:
		return Vector2(d.x, d.z).normalized() if Vector2(d.x, d.z).length() > 0.01 else Vector2(0, 1)
	func spend(_a: float) -> bool:
		return true
	func add_vel2(_v: Vector2) -> void:
		pass
	func teleport2(_p: Vector2) -> void:
		pass
	func take_hit(_a: float) -> void:
		pass
	func fx_height() -> float:
		return 0.6

func _ready():
	own_world_3d = true
	size = Vector2i(560, 360)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root3d = Node3D.new()
	add_child(root3d)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.065, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	env.ambient_light_energy = 0.7
	var we = WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 150, 0)
	root3d.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 13.5, -2.0)
	root3d.add_child(cam)
	cam.look_at(Vector3(0, 0, 7.5), Vector3.UP)
	var floor_mi = MeshKit.part(root3d, MeshKit.box(Vector3(40, 0.1, 40)), MeshKit.mat(Color(0.16, 0.14, 0.13), 0.0, 0.95), Vector3(0, -0.05, 8))
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rock_mat = MeshKit.mat(Color(0.42, 0.3, 0.22), 0.0, 0.9)
	_lava_mat = MeshKit.mat(Color(1.0, 0.45, 0.1), 1.2)
	_target_mat = MeshKit.mat(Color(0.85, 0.2, 0.2), 0.4)
	fx = FxScript.new()
	root3d.add_child(fx)
	ship = Node3D.new()
	root3d.add_child(ship)
	MeshKit.part(ship, MeshKit.cyl(0.0, 0.5, 1.4, 6), MeshKit.mat(Color(0.85, 0.85, 0.9), 0.0, 0.4, 0.3), Vector3(0, 0.4, 0), Vector3(90, 0, 0))
	host = DemoHost.new()
	weapons = WeaponsScript.new()
	root3d.add_child(weapons)
	world = DemoWorld.new(self)
	_build_range()

func _build_range() -> void:
	for c in rock.keys():
		rock[c].node.queue_free()
	rock.clear()
	for tg in targets:
		tg.node.queue_free()
	targets.clear()
	for x in range(-5, 5):
		for z in [9, 10]:
			var lava = z == 10 and (x == -1 or x == 0)
			var n = MeshKit.part(root3d, MeshKit.box(Vector3(0.96, 1.2, 0.96)), _lava_mat if lava else _rock_mat, Vector3(x + 0.5, 0.6, z + 0.5))
			rock[Vector2i(x, z)] = {"node": n, "hp": 1.5, "lava": lava}
	for p in [Vector2(-4.5, 5.0), Vector2(4.0, 4.0), Vector2(0.0, 14.0), Vector2(-3.0, 13.0), Vector2(3.5, 13.5)]:
		var n = Node3D.new()
		MeshKit.part(n, MeshKit.cyl(0.35, 0.45, 1.0, 8), _target_mat, Vector3(0, 0.5, 0))
		MeshKit.part(n, MeshKit.sphere(0.25, 6, 3), MeshKit.mat(Color.WHITE), Vector3(0, 1.1, 0))
		n.position = Vector3(p.x, 0, p.y)
		root3d.add_child(n)
		targets.append({"pos": p, "node": n, "down": 0.0})

func break_cell(c: Vector2i) -> void:
	if not rock.has(c):
		return
	fx.burst(Vector3(c.x + 0.5, 0.8, c.y + 0.5), Color(0.42, 0.3, 0.22), 6, 5.0, 0.0, 0.2, 0.6)
	rock[c].node.queue_free()
	rock.erase(c)

# Point the range at a component and its current wiring.
func show_tool(part: Dictionary) -> void:
	var key = var_to_str(part)
	if key == _key:
		return
	_key = key
	var lo = Parts.demo_loadout(part.id)
	lo.parts[0] = part.duplicate(true)
	lo.parts[0].cell = Parts.demo_loadout(part.id).parts[0].cell
	lo.parts[0].rot = 0
	stats = Parts.stats(lo)
	stats.ammo = maxi(stats.ammo, 1)
	stats.bombs = maxi(stats.bombs, 1)
	# Drills take a lane clear of the lava so they have something to chew.
	host.pos = Vector2(2.5, 0.0) if not stats.drills.is_empty() else Vector2.ZERO
	weapons.setup(host, world, stats)
	_fire_t = 0.3
	_reset_t = 7.0
	_build_range()

func _process(delta):
	if weapons == null or stats.is_empty():
		return
	t += delta
	for tg in targets:
		if tg.down > 0.0:
			tg.down -= delta
			if tg.down <= 0.0:
				tg.node.visible = true
	_fire_t -= delta
	_reset_t -= delta
	if _reset_t <= 0.0:
		_reset_t = 7.0
		host.pos = Vector2(2.5, 0.0) if not stats.drills.is_empty() else Vector2.ZERO
		_build_range()
	# Drills: drive into the wall and chew; the ship stops while it's blocked.
	if not stats.drills.is_empty():
		var blocked = false
		for d in stats.drills:
			if d.prog.get("orbit", false):
				continue
			var tip = host.pos + Vector2(0, 1.3)
			for c in rock.keys():
				var cc = Vector2(c.x + 0.5, c.y + 0.5)
				if cc.distance_to(tip) < d.radius + 0.4:
					if world.hit(cc, d.power * 1.5 * delta, d.tier) <= 0:
						blocked = true
					if randf() < 10.0 * delta:
						fx.spawn(Vector3(cc.x, 0.8, cc.y), Vector3(randf_range(-2, 2), 3.0, -2.0), Color(0.42, 0.3, 0.22), 0.0, 0.12, 0.5)
		if not blocked and host.pos.y < 13.0:
			host.pos.y += 3.0 * delta
	ship.position = Vector3(host.pos.x, 0, host.pos.y)
	var cycle = fmod(t, 2.2)
	var inp = {"laser": cycle < 1.2}
	if _fire_t <= 0.0:
		_fire_t = 2.2
		weapons.refill()
		inp.rocket = true
		inp.drop = true
	weapons.update(delta, inp)
	if _fire_t < 2.15:
		weapons._prev.rocket = false
		weapons._prev.drop = false
