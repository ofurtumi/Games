extends Node3D

# The ship in the mining mode: 2D flight in the XY plane, seen from the side
# (the camera looks down -Z, so you see the ship from above as in the race).
# Steer rotates, thrust burns fuel, brake fires retros, strafe needs side
# thrusters (all rebindable, see Controls.gd). Gravity pulls toward the nearest planet. Drills
# chew in the direction they face. Shield runs out in the heat below the
# crust and in lava; once it's gone the hull takes it, and at zero hull the
# ship is wrecked and towed home without its cargo.

const Parts = preload("res://scripts/Parts.gd")
const ShipBuilder = preload("res://scripts/ShipBuilder.gd")
const TrailScript = preload("res://scripts/Trail.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const WeaponsScript = preload("res://scripts/Weapons.gd")
const Worlds = preload("res://scripts/Worlds.gd")
const Sfx = preload("res://scripts/Sfx.gd")
var sfx_on = true

var mining
var stats = {}
var model: Node3D
var rig = {}
var trails = []
var pos = Vector2.ZERO
var vel = Vector2.ZERO
var heading = PI * 0.5
var fuel = 100.0
var shield = 100.0
var hull = 100.0
var boost = 100.0
var exposed = false
var drilling = false
var heat = 0.0
var hit_flash = 0.0
var _throttle = 0.0
var _boosting = false
var _retro = false
var _fx_cd = 0.0
var weapons

func equip(lo: Dictionary) -> void:
	stats = Parts.stats(lo)
	if model != null:
		model.queue_free()
	for t in trails:
		t.queue_free()
	trails.clear()
	model = ShipBuilder.build(ShipBuilder.with_damage(lo, mining.main if mining != null else null), stats)
	add_child(model)
	rig = model.get_meta("rig")
	for nz in rig.nozzles:
		var tr = TrailScript.new()
		tr.setup(rig.accent, 0.18 * stats.engine_scale)
		tr.plane_normal = Vector3(0, 0, 1)
		add_child(tr)
		trails.append(tr)
	if weapons == null:
		weapons = WeaponsScript.new()
		add_child(weapons)
	weapons.setup(self, Worlds.MineWorld.new(mining), stats)
	refill()

func refill() -> void:
	if weapons != null:
		weapons.refill()
	fuel = stats.fuel
	shield = stats.shield
	hull = 100.0
	boost = 100.0 * stats.boost
	exposed = false

func fwd() -> Vector2:
	return Vector2(cos(heading), sin(heading))

# Ship-local (x, z) -> world 2D. Local +Z is the nose, +X the left side.
func to_world2(local: Vector3) -> Vector2:
	var f = fwd()
	var left = Vector2(-f.y, f.x)
	return pos + f * local.z + left * local.x

func take_hit(amount: float) -> void:
	hit_flash = 1.0
	if amount > 1.0:
		Sfx.play("hit", clampf(-10.0 + amount * 0.5, -10.0, 4.0))
	if not exposed:
		shield -= amount
		if shield <= 0.0:
			shield = 0.0
			exposed = true
			mining.main.notify("SHIELD DOWN", Color(1.0, 0.3, 0.3))
			Sfx.play("shield_down")
		return
	hull -= amount
	if hull <= 0.0:
		mining.wrecked()

func step(delta: float, active: bool) -> void:
	var inp = {"turn": 0.0, "thrust": 0.0, "retro": false, "strafe": 0.0, "boost": false, "laser": false, "rocket": false}
	if active:
		inp.turn = Input.get_action_strength("left") - Input.get_action_strength("right")
		inp.thrust = Input.get_action_strength("thrust")
		inp.retro = Input.is_action_pressed("brake")
		inp.strafe = Input.get_action_strength("strafe_left") - Input.get_action_strength("strafe_right")
		inp.boost = Input.is_action_pressed("boost")
		inp.laser = Input.is_action_pressed("laser")
		inp.rocket = Input.is_action_pressed("rocket")
		inp.drop = Input.is_action_pressed("drop")
		inp.warp = Input.is_action_pressed("warp")
	if mining.has_meta("auto_input"):
		inp = mining.get_meta("auto_input")
	if fuel <= 0.0:
		inp.thrust = 0.0
		inp.strafe = 0.0
		inp.boost = false
	heading += inp.turn * stats.turn * 1.2 * delta
	var f = fwd()
	var accel = stats.accel * 0.7
	_boosting = inp.boost and inp.thrust > 0.0 and boost > 0.0
	if _boosting:
		accel *= 1.6
		boost = maxf(0.0, boost - 30.0 * delta)
	else:
		boost = minf(100.0 * stats.boost, boost + 8.0 * delta)
	_throttle = inp.thrust if stats.can_move else 0.0
	vel += f * accel * _throttle * delta
	# Fuel: the build's burn rate at full thrust, more when boosting; strafing,
	# retros, lasers and drills all take a share.
	var burn = stats.fuel_burn * _throttle * (1.6 if _boosting else 1.0)
	burn += stats.fuel_burn * 0.5 * absf(inp.strafe) * (1.0 if stats.strafe > 0.0 else 0.0)
	burn += stats.retro * 0.02 * (1.0 if inp.retro else 0.0)
	burn += 0.4 * stats.drills.size() * (1.0 if drilling else 0.0)
	fuel = maxf(0.0, fuel - burn * delta)
	# Fuel scoop: tops up while cruising through open space.
	if stats.scoop > 0.0 and vel.length() > 8.0 and mining.planets_near(pos, 8.0).is_empty():
		fuel = minf(stats.fuel, fuel + stats.scoop * delta)
	if inp.strafe != 0.0 and stats.strafe > 0.0:
		vel += Vector2(-f.y, f.x) * inp.strafe * (stats.strafe / stats.mass) * 0.6 * delta
	_retro = inp.retro
	if inp.retro and vel.length() > 0.01:
		var k = (5.0 + 4.0 * stats.brake + stats.retro / stats.mass) * delta
		vel -= vel.normalized() * minf(vel.length(), k)
	vel += mining.gravity_at(pos) * delta
	# Near a planet there's air: drag and a lower cap. Out in space you coast.
	var near_planet = not mining.planets_near(pos, 40.0).is_empty()
	if near_planet:
		vel *= 1.0 - 0.15 * delta
	var cap = mining.AIR_TOP if near_planet else mining.SPACE_TOP
	if vel.length() > cap:
		vel = vel.lerp(vel.normalized() * cap, minf(1.0, 2.0 * delta))
	pos += vel * delta
	_drill(delta)
	weapons.update(delta, inp)
	_collide()
	_hazards(delta)
	_animate(delta)

func _drill(delta: float) -> void:
	drilling = false
	for d in stats.drills:
		if d.prog.get("orbit", false):
			continue
		var tip = to_world2(d.pos)
		var dir = (to_world2(d.pos + d.dir) - tip).normalized()
		for pl in mining.planets_near(tip, d.radius + 2.0):
			var t = pl.terrain
			var lp = pl.local(tip)
			var c0 = t.world_to_cell(lp)
			var rr = ceili(d.radius) + 1
			for dj in range(-rr, rr + 1):
				for di in range(-rr, rr + 1):
					var c = c0 + Vector2i(di, dj)
					if not t.is_solid(c):
						continue
					var cw = pl.cell_world(c)
					if cw.distance_to(tip) > d.radius + 0.35 or (cw - pos).dot(dir) < 0.2:
						continue
					var res = t.damage(c, d.power * delta, d.tier)
					if res < 0:
						mining.drill_blocked(t.get_kind(c))
					if res >= 0:
						drilling = true
						if randf() < 14.0 * delta:
							mining.main.fx.spawn(Vector3(cw.x, cw.y, 1.0), Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(1, 4)),
								t.kind_color(t.get_kind(c)), 0.0, 0.14, 0.5, 0.0)
	if drilling:
		vel *= 1.0 - minf(1.0, stats.drill_drag * 0.6 * delta)

