extends Node3D

# Run director: owns the roguelike loop (acts, spawning, loot, upgrades,
# bosses, shop) and the permanent progression saved between runs.

const Data = preload("res://scripts/Data.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const EnemyScript = preload("res://scripts/Enemy.gd")
const BossScript = preload("res://scripts/Boss.gd")
const SfxScript = preload("res://scripts/Sfx.gd")

const SAVE_PATH = "user://ibud_save.json"
const PLAYER_RADIUS = Data.PLAYER_RADIUS

var player = null
var hud = null

# "menu", "playing", "web", "choice", "shop", "paused", "dead", "victory"
var state = "menu"

# Run state
var st = {}
var owned = {}
var hp = 100.0
var level = 1
var xp = 0.0
var crumbs = 0
var act = 1
var act_kills = 0
var kills = 0
var bosses_killed = 0
var run_time = 0.0
var boss = null
var boss_spawned = false
var near_nest = false
var zone_id = ""

# The web (skill tree): every node id -> data, which ones are taken, and the
# points left to spend. Points come from level-ups, sugar caches and the nest.
var web = {}
var web_owned = {}
var web_points = 0
var caches_found = 0
var caches_total = 0

var enemies = []
var shots = []
var enemy_shots = []
var pickups = []
var clouds = []
var pounce_hit = []
var captured = []

var fire_cd = 0.0
var burst_cd = 0.0

# Waves: a few telegraphed packs, a breather once they are dealt with, repeat.
var wave_cd = 2.0
var wave_index = 0
var pending_spawns = []
# Bugs currently allowed to attack; the rest circle and wait their turn.
var attackers = []
var need_caches = false

var pending_choices = []
var choice_kind = ""
var choice_options = []
var shop_purchases = 0

# Permanent progression
var meta = {"silk": 0, "levels": {}, "wins": 0, "best_act": 1}
var last_silk = 0

var nest: Node3D = null
var shot_mesh: Mesh = null
var shot_mat: Material = null
var mat_flash: Material = null
var mat_warn: Material = null
var sfx = null
var hitstop_on = false

func setup(p, h):
	player = p
	hud = h
	player.game = self
	st = Data.PLAYER_BASE_STATS.duplicate()
	sfx = SfxScript.new()
	add_child(sfx)
	# A web shot is a glowing bolt, long enough to read as a streak in flight.
	shot_mesh = MeshKit.box(Vector3(0.016, 0.016, 0.14))
	shot_mat = MeshKit.ghost_mat(Color(0.9, 0.97, 1.0, 1.0))
	mat_flash = MeshKit.ghost_mat(Color(1, 1, 1, 1))
	mat_warn = MeshKit.ghost_mat(Color(1.0, 0.15, 0.1, 1.0))
	nest = MeshKit.build_nest()
	add_child(nest)
	nest.global_position = Data.NEST_POS
	web = Data.build_web()
	_load_save()
	set_state("menu")

func set_state(new_state: String):
	state = new_state
	Engine.time_scale = 1.0
	hitstop_on = false
	var playing = state == "playing"
	get_tree().paused = not playing
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE)
	hud.on_state_changed(state)

# --- run lifecycle -------------------------------------------------------------

func start_run():
	_clear_world()
	st = Data.PLAYER_BASE_STATS.duplicate()
	owned = {}
	st["max_hp"] += 10.0 * meta_level("hp")
	st["damage"] *= 1.0 + 0.06 * meta_level("dmg")
	st["crumb_mult"] += 0.1 * meta_level("crumbs")
	st["speed"] += 0.03 * meta_level("speed")
	hp = st["max_hp"]
	level = 1
	xp = 0.0
	crumbs = 0
	act = 1
	act_kills = 0
	kills = 0
	bosses_killed = 0
	run_time = 0.0
	boss_spawned = false
	fire_cd = 0.0
	burst_cd = 0.0
	wave_cd = 2.5
	wave_index = 0
	pending_choices = []
	shop_purchases = 0
	need_caches = true
	web_owned = {"core": true}
	web_points = meta_level("start")
	zone_id = ""
	player.reset_to_spawn()
	set_state("playing")
	hud.announce("%s\n%s" % [Data.ACTS[0]["intro"], _cache_hint()], 6.0)

