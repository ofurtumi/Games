extends Node3D

# Runs a ship's tools: lasers, missile pods, bomb bays, orbiting drills and
# the warp part, each following the program wired up in its sub-grid (see
# Parts.NODES / Parts.program_of). Everything is simulated in 2D so the same code works on the
# race track (x, z) and in the side-view mining mode (x, y); the `world`
# adapter turns 2D points into terrain hits, blasts, targets and visuals.
#
# The host (Ship or Miner) provides: pos2(), vel2(), l2w(local) -> Vector2,
# d2w(local_dir) -> Vector2, spend(amount) -> bool, add_vel2(v),
# teleport2(p), take_hit(amount), fx_height().

const Parts = preload("res://scripts/Parts.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")

var host
var world
var stats = {}
var ammo = 0
var bombs = 0
var beams = []        # one per beam: {laser, angle, prog, mesh, tip, rock, cd, n}
var shots = []        # {pos, vel, life, prog, phase_left, timer, stuck, child, ang, node, kind}
var wells = []        # {pos, t}
var balls = []        # {drill, ang, node, chain}
var warp_cd = 0.0
var _prev = {}
var _laser_cd = {}
var _beam_mat: Material

func setup(h, w, st: Dictionary) -> void:
	host = h
	world = w
	stats = st
	for b in beams:
		b.mesh.queue_free()
		b.tip.queue_free()
		b.rock.queue_free()
	for b in balls:
		b.node.queue_free()
		b.chain.queue_free()
	for s in shots:
		s.node.queue_free()
	beams.clear()
	balls.clear()
	shots.clear()
	_beam_mat = MeshKit.add_mat(Color(0.5, 1.0, 0.5, 0.9))
	for l in stats.lasers:
		var before = beams.size()
		_add_beams(l, l.prog, 0.0)
		for k in range(before, beams.size()):
			beams[k].n = beams.size() - before
	for d in stats.drills:
		if d.prog.get("orbit", false):
			var ball = Node3D.new()
			ball.top_level = true
			var steel = MeshKit.mat(Color(0.6, 0.62, 0.66), 0.0, 0.3, 0.8)
			MeshKit.part(ball, MeshKit.sphere(0.45, 8, 4), steel, Vector3.ZERO)
			for k in 6:
				var a = k * TAU / 6.0
				MeshKit.part(ball, MeshKit.cyl(0.0, 0.12, 0.35, 4), steel, Vector3(cos(a) * 0.5, 0, sin(a) * 0.5), Vector3(0, -rad_to_deg(a), -90))
			add_child(ball)
			var chain = MeshInstance3D.new()
			chain.mesh = MeshKit.box(Vector3(0.07, 0.07, 1.0))
			chain.material_override = MeshKit.mat(Color(0.2, 0.2, 0.22))
			chain.top_level = true
			add_child(chain)
			balls.append({"drill": d, "ang": 0.0, "node": ball, "chain": chain})
	refill()

# A laser's program can fork: one beam per branch, fanned out, each with
# the mods and payload of its own branch.
func _add_beams(l: Dictionary, prog: Dictionary, angle: float) -> void:
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		for i in forks.size():
			_add_beams(l, forks[i], angle + (i - (forks.size() - 1) * 0.5) * 0.4)
		return
	var phase = prog.get("phase", false)
	var fast = prog.get("fast", false)
	var col = Color(0.75, 0.45, 1.0, 0.9) if phase else Color(0.5, 1.0, 0.5, 0.9)
	if fast:
		col = col.lightened(0.35)
	var w = 0.32 if fast else 0.2
	var mesh = _beam_mesh(w, MeshKit.add_mat(col))
	# The stretch inside rock for a phasing beam: thin and faint.
	var rock = _beam_mesh(w * 0.5, MeshKit.add_mat(Color(col.r, col.g, col.b, 0.35)))
	var tip = MeshInstance3D.new()
	tip.mesh = MeshKit.sphere(0.35 if prog.get("payload", "") != "" else 0.15, 8, 4)
	tip.material_override = MeshKit.add_mat(Color(1.0, 0.6, 0.2, 0.95) if prog.get("payload", "") != "" else col)
	tip.top_level = true
	tip.visible = false
	add_child(tip)
	beams.append({"laser": l, "angle": angle, "prog": prog, "mesh": mesh, "rock": rock, "tip": tip, "cd": 0.0, "n": 1})

