class_name BotSource
extends InputSource
## Simple AI that produces InputFrames like any other device.
## Grabs weapons, chases the nearest enemy, aims Superfighters-style and shoots,
## brawls up close, dives, climbs ladders and runs from grenades.

var skill := 0.7 # 0..1: reaction speed and accuracy
var rng := RandomNumberGenerator.new()
var target: Fighter = null
var goal := Vector2.ZERO
var think_t := 0.0
var jump_hold := 0.0
var attack_toggle := false
var stuck_t := 0.0
var last_x := 0.0
var wander_dir := 1
var react_t := 0.0
var charge_hold := 0.0
var jump_cd := 0.0
var path: Array = []
var want_dive := false
var best_d := INF
var frustration := 0.0
var detour_t := 0.0
var detour_goal := Vector2.ZERO
var arena_ref: Node
var dbg := ""
var last_y := 0.0
var climb_stuck := 0.0
var aim_err := 0.0


func _init(idx: int, s := 0.7) -> void:
	label = "BOT %d" % idx
	is_bot = true
	skill = s
	rng.seed = idx * 7919 + Time.get_ticks_usec()


func device_key() -> String:
	return label


func sample(me: Node, arena: Node) -> InputFrame:
	arena_ref = arena
	var f := InputFrame.new()
	var dt := 1.0 / Engine.physics_ticks_per_second
	var fighter := me as Fighter
	dbg = ""
	if not fighter.alive():
		return f
	var t: Terrain = arena.terrain
	var pos := fighter.global_position
	var center := fighter.center()

	think_t -= dt
	detour_t -= dt
	if think_t <= 0.0:
		think_t = lerpf(0.5, 0.15, skill)
		_think(fighter, arena)
	# Not getting any closer for 4s? Head somewhere else for a bit.
	var gd := center.distance_to(goal)
	if gd < best_d - 8.0:
		best_d = gd
		frustration = 0.0
	else:
		frustration += dt
	if frustration > 4.0:
		frustration = 0.0
		best_d = INF
		detour_t = 4.0
		var spots: Array = arena.pickups().map(func(p): return p.global_position)
		for o in arena.fighters:
			if o != fighter and o.alive():
				spots.append(o.global_position)
		if not spots.is_empty():
			detour_goal = spots[rng.randi_range(0, spots.size() - 1)]
		path = []
		_req_jump(0.3)

	# Run from live grenades.
	for g in arena.grenades():
		if g.global_position.distance_to(center) < 46.0 and g.fuse < 2.0:
			dbg = "grenade"
			if g.stuck_to == fighter:
				# Run at an enemy and hope.
				if target:
					f.move.x = int(signf(target.global_position.x - pos.x))
					f.sprint = true
				return f
			f.move.x = -int(signf(g.global_position.x - pos.x)) if g.global_position.x != pos.x else wander_dir
			f.sprint = true
			if fighter.is_on_floor() and rng.randf() < 0.1:
				_req_jump(0.2)
			f.jump = _jump(dt)
			return f

	var kind := fighter.weapon_kind()
	if target and target.alive():
		var tc := target.center()
		var to := tc - center
		var dist := to.length()
		# Shooting
		if kind == "gun" and dist < 320.0 and t.line_clear(center, tc):
			# Superfighters aiming: hold AIM, face them, sweep the sight up/down, fire when on.
			var side := int(signf(to.x)) if absf(to.x) > 1.0 else fighter.facing
			var want := Vector2(absf(to.x), to.y).angle() + aim_err # relative to facing
			var level := absf(to.y) < 6.0 and side == fighter.facing
			react_t += dt
			if react_t > lerpf(0.4, 0.1, skill) or level:
				dbg = "shoot"
				var tol := deg_to_rad(lerpf(5.0, 2.0, skill)) + atan2(5.0, dist)
				var on := false
				if level and not fighter.aiming:
					on = true # hip fire, they're right in front of us
				else:
					f.aim = true
					if fighter.facing != side or not fighter.aiming:
						f.move.x = side
					else:
						var diff := want - fighter.aim_ang
						if absf(diff) > tol * 0.6:
							f.move.y = int(signf(diff))
						on = absf(diff) < tol
				if on:
					var d: WeaponDef = fighter.weapon.def
					if d.charge_time > 0.0:
						charge_hold += dt
						f.attack = charge_hold < d.charge_time + 0.05
						if not f.attack:
							charge_hold = 0.0
					elif d.auto:
						f.attack = true
					else:
						attack_toggle = not attack_toggle
						f.attack = attack_toggle
				return f
		else:
			react_t = 0.0
		# Grenades
		if fighter.throwable and dist > 50.0 and dist < 160.0 and rng.randf() < 0.01 + skill * 0.01:
			f.throw = true
		# Melee
		var reach := 10.0
		if kind == "melee":
			reach = fighter.weapon.def.reach
		if absf(to.x) < reach + 4.0 and absf(to.y) < 14.0:
			dbg = "melee"
			f.move.x = int(signf(to.x)) if absf(to.x) > 1.0 else 0
			if fighter.facing != int(signf(to.x)) and to.x != 0.0:
				return f # turn first
			f.move.x = 0
			# Block sometimes when they're swinging at us.
			if target.state == Fighter.S.ATTACK and rng.randf() < skill * 0.5 and kind != "gun":
				f.aim = true
				return f
			attack_toggle = not attack_toggle
			f.attack = attack_toggle
			return f
		# Dive at medium range on the same level.
		if kind != "gun" and absf(to.y) < 8.0 and absf(to.x) > 30.0 and absf(to.x) < 80.0 \
				and absf(fighter.velocity.x) > Fighter.RUN * 1.1 and rng.randf() < 0.04 * skill:
			f.move.x = int(signf(to.x))
			f.sprint = true
			_req_jump(0.1)
			f.jump = _jump(dt)
			return f

	dbg = "nav"
	_navigate(f, fighter, t, dt)
	return f


