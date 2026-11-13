class_name Arena
extends Node2D
## One match: owns the map, fighters, items and round flow.
## Fighters are ticked here in a fixed order from InputFrames — the seam for netcode later.

const ROUND_END_DELAY := 3.0
const MATCH_END_DELAY := 5.5
const WIN_SCORE := 5
const INTRO := 1.3 # "READY..." before anyone can move

var participants: Array = [] # {source, name, color}
var map_data: Dictionary = {}

var terrain: Terrain
var nav: NavGraph
var fx: FX
var projectiles: Projectiles
var camera: ArenaCamera
var hud: Node2D
var bg: Node2D
var props_node: Node2D
var pickups_node: Node2D
var grenades_node: Node2D
var fighters_node: Node2D

var fighters: Array = []
var spawners: Array = [] # {pos, t}
var drop_t := 15.0 # next parachute supply drop
var pending_explosions: Array = [] # [t, pos, data, src]
var rng := RandomNumberGenerator.new()
var kill_y := 1000.0
var round_num := 0
var round_over_t := -1.0
var round_winner: Fighter = null
var feed: Array = [] # [text, color, t]
var time := 0.0
var intro_t := 0.0
var round_t := 0.0
var match_winner: Fighter = null
var slowmo_t := 0.0
var attract := false # running behind the title menu: no HUD, no slow-mo, no input
var net_mode := Net.OFFLINE # OFFLINE (couch), SERVER (authoritative, headless) or CLIENT (puppets)
var anet: ArenaNet
var map_key := "" # map file name, so clients can load the same map
var ev_mute := 0 # server: >0 while running code whose effects clients recreate themselves
var ev_owner := -1 # server: pid of the fighter being ticked (tags its events)
var fx_mute := 0 # client: >0 while simulating our predicted fighter
var next_net_id := 1
var spawn_points: Array = []


func setup(parts: Array, map: Dictionary) -> void:
	participants = parts
	map_data = map


func _ready() -> void:
	rng.seed = Time.get_ticks_usec()
	if net_mode != Net.OFFLINE:
		anet = ArenaNet.new(self)
	if net_mode == Net.SERVER:
		Sfx.recorder = record_sfx
	bg = Node2D.new()
	bg.set_script(load("res://scripts/world/background.gd"))
	add_child(bg)
	props_node = _layer("Props", 2)
	pickups_node = _layer("Pickups", 3)
	fighters_node = _layer("Fighters", 4)
	grenades_node = _layer("Grenades", 5)
	projectiles = Projectiles.new()
	projectiles.arena = self
	projectiles.z_index = 6
	add_child(projectiles)
	fx = FX.new()
	fx.arena = self
	fx.z_index = 8
	add_child(fx)
	camera = ArenaCamera.new()
	camera.arena = self
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	hud = Node2D.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	hud.arena = self
	hud_layer.add_child(hud)
	hud.visible = not attract
	start_round()