func _cache_hint() -> String:
	return "%d glowing sugar caches are hidden around the apartment. Each one is a web point." % Data.CACHES_PER_ACT

func _clear_world():
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies = []
	boss = null
	for c in captured:
		if is_instance_valid(c):
			c.queue_free()
	captured = []
	attackers = []
	for list in [shots, enemy_shots, pickups, clouds, pending_spawns]:
		for item in list:
			if is_instance_valid(item["node"]):
				item["node"].queue_free()
	shots = []
	enemy_shots = []
	pickups = []
	clouds = []
	pending_spawns = []
	pounce_hit = []

func _end_run(won: bool):
	last_silk = int(kills / 8.0) + bosses_killed * 20
	if won:
		last_silk += 60
		meta["wins"] = int(meta["wins"]) + 1
	meta["silk"] = int(meta["silk"]) + last_silk
	meta["best_act"] = maxi(int(meta["best_act"]), act)
	_save()
	set_state("victory" if won else "dead")

func abandon_run():
	_end_run(false)

func to_menu():
	_clear_world()
	set_state("menu")

func toggle_pause():
	if state == "playing":
		set_state("paused")
	elif state == "paused" or state == "web":
		set_state("playing")

func toggle_web():
	if state == "playing":
		set_state("web")
	elif state == "web":
		set_state("playing")

# --- the web (skill tree) --------------------------------------------------------

func web_reachable(id: String) -> bool:
	for l in web[id]["links"]:
		if web_owned.has(l):
			return true
	return false

func web_can_take(id: String) -> bool:
	return web.has(id) and not web_owned.has(id) and web_points > 0 and web_reachable(id)

func web_take(id: String):
	if state != "web" or not web_can_take(id):
		return
	web_points -= 1
	web_owned[id] = true
	for fx in web[id]["fx"]:
		_apply_fx(fx[0], fx[1], fx[2])
	sfx.play("pickup", 1.3)
	hud.on_state_changed(state)

func _apply_fx(stat: String, op: String, value):
	if op == "mul":
		st[stat] *= value
	else:
		st[stat] += value
		if stat == "max_hp":
			hp = minf(st["max_hp"], hp + value)

func add_web_point(reason: String):
	web_points += 1
	hud.announce("%s  +1 web point - press [Tab] to spend it" % reason, 3.0)


# --- main loop -----------------------------------------------------------------

func _physics_process(delta):
	if state != "playing":
		return
	run_time += delta
	if need_caches:
		need_caches = false
		_spawn_caches()
	fire_cd -= delta
	burst_cd -= delta
	if st["regen"] > 0.0:
		hp = minf(st["max_hp"], hp + st["regen"] * delta)
	near_nest = player.global_position.distance_to(nest.global_position) < 0.9
	var zone = zone_at(player.global_position)
	if zone["id"] != zone_id:
		zone_id = zone["id"]
		hud.zone_banner(zone)
	nest.rotate_y(delta * 0.8)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and fire_cd <= 0.0:
		fire_cd = 1.0 / st["fire_rate"]
		_fire()
	_update_shots(delta)
	if state != "playing":
		return
	_update_pounce()
	if state != "playing":
		return
	_update_enemy_shots(delta)
	_update_clouds(delta)
	_update_pickups(delta)
	if state != "playing":
		return
	_update_spawning(delta)
	_check_boss()
	if not pending_choices.is_empty() and state == "playing":
		_open_choice(pending_choices.pop_front())

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func closest_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab = b - a
	var l2 = ab.length_squared()
	if l2 < 0.0000001:
		return a
	var t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t

func zone_at(pos: Vector3) -> Dictionary:
	for z in Data.ZONES:
		var a = z["area"]
		if pos.x >= a[0] and pos.x <= a[1] and pos.z >= a[2] and pos.z <= a[3]:
			return z
	return Data.ZONES[Data.ZONES.size() - 1]

func zone_by_id(id: String) -> Dictionary:
	for z in Data.ZONES:
		if z["id"] == id:
			return z
	return Data.ZONES[Data.ZONES.size() - 1]