func _think(fighter: Fighter, arena: Node) -> void:
	var center := fighter.center()
	var best: Fighter = null
	var bd := INF
	for o in arena.fighters:
		if o != fighter and o.alive():
			var d: float = o.center().distance_to(center)
			if d < bd:
				bd = d
				best = o
	if best != target:
		react_t = 0.0
	target = best
	aim_err = rng.randf_range(-1.0, 1.0) * deg_to_rad(lerpf(9.0, 1.5, skill))
	goal = target.global_position if target else center
	if detour_t > 0.0:
		goal = detour_goal
	if fighter.weapon == null or (fighter.weapon.def.kind == "melee" and rng.randf() < 0.3):
		var pd := INF
		for p in arena.pickups():
			if p.thrown_by != null or p.is_empty_gun():
				continue
			var d: float = p.global_position.distance_to(center)
			if d < pd and d < maxf(bd * 1.3, 120.0):
				pd = d
				goal = p.global_position
	var t: Terrain = arena.terrain
	var here := _here(fighter, t)
	if Nav.standable(t, here) or path.is_empty():
		var gc := Nav.ground_cell(t, goal)
		path = arena_ref.nav.find_path(here, gc)
		# Can't reach that pickup? Forget it and go fight.
		if target and goal != target.global_position and not path.is_empty():
			var end: Vector2i = path[-1][0]
			if absi(end.x - gc.x) + absi(end.y - gc.y) > 2:
				goal = target.global_position
				path = arena_ref.nav.find_path(here, Nav.ground_cell(t, goal))


## The nav cell we're on. Standing on a crate/barrel counts as the cell under it.
func _here(fighter: Fighter, t: Terrain) -> Vector2i:
	var c := Nav.feet_cell(t, fighter.global_position)
	if fighter.is_on_floor() and not Nav.standable(t, c):
		# Balanced on a ledge corner: the neighbouring cell is the one holding us up.
		var lx := fmod(fighter.global_position.x, Terrain.TILE)
		var side := Vector2i(-1 if lx < Terrain.TILE / 2.0 else 1, 0)
		if Nav.standable(t, c + side):
			return c + side
		if Nav.standable(t, c - side):
			return c - side
		return Nav.ground_cell(t, fighter.global_position) # on a crate/barrel
	return c