func _beam_mesh(w: float, m: Material) -> MeshInstance3D:
	var bm = MeshInstance3D.new()
	bm.mesh = MeshKit.box(Vector3(w, w, 1.0))
	bm.material_override = m
	bm.top_level = true
	bm.visible = false
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bm)
	return bm

func refill() -> void:
	ammo = stats.ammo
	bombs = stats.bombs

func _edge(name: String, held: bool) -> bool:
	var was = _prev.get(name, false)
	_prev[name] = held
	return held and not was

func _place(node: Node3D, a: Vector2, b: Vector2, h: float) -> void:
	var a3 = world.to3(a, h)
	var b3 = world.to3(b, h)
	var seg = maxf(a3.distance_to(b3), 0.05)
	node.global_transform = Transform3D(Basis.looking_at((b3 - a3).normalized() if seg > 0.06 else Vector3.FORWARD, world.up()) * Basis.from_scale(Vector3(1, 1, seg)), (a3 + b3) * 0.5)

func update(delta: float, inp: Dictionary) -> void:
	var h = host.fx_height()
	_lasers(delta, inp.get("laser", false), h)
	if _edge("rocket", inp.get("rocket", false)) and ammo > 0 and not stats.launchers.is_empty():
		var l = stats.launchers[ammo % stats.launchers.size()]
		ammo -= 1
		_fire(l.prog, host.l2w(l.pos), host.d2w(l.dir), host.vel2() * 0.6, "missile", 2.5, 0)
	if _edge("drop", inp.get("drop", false)) and bombs > 0 and not stats.droppers.is_empty():
		var d = stats.droppers[bombs % stats.droppers.size()]
		bombs -= 1
		var prog = d.prog.duplicate(true)
		prog.timer = true
		_fire(prog, host.l2w(d.pos), host.vel2().normalized() if host.vel2().length() > 0.1 else Vector2.RIGHT, host.vel2() * 0.3, "bomb", 0.25, 0, 0.0)
	warp_cd = maxf(0.0, warp_cd - delta)
	if _edge("warp", inp.get("warp", false)) and not stats.warp.is_empty() and warp_cd <= 0.0 and host.spend(18.0):
		warp_cd = stats.warp.cooldown
		var fwd = host.d2w(Vector3(0, 0, 1))
		var from = host.pos2()
		world.burst(from, Color(0.75, 0.4, 1.0) if stats.warp.type == "blink" else Color(0.3, 0.85, 1.0), 20, 6.0, h)
		if stats.warp.type == "dash":
			host.add_vel2(fwd * 18.0)
		else:
			# Blink: the furthest clear spot up to nine metres ahead.
			for k in range(9, 1, -1):
				var to = from + fwd * k
				if not world.solid(to):
					host.teleport2(to)
					world.burst(to, Color(0.75, 0.4, 1.0), 24, 6.0, h)
					break
	_update_shots(delta, h)
	_update_balls(delta, h)
	_update_wells(delta, h)

func _lasers(delta: float, held: bool, h: float) -> void:
	var on = held and not stats.lasers.is_empty() and host.spend(22.0 * delta)
	for b in beams:
		b.mesh.visible = on
		b.tip.visible = on
		b.rock.visible = false
		if not on:
			continue
		var l = b.laser
		var prog = b.prog
		var tip = host.l2w(l.pos)
		var dir = host.d2w(l.dir).rotated(b.angle)
		var rng = l.range * (1.6 if prog.get("fast", false) else 1.0)
		var phase = 6.0 if prog.get("phase", false) else 0.0
		var end = tip + dir * rng
		var hit = false
		var t = 0.0
		var in_rock = 0.0
		var rock_from = Vector2.INF
		var rock_to = Vector2.INF
		while t < rng:
			var p = tip + dir * t
			if world.touch(p, 0.7):
				end = p
				hit = true
				break
			if world.solid(p):
				if in_rock < phase:
					if rock_from == Vector2.INF:
						rock_from = p
					rock_to = p
					in_rock += 0.4
				else:
					end = p
					hit = true
					break
			elif in_rock > 0.0:
				# Out the other side of the rock: burn whatever is next.
				phase = 0.0
			t += 0.4
		# Split beams share the laser's power.
		var dps = l.dps * (1.0 if b.n == 1 else 0.7)
		if hit:
			var res = world.hit(end, dps * delta, l.tier)
			if randf() < 25.0 * delta:
				world.spark(end, Color(0.7, 1.0, 0.5) if res >= 0 else Color(1, 0.8, 0.4), h)
		# The beam carries its payload to wherever it ends.
		if prog.get("payload", "") != "":
			b.cd -= delta
			if b.cd <= 0.0:
				b.cd = 0.8
				_payload(prog, end, h, 0, -dir)
		_place(b.mesh, tip, end, h)
		b.tip.global_position = world.to3(end, h)
		b.tip.scale = Vector3.ONE * (0.8 + 0.3 * sin(Time.get_ticks_msec() * 0.03))
		if rock_from != Vector2.INF:
			b.rock.visible = true
			_place(b.rock, rock_from, rock_to, h + 0.15)

