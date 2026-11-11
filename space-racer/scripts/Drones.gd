extends Node3D

# Hostile drones in the expedition. Guards hang around wrecks and hulls (two
# at the ones worth having), patrols circle Moss and Magma. They idle on
# station until you come close, then chase, fire slow red bolts and ram.
# Get far enough away and they go back. Every tool hurts them (the weapons'
# world adapter calls touch/blast/target/pull here); dead drones drop ore.

const MeshKit = preload("res://scripts/MeshKit.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const SPEED = 13.0
const SIGHT = 26.0
const LEASH = 60.0
const HP = 30.0
const RESPAWN = 240.0      # seconds until a dead drone's post is filled again
const RESPAWN_AWAY = 150.0 # ...and only while you're this far off

var mining
var drones = []    # {pos, vel, hp, anchor, radius, ang, state, cd, hit_cd, node, eye}
var bolts = []     # {pos, vel, life, node}
var kills = 0
var _body: Material
var _eye: Material
var _bolt_mesh: Mesh
var _bolt_mat: Material

func setup(m) -> void:
	mining = m
	_body = MeshKit.mat(Color(0.14, 0.13, 0.15), 0.0, 0.4, 0.6)
	_eye = MeshKit.mat(Color(1.0, 0.15, 0.1), 2.0)
	_bolt_mesh = MeshKit.sphere(0.22, 6, 3)
	_bolt_mat = MeshKit.add_mat(Color(1.0, 0.25, 0.15, 0.95))
	for s in mining.sites:
		if s.type == "wreck" or s.type == "hull":
			var n = 2 if s.data.has("blueprint") or s.type == "hull" else 1
			for k in n:
				spawn(s.pos, 6.0 + k * 3.0)
	for pl in mining.planets:
		if pl.def.name in ["Moss", "Magma"]:
			for k in (3 if pl.def.name == "Moss" else 4):
				spawn(pl.centre, pl.def.radius + 25.0 + k * 6.0, TAU * k / 4.0)

func spawn(anchor: Vector2, radius: float, ang: float = randf() * TAU) -> void:
	var made = _model()
	var pos = anchor + Vector2(cos(ang), sin(ang)) * radius
	made[0].position = Vector3(pos.x, pos.y, 0.8)
	drones.append({"pos": pos, "vel": Vector2.ZERO, "hp": HP, "anchor": anchor, "radius": radius, "ang": ang,
		"state": "idle", "cd": randf() * 1.5, "hit_cd": 0.0, "node": made[0], "eye": made[1], "respawn": 0.0})

# A replacement turns up on the dead one's post, out of sight.
func _revive(d: Dictionary) -> void:
	var made = _model()
	d.pos = d.anchor + Vector2(cos(d.ang), sin(d.ang)) * d.radius
	made[0].position = Vector3(d.pos.x, d.pos.y, 0.8)
	d.node = made[0]
	d.eye = made[1]
	d.hp = HP
	d.vel = Vector2.ZERO
	d.state = "idle"

func _model() -> Array:
	var node = Node3D.new()
	MeshKit.part(node, MeshKit.sphere(0.7, 4, 2), _body, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
	for s in [-1.0, 1.0]:
		MeshKit.part(node, MeshKit.box(Vector3(0.9, 0.08, 0.5)), _body, Vector3(s * 0.8, 0, 0), Vector3(0, 0, s * 20.0))
	var eye = MeshKit.part(node, MeshKit.sphere(0.25, 6, 3), _eye, Vector3(0, 0, 0.45), Vector3.ZERO, Vector3.ONE, false)
	add_child(node)
	return [node, eye]

func alive() -> Array:
	return drones.filter(func(d): return d.hp > 0.0)

func step(delta: float) -> void:
	var ship = mining.miner.pos
	for d in drones:
		if d.hp <= 0.0:
			d.respawn -= delta
			if d.respawn <= 0.0 and d.anchor.distance_to(ship) > RESPAWN_AWAY:
				_revive(d)
			continue
		var dist = d.pos.distance_to(ship)
		if dist > 320.0:
			continue
		d.hit_cd -= delta
		var target: Vector2
		match d.state:
			"idle":
				d.ang += 0.5 * delta
				target = d.anchor + Vector2(cos(d.ang), sin(d.ang)) * d.radius
				if dist < SIGHT:
					d.state = "chase"
					Sfx.play("shield_down", -8.0, 2.2)
			"chase":
				# Hold off a few metres and shoot; leash back to the post.
				target = ship + (d.pos - ship).normalized() * 7.0
				if dist > LEASH or d.pos.distance_to(d.anchor) > LEASH * 1.5:
					d.state = "idle"
				d.cd -= delta
				if d.cd <= 0.0 and dist < 32.0:
					d.cd = 1.5 + randf() * 0.5
					_fire(d, ship + mining.miner.vel * (dist / 22.0) * 0.6)
		d.vel = d.vel.lerp((target - d.pos).limit_length(1.0) * SPEED, minf(1.0, 2.5 * delta))
		d.pos += d.vel * delta
		# Rock pushes them back out.
		for pl in mining.planets_near(d.pos, 2.0):
			if pl.terrain.is_solid(pl.terrain.world_to_cell(pl.local(d.pos))):
				d.pos += (d.pos - pl.centre).normalized() * 8.0 * delta
		# Ramming.
		if dist < mining.miner.stats.radius + 0.9:
			mining.miner.take_hit(6.0)
			var n = (ship - d.pos).normalized()
			mining.miner.vel += n * 6.0
			d.vel -= n * 10.0
			damage(d, 8.0)
		d.node.position = Vector3(d.pos.x, d.pos.y, 0.8 + sin(Time.get_ticks_msec() * 0.004 + d.ang) * 0.15)
		d.node.rotation.z = atan2(d.vel.y, d.vel.x) - PI * 0.5 if d.vel.length() > 0.5 else d.node.rotation.z
		d.eye.visible = d.state == "chase" or fmod(Time.get_ticks_msec() * 0.001, 1.0) < 0.5
	_bolts(delta, ship)

func _fire(d: Dictionary, at: Vector2) -> void:
	var node = MeshInstance3D.new()
	node.mesh = _bolt_mesh
	node.material_override = _bolt_mat
	add_child(node)
	bolts.append({"pos": d.pos, "vel": (at - d.pos).normalized() * 22.0, "life": 3.0, "node": node})
	Sfx.play("drop", -10.0, 2.0)

func _bolts(delta: float, ship: Vector2) -> void:
	var keep = []
	for b in bolts:
		b.life -= delta
		b.pos += b.vel * delta
		b.node.position = Vector3(b.pos.x, b.pos.y, 0.8)
		var gone = b.life <= 0.0
		if b.pos.distance_to(ship) < mining.miner.stats.radius + 0.4:
			mining.miner.take_hit(8.0)
			gone = true
		elif mining.solid_at(b.pos):
			gone = true
		if gone:
			mining.main.fx.burst(Vector3(b.pos.x, b.pos.y, 1.0), Color(1.0, 0.3, 0.2), 6, 4.0, 1.2, 0.08, 0.3, 0.0)
			b.node.queue_free()
		else:
			keep.append(b)
	bolts = keep

func damage(d: Dictionary, amount: float) -> void:
	if d.hp <= 0.0:
		return
	d.hp -= amount
	d.state = "chase"
	mining.main.fx.burst(Vector3(d.pos.x, d.pos.y, 1.0), Color(1.0, 0.8, 0.4), 5, 5.0, 1.2, 0.08, 0.3, 0.0)
	if d.hp <= 0.0:
		kills += 1
		d.respawn = RESPAWN
		mining.main.fx.burst(Vector3(d.pos.x, d.pos.y, 1.0), Color(1.0, 0.5, 0.15), 30, 10.0, 1.2, 0.18, 0.6, 0.0)
		mining.main.fx.burst(Vector3(d.pos.x, d.pos.y, 1.0), Color(0.15, 0.14, 0.16), 14, 6.0, 0.0, 0.3, 0.9, 0.0)
		Sfx.play("small_boom")
		d.node.queue_free()
		for k in 2 + randi() % 2:
			mining.spawn_pickup(d.pos, "metal" if randf() < 0.7 else "crystal")
		mining.main.contract_event("drone", {})

# --- hooks for the weapons' world adapter ------------------------------------

# A shot touching a drone hurts it (a beam keeps hurting it, in ticks).
func touch(p: Vector2, r: float) -> bool:
	for d in drones:
		if d.hp > 0.0 and d.pos.distance_to(p) < r + 0.8:
			if d.hit_cd <= 0.0:
				d.hit_cd = 0.12
				damage(d, 7.0)
			return true
	return false

func blast(p: Vector2, r: float) -> void:
	for d in drones:
		if d.hp > 0.0 and d.pos.distance_to(p) < r + 1.0:
			damage(d, 35.0)

func nearest(p: Vector2, r: float):
	var best = null
	var bd = r
	for d in drones:
		if d.hp > 0.0 and d.pos.distance_to(p) < bd:
			bd = d.pos.distance_to(p)
			best = d.pos
	return best

func pull(p: Vector2, r: float, k: float) -> void:
	for d in drones:
		if d.hp > 0.0 and d.pos.distance_to(p) < r:
			d.vel += (p - d.pos).normalized() * k * 0.6