# Circle vs. planet cells, in each nearby planet's grid.
func _collide() -> void:
	var r = stats.radius * 0.9
	var worst = 0.0
	for pl in mining.planets_near(pos, r + 2.0):
		var t = pl.terrain
		var half = t.cell * 0.5
		for pass_i in 2:
			var c0 = t.world_to_cell(pl.local(pos))
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var c = c0 + Vector2i(di, dj)
					if not t.is_solid(c):
						continue
					var cc = pl.cell_world(c)
					var px = clampf(pos.x, cc.x - half, cc.x + half)
					var py = clampf(pos.y, cc.y - half, cc.y + half)
					var d = pos - Vector2(px, py)
					var dist = d.length()
					if dist >= r:
						continue
					var n = d / dist if dist > 0.0001 else -fwd()
					pos += n * (r - dist)
					var vn = vel.dot(n)
					if vn < 0.0:
						vel -= n * vn * 1.3
						worst = maxf(worst, -vn)
					if t.get_kind(c) == t.LAVA:
						mining.lava_contact = true
	if worst > 6.0:
		take_hit((worst - 6.0) * 2.0 * stats.impact)

func _hazards(delta: float) -> void:
	var pl = mining.nearest_planet(pos)
	heat = 0.0
	var depth = pl.depth_frac(pos)
	if depth > 0.3:
		heat = pl.def.heat * (depth - 0.3) * 30.0
	if mining.lava_contact:
		heat += 25.0
		mining.lava_contact = false
	if heat > 0.0:
		take_hit(heat * delta)
	elif stats.regen > 0.0 and not exposed:
		shield = minf(stats.shield, shield + stats.regen * delta)

