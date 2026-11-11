extends Node3D

# Hover-racer controller. Everything that makes builds feel different comes
# from Parts.stats(): mass, thrust, grip, drill tier/power, shield, magnet.
#
# Feel knobs: drift cuts lateral grip and boosts turn rate; holding a drift
# charges a mini boost released when you let go. Drills chew whatever they
# can (tier >= block hardness) and drag the ship while they work.

const Parts = preload("res://scripts/Parts.gd")
const ShipBuilder = preload("res://scripts/ShipBuilder.gd")
const TrailScript = preload("res://scripts/Trail.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")

const HOVER = 0.55
const IMPACT_SAFE = 5.0        # m/s into a wall before the shield takes damage
const IMPACT_DAMAGE = 2.4      # shield per m/s above that
const EXPOSED_TOP = 0.65       # top speed multiplier while the shield is down
const GRAVITY = 30.0
const CLEARANCE = 0.25         # hull bottom above `alt`; blocks lower than alt+this are hopped

var loadout: Dictionary
var stats: Dictionary
var model: Node3D
var rig: Dictionary
var sockets: Dictionary
var trails = []

var heading = 0.0
var alt = 0.0                  # height of a hop above hover
var vy = 0.0
var _jump_prev = false
var vel = Vector3.ZERO
var shield = 100.0
var boost = 100.0
var boost_max = 100.0
var charges = 0
var exposed = false
var drifting = false
var boosting = false
var drilling = false
var drift_charge = 0.0
var hit_flash = 0.0
var stall = 0.0
var autopilot = false
var progress_idx = 0

var _t = 0.0
var _steer_vis = 0.0
var _throttle = 0.0
var _fx_cd = 0.0
var ammo = 0
var lasing = false
var beams = []
var rockets = []          # {pos, vel, life, node}
var _rocket_prev = false
var _next_launcher = 0
var _drift_dir = 0.0
var _braking = false
var _flap = 0.0

var terrain
var track
var fx
var main

func setup(t, tr, f, m) -> void:
	terrain = t
	track = tr
	fx = f
	main = m

func equip(lo: Dictionary) -> void:
	loadout = lo
	stats = Parts.stats(lo)
	if model != null:
		model.queue_free()
	for tr in trails:
		tr.queue_free()
	trails.clear()
	model = ShipBuilder.build(lo, stats)
	add_child(model)
	rig = model.get_meta("rig")
	sockets = model.get_meta("sockets")
	shield = stats.shield
	boost_max = 100.0 * stats.boost
	boost = boost_max
	charges = stats.charges
	ammo = stats.ammo
	exposed = false
	for b in beams:
		b.queue_free()
	beams.clear()
	for l in stats.lasers:
		var bm = MeshInstance3D.new()
		bm.mesh = MeshKit.box(Vector3(0.2, 0.2, 1.0))
		bm.material_override = MeshKit.add_mat(Color(0.5, 1.0, 0.5, 0.9))
		bm.top_level = true
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.visible = false
		add_child(bm)
		beams.append(bm)
	for nz in rig.nozzles:
		var tr = TrailScript.new()
		tr.setup(rig.accent, 0.2 * stats.engine_scale)
		add_child(tr)
		trails.append(tr)
	if stats.regen > 0.0:
		rig.shield.material_override.set_shader_parameter("color", Parts.MECHANICS.aegis.accent)

func place(p: Vector3, h: float) -> void:
	position = Vector3(p.x, 0.0, p.z)
	heading = h
	vel = Vector3.ZERO
	alt = 0.0
	vy = 0.0
	rotation.y = heading
	for tr in trails:
		tr.clear_points()

func forward() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))

func _input_state() -> Dictionary:
	if autopilot:
		return _autopilot()
	if main.shot_path != "":
		return {"throttle": 0.0, "brake": false, "steer": 0.0, "boost": false, "jump": false}
	return {
		"throttle": 1.0 if Input.is_action_pressed("thrust") else 0.0,
		"brake": Input.is_action_pressed("brake"),
		"steer": Input.get_action_strength("left") - Input.get_action_strength("right"),
		"boost": Input.is_action_pressed("boost"),
		"jump": Input.is_action_pressed("hop"),
		"laser": Input.is_action_pressed("laser"),
		"rocket": Input.is_action_pressed("rocket"),
	}