# Launch along `dir`. A program that forks fires one shot per branch, fanned
# out; anything without a payload gets a plain bomb so it still goes off.
func _fire(prog: Dictionary, pos: Vector2, dir: Vector2, base_vel: Vector2, kind: String, life: float, depth: int, speed: float = 34.0) -> void:
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		for i in forks.size():
			var a = (i - (forks.size() - 1) * 0.5) * 0.3
			_fire(forks[i], pos, dir.rotated(a), base_vel, kind, life, depth, speed)
		return
	var p = prog.duplicate(true)
	if p.get("payload", "") == "":
		p.payload = "bomb" if depth == 0 else "mini"
	var spd = speed * (1.8 if p.get("fast", false) else 1.0)
	var s = _spawn(pos, dir * spd + base_vel, p, kind, life, depth > 0)
	s.depth = depth
	if kind == "bomb":
		s.wait = 1.6

func _spawn(pos: Vector2, vel: Vector2, prog: Dictionary, kind: String, life: float, child: bool = false) -> Dictionary:
	var node = Node3D.new()
	node.top_level = true
	if kind == "bomb":
		MeshKit.part(node, MeshKit.sphere(0.25, 8, 4), MeshKit.mat(Color(0.15, 0.15, 0.17), 0.0, 0.4, 0.6), Vector3.ZERO)
		MeshKit.part(node, MeshKit.sphere(0.09, 6, 3), MeshKit.mat(Color(1.0, 0.2, 0.1), 1.5), Vector3(0, 0.22, 0), Vector3.ZERO, Vector3.ONE, false)
	else:
		var sc = 0.6 if child else 1.0
		MeshKit.part(node, MeshKit.cyl(0.08 * sc, 0.08 * sc, 0.6 * sc, 6), MeshKit.mat(Color(0.85, 0.85, 0.8)), Vector3.ZERO, Vector3(90, 0, 0))
		MeshKit.part(node, MeshKit.cyl(0.07 * sc, 0.0, 0.5 * sc, 6), MeshKit.add_mat(Color(1.0, 0.6, 0.2, 0.9)), Vector3(0, 0, -0.5 * sc), Vector3(90, 0, 0), Vector3.ONE, false)
	add_child(node)
	var s = {"pos": pos, "vel": vel, "life": life, "prog": prog, "phase_left": 6.0 if prog.get("phase", false) else 0.0,
		"wait": 2.0, "stuck": false, "child": child, "depth": 0, "ang": randf() * TAU, "node": node, "kind": kind, "seek": 0.0, "target": null}
	shots.append(s)
	return s

