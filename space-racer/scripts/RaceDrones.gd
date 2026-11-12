extends Node3D

# Drone turrets hovering over the kerb on the later planets' tracks. Each
# keeps to its post off the edge of the track, turns to face whoever comes
# by and fires slow red bolts across the road at them (you and the rivals
# alike). Every tool hurts them (RaceWorld calls touch/blast/target/pull
# here); a drone you shoot down drops ore and counts for bounty contracts.
# A downed post is filled again a while later, once you're well away.

const MeshKit = preload("res://scripts/MeshKit.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const PER_PLANET = [0, 2, 3, 4]   # Cinder, Rime, Moss, Magma
const HP = 24.0
const HOVER = 2.4
const SIGHT = 24.0
const BOLT_SPEED = 20.0
const RESPAWN = 40.0
const RESPAWN_AWAY = 60.0

var main
var drones = []    # {post, pos, hp, cd, hit_cd, respawn, node, eye}
var bolts = []     # {pos, vel, life, node}
var _body: Material
var _eye: Material
var _bolt_mesh: Mesh
var _bolt_mat: Material

func setup(m) -> void:
	main = m
	_body = MeshKit.mat(Color(0.14, 0.13, 0.15), 0.0, 0.4, 0.6)
	_eye = MeshKit.mat(Color(1.0, 0.15, 0.1), 2.0)
	_bolt_mesh = MeshKit.sphere(0.22, 6, 3)
	_bolt_mat = MeshKit.add_mat(Color(1.0, 0.25, 0.15, 0.95))

func clear() -> void:
	for d in drones:
		if d.node != null:
			d.node.queue_free()
	for b in bolts:
		b.node.queue_free()
	drones.clear()
	bolts.clear()

# New posts for the current track (after it's built or the race restarts).
func reset() -> void:
	clear()
	var track = main.track
	if track.pts.size() < 10:
		return
	var n = PER_PLANET[main.planet_index % PER_PLANET.size()]
	for k in n:
		# Spread round the lap, clear of the start, alternating sides.
		var i = track.index_at(0.22 + 0.7 * k / maxf(n, 1.0))
		var s = 1.0 if k % 2 == 0 else -1.0
		var post = track.pts[i] + track.side(i) * s * maxf(track.hw[i] - 0.4, 1.0)
		post.y = track.pts[i].y + HOVER
		var d = {"post": post, "pos": post, "hp": HP, "cd": 1.0 + randf(), "hit_cd": 0.0, "respawn": 0.0, "node": null, "eye": null}
		_revive(d)
		drones.append(d)

func _revive(d: Dictionary) -> void:
	var node = Node3D.new()
	MeshKit.part(node, MeshKit.sphere(0.7, 4, 2), _body, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
	for s in [-1.0, 1.0]:
		MeshKit.part(node, MeshKit.box(Vector3(0.9, 0.5, 0.08)), _body, Vector3(s * 0.8, 0, 0), Vector3(0, s * 20.0, 0))
	d.eye = MeshKit.part(node, MeshKit.sphere(0.25, 6, 3), _eye, Vector3(0, 0, 0.45), Vector3.ZERO, Vector3.ONE, false)
	add_child(node)
	d.node = node
	d.pos = d.post
	d.hp = HP
	node.position = d.pos

func alive() -> Array:
	return drones.filter(func(d): return d.hp > 0.0)

# Who a drone can see: racers on the road, not wrecked or respawning.
func _racers() -> Array:
	var out = []
	if main._respawn_left <= 0.0 and main.ship.is_processing():
		out.append(main.ship)
	for rv in main.rivals:
		if rv.down_left <= 0.0:
			out.append(rv)
	return out

func step(delta: float) -> void:
	var racers = _racers()
	var t = Time.get_ticks_msec() * 0.001
	for d in drones:
		if d.hp <= 0.0:
			d.respawn -= delta
			if d.respawn <= 0.0 and main.ship.position.distance_to(d.post) > RESPAWN_AWAY:
				_revive(d)
			continue
		d.hit_cd -= delta
		d.cd -= delta
		var near = null
		var nd = SIGHT
		for r in racers:
			var dist = r.position.distance_to(d.pos)
			if dist < nd:
				nd = dist
				near = r
		d.pos = d.post + Vector3(sin(t * 0.7 + d.post.x) * 0.6, sin(t * 2.0 + d.post.z) * 0.15, cos(t * 0.6 + d.post.z) * 0.6)
		d.node.position = d.pos
		if near != null:
			var to = near.position - d.pos
			d.node.rotation.y = atan2(to.x, to.z)
			if d.cd <= 0.0:
				d.cd = 1.4 + randf() * 0.6
				# Lead the target a little; a fast ship still outruns it.
				_fire(d, near.position + near.vel * (nd / BOLT_SPEED) * 0.5)
		d.eye.visible = near != null or fmod(t, 1.0) < 0.5
	_bolts(delta, racers)

func _fire(d: Dictionary, at: Vector3) -> void:
	var node = MeshInstance3D.new()
	node.mesh = _bolt_mesh
	node.material_override = _bolt_mat
	add_child(node)
	var from = d.pos + Vector3(0, -0.6, 0)
	var dir = at + Vector3(0, 0.8, 0) - from
	node.position = from
	bolts.append({"pos": from, "vel": dir.normalized() * BOLT_SPEED, "life": 2.5, "node": node})
	if main.ship.position.distance_to(d.pos) < 30.0:
		Sfx.play("drop", -10.0, 2.0)

func _bolts(delta: float, racers: Array) -> void:
	var keep = []
	for b in bolts:
		b.life -= delta
		b.pos += b.vel * delta
		b.node.position = b.pos
		var gone = b.life <= 0.0 or b.pos.y < main.track.pts[0].y - 0.5
		for r in racers:
			if gone:
				break
			var q = r.position + Vector3(0, 0.8 + r.alt, 0)
			if Vector2(q.x - b.pos.x, q.z - b.pos.z).length() < r.stats.radius + 0.4 and absf(q.y - b.pos.y) < 1.4:
				r.take_hit(8.0)
				gone = true
		if not gone:
			var c = main.terrain.world_to_cell(b.pos)
			gone = main.terrain.is_solid(c) and main.terrain.top_of(c) > b.pos.y
		if gone:
			main.fx.burst(b.pos, Color(1.0, 0.3, 0.2), 6, 4.0, 1.2, 0.08, 0.3, 0.0)
			b.node.queue_free()
		else:
			keep.append(b)
	bolts = keep

func damage(d: Dictionary, amount: float, by = null) -> void:
	if d.hp <= 0.0:
		return
	d.hp -= amount
	main.fx.burst(d.pos, Color(1.0, 0.8, 0.4), 5, 5.0, 1.2, 0.08, 0.3, 0.0)
	if d.hp > 0.0:
		return
	d.respawn = RESPAWN
	main.fx.burst(d.pos, Color(1.0, 0.5, 0.15), 30, 10.0, 1.2, 0.18, 0.6, 0.0)
	main.fx.burst(d.pos, Color(0.15, 0.14, 0.16), 14, 6.0, 0.0, 0.3, 0.9, 0.0)
	Sfx.play("small_boom", 0.0 if main.ship.position.distance_to(d.pos) < 30.0 else -8.0)
	d.node.queue_free()
	d.node = null
	if by == main.ship:
		for k in 2:
			main.spawn_pickup(d.pos, "metal" if randf() < 0.7 else "crystal")
		main.contract_event("drone", {})

# --- hooks for the race world adapter (positions on the ground plane) --------

func _flat(d: Dictionary) -> Vector2:
	return Vector2(d.pos.x, d.pos.z)

func touch(p: Vector2, r: float, by = null) -> bool:
	for d in drones:
		if d.hp > 0.0 and _flat(d).distance_to(p) < r + 0.8:
			if d.hit_cd <= 0.0:
				d.hit_cd = 0.12
				damage(d, 7.0, by)
			return true
	return false

func blast(p: Vector2, r: float, by = null) -> void:
	for d in drones:
		if d.hp > 0.0 and _flat(d).distance_to(p) < r + 1.0:
			damage(d, 30.0, by)

func nearest(p: Vector2, r: float):
	var best = null
	var bd = r
	for d in drones:
		if d.hp > 0.0 and _flat(d).distance_to(p) < bd:
			bd = _flat(d).distance_to(p)
			best = _flat(d)
	return best

func pull(p: Vector2, r: float, k: float) -> void:
	# Anchored to their posts: a tug knocks them about but they drift back.
	for d in drones:
		if d.hp > 0.0 and _flat(d).distance_to(p) < r:
			var v = (p - _flat(d)).normalized() * minf(k * 0.05, 0.4)
			d.node.position += Vector3(v.x, 0.0, v.y)