# Chases a point a little way down the centreline. Handy for screenshots and
# for eyeballing how a build handles without driving it yourself.
func _autopilot() -> Dictionary:
	var n = track.pts.size()
	var target = track.pts[(progress_idx + 9) % n]
	var to = target - position
	var want = atan2(to.x, to.z)
	var diff = wrapf(want - heading, -PI, PI)
	# Hop barriers if there's no drill to chew through them.
	var ahead = terrain.get_kind(terrain.world_to_cell(position + forward() * (2.0 + vel.length() * 0.12)))
	var jump = ahead == terrain.BARRIER and stats.drill_tier == 0
	return {"throttle": 1.0, "brake": absf(diff) > 0.5 and vel.length() > 12.0, "steer": clampf(diff * 2.5, -1.0, 1.0),
		"boost": absf(diff) < 0.15 and boost > boost_max * 0.4, "jump": jump}

func _process(delta):
	if model == null:
		return
	delta = minf(delta, 1.0 / 30.0)
	_t += delta
	var inp = _input_state()
	if stall > 0.0:
		stall -= delta
		inp.throttle = 0.0
		inp.steer = 0.0
		heading += delta * 9.0 * stall
	_hop(delta, inp)
	_drive(delta, inp)
	_drill(delta)
	_weapons(delta, inp)
	_collide()
	_animate(delta, inp)

func airborne() -> bool:
	return alt > 0.05

func _hop(delta: float, inp: Dictionary) -> void:
	var pressed = inp.jump and not _jump_prev
	_jump_prev = inp.jump
	if pressed and not airborne() and stall <= 0.0:
		vy = stats.jump
		alt = 0.06
		fx.burst(position + Vector3(0, 0.2, 0), terrain.planet.ground.lightened(0.3), 10, 4.0, 0.0, 0.2, 0.4, 6.0)
	if airborne() or vy > 0.0:
		vy -= GRAVITY * delta
		alt += vy * delta
		if alt <= 0.0:
			alt = 0.0
			if vy < -5.0:
				fx.burst(position + Vector3(0, 0.2, 0), terrain.planet.ground.lightened(0.3), 12, 5.0, 0.0, 0.22, 0.5, 6.0)
			vy = 0.0

func launch(v: float) -> void:
	vy = maxf(vy, v)
	alt = maxf(alt, 0.06)

# True if the hull is above this block (hopping over a barrier, or over a
# wall that's been drilled half down).
func clears(c: Vector2i) -> bool:
	return alt + CLEARANCE > terrain.top_of(c)

