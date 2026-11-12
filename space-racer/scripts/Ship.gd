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
const WeaponsScript = preload("res://scripts/Weapons.gd")
const Worlds = preload("res://scripts/Worlds.gd")
const Sfx = preload("res://scripts/Sfx.gd")

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
const ENGINE_HEARD = 40.0  # rivals' engines are heard within this many metres
var rival = false          # AI racer: no input, no notifications
var distance = 0.0         # centreline samples travelled this race (for standings)
var down_left = 0.0        # rivals: seconds until back on track after a wreck
var pilot = "YOU"
var finish_time = -1.0
var sfx_on: bool:
	get:
		return not rival
var progress_idx = 0
var zap_cd = 0.0           # weapons can only hurt a racer this often
var aggro = 1.0            # rivals: how keen they are to use their tools
var pace = 1.0             # rivals: throttle they race at (Easy holds back)
var _ai_cd = {}            # rivals: per-tool cooldowns
var _ai_hold = {}          # rivals: tool keys held this frame

var _t = 0.0
var _steer_vis = 0.0
var _throttle = 0.0
var _fx_cd = 0.0
var weapons
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
	var dmg = ShipBuilder.with_damage(lo, null if rival or main == null else main)
	stats = Parts.stats(dmg)
	if model != null:
		model.queue_free()
	for tr in trails:
		tr.queue_free()
	trails.clear()
	model = ShipBuilder.build(dmg, stats)
	add_child(model)
	rig = model.get_meta("rig")
	sockets = model.get_meta("sockets")
	shield = stats.shield
	boost_max = 100.0 * stats.boost
	boost = boost_max
	charges = stats.charges
	exposed = false
	if weapons == null:
		weapons = WeaponsScript.new()
		add_child(weapons)
	weapons.setup(self, Worlds.RaceWorld.new(main, self), stats)
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
		"drop": Input.is_action_pressed("drop"),
		"warp": Input.is_action_pressed("warp"),
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
	var out = {"throttle": pace, "brake": absf(diff) > 0.5 and vel.length() > 12.0, "steer": clampf(diff * 2.5, -1.0, 1.0),
		"boost": absf(diff) < 0.15 and boost > boost_max * 0.4, "jump": jump}
	if rival:
		_ai_tools(out, absf(diff), ahead)
	return out

# Rivals use whatever tools they've got: cut at whoever is in front, lob
# missiles down the straight, drop bombs on whoever is tailing them, dash
# when the road ahead is clear. Cooldowns and a little hesitation keep it fair.
func _ai_tools(out: Dictionary, turn: float, ahead: int) -> void:
	# Nobody opens fire while the field is still bunched up off the line.
	if main.race_time < 3.0:
		return
	var delta = get_process_delta_time()
	for k in _ai_cd:
		_ai_cd[k] -= delta
	# Weapons fire on a fresh press, so let go for a frame after each shot.
	for k in ["rocket", "drop", "warp"]:
		if _ai_hold.get(k, false):
			_ai_hold[k] = false
			out[k] = false
	var fwd = forward()
	var side = Vector3(fwd.z, 0.0, -fwd.x)
	var front = null
	var front_d = 1e9
	var behind = null
	for s in [main.ship] + main.rivals:
		if s == self or (s.rival and s.down_left > 0.0) or (not s.rival and main._respawn_left > 0.0):
			continue
		var to = s.position - position
		var f = to.dot(fwd)
		var l = absf(to.dot(side))
		if f > 1.0 and l < 2.5 + f * 0.25 and f < front_d:
			front = s
			front_d = f
		elif f < -2.0 and f > -14.0 and l < 3.0:
			behind = s
	var lat = 0.0
	if front != null:
		lat = absf((front.position - position).dot(side))
	if not stats.lasers.is_empty():
		var reach = 0.0
		for l in stats.lasers:
			reach = maxf(reach, l.range)
		var on_target = front != null and front_d < reach * 1.1 and lat < 1.6
		out.laser = (on_target and _ai_cd.get("laser", 0.0) <= 0.0) or (ahead == terrain.BARRIER and stats.drill_tier == 0)
		if on_target and randf() < 0.4 * delta / aggro:
			_ai_cd["laser"] = 1.5    # breathe now and then
	if not stats.launchers.is_empty() and weapons.ammo > 0 and _ai_cd.get("rocket", 0.0) <= 0.0 and front != null:
		var homing = stats.launchers[0].prog.get("homing", false)
		if front_d < 38.0 and (homing or lat < 1.5 + front_d * 0.04):
			out.rocket = true
			_ai_hold["rocket"] = true
			_ai_cd["rocket"] = (2.5 + randf() * 2.5) / aggro
	if not stats.droppers.is_empty() and weapons.bombs > 0 and _ai_cd.get("drop", 0.0) <= 0.0 and behind != null:
		out.drop = true
		_ai_hold["drop"] = true
		_ai_cd["drop"] = (3.0 + randf() * 2.0) / aggro
	if not stats.warp.is_empty() and _ai_cd.get("warp", 0.0) <= 0.0 and turn < 0.08 and ahead != terrain.BARRIER and vel.length() > 10.0:
		out.warp = true
		_ai_hold["warp"] = true
		_ai_cd["warp"] = 4.0 + randf() * 3.0