func _animate(delta: float) -> void:
	if delta > 0.0:
		var sp = clampf(vel.length() / 40.0, 0.0, 1.5)
		Sfx.loop("engine", true, -12.0 + _throttle * 6.0, 0.6 + sp * 0.8)
		Sfx.loop("boost", _boosting, -4.0)
		Sfx.loop("drill", drilling, -4.0)
	position = Vector3(pos.x, pos.y, 0.0)
	var f3 = Vector3(cos(heading), sin(heading), 0.0)
	var up = Vector3(0, 0, 1)
	model.transform = Transform3D(Basis(up.cross(f3), up, f3), Vector3(0, 0, 0.15))
	for fl in rig.flames:
		fl.scale = Vector3(1, 1, 0.2 + _throttle * 0.7 + (0.9 if _boosting else 0.0) + randf() * 0.1)
	for sp in rig.spinners:
		sp[0].rotate_object_local(sp[1], sp[2] * delta * (2.5 if drilling else 1.0))
	for b in rig.brakes:
		b.rotation.x = lerpf(b.rotation.x, deg_to_rad(65.0) if _retro else 0.0, minf(1.0, 10.0 * delta))
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	rig.shield.visible = not exposed
	rig.shield.material_override.set_shader_parameter("strength", 0.04 + 0.16 * shield / stats.shield)
	rig.shield.material_override.set_shader_parameter("hit", hit_flash)
	for i in trails.size():
		trails[i].push(rig.nozzles[i].global_position, delta, (0.3 + 0.7 * _throttle) if vel.length() > 1.0 else 0.0)
	if exposed:
		_fx_cd -= delta
		if _fx_cd <= 0.0:
			_fx_cd = 0.08
			mining.main.fx.spawn(Vector3(pos.x, pos.y, 1.0), Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), 2.0), Color(0.15, 0.15, 0.15), 0.0, 0.3, 0.8, 0.0)

# ---------------------------------------------------------------- weapons host

func pos2() -> Vector2:
	return pos

func vel2() -> Vector2:
	return vel

func l2w(local: Vector3) -> Vector2:
	return to_world2(local)

func d2w(d: Vector3) -> Vector2:
	return (to_world2(d) - to_world2(Vector3.ZERO)).normalized()

# In the field, tools run on fuel.
func spend(amount: float) -> bool:
	var cost = amount * 0.08
	if fuel < cost:
		return false
	fuel -= cost
	return true

func add_vel2(v: Vector2) -> void:
	vel += v

func teleport2(p: Vector2) -> void:
	pos = p
	for tr in trails:
		tr.clear_points()

func fx_height() -> float:
	return 0.5