func _drive(delta: float, inp: Dictionary) -> void:
	var fwd = forward()
	var lat = Vector3(fwd.z, 0.0, -fwd.x)
	var fspeed = vel.dot(fwd)
	# Brake-drift: brake while turning at speed to break traction. The drift
	# holds as long as you keep steering the same way; better brakes swing the
	# tail harder and scrub less speed doing it.
	if not drifting and inp.brake and absf(inp.steer) > 0.3 and fspeed > 9.0 and not airborne():
		drifting = true
		_drift_dir = signf(inp.steer)
	elif drifting and (signf(inp.steer) != _drift_dir or fspeed < 5.0):
		drifting = false
	var drift_turn = 1.25 + 0.2 * stats.brake
	var turn = stats.turn * (drift_turn if drifting else 1.0) * clampf(absf(fspeed) / 6.0, 0.35, 1.0)
	heading += inp.steer * turn * delta * (1.0 if fspeed >= -0.5 else -1.0)
	rotation.y = heading
	fwd = forward()
	lat = Vector3(fwd.z, 0.0, -fwd.x)

	var top = stats.top * (EXPOSED_TOP if exposed else 1.0)
	var accel = stats.accel
	boosting = inp.boost and boost > 0.0 and inp.throttle > 0.0 and stats.can_move
	if boosting:
		accel *= 1.6
		top *= 1.35
		boost = maxf(0.0, boost - 35.0 * delta)
	else:
		boost = minf(boost_max, boost + 9.0 * delta)
	_throttle = inp.throttle if stats.can_move else 0.0
	_braking = inp.brake and fspeed > 0.5
	vel += fwd * accel * _throttle * delta * (0.5 if airborne() else 1.0)
	# Side thrusters shove you into the turn.
	if stats.strafe > 0.0 and absf(inp.steer) > 0.1:
		vel += lat * inp.steer * (stats.strafe / stats.mass) * 0.6 * delta
	if inp.brake:
		if fspeed > 0.5:
			# In a drift the brake mostly feeds the slide instead of stopping you.
			var k = (0.25 / stats.brake) if drifting else 1.0
			vel -= fwd * minf(fspeed, (14.0 + 10.0 * stats.brake + stats.retro / stats.mass) * k * delta)
		elif fspeed > -top * 0.35:
			vel -= fwd * maxf(accel, 8.0) * 0.5 * delta

	# Grip: bleed off sideways velocity. Drifting keeps most of it.
	var lat_v = vel.dot(lat)
	var grip = stats.grip * ((0.1 + 0.03 * stats.brake) if drifting else 1.0) * (0.35 if airborne() else 1.0)
	vel -= lat * lat_v * minf(1.0, grip * delta)
	vel *= 1.0 - (0.2 + (0.6 if inp.throttle == 0.0 else 0.0)) * delta
	var speed = vel.length()
	if speed > top:
		vel = vel.normalized() * lerpf(speed, top, minf(1.0, 2.5 * delta))

	# Mini boost from holding a drift.
	if drifting and absf(inp.steer) > 0.1:
		drift_charge += delta
		_fx_cd -= delta
		if _fx_cd <= 0.0:
			_fx_cd = 0.03
			var c = Color(1.0, 0.85, 0.3) if drift_charge < 0.8 else (Color(1.0, 0.4, 0.1) if drift_charge < 1.6 else Color(1.0, 0.3, 0.9))
			for s in [-1.0, 1.0]:
				var p = position + fwd * -sockets.length * 0.4 + lat * s * sockets.width * 0.45 + Vector3(0, 0.1, 0)
				fx.spawn(p, -fwd * 3.0 + lat * s * 2.0 + Vector3(0, 2.5, 0), c, 1.2, 0.09, 0.35, 10.0)
	elif drift_charge > 0.0:
		if drift_charge > 0.5:
			var k = minf(drift_charge, 2.0)
			vel += fwd * (4.0 + 4.0 * k)
		drift_charge = 0.0
	position += vel * delta

func _drill(delta: float) -> void:
	drilling = false
	var clank_at = Vector3.INF
	for d in stats.drills:
		var dir = transform.basis * d.dir
		var tip = position + transform.basis * d.pos
		var r = d.radius
		var c0 = terrain.world_to_cell(tip)
		var rr = ceili(r) + 1
		for dj in range(-rr, rr + 1):
			for di in range(-rr, rr + 1):
				var c = c0 + Vector2i(di, dj)
				if not terrain.is_solid(c) or clears(c):
					continue
				var cc = terrain.cell_center(c)
				if Vector2(cc.x - tip.x, cc.z - tip.z).length() > r + 0.35:
					continue
				# Only chew what's in front of the bit, not walls we scrape past.
				if (cc - position).dot(dir) < 0.2:
					continue
				var res = terrain.damage(c, d.power * delta, d.tier)
				if res >= 0:
					drilling = true
					if randf() < 18.0 * delta:
						fx.spawn(cc + Vector3(0, 0.8, 0), (position - cc).normalized() * 3.0 + Vector3(randf_range(-2, 2), 4.0, randf_range(-2, 2)),
							terrain.kind_color(terrain.get_kind(c)), 0.0, 0.14, 0.5)
				else:
					clank_at = tip
	if drilling:
		vel *= 1.0 - minf(1.0, stats.drill_drag * delta)
	if clank_at != Vector3.INF and randf() < 20.0 * delta:
		fx.spawn(clank_at + Vector3(0, 0.4, 0), Vector3(randf_range(-4, 4), 5.0, randf_range(-4, 4)), Color(1.0, 0.8, 0.4), 1.2, 0.07, 0.25)