# Random point on a walkable surface inside the zone, or null.
func _find_floor_point(zone: Dictionary, min_dist: float, max_dist: float, want_los: bool):
	var s = zone["spawn"]
	var fallback = null
	for i in 12:
		var x = randf_range(s[0], s[1])
		var z = randf_range(s[2], s[3])
		var hit = ray(Vector3(x, 4.6, z), Vector3(x, -0.6, z))
		if hit.is_empty() or hit["normal"].y < 0.7:
			continue
		var p = hit["position"]
		var d = p.distance_to(player.global_position)
		if d < min_dist or d > max_dist:
			continue
		if not want_los:
			return p
		if ray(p + Vector3.UP * 0.15, player.global_position).is_empty():
			return p
		if fallback == null:
			fallback = p
	return fallback

# --- combat: player ------------------------------------------------------------

# What the crosshair is on: the nearest bug along the camera ray, else the
# first wall it hits. Shots leave the spider and fly at that point.
func aim_point() -> Vector3:
	var aim = player.aim_ray()
	var from: Vector3 = aim[0]
	var to: Vector3 = from + aim[1] * 30.0
	var wall = ray(from, to)
	if not wall.is_empty():
		to = wall["position"]
	var best = to
	var best_d = from.distance_to(to)
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var axis = e.closest_axis_point(closest_on_segment(from, to, e.center()))
		var c = closest_on_segment(from, to, axis)
		var d = from.distance_to(c)
		if c.distance_to(axis) <= e.radius and d < best_d:
			best_d = d
			best = c
	return best

func _fire():
	var origin = player.global_position + Vector3.UP * 0.02
	var fwd = (aim_point() - origin).normalized()
	var up = player.camera.global_transform.basis.y.normalized()
	var n = int(st["shots"])
	for i in n:
		var ang = deg_to_rad((i - (n - 1) / 2.0) * 5.0)
		var dir = fwd.rotated(up, ang)
		var node = MeshInstance3D.new()
		node.mesh = shot_mesh
		node.material_override = shot_mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.global_transform = Transform3D(_basis_along(dir), origin)
		shots.append({"node": node, "pos": origin, "vel": dir * st["shot_speed"], "pierce": int(st["pierce"]), "life": 2.5, "hit": []})
	sfx.play("shoot")
	player.on_fired()

func _basis_along(dir: Vector3) -> Basis:
	var up = Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	return Basis.looking_at(dir, up)

func _update_shots(delta):
	for s in shots.duplicate():
		var from = s["pos"]
		var to = from + s["vel"] * delta
		var wall = ray(from, to)
		var done = false
		if not wall.is_empty():
			to = wall["position"]
			done = true
			fx_burst(to, Color(0.95, 0.97, 1.0), 5, 0.012, 0.5)
		for e in enemies.duplicate():
			if not is_instance_valid(e) or e.dead or s["hit"].has(e):
				continue
			var axis = e.closest_axis_point(closest_on_segment(from, to, e.center()))
			var c = closest_on_segment(from, to, axis)
			if c.distance_to(axis) <= e.radius + 0.02:
				s["hit"].append(e)
				_hit_enemy(e, st["damage"], true, s["vel"].normalized())
				if state != "playing":
					return
				if s["pierce"] <= 0:
					to = c
					done = true
					break
				s["pierce"] -= 1
		s["pos"] = to
		s["life"] -= delta
		s["node"].global_position = to
		if done or s["life"] <= 0.0:
			s["node"].queue_free()
			shots.erase(s)

func _hit_enemy(e, base_damage: float, can_chain: bool, hit_dir: Vector3 = Vector3.UP):
	var crit = randf() < st["crit"]
	var dmg = base_damage
	if crit:
		dmg *= st["crit_mult"]
	if st["venom"] > 0.0:
		e.apply_venom(st["venom"], 3.0)
	if st["slow_shots"] > 0.0:
		e.apply_slow(1.0 - st["slow_shots"], 2.0)
	var from = e.center()
	e.take_damage(dmg, crit, hit_dir)
	var killed = e.dead
	fx_burst(from, e.cfg["color"], 14 if killed else 5, e.radius * (0.35 if killed else 0.22), 1.2 if killed else 0.7)
	if killed:
		sfx.play("kill", 1.0 if e.radius < 0.08 else 0.7)
		player.add_shake(0.5 if not e.elite else 1.2)
		if e.elite or e.is_boss:
			hitstop(0.09)
	else:
		sfx.play("crit" if crit else "hit")
	hud.hitmarker(killed, crit)
	if can_chain and st["chain"] > 0 and state == "playing":
		var best = null
		var best_d = 1.5
		for o in enemies:
			if o == e or not is_instance_valid(o) or o.dead:
				continue
			var d = o.center().distance_to(from)
			if d < best_d:
				best_d = d
				best = o
		if best != null:
			_hit_enemy(best, base_damage * 0.5, false, (best.center() - from).normalized())

