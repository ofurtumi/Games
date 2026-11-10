extends Node3D

# A bug. Movement is done by hand with a couple of raycasts per frame instead
# of physics bodies, which keeps dozens of tiny creatures cheap and predictable.
#
# Bugs don't hurt on touch. They close in, blink red while winding up, then
# lunge; the lunge is what hurts and it can be sidestepped. Only a few may
# attack at once (Game hands out attack slots), the rest circle and wait.
# Getting shot staggers a bug and cancels its wind-up.

const MeshKit = preload("res://scripts/MeshKit.gd")
const Data = preload("res://scripts/Data.gd")

const PLAYER_RADIUS = 0.07
const GRAVITY = 9.0

const ATTACK_RANGE = 0.3
const RING_RANGE = 0.45
const WINDUP_TIME = 0.55
const LUNGE_TIME = 0.3
const LUNGE_SPEED = 2.6
const RECOVER_TIME = 0.9
const STAGGER_TIME = 0.18

var game = null
var kind = ""
var cfg = {}
var max_hp = 10.0
var hp = 10.0
var speed = 1.0
var radius = 0.05
var center_y = 0.0
var hit_height = 0.0
var damage = 5.0
var xp = 1
var crumbs = 1
var elite = false
var is_boss = false
var dead = false

var visual: Node3D = null
var base_scale = Vector3.ONE
var vy = 0.0
var vel = Vector3.ZERO
var knock = Vector3.ZERO
var last_wall_normal = Vector3.UP
var attack_cd = 0.0
var shoot_cd = 2.0
var wobble = 0.0

# Melee state: "approach", "windup", "lunge", "recover"
var mstate = "approach"
var mt = 0.0
var lunge_dir = Vector3.ZERO
var strafe_sign = 1.0
var stun = 0.0

# Hit flash / attack telegraph. parts holds [MeshInstance3D, original material].
var parts = []
var tint = ""
var flash_t = 0.0
var telegraph = false

var slow_timer = 0.0
var slow_factor = 1.0
var venom_dps = 0.0
var venom_timer = 0.0
var venom_tick = 0.0

var check_t = 0.0
var last_dist = 999.0
var stuck = 0

func setup(g, k: String, hp_mult: float, dmg_mult: float, make_elite: bool):
	game = g
	kind = k
	if Data.BOSSES.has(k):
		cfg = Data.BOSSES[k]
		is_boss = true
		center_y = cfg["center_y"]
		hit_height = cfg["hit_height"]
	else:
		cfg = Data.ENEMIES[k]
	radius = cfg["radius"]
	speed = cfg["speed"]
	max_hp = cfg["hp"] * hp_mult
	damage = cfg["damage"] * dmg_mult
	xp = cfg["xp"]
	crumbs = cfg["crumbs"]
	elite = make_elite
	visual = MeshKit.build_enemy(kind, radius, cfg["color"])
	add_child(visual)
	_collect_parts(visual)
	if elite:
		max_hp *= 4.0
		damage *= 1.5
		xp *= 4
		crumbs *= 6
		radius *= 1.5
		base_scale = Vector3.ONE * 1.5
	hp = max_hp
	wobble = randf() * 10.0
	shoot_cd = randf_range(1.5, 3.0)
	strafe_sign = 1.0 if randf() < 0.5 else -1.0
	# Pop in.
	visual.scale = base_scale * 0.2

func _collect_parts(node: Node):
	for c in node.get_children():
		if c is MeshInstance3D:
			parts.append([c, c.material_override])
		_collect_parts(c)

func center() -> Vector3:
	return global_position + Vector3(0, center_y, 0)

# Closest point of the hit volume's axis to p (the centre for spheres).
func closest_axis_point(p: Vector3) -> Vector3:
	if hit_height <= 0.0:
		return center()
	var y = clampf(p.y, global_position.y + radius, global_position.y + hit_height - radius)
	return Vector3(global_position.x, y, global_position.z)

func _physics_process(delta):
	if dead or game == null or game.state != "playing":
		return
	attack_cd -= delta
	flash_t -= delta
	_tick_status(delta)
	if dead:
		return
	var ppos = game.player.global_position
	var to_player = ppos - center()
	var spd = speed
	if slow_timer > 0.0:
		spd *= slow_factor
	telegraph = false
	if stun > 0.0:
		stun -= delta
		if cfg["ai"] == "crawler":
			_move_crawler(delta, Vector3.ZERO, 0.0)
	else:
		_think(delta, ppos, to_player, spd)
	if dead:
		return
	if knock.length_squared() > 0.0001:
		_try_move(knock * delta)
		knock = knock.move_toward(Vector3.ZERO, 8.0 * delta)
	_update_tint()
	visual.scale = visual.scale.lerp(base_scale, clampf(12.0 * delta, 0.0, 1.0))
	# Only bosses hurt on plain contact; bugs have to land a lunge.
	if is_boss and attack_cd <= 0.0 and closest_axis_point(ppos).distance_to(ppos) < radius + PLAYER_RADIUS:
		attack_cd = 0.8
		game.damage_player(damage, center())
	if global_position.y < -3.0:
		game.recycle_enemy(self)
		return
	_tick_leash(delta, to_player.length())