# Lasers: a beam marched forward until it meets rock (damaged up to the
# laser's tier) or a mine (set off). Rockets: fly straight, blow up on rock,
# mines or after two seconds. Both run off the ship's boost / ammo.
func _weapons(delta: float, inp: Dictionary) -> void:
	var y = HOVER + alt + 0.3
	lasing = inp.get("laser", false) and boost > 0.0 and not stats.lasers.is_empty()
	if lasing:
		boost = maxf(0.0, boost - 22.0 * delta)
	for i in stats.lasers.size():
		var l = stats.lasers[i]
		var bm = beams[i]
		bm.visible = lasing
		if not lasing:
			continue
		var tip = position + transform.basis * l.pos + Vector3(0, y, 0)
		var dir = transform.basis * l.dir
		var end = tip + dir * l.range
		var t = 0.0
		var done = false
		while t < l.range and not done:
			var p = tip + dir * t
			var c = terrain.world_to_cell(p)
			if terrain.is_solid(c) and terrain.top_of(c) > y * 0.6:
				var res = terrain.damage(c, l.dps * delta, l.tier)
				if randf() < 25.0 * delta:
					fx.spawn(p, Vector3(randf_range(-3, 3), 4.0, randf_range(-3, 3)), Color(0.7, 1.0, 0.5) if res >= 0 else Color(1, 0.8, 0.4), 1.2, 0.08, 0.3)
				end = p
				done = true
			for m in track.mines:
				if m.timer <= 0.0 and Vector2(p.x - m.pos.x, p.z - m.pos.z).length() < 0.7:
					main.detonate_mine(m)
					end = p
					done = true
					break
			t += 0.4
		var length = tip.distance_to(end)
		bm.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(1, 1, maxf(length, 0.05))), (tip + end) * 0.5)
	var fire = inp.get("rocket", false)
	if fire and not _rocket_prev and ammo > 0 and not stats.launchers.is_empty():
		var l = stats.launchers[_next_launcher % stats.launchers.size()]
		_next_launcher += 1
		ammo -= 1
		var node = Node3D.new()
		node.top_level = true
		MeshKit.part(node, MeshKit.cyl(0.08, 0.08, 0.6, 6), MeshKit.mat(Color(0.85, 0.85, 0.8)), Vector3.ZERO, Vector3(90, 0, 0))
		MeshKit.part(node, MeshKit.cyl(0.07, 0.0, 0.5, 6), MeshKit.add_mat(Color(1.0, 0.6, 0.2, 0.9)), Vector3(0, 0, -0.5), Vector3(90, 0, 0), Vector3.ONE, false)
		add_child(node)
		var d = transform.basis * l.dir
		rockets.append({"pos": position + transform.basis * l.pos + Vector3(0, y, 0), "vel": d * 38.0 + vel * 0.6, "life": 2.0, "node": node})
	_rocket_prev = fire
	var keep = []
	for r in rockets:
		r.life -= delta
		r.pos += r.vel * delta
		r.node.global_transform = Transform3D(Basis.looking_at(-r.vel.normalized(), Vector3.UP), r.pos)
		if randf() < 30.0 * delta:
			fx.spawn(r.pos, -r.vel * 0.05 + Vector3(0, 1.0, 0), Color(0.35, 0.35, 0.35), 0.0, 0.18, 0.5, -1.0)
		var c = terrain.world_to_cell(r.pos)
		var boom = r.life <= 0.0 or (terrain.is_solid(c) and terrain.top_of(c) > r.pos.y * 0.6)
		for m in track.mines:
			if m.timer <= 0.0 and Vector2(r.pos.x - m.pos.x, r.pos.z - m.pos.z).length() < 1.0:
				main.detonate_mine(m)
				boom = true
		if boom:
			main._explode(r.pos, 2.8, 2)
			if position.distance_to(r.pos) < 3.2:
				take_hit(12.0)
			r.node.queue_free()
		else:
			keep.append(r)
	rockets = keep