func _navigate(f: InputFrame, fighter: Fighter, t: Terrain, dt: float) -> void:
	var pos := fighter.global_position
	var on_floor := fighter.is_on_floor()
	var climbing := fighter.state == Fighter.S.CLIMB
	if fighter.state == Fighter.S.LEDGE:
		# Hanging: pull up if where we're going is up there, otherwise let go.
		var nxt_up: bool = path.size() > 1 and path[1][0].y < Nav.feet_cell(t, pos).y
		if goal.y < pos.y - 10.0 or nxt_up:
			f.move.y = -1
		else:
			f.move.y = 1
		return
	var here := _here(fighter, t)
	# Advance along the path: skip nodes we've reached.
	var idx := -1
	for i in path.size():
		if path[i][0] == here:
			idx = i
	var on_path := idx >= 0
	if on_path:
		path = path.slice(idx)
	elif Nav.standable(t, here) and (on_floor or climbing):
		# Off the plan (knocked around, landed somewhere else): replan from here.
		path = arena_ref.nav.find_path(here, Nav.ground_cell(t, goal))
		on_path = true
	if climbing:
		climb_stuck = climb_stuck + dt if absf(pos.y - last_y) < 0.1 else 0.0
		last_y = pos.y
		if climb_stuck > 0.8:
			# Blocked on a ladder (crate on the hatch, someone above): bail.
			climb_stuck = 0.0
			path = []
			_req_jump(0.1)
			f.move.x = fighter.facing
			f.jump = _jump(dt)
			return
	if not on_path and not path.is_empty():
		var nxt_cell: Vector2i = path[mini(1, path.size() - 1)][0]
		if climbing:
			# Between ladder cells (e.g. head poking through a platform): keep climbing.
			f.move.y = signi(nxt_cell.y - here.y) if nxt_cell.y != here.y else -1
			return
		# Airborne between nodes: steer at the node we're heading for, nothing else.
		var aim_x := t.cell_center(nxt_cell).x
		if absf(aim_x - pos.x) > 2.0:
			f.move.x = int(signf(aim_x - pos.x))
		f.jump = fighter.inp.jump and fighter.velocity.y < 0.0 # keep holding for full height
		jump_hold = 0.0
		return
	if path.size() < 2:
		# At the goal (or no route): walk straight at it.
		var dx := goal.x - pos.x
		if absf(dx) > 4.0:
			f.move.x = int(signf(dx))
		if climbing:
			f.move.y = -1 if goal.y < pos.y else 1
		_unstick(f, fighter, t, dt, f.move.x if f.move.x != 0 else fighter.facing)
		f.jump = _jump(dt)
		return
	var cur: Vector2i = path[0][0]
	var nxt: Vector2i = path[1][0]
	var edge: String = path[1][1]
	var tx := t.cell_center(nxt).x
	var dir := int(signf(tx - pos.x)) if absf(tx - pos.x) > 1.5 else 0
	match edge:
		"walk", "drop":
			f.move.x = dir
			if climbing:
				_req_jump(0.1)
		"jump", "leap", "ledge":
			f.move.x = dir
			f.sprint = edge == "leap" or absi(nxt.x - cur.x) >= 3
			var take_off := t.cell_center(cur).x
			# Line up under/near the takeoff cell, then go.
			if on_floor and (absf(pos.x - take_off) < 3.0 or edge == "leap" or nxt.x == cur.x):
				_req_jump(0.32)
			elif not on_floor:
				f.move.x = dir
		"climb":
			if not climbing:
				f.move.x = int(signf(t.cell_center(cur).x - pos.x)) if absf(t.cell_center(cur).x - pos.x) > 2.0 else 0
			f.move.y = signi(nxt.y - cur.y)
			if f.move.y == 0:
				f.move.y = -1
		"climbdown":
			var cx := t.cell_center(cur).x
			if absf(cx - pos.x) > 2.0:
				f.move.x = int(signf(cx - pos.x))
			else:
				f.move.y = 1
		"pdrop":
			if on_floor and t.is_platform_at(pos + Vector2(0, 2)):
				f.move.y = 1
				_req_jump(0.05)
			else:
				f.move.x = dir # plan doesn't match where we are; drift toward it
	f.sprint = f.sprint or (absf(goal.x - pos.x) > 90.0 and fighter.weapon_kind() != "gun" and edge == "walk")
	_unstick(f, fighter, t, dt, dir if dir != 0 else fighter.facing)
	last_x = pos.x
	f.jump = _jump(dt)
	if f.jump and not fighter.inp.jump and not want_dive:
		f.sprint = false # sprint+jump would dive; a real jump goes higher


func _unstick(f: InputFrame, fighter: Fighter, t: Terrain, dt: float, dir: int) -> void:
	var pos := fighter.global_position
	if fighter.is_on_floor() and f.move.x != 0 and absf(pos.x - last_x) < 0.2:
		stuck_t += dt
		var wall := t.is_solid_at(pos + Vector2(dir * 6.0, -4.0)) or t.is_solid_at(pos + Vector2(dir * 6.0, -12.0))
		if stuck_t > 0.4 and wall:
			# Break through: punch / swing / shoot whatever is in the way.
			attack_toggle = not attack_toggle
			f.attack = attack_toggle
			if fighter.weapon_kind() == "gun":
				f.aim = true
				f.move = Vector2i(dir, 0)
		if stuck_t > 0.7:
			_req_jump(0.3)
		if stuck_t > 2.5:
			path = []
			stuck_t = 0.0
	else:
		stuck_t = 0.0
	last_x = pos.x


func _req_jump(dur: float) -> void:
	if jump_hold <= 0.0 and jump_cd <= 0.0:
		jump_hold = dur
		jump_cd = dur + 0.08


func _jump(dt: float) -> bool:
	jump_cd -= dt
	if jump_hold > 0.0:
		jump_hold -= dt
		return true
	return false