func on_pounce_start():
	pounce_hit = []
	sfx.play("pounce")

func _update_pounce():
	if player.pounce_time <= 0.0:
		return
	var ppos = player.global_position
	for e in enemies.duplicate():
		if not is_instance_valid(e) or e.dead or pounce_hit.has(e):
			continue
		if e.closest_axis_point(ppos).distance_to(ppos) < e.radius + 0.2:
			pounce_hit.append(e)
			var away = (e.center() - ppos).normalized()
			e.push(away * 2.0)
			_hit_enemy(e, st["pounce_dmg"] * st["damage"] / 10.0, false, away)
			if st["pounce_heal"] > 0.0:
				hp = minf(st["max_hp"], hp + st["pounce_heal"])
			if st["pounce_stun"] > 0.0 and not e.dead and not e.is_boss:
				e.stun = maxf(e.stun, st["pounce_stun"])
			if e.dead:
				# A killing pounce is ready again almost at once: keep hunting.
				player.pounce_cd = minf(player.pounce_cd, 0.25)
				hitstop(0.06)
			if state != "playing":
				return

func try_burst():
	if state != "playing" or burst_cd > 0.0:
		return
	burst_cd = st["burst_cd"]
	_burst(player.global_position)
	if st["burst_echo"] > 0:
		get_tree().create_timer(0.6, false).timeout.connect(_echo_burst)

func _echo_burst():
	if state == "playing":
		_burst(player.global_position)

func _burst(ppos: Vector3):
	sfx.play("burst")
	player.add_shake(1.0)
	var r = st["burst_radius"]
	var fx = MeshInstance3D.new()
	fx.mesh = MeshKit.sphere(1.0)
	fx.material_override = MeshKit.ghost_mat(Color(0.9, 0.95, 1.0, 0.35))
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fx)
	fx.global_position = ppos
	fx.scale = Vector3.ONE * 0.1
	var tw = fx.create_tween()
	tw.tween_property(fx, "scale", Vector3.ONE * r, 0.25)
	tw.tween_callback(fx.queue_free)
	for e in enemies.duplicate():
		if not is_instance_valid(e) or e.dead:
			continue
		if e.closest_axis_point(ppos).distance_to(ppos) < r + e.radius:
			e.apply_slow(maxf(0.1, 0.4 - st["burst_slow"]), 3.0 + st["burst_slow"] * 8.0)
			var away = (e.center() - ppos).normalized()
			e.push(away * 3.0)
			_hit_enemy(e, st["burst_dmg"] * st["damage"] / 10.0, false, away)
			if state != "playing":
				return

func interact():
	if state == "playing" and near_nest:
		set_state("shop")

func damage_player(amount: float, source = null, dot: bool = false):
	if state != "playing":
		return
	if not dot:
		if player.invuln > 0.0:
			return
		player.invuln = 0.6
		hud.flash()
		sfx.play("hurt")
		player.add_shake(2.5)
		if source != null:
			var away = player.global_position - source
			if away.length() > 0.001:
				player.velocity += away.normalized() * 2.0 + Vector3.UP * 1.0
	hp -= amount * (1.0 - st["armor"])
	if hp <= 0.0:
		if st["revives"] > 0:
			st["revives"] -= 1
			hp = st["max_hp"] * 0.5
			player.invuln = 2.0
			hud.announce("Nine Lives! You crawl back up.", 3.0)
		else:
			hp = 0.0
			_end_run(false)