# Circle vs. grid cells. Hard impacts drain the shield.
func _collide() -> void:
	var r = stats.radius * 0.9
	var c0 = terrain.world_to_cell(position)
	var half = terrain.cell * 0.5
	var worst = 0.0
	var hit_at = Vector3.ZERO
	for pass_i in 2:
		for dj in range(-2, 3):
			for di in range(-2, 3):
				var c = c0 + Vector2i(di, dj)
				if not terrain.is_solid(c) or clears(c):
					continue
				var cc = terrain.cell_center(c)
				var px = clampf(position.x, cc.x - half, cc.x + half)
				var pz = clampf(position.z, cc.z - half, cc.z + half)
				var d = Vector2(position.x - px, position.z - pz)
				var dist = d.length()
				if dist >= r:
					continue
				var n = d / dist if dist > 0.0001 else Vector2(-sin(heading), -cos(heading))
				position.x += n.x * (r - dist)
				position.z += n.y * (r - dist)
				var vn = vel.x * n.x + vel.z * n.y
				if vn < 0.0:
					vel.x -= n.x * vn * 1.3
					vel.z -= n.y * vn * 1.3
					if -vn > worst:
						worst = -vn
						hit_at = Vector3(px, 0.7, pz)
	if worst > IMPACT_SAFE:
		take_hit((worst - IMPACT_SAFE) * IMPACT_DAMAGE * stats.impact)
		fx.burst(hit_at, Color(1.0, 0.75, 0.4), int(clampf(worst, 4, 16)), 7.0, 1.2, 0.08, 0.35)

func take_hit(amount: float) -> void:
	hit_flash = 1.0
	if exposed:
		stall = minf(0.6, 0.15 + amount * 0.01)
		return
	shield -= amount
	if shield <= 0.0:
		shield = 0.0
		exposed = true
		main.notify("SHIELD DOWN", Color(1.0, 0.3, 0.3))
		fx.burst(position + Vector3(0, 1, 0), Color(0.5, 0.7, 1.0), 30, 8.0, 3.0, 0.1, 0.6, 4.0)

# Checkpoint nanobots: full shield, back in the race.
func restore() -> void:
	var was_exposed = exposed
	shield = stats.shield
	exposed = false
	charges = stats.charges
	ammo = stats.ammo
	for k in 40:
		var a = randf() * TAU
		var p = position + Vector3(cos(a) * 1.4, randf_range(0.2, 1.6), sin(a) * 1.4)
		fx.spawn(p, Vector3(-sin(a) * 5.0, randf_range(0.5, 2.0), cos(a) * 5.0) + vel * 0.8, Color(0.3, 1.0, 0.55), 1.2, 0.07, 0.7, 0.0)
	if was_exposed:
		main.notify("SHIELD RESTORED", Color(0.3, 1.0, 0.55))

func _animate(delta: float, inp: Dictionary) -> void:
	if stats.regen > 0.0 and not exposed:
		shield = minf(stats.shield, shield + stats.regen * delta)
	_steer_vis = lerpf(_steer_vis, inp.steer, minf(1.0, 8.0 * delta))
	var speed = vel.length()
	model.position.y = HOVER + alt + sin(_t * 2.6) * 0.05
	model.rotation.z = -_steer_vis * 0.3 * clampf(speed / 15.0, 0.0, 1.0)
	model.rotation.x = -_throttle * 0.04 - clampf(vy * 0.03, -0.25, 0.25)
	model.rotation.y = lerpf(model.rotation.y, _steer_vis * 0.3 if drifting else 0.0, minf(1.0, 6.0 * delta))
	for f in rig.flames:
		var flen = 0.25 + _throttle * 0.6 + (1.0 if boosting else 0.0) + randf() * 0.15
		f.scale = Vector3(1, 1, flen)
	_flap = lerpf(_flap, 1.0 if _braking or drifting else 0.0, minf(1.0, 10.0 * delta))
	for f in rig.brakes:
		f.rotation.x = deg_to_rad(65.0) * _flap
	for sp in rig.spinners:
		sp[0].rotate_object_local(sp[1], sp[2] * delta * (2.5 if drilling else 1.0))
	var sm = rig.shield.material_override
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	rig.shield.visible = not exposed
	sm.set_shader_parameter("strength", 0.04 + 0.16 * shield / stats.shield)
	sm.set_shader_parameter("hit", hit_flash)
	var strength = 0.3 + 0.7 * _throttle + (0.6 if boosting else 0.0)
	for i in trails.size():
		trails[i].push(rig.nozzles[i].global_position, delta, strength if speed > 1.0 else 0.0)
	if exposed:
		_fx_cd -= delta
		if _fx_cd <= 0.0:
			_fx_cd = 0.06
			fx.spawn(position + Vector3(0, 0.9, 0), Vector3(randf_range(-0.5, 0.5), 2.0, randf_range(-0.5, 0.5)) - vel * 0.2, Color(0.15, 0.15, 0.15), 0.0, 0.3, 0.8, -1.0)