func _update_shots(delta: float, h: float) -> void:
	var keep = []
	for s in shots:
		var boom = false
		if s.stuck:
			s.wait -= delta
			boom = s.wait <= 0.0
			if randf() < 6.0 * delta:
				world.spark(s.pos, Color(1.0, 0.25, 0.1), h)
		elif s.prog.get("orbit", false):
			s.ang += 4.5 * delta
			s.pos = host.pos2() + Vector2(cos(s.ang), sin(s.ang)) * 3.0
			s.life -= delta * 0.25
			boom = world.touch(s.pos, 0.8) or s.life <= 0.0
		else:
			if s.prog.get("homing", false):
				s.seek -= delta
				if s.seek <= 0.0:
					s.seek = 0.25
					s.target = world.target(s.pos, 24.0)
				if s.target != null:
					var speed = maxf(s.vel.length(), 14.0)
					s.vel = s.vel.lerp((s.target - s.pos).normalized() * speed, minf(1.0, 4.0 * delta))
			s.pos += s.vel * delta
			s.life -= delta
			if world.touch(s.pos, 0.8):
				boom = true
			elif world.solid(s.pos):
				if s.phase_left > 0.0:
					s.phase_left -= s.vel.length() * delta
				elif s.prog.get("timer", false):
					s.stuck = true
				else:
					boom = true
			if s.life <= 0.0 and not boom:
				if s.prog.get("timer", false) and not s.stuck:
					s.stuck = true
					s.vel = Vector2.ZERO
				elif not s.stuck:
					boom = true
			if randf() < 30.0 * delta and s.kind == "missile":
				world.smoke(s.pos, h)
		var p3 = world.to3(s.pos, h)
		if s.vel.length() > 0.1 and not s.stuck:
			var v3 = world.to3(s.pos + s.vel.normalized(), h) - p3
			s.node.global_transform = Transform3D(Basis.looking_at(-v3.normalized(), world.up()), p3)
		else:
			s.node.global_position = p3
		if boom:
			_payload(s.prog, s.pos, h, s.depth, s.vel.normalized() if s.vel.length() > 0.1 else Vector2.RIGHT)
			s.node.queue_free()
		else:
			keep.append(s)
	shots = keep

func _payload(prog: Dictionary, p: Vector2, h: float, depth: int = 0, dir: Vector2 = Vector2.RIGHT) -> void:
	match prog.payload:
		"bomb":
			world.blast(p, 2.6, 2)
			_self_hit(p, 3.0, 10.0)
		"mini":
			world.blast(p, 1.4, 2)
		"dig":
			world.blast(p, 2.0, 3)
			_self_hit(p, 2.5, 8.0)
		"cluster":
			world.blast(p, 1.2, 1)
			for k in 5:
				var a = TAU * k / 5.0
				_spawn(p, Vector2(cos(a), sin(a)) * 12.0, {"payload": "mini", "homing": true}, "missile", 1.4, true)
		"gravity":
			wells.append({"pos": p, "t": 3.0})
		"quench":
			world.quench(p, 3.5)
			world.burst(p, Color(0.85, 0.9, 0.95), 30, 5.0, h)
		_:
			world.burst(p, Color(1.0, 0.7, 0.3), 12, 6.0, h)
	# Whatever is wired after the payload launches from here.
	if depth < 3:
		var kids = prog.get("children", [])
		for i in kids.size():
			var a = (i - (kids.size() - 1) * 0.5) * 0.6
			_fire(kids[i], p - dir * 0.6, dir.rotated(a), Vector2.ZERO, "missile", 1.2, depth + 1, 16.0)

func _self_hit(p: Vector2, r: float, dmg: float) -> void:
	if host.pos2().distance_to(p) < r:
		host.take_hit(dmg)

func _update_balls(delta: float, h: float) -> void:
	for b in balls:
		b.ang += 3.2 * delta
		var p = host.pos2() + Vector2(cos(b.ang), sin(b.ang)) * 3.2
		var d = b.drill
		for k in 4:
			var q = p + Vector2(cos(k * PI * 0.5), sin(k * PI * 0.5)) * 0.5
			if world.solid(q):
				world.hit(q, d.power * 1.4 * delta, d.tier)
		world.touch(p, 0.9)
		if randf() < 8.0 * delta and world.solid(p + (p - host.pos2()).normalized() * 0.8):
			world.spark(p, Color(1.0, 0.8, 0.4), h)
		b.node.global_position = world.to3(p, h)
		b.node.rotate_y(9.0 * delta)
		_place(b.chain, host.pos2(), p, h)

func _update_wells(delta: float, h: float) -> void:
	var keep = []
	for w in wells:
		w.t -= delta
		world.pull(w.pos, 12.0, 30.0 * delta)
		if randf() < 30.0 * delta:
			var a = randf() * TAU
			world.swirl(w.pos, a, h)
		if w.t > 0.0:
			keep.append(w)
	wells = keep