# One-shot spray of little cubes: hit sparks, death splats, web puffs.
func fx_burst(pos: Vector3, color: Color, amount: int, size: float, speed: float):
	var fx = CPUParticles3D.new()
	fx.mesh = MeshKit.box(Vector3.ONE * size)
	fx.material_override = MeshKit.ghost_mat(color)
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.amount = amount
	fx.lifetime = 0.45
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.direction = Vector3.UP
	fx.spread = 180.0
	fx.initial_velocity_min = speed * 0.4
	fx.initial_velocity_max = speed
	fx.gravity = Vector3(0, -3.0, 0)
	fx.scale_amount_min = 0.5
	fx.scale_amount_max = 1.0
	add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	get_tree().create_timer(1.0).timeout.connect(fx.queue_free)

# Freeze-frame for a few hundredths of a second to sell a heavy hit.
func hitstop(seconds: float):
	if hitstop_on:
		return
	hitstop_on = true
	Engine.time_scale = 0.05
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_end_hitstop)

func _end_hitstop():
	if hitstop_on:
		hitstop_on = false
		Engine.time_scale = 1.0

# --- attack slots ----------------------------------------------------------------

func _attack_slots() -> int:
	return 2 if act < 2 else 3

func _prune_attackers():
	for a in attackers.duplicate():
		if not is_instance_valid(a) or a.dead:
			attackers.erase(a)

func attack_slot_free(e) -> bool:
	_prune_attackers()
	return attackers.has(e) or attackers.size() < _attack_slots()

func take_attack_slot(e) -> bool:
	if not attack_slot_free(e):
		return false
	if not attackers.has(e):
		attackers.append(e)
		sfx.play("warn")
	return true

func release_attack_slot(e):
	attackers.erase(e)

func show_damage_number(pos: Vector3, amount: float, crit: bool):
	var l = Label3D.new()
	l.text = str(int(ceil(amount)))
	l.font_size = 80 if crit else 52
	l.pixel_size = 0.0011
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.85, 0.2) if crit else Color(1, 1, 1)
	l.outline_size = 10
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04))
	var tw = l.create_tween()
	tw.tween_property(l, "position:y", l.position.y + 0.18, 0.5)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)

# --- combat: enemies -----------------------------------------------------------

func spawn_enemy(kind: String, pos: Vector3, make_elite: bool):
	var e = EnemyScript.new()
	add_child(e)
	e.global_position = pos
	var hp_mult = 1.0 + 0.6 * (act - 1) + run_time / 60.0 * 0.08
	var dmg_mult = 1.0 + 0.35 * (act - 1)
	e.setup(self, kind, hp_mult, dmg_mult, make_elite)
	enemies.append(e)

func recycle_enemy(e):
	e.dead = true
	enemies.erase(e)
	e.queue_free()

func spawn_enemy_shot(pos: Vector3, velocity: Vector3, dmg: float, r: float, slipper: bool):
	var node = MeshInstance3D.new()
	if slipper:
		node.mesh = MeshKit.box(Vector3(0.28, 0.08, 0.65))
		node.material_override = MeshKit.mat(Color(0.75, 0.15, 0.15))
	else:
		node.mesh = MeshKit.sphere(r)
		node.material_override = MeshKit.mat(Color(1.0, 0.5, 0.1), 1.5)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = pos
	enemy_shots.append({"node": node, "pos": pos, "vel": velocity, "dmg": dmg, "radius": r, "life": 4.0, "spin": slipper})

func _update_enemy_shots(delta):
	var ppos = player.global_position
	for s in enemy_shots.duplicate():
		var from = s["pos"]
		var to = from + s["vel"] * delta
		var done = not ray(from, to).is_empty()
		if closest_on_segment(from, to, ppos).distance_to(ppos) < s["radius"] + PLAYER_RADIUS:
			damage_player(s["dmg"], from)
			done = true
			if state != "playing":
				return
		s["pos"] = to
		s["life"] -= delta
		s["node"].global_position = to
		if s["spin"]:
			s["node"].rotate_x(delta * 12.0)
		if done or s["life"] <= 0.0:
			s["node"].queue_free()
			enemy_shots.erase(s)

# Lingering bug-spray cloud that hurts while you stay inside it.
func spawn_cloud(pos: Vector3, velocity: Vector3, dps: float):
	var node = MeshInstance3D.new()
	node.mesh = MeshKit.sphere(1.0)
	node.material_override = MeshKit.ghost_mat(Color(0.55, 0.9, 0.3, 0.3))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = pos
	node.scale = Vector3.ONE * 0.2
	clouds.append({"node": node, "pos": pos, "vel": velocity, "dps": dps, "life": 4.0, "radius": 0.2})