# Overridden by Boss.gd.
func _think(delta, ppos, to_player, spd):
	if cfg["ai"] == "shooter":
		_move_shooter(delta, ppos, to_player, spd)
	else:
		_melee(delta, to_player, spd)
	_face(to_player, delta)

func _tick_status(delta):
	if slow_timer > 0.0:
		slow_timer -= delta
	if venom_timer > 0.0:
		venom_timer -= delta
		venom_tick -= delta
		if venom_tick <= 0.0:
			venom_tick = 0.5
			take_damage(venom_dps * 0.5, false)

# Recycle bugs that got lost behind a wall or left far behind.
func _tick_leash(delta, dist):
	if is_boss:
		return
	check_t += delta
	if check_t < 3.0:
		return
	check_t = 0.0
	if dist > 11.0 or (dist > 2.5 and dist > last_dist - 0.15):
		stuck += 1
	else:
		stuck = 0
	last_dist = dist
	if stuck >= 3:
		game.recycle_enemy(self)

func _update_tint():
	var want = ""
	if flash_t > 0.0:
		want = "white"
	elif telegraph and fmod(mt + shoot_cd, 0.16) < 0.08:
		want = "red"
	if want == tint:
		return
	tint = want
	for p in parts:
		if tint == "white":
			p[0].material_override = game.mat_flash
		elif tint == "red":
			p[0].material_override = game.mat_warn
		else:
			p[0].material_override = p[1]

func _face(dir: Vector3, delta):
	if absf(dir.x) + absf(dir.z) < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(10.0 * delta, 0.0, 1.0))

# Moves by `motion`, sliding along whatever is in the way.
# Returns true when something blocked the move.
func _try_move(motion: Vector3) -> bool:
	var dist_m = motion.length()
	if dist_m < 0.00001:
		return false
	var dir = motion / dist_m
	var hit = game.ray(global_position, global_position + dir * (dist_m + radius))
	if hit.is_empty():
		global_position += motion
		return false
	last_wall_normal = hit["normal"]
	var slid = motion.slide(last_wall_normal)
	var slid_len = slid.length()
	if slid_len > 0.00001:
		var hit2 = game.ray(global_position, global_position + slid / slid_len * (slid_len + radius))
		if hit2.is_empty():
			global_position += slid
	return true

# Walks toward to_target on the ground, climbs walls and furniture when the
# target is higher up, and falls when there is nothing underneath.
func _move_crawler(delta, to_target: Vector3, spd: float):
	var flat = Vector3(to_target.x, 0.0, to_target.z)
	var flat_len = flat.length()
	var climbing = false
	if flat_len > 0.02 and spd > 0.0:
		var dir = flat / flat_len
		var blocked = _try_move(dir * spd * delta)
		if blocked and last_wall_normal.y < 0.6:
			var want_up = to_target.y > radius
			if not want_up:
				# Low obstacle like a stair step? Then hop over it anyway.
				var high = global_position + Vector3.UP * 0.5
				want_up = game.ray(high, high + dir * (radius + 0.1)).is_empty()
			if want_up:
				climbing = true
				vy = 0.0
				var up_hit = game.ray(global_position, global_position + Vector3.UP * (radius + spd * delta))
				if up_hit.is_empty():
					global_position.y += spd * 0.8 * delta
	if not climbing:
		vy -= GRAVITY * delta
		var fall = vy * delta
		var down = game.ray(global_position, global_position + Vector3.DOWN * (radius + maxf(-fall, 0.0) + 0.01))
		if down.is_empty():
			global_position.y += fall
		else:
			global_position.y = down["position"].y + radius
			vy = 0.0

func _move_flier(delta, to_target: Vector3, spd: float):
	wobble += delta * 6.0
	var target = to_target + Vector3(sin(wobble * 0.7), cos(wobble) * 0.5, cos(wobble * 0.9)) * 0.15
	var desired = Vector3.ZERO
	if target.length() > 0.001 and spd > 0.0:
		desired = target.normalized() * spd
	vel = vel.lerp(desired, clampf(3.0 * delta, 0.0, 1.0))
	_try_move(vel * delta)

func _go(delta, to_target: Vector3, spd: float):
	if cfg["ai"] == "crawler":
		_move_crawler(delta, to_target, spd)
	else:
		_move_flier(delta, to_target, spd)