func _layer(nm: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = nm
	n.z_index = z
	add_child(n)
	return n


func start_round() -> void:
	var new_match := match_winner != null
	if match_winner:
		Game.scores.clear()
		round_num = 0
		match_winner = null
	if net_mode == Net.SERVER and new_match and not Game.maps.is_empty():
		# New match on the server: rotate to the next map.
		Game.map_index = (Game.map_index + 1) % Game.maps.size()
		map_data = Game.maps[Game.map_index]["data"]
		map_key = Game.maps[Game.map_index]["name"]
	round_num += 1
	round_t = 0.0
	intro_t = 0.0 if Game.args.has("scenario") or Game.args.has("quick") and DisplayServer.get_name() == "headless" else INTRO
	round_over_t = -1.0
	round_winner = null
	for n in [props_node, pickups_node, grenades_node, fighters_node]:
		for c in n.get_children():
			c.queue_free()
	if terrain:
		terrain.queue_free()
	terrain = Terrain.new()
	terrain.arena = self
	terrain.z_index = 1
	add_child(terrain)
	var ents := terrain.load_rows(map_data.get("tiles", []))
	terrain.tile_destroyed.connect(func(_c, _m): Game.stat("tiles_destroyed"))
	terrain.track_changes = net_mode == Net.SERVER
	if net_mode != Net.CLIENT:
		nav = NavGraph.new(terrain)
		terrain.tile_destroyed.connect(nav.on_tile_changed)
	bg.size = terrain.pixel_size()
	bg.queue_redraw()
	kill_y = terrain.pixel_size().y + 48.0
	fx.clear()
	projectiles.clear()
	pending_explosions.clear()

	fighters.clear()
	var spawns: Array = ents["spawns"].duplicate()
	if spawns.is_empty():
		spawns.append(terrain.pixel_size() * Vector2(0.5, 0.3))
	spawn_points = spawns.duplicate()
	if net_mode == Net.CLIENT:
		anet.puppets = {"p": {}, "g": {}, "o": {}}
		camera.snap()
		return
	_shuffle(spawns)
	for i in participants.size():
		var p: Dictionary = participants[i]
		_spawn_fighter(p, spawns[i % spawns.size()] + Vector2((i / spawns.size()) * 6, 0))
	for pos in ents["crates"]:
		_spawn_prop("crate", pos)
	for pos in ents["barrels"]:
		_spawn_prop("barrel", pos)
	drop_t = rng.randf_range(10.0, 16.0)
	spawners.clear()
	for pos in ents["spawners"]:
		spawners.append({"pos": pos, "t": rng.randf_range(6.0, 12.0)})
		if rng.randf() < 0.6:
			_spawn_random_at(pos)
	camera.snap()
	if intro_t > 0.0 and not attract:
		Sfx.play("countdown_beep")
	if net_mode == Net.SERVER:
		net_roster_changed()


func _spawn_fighter(p: Dictionary, pos: Vector2) -> Fighter:
	var f := Fighter.new()
	f.setup(p.get("pid", fighters.size()), p["name"], p["color"], p["source"], self)
	f.position = pos
	f.facing = 1 if f.position.x < terrain.pixel_size().x / 2.0 else -1
	f.died.connect(_on_died)
	fighters_node.add_child(f)
	f.reset_physics_interpolation()
	fighters.append(f)
	return f


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _spawn_prop(kind: String, pos: Vector2) -> void:
	var p := Prop.new()
	p.setup(kind, self)
	p.net_id = _new_id()
	p.position = pos
	props_node.add_child(p)


func _spawn_random_at(pos: Vector2) -> void:
	var d := Items.pick_random(rng)
	if d:
		spawn_pickup(d, null, pos + Vector2(0, -2), Vector2.ZERO, null)


func _process(dt: float) -> void:
	# Slow-motion on the round-winning kill (real time, so it ends on schedule).
	if slowmo_t > 0.0:
		slowmo_t -= dt / maxf(Engine.time_scale, 0.01)
		Engine.time_scale = lerpf(1.0, 0.22, clampf(slowmo_t / 0.4, 0.0, 1.0))
		if slowmo_t <= 0.0:
			Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_exit_tree_net()


func _physics_process(dt: float) -> void:
	if net_mode == Net.CLIENT:
		time += dt
		for f in feed:
			f[2] -= dt
		feed = feed.filter(func(e): return e[2] > 0.0)
		anet.client_tick(dt)
		return
	if net_mode == Net.SERVER and Net.clients.is_empty():
		return # nobody connected: don't burn the home server's CPU
	time += dt
	round_t += dt
	if intro_t > 0.0 and intro_t - dt <= 0.0 and not attract:
		Sfx.play("round_start")
	intro_t = maxf(0.0, intro_t - dt)
	nav.step()
	# Delayed explosions (barrel chains)
	var i := pending_explosions.size() - 1
	while i >= 0:
		pending_explosions[i][0] -= dt
		if pending_explosions[i][0] <= 0.0:
			var e: Array = pending_explosions[i]
			pending_explosions.remove_at(i)
			explode(e[1], e[2], e[3])
		i -= 1

	for f in fighters:
		if not f.alive() and f.global_position.y > kill_y:
			f.visible = false
			continue
		var frame: InputFrame = f.source.sample(f, self) if f.alive() and round_over_t < 0.0 and intro_t <= 0.0 else InputFrame.new()
		ev_owner = f.player_index
		f.tick(dt, frame)
		ev_owner = -1
		if f.alive() and f.global_position.y > kill_y:
			f.die(f.last_hitter, "fall")

	for s in spawners:
		s["t"] -= dt
		if s["t"] <= 0.0:
			s["t"] = rng.randf_range(9.0, 15.0)
			var occupied := false
			for p in pickups():
				if p.global_position.distance_to(s["pos"]) < 14.0:
					occupied = true
			if not occupied:
				_spawn_random_at(s["pos"])
				Sfx.play("pickup_small", s["pos"], -8.0)
				fx.flash(s["pos"] + Vector2(0, -4), 6.0, Color(1, 1, 0.7), 0.2)

	drop_t -= dt
	if drop_t <= 0.0 and round_over_t < 0.0:
		# Wider maps get drops more often.
		drop_t = rng.randf_range(16.0, 24.0) * clampf(60.0 / float(terrain.width), 0.4, 1.0)
		_supply_drop()

	for f in feed:
		f[2] -= dt
	feed = feed.filter(func(e): return e[2] > 0.0)

	_check_round(dt)
	if net_mode == Net.SERVER:
		anet.server_tick()
	if Game.args.has("trace-every"):
		var f0: Fighter = fighters[0]
		if Engine.get_physics_frames() % int(Game.args["trace-every"]) == 0:
			var extra := ""
			if f0.source is BotSource:
				var b: BotSource = f0.source
				extra = " path=%d %s mv=%s dbg=%s" % [b.path.size(), str(b.path[1]) if b.path.size() > 1 else "-", f0.inp.move, b.dbg]
			print("[t %.2f] pos=(%.1f,%.1f) v=(%.0f,%.0f) %s floor=%s mask6=%s%s" % [time, f0.global_position.x, f0.global_position.y,
				f0.velocity.x, f0.velocity.y, Fighter.S.keys()[f0.state], f0.is_on_floor(), f0.get_collision_mask_value(6), extra])
	if Game.args.has("trace") and Engine.get_physics_frames() % 180 == 0:
		var line := "[trace t=%.0f]" % time
		for f in fighters:
			var g := ""
			if f.source is BotSource:
				var pth: Array = f.source.path
				g = " goal=(%d,%d) path=%d %s wpn=%s mv=%s dbg=%s fl=%s" % [f.source.goal.x / 8, f.source.goal.y / 8, pth.size(),
					str(pth[1]) if pth.size() > 1 else "-", f.weapon.def.id if f.weapon else "-", f.inp.move, f.source.dbg, f.is_on_floor()]
			line += " %s@(%d,%d) %s hp%d%s |" % [f.display_name, f.global_position.x / 8, f.global_position.y / 8, Fighter.S.keys()[f.state], f.hp, g]
		print(line)


## A weapon floats down from the sky somewhere it can land.
func _supply_drop() -> void:
	var d := Items.pick_random(rng)
	if d == null:
		return
	for attempt in 12:
		var x := rng.randf_range(24.0, terrain.pixel_size().x - 24.0)
		var y := 4.0
		var start_y := -12.0
		while y < 24.0 and terrain.is_solid_at(Vector2(x, y)): # enclosed map: start under the ceiling
			y += 8.0
			start_y = y + 4.0
		if terrain.is_solid_at(Vector2(x, y)):
			continue
		var y0 := y
		while y < terrain.pixel_size().y and not terrain.is_solid_at(Vector2(x, y)):
			y += 8.0
		if y >= terrain.pixel_size().y - 8.0 or y - y0 < 24.0:
			continue # bottomless pit, or no room
		var p := spawn_pickup(d, null, Vector2(x, start_y), Vector2.ZERO, null)
		p.chute = true
		Game.stat("supply_drops")
		fx.text(Vector2(x, start_y + 26.0), "SUPPLY DROP", Color(1, 0.85, 0.4))
		Sfx.play("pickup_small", Vector2(x, start_y + 26.0), -2.0)
		return


func _check_round(dt: float) -> void:
	if Game.args.has("scenario"):
		return # tests inspect the fighters as they are; no respawns
	if round_over_t >= 0.0:
		round_over_t -= dt
		if round_over_t <= 0.0:
			start_round()
		return
	var alive := fighters.filter(func(f): return f.alive())
	var over := alive.size() <= 1 if fighters.size() > 1 else alive.is_empty()
	if over:
		round_over_t = ROUND_END_DELAY
		round_winner = alive[0] if alive.size() == 1 else null
		if round_winner:
			Game.add_score(round_winner.player_index)
			if Game.score_of(round_winner.player_index) >= WIN_SCORE and fighters.size() > 1:
				match_winner = round_winner
				round_over_t = MATCH_END_DELAY
		if not attract:
			Sfx.play("round_win" if round_winner else "death")
		if DisplayServer.get_name() != "headless" and fighters.size() > 1 and not attract:
			Sfx.play("slowmo")
			slowmo_t = 1.4
			camera.punch(1.35)


func _on_died(victim: Fighter, killer: Fighter, cause: String) -> void:
	Game.stat("death_" + cause)
	var s := ""
	if killer and killer != victim:
		s = "%s > %s" % [killer.display_name, victim.display_name]
	else:
		s = "%s %s" % [victim.display_name, {"fall": "FELL", "explosion": "EXPLODED", "fire": "BURNED", "left": "LEFT"}.get(cause, "DIED")]
	feed.append([s, killer.color if killer else victim.color, 4.0])
	record("feed", [s, killer.color if killer else victim.color])
	shake(3.0)


func _unhandled_input(e: InputEvent) -> void:
	if attract:
		return
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		Sfx.play("ui_back")
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		Game.goto_menu()
	elif e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_BACK:
		Game.goto_menu()


# ---------------------------------------------------------------- world API

func props() -> Array:
	return props_node.get_children().filter(func(p): return not p.is_queued_for_deletion() and not p.dead)


func pickups() -> Array:
	return pickups_node.get_children().filter(func(p): return not p.is_queued_for_deletion())


func grenades() -> Array:
	return grenades_node.get_children().filter(func(g): return not g.is_queued_for_deletion())


func spawn_pickup(def: WeaponDef, st: WeaponState, pos: Vector2, vel: Vector2, thrown_by: Fighter, cnt := -1) -> Pickup:
	var p := Pickup.new()
	p.setup(def, st, self, cnt)
	p.net_id = _new_id()
	p.position = pos
	p.velocity = vel
	p.thrown_by = thrown_by
	if thrown_by:
		p.no_pick_by = thrown_by
		p.no_pick_t = 0.5
	pickups_node.add_child(p)
	return p


func remove_pickup(p: Node) -> void:
	p.queue_free()


func spawn_grenade(def: WeaponDef, who: Fighter, pos: Vector2, vel: Vector2) -> void:
	var g := Grenade.new()
	g.net_id = _new_id()
	g.position = pos
	g.setup(def, who, self, vel)
	grenades_node.add_child(g)


func queue_explosion(pos: Vector2, data: Dictionary, src: Fighter, delay: float) -> void:
	pending_explosions.append([delay, pos, data, src])


func explode(pos: Vector2, data: Dictionary, src: Fighter, power := 1.0) -> void:
	Game.stat("explosions")
	var r: float = data.get("radius", 30.0)
	Sfx.play("explosion", pos, clampf(linear_to_db(r * power / 30.0), -10.0, 4.0), 0.1)
	var dmg: float = data.get("damage", 60.0) * power
	var kb: float = data.get("knockback", 200.0) * power
	terrain.damage_circle(pos, r, float(data.get("terrain_damage", 60.0)) * power)
	if net_mode == Net.SERVER:
		record("scorch", [pos, r * 0.9])
	else:
		terrain.scorch(pos, r * 0.9)
	var reach := r * 1.25
	for f in fighters:
		var d: float = f.center().distance_to(pos)
		if d > reach:
			continue
		var k := 1.0 - d / reach
		var dir: Vector2 = (f.center() - pos).normalized() if d > 0.5 else Vector2.UP
		dir = (dir + Vector2(0, -0.6)).normalized()
		f.apply_hit({"dmg": dmg * k, "kb": dir * kb * (0.4 + 0.6 * k), "src": src, "kind": "explosion",
			"knockdown": k > 0.25, "from_x": pos.x})
	for p in props():
		var d: float = p.global_position.distance_to(pos)
		if d < reach:
			p.take_damage(dmg * (1.0 - d / reach), src, (p.global_position - pos).normalized() * kb)
	for p in pickups():
		var d: float = p.global_position.distance_to(pos)
		if d < reach:
			p.velocity += ((p.global_position - pos).normalized() + Vector2(0, -0.5)) * kb * 0.8
			p.spin = rng.randf_range(-20, 20)
	for g in grenades():
		var d: float = g.global_position.distance_to(pos)
		if d < reach and not g.done:
			g.bat((g.global_position - pos).normalized() * kb * 0.8, g.thrower)
	fx.flash(pos, r * 0.45, Color(1, 1, 0.85, 0.8), 0.04)
	fx.fireball(pos, r)
	fx.burst(pos, Color(1, 0.75, 0.3), int(r * 0.6), r * 4.5, 0.35, 250.0, true)
	if data.has("fire"):
		var fire: Dictionary = data["fire"]
		for n in int(fire.get("count", 8)):
			fx.spawn_flame(pos, Vector2(rng.randf_range(-110, 110), rng.randf_range(-160, -40)), src,
				float(fire.get("dps", 25)), float(fire.get("duration", 4.0)))
	shake(clampf(r / 6.0, 2.0, 12.0))


func shake(amount: float) -> void:
	record("shake", [amount])
	camera.add_shake(amount)


# ---------------------------------------------------------------- online

func _new_id() -> int:
	next_net_id += 1
	return next_net_id


func _exit_tree_net() -> void:
	if Sfx.recorder == Callable(self, "record_sfx"):
		Sfx.recorder = Callable()


## Server: remember something clients must see/hear (they recreate it from the snapshot).
func record(kind: String, args: Array) -> void:
	if net_mode == Net.SERVER and ev_mute == 0:
		anet.events.append([kind, args, ev_owner])


func record_sfx(sound: String, pos: Variant, vol_db: float, pitch_var: float) -> void:
	record("sfx", [sound, pos, vol_db, pitch_var])


func source_of(pid: int) -> InputSource:
	for f in fighters:
		if f.player_index == pid:
			return f.source
	return null


## Server: new participants drop straight into the running round.
func net_join(pids: Array) -> void:
	for pid in pids:
		var p := Game.participant(pid)
		if p.is_empty() or source_of(pid) != null:
			continue
		# Spawn as far as possible from everyone else.
		var best: Vector2 = spawn_points[0] if not spawn_points.is_empty() else terrain.pixel_size() * Vector2(0.5, 0.3)
		var bd := -1.0
		for sp in spawn_points:
			var d := INF
			for f in fighters:
				if f.alive():
					d = minf(d, f.global_position.distance_to(sp))
			if d > bd:
				bd = d
				best = sp
		var f := _spawn_fighter(p, best)
		f.invuln_t = 1.5
		fx.burst(f.center(), Color(1, 1, 1, 0.7), 10, 60.0, 0.4, -20.0, false, 2.0)


## Server: these participants are gone (disconnected, or a bot making room).
func net_leave(pids: Array) -> void:
	for f in fighters:
		if f.player_index in pids and not f.left:
			f.leave()
	net_roster_changed()


func net_roster_changed() -> void:
	if net_mode == Net.SERVER and anet:
		Net.broadcast_roster(anet.roster_list())


## Client: the server started a new round (or a new map).
func client_new_round(key: String, num: int) -> void:
	var m := Game.map_by_name(key)
	if not m.is_empty():
		map_data = m
	map_key = key
	match_winner = null
	for f in fighters:
		f.queue_free()
	fighters.clear()
	anet.history.clear()
	anet.pending_me = PackedFloat32Array()
	start_round()
	round_num = num