func _update_clouds(delta):
	var ppos = player.global_position
	for c in clouds.duplicate():
		c["pos"] += c["vel"] * delta
		c["vel"] = c["vel"].move_toward(Vector3.ZERO, 3.0 * delta)
		c["radius"] = minf(0.7, c["radius"] + 0.5 * delta)
		c["life"] -= delta
		c["node"].global_position = c["pos"]
		c["node"].scale = Vector3.ONE * c["radius"]
		if ppos.distance_to(c["pos"]) < c["radius"] + PLAYER_RADIUS:
			damage_player(c["dps"] * delta, null, true)
			if state != "playing":
				return
		if c["life"] <= 0.0:
			c["node"].queue_free()
			clouds.erase(c)

func on_enemy_killed(e):
	enemies.erase(e)
	kills += 1
	if st["lifesteal"] > 0.0:
		hp = minf(st["max_hp"], hp + st["lifesteal"])
	if e.is_boss:
		if e.is_capture():
			captured.append(e)
		add_xp(e.xp)
		_on_boss_killed(e)
		return
	act_kills += 1
	if st["venom_spread"] > 0.0 and e.venom_timer > 0.0:
		_spread_venom(e)
	var zone = zone_at(e.global_position)
	var xp_gain = float(e.xp)
	var crumb_gain = float(e.crumbs) * st["crumb_mult"]
	var heart_chance = 0.03
	match zone["bonus"]:
		"xp":
			xp_gain *= 1.5
		"crumbs":
			crumb_gain *= 1.5
		"hearts":
			heart_chance *= 3.0
		"elites":
			crumb_gain *= 1.25
	add_xp(xp_gain)
	_spawn_pickup("crumb", e.center(), maxi(1, int(round(crumb_gain))))
	if e.elite or randf() < heart_chance:
		_spawn_pickup("heart", e.center() + Vector3(0.08, 0.0, 0.0), 15)

# Toxic Bloom: a poisoned bug bursts and poisons everything close by.
func _spread_venom(source):
	fx_burst(source.center(), Color(0.6, 1.0, 0.2), 10, 0.015, 0.8)
	for o in enemies:
		if o != source and is_instance_valid(o) and not o.dead and o.center().distance_to(source.center()) < 0.6:
			o.apply_venom(st["venom"], 3.0)

func _update_spawning(delta):
	# Telegraphed spawns: a dark blob swells for a second, then the bug pops out.
	for sp in pending_spawns.duplicate():
		sp["t"] -= delta
		sp["node"].scale = Vector3.ONE * clampf(1.0 - sp["t"], 0.1, 1.0)
		if sp["t"] <= 0.0:
			sp["node"].queue_free()
			pending_spawns.erase(sp)
			spawn_enemy(sp["kind"], sp["pos"], sp["elite"])
			fx_burst(sp["pos"], Color(0.1, 0.1, 0.1), 6, 0.02, 0.6)
	var alive = enemies.size() + pending_spawns.size()
	if boss != null:
		alive -= 1
	if alive > 1:
		# The breather only starts once the wave is (almost) dealt with.
		wave_cd = 2.5 if boss == null else 6.0
		return
	wave_cd -= delta
	if wave_cd > 0.0:
		return
	wave_cd = 2.5
	wave_index += 1
	var packs = clampi(1 + act + wave_index / 4, 2, 5)
	if boss != null:
		packs = 1
	var zone = zone_at(player.global_position)
	var elite_chance = 0.15 if zone["bonus"] == "elites" else 0.05
	var spawned = false
	for n in packs:
		var kind = zone["enemies"].pick_random()
		if act >= 2 and randf() < 0.15:
			kind = "wasp"
		var cfg = Data.ENEMIES[kind]
		var anchor = _find_floor_point(zone, 1.5, 7.0, true)
		if anchor == null:
			continue
		var flying = cfg["ai"] != "crawler"
		var r = cfg["radius"] * Data.BUG_SCALE
		for i in cfg["pack"]:
			var pos = anchor + Vector3(randf_range(-0.2, 0.2), r + 0.02, randf_range(-0.2, 0.2))
			if flying:
				pos.y += randf_range(0.3, 0.8)
			var node = MeshKit.part(self, MeshKit.sphere(r * 1.6), MeshKit.ghost_mat(Color(0.05, 0.02, 0.08, 0.8)), pos)
			pending_spawns.append({"node": node, "pos": pos, "kind": kind, "elite": i == 0 and randf() < elite_chance, "t": 1.0 + 0.12 * i})
			spawned = true
	if spawned:
		sfx.play("spawn")