# Your own weapons always make noise; a rival's only when it's close by.
func loud_weapons() -> bool:
	return not rival or (main.ship != null and position.distance_to(main.ship.position) < 30.0)

func _process(delta):
	if model == null:
		return
	delta = minf(delta, 1.0 / 30.0)
	_t += delta
	zap_cd -= delta
	var inp = _input_state()
	if stall > 0.0:
		stall -= delta
		inp.throttle = 0.0
		inp.steer = 0.0
		heading += delta * 9.0 * stall
	_hop(delta, inp)
	_drive(delta, inp)
	_drill(delta)
	weapons.update(delta, inp)
	_collide()
	_animate(delta, inp)

func airborne() -> bool:
	return alt > 0.05

func _hop(delta: float, inp: Dictionary) -> void:
	var pressed = inp.jump and not _jump_prev
	_jump_prev = inp.jump
	if pressed and not airborne() and stall <= 0.0:
		vy = stats.jump
		if sfx_on:
			Sfx.play("hop")
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
		if d.prog.get("orbit", false):
			continue
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
	if sfx_on:
		Sfx.play("hit", clampf(-10.0 + amount * 0.5, -10.0, 4.0))
	if exposed:
		# No shield left: a real hit ends you.
		if amount >= 6.0:
			if rival:
				main.rival_destroyed(self)
			else:
				main.ship_destroyed()
			return
		stall = minf(0.6, 0.15 + amount * 0.01)
		return
	shield -= amount
	if shield <= 0.0:
		shield = 0.0
		exposed = true
		if not rival:
			main.notify("SHIELD DOWN", Color(1.0, 0.3, 0.3))
			Sfx.play("shield_down")
		fx.burst(position + Vector3(0, 1, 0), Color(0.5, 0.7, 1.0), 30, 8.0, 3.0, 0.1, 0.6, 4.0)

# Checkpoint nanobots: full shield, back in the race.
func restore() -> void:
	var was_exposed = exposed
	shield = stats.shield
	exposed = false
	charges = stats.charges
	if weapons != null:
		weapons.refill()
	for k in 40:
		var a = randf() * TAU
		var p = position + Vector3(cos(a) * 1.4, randf_range(0.2, 1.6), sin(a) * 1.4)
		fx.spawn(p, Vector3(-sin(a) * 5.0, randf_range(0.5, 2.0), cos(a) * 5.0) + vel * 0.8, Color(0.3, 1.0, 0.55), 1.2, 0.07, 0.7, 0.0)
	if was_exposed and not rival:
		main.notify("SHIELD RESTORED", Color(0.3, 1.0, 0.55))

func _animate(delta: float, inp: Dictionary) -> void:
	if stats.regen > 0.0 and not exposed:
		shield = minf(stats.shield, shield + stats.regen * delta)
	_steer_vis = lerpf(_steer_vis, inp.steer, minf(1.0, 8.0 * delta))
	var speed = vel.length()
	if sfx_on:
		var sp = clampf(speed / maxf(stats.top, 1.0), 0.0, 1.5)
		Sfx.loop("engine", true, -10.0 + _throttle * 5.0 + sp * 3.0, 0.6 + sp * 1.0)
		Sfx.loop("boost", boosting, -4.0)
		Sfx.loop("skid", drifting, -6.0, 0.8 + sp * 0.4)
		Sfx.loop("drill", drilling, -4.0)
	elif rival and main.ship != null and main.ship != self:
		# Rivals are heard when they're close: louder nearer you, panned by
		# where they are on screen.
		var d = position.distance_to(main.ship.position)
		var sp = clampf(speed / maxf(stats.top, 1.0), 0.0, 1.5)
		Sfx.loop_at("rival%d" % get_instance_id(), "engine", position, d < ENGINE_HEARD and down_left <= 0.0,
			-12.0 + _throttle * 3.0 - d * 0.55, 0.7 + sp * 0.9 + (get_instance_id() % 7) * 0.02)
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

# ---------------------------------------------------------------- weapons host

func pos2() -> Vector2:
	return Vector2(position.x, position.z)

func vel2() -> Vector2:
	return Vector2(vel.x, vel.z)

func l2w(local: Vector3) -> Vector2:
	var p = position + transform.basis * local
	return Vector2(p.x, p.z)

func d2w(d: Vector3) -> Vector2:
	var w = transform.basis * d
	return Vector2(w.x, w.z).normalized()

func spend(amount: float) -> bool:
	if boost < amount:
		return false
	boost -= amount
	return true

func add_vel2(v: Vector2) -> void:
	vel += Vector3(v.x, 0.0, v.y)

func teleport2(p: Vector2) -> void:
	position = Vector3(p.x, 0.0, p.y)
	for tr in trails:
		tr.clear_points()

func fx_height() -> float:
	return HOVER + alt + 0.3