func _melee(delta, to_player: Vector3, spd: float):
	var dist = to_player.length()
	var gap = dist - radius - PLAYER_RADIUS
	var dir = to_player / dist if dist > 0.001 else Vector3.FORWARD
	mt -= delta
	match mstate:
		"approach":
			if gap < ATTACK_RANGE and game.take_attack_slot(self):
				mstate = "windup"
				mt = WINDUP_TIME
				vel = Vector3.ZERO
			elif gap < RING_RANGE and not game.attack_slot_free(self):
				# No slot: circle the spider and keep a little distance.
				var orbit = dir.cross(Vector3.UP) * strafe_sign * 0.6
				if gap < ATTACK_RANGE:
					orbit -= dir * 0.6
				orbit.y = to_player.y
				_go(delta, orbit, spd * 0.7)
			else:
				_go(delta, to_player, spd)
		"windup":
			telegraph = true
			_go(delta, Vector3.ZERO, 0.0)
			# Rear back before the strike.
			visual.position = Vector3(0, 0, -radius * 0.6 * (1.0 - mt / WINDUP_TIME))
			if mt <= 0.0:
				visual.position = Vector3.ZERO
				lunge_dir = dir
				mstate = "lunge"
				mt = LUNGE_TIME
		"lunge":
			_try_move(lunge_dir * LUNGE_SPEED * delta)
			if gap < 0.03:
				game.damage_player(damage, center())
				mt = 0.0
			if mt <= 0.0:
				_end_attack(RECOVER_TIME)
		_:
			# Back off after the strike instead of sitting on the spider.
			if gap < 0.2:
				var retreat = -dir
				retreat.y = 0.0
				_go(delta, retreat, spd * 0.6)
			else:
				_go(delta, Vector3.ZERO, 0.0)
			if mt <= 0.0:
				game.release_attack_slot(self)
				mstate = "approach"

func _end_attack(rest: float):
	visual.position = Vector3.ZERO
	vy = 0.0
	vel = Vector3.ZERO
	mstate = "recover"
	mt = rest

func _move_shooter(delta, ppos: Vector3, to_player: Vector3, spd: float):
	wobble += delta * 2.0
	var dist = to_player.length()
	var desired = Vector3.ZERO
	if dist > 0.001:
		var dir = to_player / dist
		if dist > 2.3:
			desired = dir * spd
		elif dist < 1.3:
			desired = -dir * spd
		else:
			desired = dir.cross(Vector3.UP) * spd * 0.6 * signf(sin(wobble * 0.5))
		desired.y += (0.4 - (global_position.y - ppos.y)) * 1.5
	vel = vel.lerp(desired, clampf(3.0 * delta, 0.0, 1.0))
	_try_move(vel * delta)
	shoot_cd -= delta
	# Blink before firing so the stinger can be dodged.
	telegraph = shoot_cd < 0.5 and dist < 5.0
	if shoot_cd <= 0.0 and dist < 5.0 and dist > 0.1:
		if game.ray(center(), ppos).is_empty():
			shoot_cd = 2.8
			game.spawn_enemy_shot(center(), to_player / dist * 3.5, damage, 0.035, false)
		else:
			shoot_cd = 0.6

func apply_slow(factor: float, time: float):
	if is_boss:
		factor = maxf(factor, 0.75)
	slow_factor = factor
	slow_timer = maxf(slow_timer, time)

func is_capture() -> bool:
	return cfg.get("capture", false)

func apply_venom(dps: float, time: float):
	if is_capture():
		return
	venom_dps = maxf(venom_dps, dps)
	venom_timer = maxf(venom_timer, time)

func push(impulse: Vector3):
	if not is_boss:
		knock += impulse

# hit_dir is the direction the blow came from (zero for damage over time):
# a real hit flashes, shoves and staggers the bug, cancelling its attack.
func take_damage(amount: float, crit: bool, hit_dir: Vector3 = Vector3.ZERO):
	if dead:
		return
	hp -= amount
	game.show_damage_number(center() + Vector3.UP * (radius + 0.05), amount, crit)
	if hit_dir != Vector3.ZERO:
		flash_t = 0.09
		if not is_boss:
			visual.scale = base_scale * 1.35
			knock += hit_dir * 1.3
			stun = STAGGER_TIME
			shoot_cd = maxf(shoot_cd, 0.8)
			if mstate == "windup" or mstate == "lunge":
				_end_attack(0.4)
	if hp <= 0.0:
		die()

func die():
	if dead:
		return
	dead = true
	game.release_attack_slot(self)
	if is_capture():
		_on_captured()
		game.on_enemy_killed(self)
		return
	game.on_enemy_killed(self)
	queue_free()

# Capture bosses are not removed: they stay where they are, wrapped in a net.
func _on_captured():
	visual.scale = base_scale
	flash_t = 0.0
	telegraph = false
	_update_tint()
	var net = MeshKit.build_net(radius * 1.6)
	net.position = Vector3(0, center_y, 0)
	add_child(net)