# --- bosses and acts -----------------------------------------------------------

func act_info() -> Dictionary:
	return Data.ACTS[clampi(act - 1, 0, Data.ACTS.size() - 1)]

func _check_boss():
	if boss_spawned or act_kills < act_info()["quota"]:
		return
	boss_spawned = true
	var kind = act_info()["boss"]
	var cfg = Data.BOSSES[kind]
	var pos = cfg["spawn"]
	if kind == "mouse":
		var p = _find_floor_point(zone_by_id(cfg["zone"]), 2.0, 99.0, false)
		if p != null:
			pos = p + Vector3.UP * cfg["radius"]
	var b = BossScript.new()
	add_child(b)
	b.global_position = pos
	b.setup(self, kind, 1.0, 1.0, false)
	enemies.append(b)
	boss = b
	sfx.play("boss", 1.0, 0.0)
	player.add_shake(2.0)
	hud.announce("%s appears in the %s!" % [cfg["name"].to_upper(), zone_by_id(cfg["zone"])["name"]], 5.0)

func _on_boss_killed(e):
	boss = null
	bosses_killed += 1
	add_crumbs(40 * act)
	hp = minf(st["max_hp"], hp + st["max_hp"] * 0.4)
	if act >= Data.ACTS.size():
		_end_run(true)
		return
	pending_choices.append("relic:" + e.kind)
	act += 1
	act_kills = 0
	boss_spawned = false
	need_caches = true
	wave_index = 0
	wave_cd = 5.0
	hud.announce("%s\n%s\nNew sugar caches have been hidden." % [e.cfg.get("defeat_text", "%s defeated!" % e.cfg["name"]), act_info()["intro"]], 6.0)

# --- loot ----------------------------------------------------------------------

func add_crumbs(amount: int):
	crumbs += amount

func add_xp(amount: float):
	xp += amount * st["xp_mult"]
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		sfx.jingle()
		add_web_point("Level %d!" % level)

func xp_needed() -> float:
	return 12.0 + level * 10.0

func _spawn_pickup(kind: String, pos: Vector3, value: int):
	var node: Node3D
	var life = 40.0
	if kind == "cache":
		node = MeshKit.build_cache()
		life = 99999.0
	else:
		var mi = MeshInstance3D.new()
		if kind == "heart":
			mi.mesh = MeshKit.sphere(0.025)
			mi.material_override = MeshKit.mat(Color(1.0, 0.2, 0.3), 1.5)
		else:
			mi.mesh = MeshKit.box(Vector3(0.025, 0.025, 0.025))
			mi.material_override = MeshKit.mat(Color(0.95, 0.75, 0.3), 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node = mi
	add_child(node)
	node.global_position = pos
	# Loot settles on whatever surface is below it.
	var rest_y = pos.y
	var floor_hit = ray(pos, pos + Vector3.DOWN * 6.0)
	if not floor_hit.is_empty():
		rest_y = floor_hit["position"].y + (0.06 if kind == "cache" else 0.04)
	pickups.append({"node": node, "kind": kind, "value": value, "pos": pos, "rest_y": rest_y, "life": life})

# Sugar-cube caches hidden around the apartment at the start of each act.
func _spawn_caches():
	for p in pickups.duplicate():
		if p["kind"] == "cache":
			p["node"].queue_free()
			pickups.erase(p)
	caches_found = 0
	caches_total = 0
	for i in Data.CACHES_PER_ACT:
		var zone = Data.ZONES.pick_random()
		var pos = _find_floor_point(zone, 2.0, 99.0, false)
		if pos != null:
			_spawn_pickup("cache", pos + Vector3.UP * 0.06, 15 + 5 * act)
			caches_total += 1

# The closest cache still lying around, or null.
func nearest_cache():
	var best = null
	var best_d = INF
	for p in pickups:
		if p["kind"] == "cache":
			var d = p["pos"].distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best

func _update_pickups(delta):
	var ppos = player.global_position
	for p in pickups.duplicate():
		var pos = p["pos"]
		var d = pos.distance_to(ppos)
		var reach = st["magnet"]
		if p["kind"] == "cache":
			reach = 0.0
		if d < reach:
			pos = pos.move_toward(ppos, 6.0 * delta)
		else:
			pos.y = move_toward(pos.y, p["rest_y"], 2.0 * delta)
		p["pos"] = pos
		p["life"] -= delta
		p["node"].global_position = pos
		p["node"].rotate_y(delta * 2.0)
		if d < (0.12 if p["kind"] == "cache" else 0.1):
			_collect(p)
			p["node"].queue_free()
			pickups.erase(p)
		elif p["life"] <= 0.0:
			p["node"].queue_free()
			pickups.erase(p)

func _collect(p: Dictionary):
	sfx.play("pickup", 1.0 if p["kind"] == "crumb" else 0.7)
	match p["kind"]:
		"heart":
			hp = minf(st["max_hp"], hp + p["value"])
		"cache":
			caches_found += 1
			add_crumbs(int(p["value"] * st["crumb_mult"]))
			sfx.jingle()
			add_web_point("Sugar cache %d/%d!" % [caches_found, caches_total])
		_:
			add_crumbs(p["value"])

# --- relics ------------------------------------------------------------------

func _roll_relics(n: int, boss_kind: String) -> Array:
	var pool = []
	for id in Data.UPGRADES:
		var u = Data.UPGRADES[id]
		if u.get("relic", "") == boss_kind and owned.get(id, 0) < u["max"]:
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, n)

func _open_choice(kind: String):
	choice_options = _roll_relics(3, kind.substr(6))
	if choice_options.is_empty():
		add_crumbs(25)
		return
	choice_kind = kind
	set_state("choice")

func pick_choice(index: int):
	if state != "choice" or index < 0 or index >= choice_options.size():
		return
	apply_upgrade(choice_options[index])
	set_state("playing")

func apply_upgrade(id: String):
	owned[id] = owned.get(id, 0) + 1
	match id:
		"relic_tail":
			st["chain"] += 1
		"relic_cheese":
			st["max_hp"] += 60.0
			hp = st["max_hp"]
		"relic_whisker":
			st["crit"] += 0.15
			st["speed"] += 0.2
		"relic_claw":
			st["damage"] *= 1.6
		"relic_lives":
			st["revives"] += 1
		"relic_catnip":
			st["fire_rate"] *= 1.4
			st["pierce"] += 1

# --- shop (the nest) -----------------------------------------------------------

func shop_price() -> int:
	return int(30.0 * pow(1.35, shop_purchases))

func shop_buy_point():
	if state != "shop":
		return
	var price = shop_price()
	if crumbs < price:
		return
	crumbs -= price
	shop_purchases += 1
	web_points += 1
	sfx.play("pickup", 1.3)
	hud.on_state_changed(state)

func shop_heal():
	if state != "shop" or crumbs < 15 or hp >= st["max_hp"]:
		return
	crumbs -= 15
	hp = minf(st["max_hp"], hp + 40.0)
	hud.on_state_changed(state)

func close_shop():
	if state == "shop":
		set_state("playing")

# --- permanent progression -----------------------------------------------------

func meta_level(id: String) -> int:
	return int(meta["levels"].get(id, 0))

func meta_cost(id: String) -> int:
	return int(Data.META[id]["cost"]) * (meta_level(id) + 1)

func buy_meta(id: String):
	if state != "menu" or meta_level(id) >= Data.META[id]["max"]:
		return
	var cost = meta_cost(id)
	if int(meta["silk"]) < cost:
		return
	meta["silk"] = int(meta["silk"]) - cost
	meta["levels"][id] = meta_level(id) + 1
	_save()
	hud.on_state_changed(state)

func _save():
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta))
		f.close()

func _load_save():
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key in ["silk", "wins", "best_act"]:
		if data.has(key):
			meta[key] = int(data[key])
	if typeof(data.get("levels")) == TYPE_DICTIONARY:
		meta["levels"] = data["levels"]
