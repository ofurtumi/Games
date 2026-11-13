class_name Fighter
extends CharacterBody2D
## A player character. Driven entirely by InputFrames passed to tick() by the Arena.
## Origin is at the feet.

signal died(victim: Fighter, killer: Fighter, cause: String)

enum S { NORMAL, ATTACK, DIVE, ROLL, STOMP, DOWN, STUN, CLIMB, DEAD, LEDGE, LEDGE_UP, SLIDE }

const GRAVITY := 950.0
const FALL_MULT := 1.3 # heavier on the way down: snappy arcs
const APEX_MULT := 0.6 # brief hang at the top while jump is held
const MAX_FALL := 450.0
const RUN := 95.0
const SPRINT := 150.0
const ACC_GROUND := 1500.0
const TURN_ACC := 2400.0
const ACC_AIR := 950.0
const JUMP_V := -270.0
const JUMP_CUT_V := -80.0
const COYOTE := 0.08
const BUFFER := 0.12
const CLIMB_V := 65.0
const STAND_H := 18.0
const LOW_H := 10.0
const AIM_MIN_SPD := 0.9 # rad/s when you start sweeping (taps = fine adjustments)
const AIM_MAX_SPD := 4.2
const AIM_ACCEL := 11.0
const AIM_MEMORY := 0.6 # re-aiming within this many seconds keeps the old angle

## Unarmed moveset. a0..a1 = active hit window (seconds into the move).
const MOVES := {
	"punch": {"dur": 0.22, "a0": 0.05, "a1": 0.11, "dmg": 7.0, "kb": Vector2(80, -30), "reach": 9.0, "stun": 0.25, "terrain": 2.0},
	"hook": {"dur": 0.4, "a0": 0.1, "a1": 0.18, "dmg": 12.0, "kb": Vector2(190, -110), "reach": 10.0, "stun": 0.45, "terrain": 4.0},
	"lunge": {"dur": 0.42, "a0": 0.04, "a1": 0.24, "dmg": 11.0, "kb": Vector2(230, -120), "reach": 9.0, "knockdown": true, "terrain": 6.0},
	"kick": {"dur": 0.5, "a0": 0.03, "a1": 0.45, "dmg": 13.0, "kb": Vector2(210, -80), "reach": 9.0, "knockdown": true, "terrain": 3.0},
}

var player_index := 0
var display_name := "P1"
var color := Color(0.9, 0.25, 0.25)
var source: InputSource
var arena: Node

var hp := 100.0
var max_hp := 100.0
var facing := 1
var state := S.NORMAL
var state_t := 0.0
var state_len := 0.0
var inp := InputFrame.new()
var prev := InputFrame.new()

var coyote_t := 0.0
var buffer_t := 0.0
var drop_t := 0.0
var jumping := false
var aiming := false
var blocking := false
var crouching := false
var aim_dir := Vector2.RIGHT
var aim_ang := 0.0 # radians relative to facing; negative = up
var aim_spd := 0.0
var aim_rest_t := 99.0
var was_aiming := false
var combo := 0
var combo_t := 0.0
var cur_move := {}
var cur_move_name := ""
var attack_hit := {}
var terrain_hit_done := false
var invuln_t := 0.0
var hurt_flash := 0.0
var walk_phase := 0.0
var last_hitter: Fighter = null
var last_hit_t := 0.0
var gibbed := false
var fall_speed := 0.0
var empty_t := 0.0

var weapon: WeaponState = null
var throwable: WeaponDef = null
var throw_count := 0

var shape: RectangleShape2D
var col: CollisionShape2D

# visuals
var visual: Node2D
var body: Sprite2D
var arm_pivot: Node2D
var arm_spr: Sprite2D
var wpn_spr: Sprite2D
var sq := Vector2.ONE # squash & stretch
var was_on_floor := true
var ledge_cell := Vector2i.ZERO
var ledge_cd := 0.0
var ledge_from := Vector2.ZERO
var ledge_to := Vector2.ZERO
var vault_t := 0.0
var arm_kick := 0.0
var hitstop_t := 0.0 # brief freeze when a melee hit lands (both fighters)
var puppet := false # online client: the server simulates this fighter, we only draw it
var net_floor := false
var left := false # online: player disconnected / bot made room
var _prev_vy := 0.0


func setup(idx: int, nm: String, c: Color, src: InputSource, a: Node) -> void:
	player_index = idx
	display_name = nm
	color = c
	source = src
	arena = a


func _ready() -> void:
	collision_layer = Layers.FIGHTERS
	collision_mask = Layers.BODY_MASK
	floor_snap_length = 3.0
	floor_max_angle = deg_to_rad(50)
	shape = RectangleShape2D.new()
	shape.size = Vector2(6, STAND_H)
	col = CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -STAND_H / 2.0)
	add_child(col)
	_build_visual()


# ---------------------------------------------------------------- queries

func alive() -> bool:
	return state != S.DEAD


func height() -> float:
	return shape.size.y


func center() -> Vector2:
	return global_position + Vector2(0, -height() * 0.5)


func hitbox() -> Rect2:
	return Rect2(global_position.x - 3.0, global_position.y - height(), 6.0, height())


func weapon_kind() -> String:
	return weapon.def.kind if weapon else ""


func _floor() -> bool:
	return net_floor if puppet else is_on_floor()


func _jp() -> bool: return inp.jump and not prev.jump
func _ap() -> bool: return inp.attack and not prev.attack
func _tp() -> bool: return inp.throw and not prev.throw
func _ip() -> bool: return inp.interact and not prev.interact


func _dir8() -> Vector2:
	if inp.move == Vector2i.ZERO:
		return Vector2(facing, 0)
	return Vector2(inp.move).normalized()


## Superfighters-style aiming: hold AIM to stand and raise a laser sight, then UP/DOWN
## sweep the angle smoothly (accelerating the longer you hold) and LEFT/RIGHT flip
## sides. Without AIM, guns hip-fire straight ahead. Pure function of InputFrames,
## so it stays deterministic for netplay.
func _update_aim(dt: float) -> void:
	if aiming:
		if not was_aiming and aim_rest_t > AIM_MEMORY:
			aim_ang = 0.0
		if inp.move.x != 0:
			facing = inp.move.x
		if inp.move.y != 0:
			aim_spd = minf(aim_spd + dt * AIM_ACCEL, AIM_MAX_SPD)
			aim_ang = clampf(aim_ang + inp.move.y * aim_spd * dt, -PI / 2.0, PI / 2.0)
		else:
			aim_spd = AIM_MIN_SPD
		aim_rest_t = 0.0
	else:
		aim_rest_t += dt
		aim_spd = AIM_MIN_SPD
	was_aiming = aiming
	var a := aim_ang if aiming else 0.0
	aim_dir = Vector2(cos(a) * facing, sin(a))


func muzzle_pos() -> Vector2:
	var sh := Art.shoulder(Art.frame(_anim_name()))
	var la := Vector2(aim_dir.x * facing, aim_dir.y)
	var w := Art.weapon(weapon.def)
	var local: Vector2 = sh + (Vector2(4, 0) + w["muzzle"] - w["grip"]).rotated(la.angle())
	return global_position + Vector2(local.x * facing, local.y)


func _set_state(s: S, length := 0.0) -> void:
	state = s
	state_t = 0.0
	state_len = length


# ---------------------------------------------------------------- tick

func tick(dt: float, frame: InputFrame) -> void:
	if hitstop_t > 0.0:
		hitstop_t -= dt
		inp = frame # keep the newest held state; presses still register afterwards
		visual.position = Vector2(arena.rng.randf_range(-1, 1), 0) if hurt_flash > 0.0 or hitstop_t > 0.02 else Vector2.ZERO
		return
	visual.position = Vector2.ZERO
	prev = inp
	inp = frame
	state_t += dt
	hurt_flash = maxf(0.0, hurt_flash - dt)
	invuln_t = maxf(0.0, invuln_t - dt)
	combo_t = maxf(0.0, combo_t - dt)
	ledge_cd = maxf(0.0, ledge_cd - dt)
	vault_t = maxf(0.0, vault_t - dt)
	last_hit_t -= dt
	if last_hit_t <= 0.0:
		last_hitter = null
	if drop_t > 0.0:
		drop_t -= dt
		if drop_t <= 0.0 and state != S.CLIMB:
			set_collision_mask_value(Layers.PLATFORM_BIT, true)
	if weapon:
		weapon.cooldown = maxf(0.0, weapon.cooldown - dt)
	if state != S.NORMAL:
		aiming = false
		blocking = false
		crouching = false

	match state:
		S.NORMAL: _normal(dt)
		S.ATTACK: _attack(dt)
		S.DIVE: _dive(dt)
		S.ROLL: _roll(dt)
		S.STOMP: _stomp(dt)
		S.DOWN, S.STUN: _hurt(dt)
		S.CLIMB: _climb(dt)
		S.DEAD: _dead(dt)
		S.LEDGE: _ledge(dt)
		S.LEDGE_UP: _ledge_up(dt)
		S.SLIDE: _slide(dt)

	_update_shape()
	fall_speed = velocity.y
	if state != S.LEDGE and state != S.LEDGE_UP:
		move_and_slide()
	_post_move()
	if is_on_floor() and not was_on_floor and fall_speed > 120.0 and state != S.DEAD:
		sq = Vector2(1.0 + fall_speed / 900.0, 1.0 - fall_speed / 1400.0)
		Sfx.play("land_heavy" if fall_speed > 330.0 else "land", global_position, -4.0)
	was_on_floor = is_on_floor()
	_update_visual(dt)


func _gravity(dt: float, mult := 1.0) -> void:
	var g := GRAVITY * mult
	if velocity.y > 0.0:
		g *= FALL_MULT
	elif jumping and inp.jump and absf(velocity.y) < 60.0:
		g *= APEX_MULT
	velocity.y = minf(velocity.y + g * dt, MAX_FALL)


func _normal(dt: float) -> void:
	var on_floor := is_on_floor()
	coyote_t = COYOTE if on_floor else coyote_t - dt
	buffer_t = BUFFER if _jp() else buffer_t - dt
	var kind := weapon_kind()
	aiming = inp.aim and kind == "gun"
	blocking = inp.aim and kind != "gun" and on_floor
	crouching = on_floor and inp.move.y > 0 and not aiming and not blocking
	_update_aim(dt)

	# Ladders (not while aiming: up/down moves the sight instead)
	var may_climb := not aiming
	if may_climb and inp.move.y < 0 and arena.terrain.is_ladder_at(center()):
		_start_climb()
		return
	if may_climb and inp.move.y > 0 and on_floor and (arena.terrain.is_ladder_at(global_position + Vector2(0, 4)) \
			or (arena.terrain.is_platform_at(global_position + Vector2(0, 4)) and arena.terrain.is_ladder_at(global_position + Vector2(0, 10)))):
		_start_climb()
		return

	# Horizontal
	var mult := weapon.def.move_mult if weapon else 1.0
	var target := 0.0
	if crouching:
		target = inp.move.x * 25.0
	elif not (aiming or blocking):
		target = inp.move.x * (SPRINT if inp.sprint else RUN) * mult
	if inp.move.x != 0 and not aiming:
		facing = inp.move.x
	var acc := ACC_GROUND if on_floor else (ACC_AIR if inp.move.x != 0 else 160.0)
	if on_floor and target != 0.0 and signf(target) != signf(velocity.x):
		acc = TURN_ACC
	velocity.x = move_toward(velocity.x, target, acc * dt)

	# Slide: sprinting + tap DOWN. Low enough to go under bullets.
	if on_floor and inp.move.y > 0 and prev.move.y <= 0 and inp.sprint and absf(velocity.x) > RUN * mult and not aiming:
		_set_state(S.SLIDE, 0.5)
		Game.stat("slides")
		Sfx.play("dive", global_position, -3.0)
		velocity.x = facing * maxf(absf(velocity.x) + 30.0, 200.0)
		sq = Vector2(1.2, 0.85)
		attack_hit.clear()
		arena.fx.burst(global_position, Color(0.75, 0.7, 0.65), 4, 30.0, 0.3, 50.0)
		return

	# Jump / drop / dive
	if buffer_t > 0.0 and coyote_t > 0.0 and not aiming:
		buffer_t = 0.0
		coyote_t = 0.0
		if inp.move.y > 0 and arena.terrain.is_platform_at(global_position + Vector2(0, 2)):
			drop_t = 0.25
			set_collision_mask_value(Layers.PLATFORM_BIT, false)
		elif inp.sprint and absf(velocity.x) > RUN * mult * 1.05:
			_set_state(S.DIVE)
			Game.stat("dives")
			velocity = Vector2(facing * 235.0, -175.0)
			Sfx.play("dive", global_position)
			sq = Vector2(1.3, 0.75)
			attack_hit.clear()
			return
		else:
			velocity.y = JUMP_V
			jumping = true
			sq = Vector2(0.75, 1.3)
			Sfx.play("jump", global_position, -4.0, 0.1)
	if jumping and not inp.jump and velocity.y < JUMP_CUT_V:
		velocity.y = JUMP_CUT_V
		jumping = false
	if velocity.y >= 0.0:
		jumping = false
	_gravity(dt)
	if not on_floor and _try_ledge():
		return
	if on_floor:
		_try_vault()

	# Actions: THROW picks up when standing on an item, otherwise throws.
	if _tp():
		if _pickups_touching().is_empty():
			_throw()
		else:
			_try_pickup()
	elif _ip():
		_try_pickup()
	if weapon_kind() == "gun":
		_gun(dt)
	elif _ap():
		_start_attack(on_floor)
	_auto_pickup()
	if on_floor:
		var step0 := int(walk_phase) / 4
		walk_phase += absf(velocity.x) * dt * 0.12
		if int(walk_phase) / 4 != step0:
			Sfx.play("footstep", global_position, -10.0, 0.2)


# ---------------------------------------------------------------- unarmed / melee

func _start_attack(on_floor: bool) -> void:
	if weapon_kind() == "melee":
		var d := weapon.def
		_begin_move("swing", {"dur": d.swing_time, "a0": d.swing_time * 0.3, "a1": d.swing_time * 0.6,
			"dmg": d.damage, "kb": Vector2(d.knockback, -d.knockback * 0.35), "reach": d.reach,
			"stun": 0.35, "terrain": d.terrain_damage, "knockdown": d.knockback >= 200.0})
		if d.style == "bigsword" and on_floor:
			velocity.x += facing * 60.0
		return
	if not on_floor:
		if inp.move.y > 0:
			_set_state(S.STOMP)
			attack_hit.clear()
			velocity = Vector2(velocity.x * 0.3, 380.0)
			return
		_begin_move("kick")
		velocity.x = facing * maxf(absf(velocity.x), 140.0)
		velocity.y = minf(velocity.y, -40.0)
		return
	if inp.sprint and absf(velocity.x) > RUN + 10.0:
		_begin_move("lunge")
		velocity.x = facing * 210.0
		return
	if combo_t > 0.0 and combo >= 2:
		combo = 0
		_begin_move("hook")
	else:
		combo = combo + 1 if combo_t > 0.0 else 1
		_begin_move("punch")
	combo_t = 0.55


func _begin_move(nm: String, data := {}) -> void:
	Game.stat("move_" + nm)
	cur_move_name = nm
	cur_move = data if not data.is_empty() else MOVES[nm]
	attack_hit.clear()
	terrain_hit_done = false
	_set_state(S.ATTACK, cur_move["dur"])
	Sfx.play("swing", center(), 0.0 if nm == "swing" else -7.0, 0.15)


func _attack(dt: float) -> void:
	var on_floor := is_on_floor()
	if cur_move_name == "kick":
		_gravity(dt, 0.8)
		if on_floor and state_t > 0.08:
			_set_state(S.NORMAL)
			return
	else:
		_gravity(dt)
		if on_floor:
			var fr := 500.0 if cur_move_name == "lunge" else 1400.0
			velocity.x = move_toward(velocity.x, 0.0, fr * dt)
		else:
			velocity.x = move_toward(velocity.x, inp.move.x * RUN, ACC_AIR * dt)
	if state_t >= cur_move["a0"] and state_t <= cur_move["a1"]:
		_do_hit(cur_move)
	if state_t >= state_len:
		_set_state(S.NORMAL)


func _hit_rect(reach: float) -> Rect2:
	var h := height()
	var x := global_position.x + 2.0 if facing > 0 else global_position.x - 2.0 - reach
	if cur_move_name == "kick":
		return Rect2(x, global_position.y - h * 0.7, reach, h * 0.6)
	return Rect2(x, global_position.y - h, reach, h - 2.0)


func _do_hit(m: Dictionary) -> void:
	var rect := _hit_rect(m["reach"])
	var kb: Vector2 = m["kb"]
	kb.x *= facing
	for f in arena.fighters:
		if f == self or attack_hit.has(f):
			continue
		if rect.intersects(f.hitbox()):
			attack_hit[f] = true
			var hit: bool = f.apply_hit({"dmg": m["dmg"], "kb": kb, "src": self, "kind": "melee",
				"stun": m.get("stun", 0.3), "knockdown": m.get("knockdown", false), "from_x": global_position.x})
			if hit:
				if cur_move_name == "swing" and weapon and weapon.def.style != "blunt":
					Sfx.play("blade_hit", f.center())
				elif cur_move_name in ["hook", "kick", "lunge"] or float(m["dmg"]) >= 15.0:
					Sfx.play("punch_heavy", f.center())
				else:
					Sfx.play("punch", f.center())
				arena.fx.burst(f.center(), Color(1, 1, 0.85), 4, 60.0, 0.15, 0.0)
				arena.shake(1.5 + float(m["dmg"]) / 25.0)
	for p in arena.props():
		if not attack_hit.has(p) and rect.intersects(p.rect()):
			attack_hit[p] = true
			p.take_damage(m["dmg"], self, kb)
	for g in arena.grenades():
		if not attack_hit.has(g) and rect.has_point(g.global_position):
			attack_hit[g] = true
			g.bat(Vector2(facing * 260.0, -120.0), self)
	if not terrain_hit_done and float(m.get("terrain", 0.0)) > 0.0:
		terrain_hit_done = true
		arena.terrain.damage_rect(rect, m["terrain"])


func _dive(dt: float) -> void:
	_gravity(dt)
	var r := hitbox().grow(2.0)
	for f in arena.fighters:
		if f != self and f.alive() and not attack_hit.has(f) and r.intersects(f.hitbox()):
			attack_hit[f] = true
			f.apply_hit({"dmg": 6.0, "kb": Vector2(facing * 170.0, -110.0), "src": self, "kind": "tackle",
				"knockdown": true, "from_x": global_position.x})
			velocity.x *= 0.35
			arena.shake(2.0)
			Sfx.play("punch_heavy", f.center())
	if _ap():
		_begin_move("kick")
		return
	if _tp():
		_throw()
	if _try_ledge():
		return
	if is_on_floor() and state_t > 0.05:
		_set_state(S.ROLL, 0.32)
		Sfx.play("roll", global_position, -4.0)
	elif is_on_wall() and state_t > 0.05:
		velocity.x = -facing * 50.0
		_set_state(S.STUN, 0.3)


func _slide(dt: float) -> void:
	_gravity(dt)
	velocity.x = move_toward(velocity.x, 0.0, 330.0 * dt)
	var feet := Rect2(global_position.x - 4.0 + facing * 3.0, global_position.y - 7.0, 8.0, 7.0)
	for f in arena.fighters:
		if f != self and f.alive() and not attack_hit.has(f) and feet.intersects(f.hitbox()) and f.state != S.SLIDE:
			attack_hit[f] = true
			f.apply_hit({"dmg": 5.0, "kb": Vector2(facing * 60.0, -150.0), "src": self, "kind": "tackle",
				"knockdown": true, "from_x": global_position.x})
	if int(state_t * 30.0) % 3 == 0 and is_on_floor():
		arena.fx.burst(global_position + Vector2(-facing * 3.0, 0), Color(0.7, 0.65, 0.6, 0.7), 1, 20.0, 0.25, -10.0, false)
	if _jp() and is_on_floor() and not arena.terrain.is_solid_at(global_position + Vector2(0, -STAND_H)):
		_set_state(S.NORMAL)
		velocity.y = JUMP_V * 0.9
		jumping = true
		sq = Vector2(0.8, 1.25)
		return
	if not is_on_floor() and state_t > 0.1:
		_set_state(S.NORMAL)
		return
	if is_on_wall() or state_t >= state_len or absf(velocity.x) < 40.0:
		_set_state(S.NORMAL)


func _roll(dt: float) -> void:
	_gravity(dt)
	velocity.x = move_toward(velocity.x, facing * 100.0, 500.0 * dt)
	if state_t >= state_len:
		_set_state(S.NORMAL)


func _stomp(dt: float) -> void:
	velocity.y = 400.0
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * dt)
	var feet := Rect2(global_position.x - 4.0, global_position.y - 4.0, 8.0, 10.0)
	for f in arena.fighters:
		if f != self and f.alive() and feet.intersects(f.hitbox()):
			f.apply_hit({"dmg": 22.0, "kb": Vector2(signf(f.global_position.x - global_position.x) * 60.0, -60.0),
				"src": self, "kind": "stomp", "knockdown": true, "from_x": global_position.x})
			velocity.y = -200.0
			arena.shake(3.0)
			Sfx.play("punch_heavy", f.center(), 2.0)
			_set_state(S.NORMAL)
			return


func _land_stomp() -> void:
	Sfx.play("land_heavy", global_position)
	arena.terrain.damage_rect(Rect2(global_position.x - 5.0, global_position.y, 10.0, 4.0), 14.0)
	arena.fx.burst(global_position, Color(0.7, 0.65, 0.6), 8, 70.0, 0.3, 200.0)
	arena.shake(1.5)
	_set_state(S.STUN, 0.15)


func _hurt(dt: float) -> void:
	_gravity(dt)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, (450.0 if state == S.DOWN else 900.0) * dt)
	if state_t >= state_len:
		if state == S.DOWN:
			invuln_t = 0.4
		_set_state(S.NORMAL)


# ---------------------------------------------------------------- ledges

## Grab the top corner of a block when it passes our hands on the way up/down.
func _try_ledge() -> bool:
	if ledge_cd > 0.0 or velocity.y < -90.0 or aiming:
		return false
	var dir := facing
	if inp.move.x != 0:
		dir = inp.move.x
	elif absf(velocity.x) < 20.0:
		return false # not heading anywhere: don't snag
	if inp.move.y > 0:
		return false # holding down = let me fall
	var t: Terrain = arena.terrain
	var hand_y := global_position.y - 20.0
	var c := t.cell_of(Vector2(global_position.x + dir * 5.0, hand_y))
	if not t.is_solid(c):
		c.y += 1
		if not t.is_solid(c):
			return false
	var top := c.y * float(Terrain.TILE)
	if hand_y < top - 4.0 or hand_y > top + 6.0:
		return false
	for k in range(1, 4): # room to stand up there
		if t.is_solid(c + Vector2i(0, -k)):
			return false
	if t.is_solid(Vector2i(c.x - dir, c.y - 1)) or t.is_solid(Vector2i(c.x - dir, c.y - 2)):
		return false # no room for our head beside the ledge
	var wall_x := c.x * float(Terrain.TILE) if dir > 0 else (c.x + 1) * float(Terrain.TILE)
	ledge_cell = c
	facing = dir
	global_position = Vector2(wall_x - dir * 3.5, top + 20.0)
	velocity = Vector2.ZERO
	jumping = false
	sq = Vector2(0.85, 1.15)
	_set_state(S.LEDGE)
	Game.stat("ledge_grabs")
	Sfx.play("ledge_grab", global_position, -3.0)
	return true


func _ledge(_dt: float) -> void:
	velocity = Vector2.ZERO
	if not arena.terrain.is_solid(ledge_cell):
		_set_state(S.NORMAL) # ledge got blown away
		ledge_cd = 0.3
		return
	if _jp() and inp.move.x == -facing:
		# Kick off the wall, away from it.
		facing = -facing
		velocity = Vector2(facing * 150.0, JUMP_V * 0.85)
		Sfx.play("jump", global_position, -4.0)
		jumping = true
		ledge_cd = 0.3
		_set_state(S.NORMAL)
	elif inp.move.y < 0 or _jp():
		ledge_from = global_position
		ledge_to = Vector2((ledge_cell.x + 0.5) * Terrain.TILE, ledge_cell.y * float(Terrain.TILE))
		_set_state(S.LEDGE_UP, 0.24)
		Sfx.play("climb", global_position, -3.0)
	elif inp.move.y > 0 or inp.move.x == -facing:
		ledge_cd = 0.35
		velocity.y = 20.0
		_set_state(S.NORMAL)
	elif _ap() or _tp():
		ledge_cd = 0.35
		_set_state(S.NORMAL)


func _ledge_up(_dt: float) -> void:
	velocity = Vector2.ZERO
	var p := clampf(state_t / state_len, 0.0, 1.0)
	# Up first, then over the lip.
	var up := ease(clampf(p / 0.6, 0.0, 1.0), 0.5)
	var over := ease(clampf((p - 0.45) / 0.55, 0.0, 1.0), 0.5)
	global_position = Vector2(lerpf(ledge_from.x, ledge_to.x, over), lerpf(ledge_from.y, ledge_to.y, up))
	if p >= 1.0:
		global_position = ledge_to
		sq = Vector2(1.15, 0.85)
		_set_state(S.NORMAL)


## Knee-high obstacle while running: hop over it without needing a jump.
func _try_vault() -> void:
	if vault_t > 0.0 or inp.move.x == 0 or absf(velocity.x) < 40.0 or aiming or crouching:
		return
	var t: Terrain = arena.terrain
	var d := inp.move.x
	var front := global_position + Vector2(d * 5.0, -3.0)
	if not t.is_solid_at(front):
		return
	for k in [11.0, 19.0, 27.0]: # clear above the step and above us
		if t.is_solid_at(global_position + Vector2(d * 5.0, -k)) or t.is_solid_at(global_position + Vector2(0, -k - 1.0)):
			return
	velocity.y = -175.0
	vault_t = 0.3
	Sfx.play("jump", global_position, -8.0)
	sq = Vector2(1.1, 0.9)


func _start_climb() -> void:
	Game.stat("climbs")
	_set_state(S.CLIMB)
	velocity = Vector2.ZERO
	set_collision_mask_value(Layers.PLATFORM_BIT, false)


func _climb(dt: float) -> void:
	velocity = Vector2(inp.move.x * 30.0, inp.move.y * CLIMB_V)
	var t: Terrain = arena.terrain
	var col_x := (t.cell_of(center()).x + 0.5) * Terrain.TILE
	global_position.x = move_toward(global_position.x, col_x, 60.0 * dt)
	var on_ladder := t.is_ladder_at(center()) or t.is_ladder_at(global_position + Vector2(0, -1))
	if _jp():
		_exit_climb()
		velocity = Vector2(inp.move.x * RUN, JUMP_V * 0.8)
	elif inp.move.x != 0 and inp.move.y == 0:
		_exit_climb() # step off sideways
		velocity.x = inp.move.x * RUN * 0.6
	elif not on_ladder:
		_exit_climb()
		if inp.move.y < 0:
			velocity.y = -170.0 # hop onto the ledge above
			drop_t = 0.15
	elif is_on_floor() and inp.move.y > 0 and not t.is_ladder_at(global_position + Vector2(0, 2)):
		_exit_climb()
	elif _tp():
		_throw()
	elif _ap():
		_exit_climb()
		if weapon_kind() == "gun":
			aim_dir = Vector2(facing, 0)
			if weapon.ammo > 0 and weapon.def.charge_time <= 0.0:
				_shoot(1.0)
		else:
			_start_attack(false)


func _exit_climb() -> void:
	_set_state(S.NORMAL)
	if drop_t <= 0.0:
		drop_t = 0.05


func _dead(dt: float) -> void:
	_gravity(dt)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * dt)


func _post_move() -> void:
	if state == S.STOMP and is_on_floor():
		_land_stomp()
	elif state == S.NORMAL and is_on_floor() and fall_speed > 330.0:
		arena.fx.burst(global_position, Color(0.75, 0.7, 0.65), 4, 40.0, 0.25, 100.0)
	# Empty guns get tossed automatically.
	if weapon and weapon.def.kind == "gun" and weapon.ammo <= 0 and weapon.cooldown <= 0.0:
		empty_t += get_physics_process_delta_time()
		if empty_t > 0.35:
			_drop_weapon(Vector2(-facing * 50.0, -110.0))
	else:
		empty_t = 0.0


func _update_shape() -> void:
	var low := state in [S.ROLL, S.DOWN, S.DEAD, S.SLIDE] or crouching
	if not low and shape.size.y < STAND_H:
		# Don't stand up into a ceiling.
		if arena.terrain.is_solid_at(global_position + Vector2(-2.5, -STAND_H + 1)) \
				or arena.terrain.is_solid_at(global_position + Vector2(2.5, -STAND_H + 1)):
			low = true
			crouching = state == S.NORMAL
	var h := LOW_H if low else STAND_H
	if shape.size.y != h:
		shape.size = Vector2(6, h)
		col.position = Vector2(0, -h / 2.0)


# ---------------------------------------------------------------- guns

func _gun(dt: float) -> void:
	var d := weapon.def
	var held := inp.attack
	var pressed := _ap()
	var released := prev.attack and not inp.attack
	if d.spin_up > 0.0:
		weapon.spin = clampf(weapon.spin + (dt if held else -dt * 2.0), 0.0, d.spin_up)
	if d.charge_time > 0.0:
		if held and weapon.ammo > 0 and weapon.cooldown <= 0.0:
			weapon.charge = minf(weapon.charge + dt, d.charge_time)
		elif released and weapon.charge > 0.0:
			var pct := weapon.charge / d.charge_time
			if d.charge_scales or pct >= 1.0:
				_shoot(maxf(pct, 0.25))
			weapon.charge = 0.0
		return
	var want := held if d.auto else pressed
	if want and weapon.cooldown <= 0.0 and (d.spin_up <= 0.0 or weapon.spin >= d.spin_up):
		if weapon.ammo > 0:
			_shoot(1.0)
	elif pressed and weapon.ammo <= 0:
		Sfx.play("empty_click", center())


func _shoot(power: float) -> void:
	var d := weapon.def
	var dir := aim_dir
	var spread := d.spread * (1.0 if aiming else 1.4)
	var muzzle := muzzle_pos()
	for i in d.pellets:
		var ang := dir.angle() + deg_to_rad(arena.rng.randf_range(-spread, spread))
		var spd: float = d.bullet_speed * (0.5 + 0.5 * power) * (arena.rng.randf_range(0.9, 1.1) if d.pellets > 1 else 1.0)
		arena.projectiles.spawn(self, muzzle, Vector2.from_angle(ang) * spd, d, power, center() + Vector2(0, -2))
	weapon.ammo -= 1
	weapon.cooldown = d.fire_rate
	Sfx.play(Sfx.gun_sound(d.id, d), muzzle, 0.0, 0.12 if d.auto else 0.06)
	Game.stat("shots_" + d.id)
	velocity -= dir * d.recoil * power
	arena.fx.flash(muzzle, 3.0 + d.pellets * 0.3, Color(1, 0.85, 0.4), 0.05)
	if d.id not in ["sling", "bow", "laser", "flamethrower"]:
		arena.fx.shell(center() + Vector2(facing * 2.0, -3.0), Vector2(-facing * arena.rng.randf_range(30, 70), arena.rng.randf_range(-120, -70)),
			Color(0.55, 0.75, 0.3) if d.pellets > 1 else Color(0.9, 0.72, 0.3))
	arena.fx.burst(muzzle, Color(1, 0.8, 0.4), 2 + d.pellets / 3, 60.0, 0.12, 0.0, false)
	arm_kick = 0.25 + d.recoil / 400.0
	arena.shake(d.recoil / 120.0 + 0.3)


# ---------------------------------------------------------------- items

func _throw() -> void:
	var dir := Vector2(facing, -0.35).normalized() if inp.move.y == 0 else _dir8()
	if aiming:
		dir = aim_dir
	var from := center() + Vector2(facing * 4.0, -2.0)
	if throwable and throw_count > 0:
		var def := throwable
		throw_count -= 1
		if throw_count <= 0:
			throwable = null
		arena.spawn_grenade(def, self, from, dir * 230.0 + velocity * 0.4)
	elif weapon:
		var w := weapon
		var tdir := aim_dir if aiming else Vector2(facing, -0.08).normalized()
		weapon = null
		aiming = false
		arena.spawn_pickup(w.def, w, from, tdir * 320.0, self)
		Sfx.play("throw", from)


func _drop_weapon(vel: Vector2) -> void:
	if weapon == null:
		return
	var w := weapon
	weapon = null
	aiming = false
	var p: Node = arena.spawn_pickup(w.def, w, center(), vel, null)
	p.no_pick_by = self
	p.no_pick_t = 0.6


func _pickups_touching() -> Array:
	var r := hitbox().grow(3.0)
	var out := []
	for p in arena.pickups():
		if p.thrown_by == null and r.has_point(p.global_position) and not (p.no_pick_by == self and p.no_pick_t > 0.0):
			out.append(p)
	return out


func _auto_pickup() -> void:
	for p in _pickups_touching():
		if p.def.kind == "throwable":
			if throwable == null or throwable == p.def:
				_take(p)
		elif weapon == null and (p.state == null or p.state.ammo > 0 or p.def.kind != "gun"):
			_take(p)


func _try_pickup() -> void:
	var best: Node = null
	for p in _pickups_touching():
		if best == null or p.global_position.distance_to(center()) < best.global_position.distance_to(center()):
			best = p
	if best == null:
		return
	if best.def.kind == "throwable":
		if throwable and throwable != best.def and throw_count > 0:
			arena.spawn_pickup(throwable, null, center(), Vector2(-facing * 40.0, -100.0), null, throw_count)
			throwable = null
	else:
		_drop_weapon(Vector2(-facing * 40.0, -110.0))
	_take(best)


func _take(p: Node) -> void:
	if p.def.kind == "throwable":
		if throwable == p.def:
			throw_count += p.count
		else:
			throwable = p.def
			throw_count = p.count
	else:
		weapon = p.state if p.state else WeaponState.new(p.def)
		weapon.charge = 0.0
		weapon.spin = 0.0
	Game.stat("pickup_" + p.def.id)
	Sfx.play("pickup_small" if p.def.kind == "throwable" else "pickup", center())
	if not source.is_bot:
		arena.fx.text(center() + Vector2(0, -16), p.def.name.to_upper(), Color(1, 0.95, 0.7))
	arena.remove_pickup(p)


# ---------------------------------------------------------------- getting hit

## Returns true if the hit connected (projectiles stop), false if it was dodged.
func apply_hit(h: Dictionary) -> bool:
	var kind: String = h.get("kind", "melee")
	var src: Fighter = h.get("src")
	var dmg: float = h.get("dmg", 0.0)
	var kb: Vector2 = h.get("kb", Vector2.ZERO)
	if state == S.DEAD:
		velocity += kb * 0.5
		if kind == "explosion" and dmg > 20.0 and not gibbed:
			_gib()
		return kind != "bullet"
	if invuln_t > 0.0 and not (kind in ["explosion", "fire"]):
		return false
	if state == S.ROLL and kind == "bullet":
		return false
	var from_x: float = h.get("from_x", global_position.x - facing)
	var from_front := signf(from_x - global_position.x) == float(facing)
	if blocking and from_front:
		if kind == "melee":
			Sfx.play("block", center())
			velocity.x = -facing * 90.0
			arena.fx.burst(center() + Vector2(facing * 4.0, 0), Color(1, 1, 0.7), 5, 70.0, 0.15, 0.0)
			return true
		if kind == "bullet" and weapon and weapon.def.shield:
			Sfx.play("bullet_hit_metal", center())
			arena.fx.burst(center() + Vector2(facing * 6.0, 0), Color(1, 0.9, 0.5), 4, 80.0, 0.15, 0.0)
			return true
	# Disarm: getting punched or tackled while aiming knocks the gun loose.
	if aiming and weapon and kind in ["melee", "tackle", "stomp"]:
		_drop_weapon(Vector2(-facing * 40.0, -130.0))
		Game.stat("disarms")
		arena.fx.text(center() + Vector2(0, -12), "DISARM", Color(1, 0.9, 0.3))
	hp -= dmg
	Game.stat("dmg_" + kind, int(dmg))
	if kind != "fire" and dmg > 0.0:
		Sfx.play("hurt", center(), -3.0, 0.15)
	hurt_flash = 0.1
	if kind in ["melee", "tackle", "stomp"] and dmg > 0.0:
		var stop := clampf(0.03 + dmg * 0.004, 0.04, 0.11)
		hitstop_t = stop
		if src and src != self:
			src.hitstop_t = maxf(src.hitstop_t, stop)
		arena.shake(1.0 + dmg * 0.08)
	if src and src != self:
		last_hitter = src
		last_hit_t = 4.0
	if dmg > 0.0 and kind != "fire":
		arena.fx.blood(center(), kb.normalized(), int(clampf(dmg / 3.0, 2.0, 18.0)))
	if weapon:
		weapon.charge = 0.0
	if hp <= 0.0:
		die(src if src and src != self else last_hitter, kind, h)
		return true
	if kind == "bullet":
		velocity.x += kb.x * 0.6
		if kb.length() > 160.0:
			velocity = kb
			_set_state(S.STUN, 0.25)
	elif kind == "fire":
		pass
	elif h.get("knockdown", false):
		velocity = kb
		_set_state(S.DOWN, 0.8)
	else:
		velocity = kb
		_set_state(S.STUN, h.get("stun", 0.25))
	return true


func die(killer: Fighter, cause := "", h := {}) -> void:
	if state == S.DEAD:
		return
	hp = 0.0
	_set_state(S.DEAD)
	collision_layer = 0
	set_collision_mask_value(Layers.PLATFORM_BIT, true)
	velocity = h.get("kb", velocity) * 1.2
	if weapon:
		_drop_weapon(Vector2(arena.rng.randf_range(-60, 60), -150.0))
	if throwable and throw_count > 0:
		arena.spawn_pickup(throwable, null, center(), Vector2(arena.rng.randf_range(-60, 60), -120.0), null, throw_count)
		throwable = null
	Sfx.play("death", center())
	if cause == "explosion" and float(h.get("dmg", 0.0)) > 30.0:
		_gib()
	died.emit(self, killer, cause)


## Online: vanish (disconnected player, or a bot making room for someone joining).
func leave() -> void:
	left = true
	if state != S.DEAD:
		arena.fx.burst(center(), Color(1, 1, 1, 0.7), 10, 60.0, 0.4, -20.0, false, 2.0)
		hp = 0.0
		_set_state(S.DEAD)
		collision_layer = 0
		if weapon:
			_drop_weapon(Vector2(0, -100.0))
		died.emit(self, null, "left")
	visible = false


## Online client: take the server's state for this fighter (position is interpolated separately).
func net_apply(r: PackedFloat32Array) -> void:
	var st := int(r[5])
	if st != state:
		state = st as S
	state_t = r[6]
	facing = int(r[7])
	aim_ang = r[8]
	var flags := int(r[9])
	aiming = flags & 1 != 0
	blocking = flags & 2 != 0
	crouching = flags & 4 != 0
	net_floor = flags & 8 != 0
	gibbed = flags & 16 != 0
	jumping = flags & 32 != 0
	left = flags & 64 != 0
	hp = r[10]
	var wd := Net.item_def(int(r[11]))
	if wd == null:
		weapon = null
	elif weapon == null or weapon.def != wd:
		weapon = WeaponState.new(wd)
	if weapon:
		weapon.ammo = int(r[12])
		weapon.charge = r[13]
		weapon.spin = r[14]
	throwable = Net.item_def(int(r[15]))
	throw_count = int(r[16])
	var mv: String = ArenaNet.MOVES[clampi(int(r[17]), 0, ArenaNet.MOVES.size() - 1)]
	cur_move_name = mv
	if mv == "swing" and weapon:
		cur_move = {"a0": weapon.def.swing_time * 0.3}
	elif MOVES.has(mv):
		cur_move = MOVES[mv]
	hurt_flash = r[18]
	invuln_t = r[19]
	arm_kick = r[20]
	vault_t = r[21]
	max_hp = r[22]
	state_len = r[23]
	velocity = Vector2(r[3], r[4])
	var a := aim_ang if aiming else 0.0
	aim_dir = Vector2(cos(a) * facing, sin(a))
	collision_layer = 0 if state == S.DEAD else Layers.FIGHTERS


## Online client: per-tick visuals for a puppet (no simulation).
func puppet_visual(dt: float) -> void:
	if net_floor and not was_on_floor and _prev_vy > 120.0 and state != S.DEAD:
		sq = Vector2(1.0 + _prev_vy / 900.0, 1.0 - _prev_vy / 1400.0)
	if net_floor:
		walk_phase += absf(velocity.x) * dt * 0.12
	was_on_floor = net_floor
	_prev_vy = velocity.y
	_update_shape()
	_update_visual(dt)
	if left:
		visible = false


func _gib() -> void:
	gibbed = true
	Sfx.play("gib", center())
	col.set_deferred("disabled", true)
	var c := center()
	arena.fx.burst(c, Color(0.7, 0.05, 0.05), 40, 200.0, 2.5, 500.0, true)
	arena.fx.burst(c, color, 6, 150.0, 3.0, 500.0, true, 2.0)
	arena.fx.burst(c, Color(0.96, 0.8, 0.62), 4, 150.0, 3.0, 500.0, true, 2.0)
	queue_redraw()


# ---------------------------------------------------------------- visuals

func _build_visual() -> void:
	visual = Node2D.new()
	add_child(visual)
	body = Sprite2D.new()
	body.texture = Art.fighter_texture(color, player_index)
	body.hframes = Art.frame_count()
	body.vframes = 2
	body.centered = false
	body.offset = Vector2(-12, -24)
	visual.add_child(body)
	arm_pivot = Node2D.new()
	visual.add_child(arm_pivot)
	wpn_spr = Sprite2D.new()
	wpn_spr.centered = false
	arm_pivot.add_child(wpn_spr)
	arm_spr = Sprite2D.new()
	arm_spr.texture = Art.team_arm(color, player_index)
	arm_spr.centered = false
	arm_spr.offset = -Vector2(2, 2)
	arm_pivot.add_child(arm_spr)


func _anim_name() -> String:
	match state:
		S.DEAD, S.DOWN:
			return "down"
		S.ROLL:
			return "roll%d" % (int(state_t * 14.0) % 4)
		S.DIVE:
			return "dive"
		S.CLIMB:
			return "climb%d" % (int(global_position.y / 5.0) % 2)
		S.STUN:
			return "hurt"
		S.STOMP:
			return "stomp"
		S.LEDGE:
			return "hang"
		S.LEDGE_UP:
			return "ledgeup"
		S.SLIDE:
			return "slide"
		S.ATTACK:
			match cur_move_name:
				"punch": return "punch0" if state_t < float(cur_move["a0"]) else "punch1"
				"hook": return "hook"
				"lunge": return "lunge"
				"kick": return "kick"
				_: return "lunge" if state_t > float(cur_move["a0"]) else "aim"
	if blocking:
		return "guard" if weapon == null else "aim"
	if crouching:
		return "crouch"
	if not _floor():
		if vault_t > 0.1:
			return "vault"
		return "jump" if velocity.y < 0.0 else "fall"
	if aiming:
		return "aim"
	if absf(velocity.x) > 8.0:
		return "run%d" % (int(walk_phase) % 8)
	return "idle%d" % (int(state_t * 1.6) % 2)


func _update_visual(dt: float) -> void:
	visible = not gibbed and not left
	sq = sq.lerp(Vector2.ONE, 1.0 - exp(-dt * 14.0))
	visual.scale = Vector2(facing * sq.x, sq.y)
	var fname := _anim_name()
	var fi := Art.frame(fname)
	var holding := weapon != null and (state == S.NORMAL or (state == S.ATTACK and cur_move_name == "swing")) \
		and not fname.begins_with("roll")
	body.frame = (body.hframes if holding else 0) + fi
	arm_pivot.visible = holding
	if holding:
		arm_kick = maxf(0.0, arm_kick - dt * 3.0)
		arm_pivot.position = Art.shoulder(fi)
		var d := weapon.def
		var ang := 0.0
		if d.kind == "gun":
			ang = Vector2(aim_dir.x * facing, aim_dir.y).angle() - arm_kick
			if not aiming and absf(velocity.x) > 8.0 and _floor():
				ang += sin(walk_phase * PI / 2.0) * 0.06
		elif state == S.ATTACK:
			var p := clampf(state_t / maxf(state_len * 0.6, 0.01), 0.0, 1.0)
			ang = lerpf(-2.4, 0.9, ease(p, 0.35))
		elif blocking:
			ang = -PI / 2.0
		else:
			ang = -0.9 if d.style != "bigsword" else -0.25
		arm_pivot.rotation = ang
		var w := Art.weapon(d)
		wpn_spr.texture = w["tex"]
		wpn_spr.offset = -w["grip"]
		wpn_spr.position = Vector2(4, 0)
	var m := Color.WHITE
	if state == S.DEAD:
		m = Color(0.6, 0.55, 0.55)
	elif hurt_flash > 0.0:
		m = Color(4, 4, 4)
	elif invuln_t > 0.0 and int(invuln_t * 20.0) % 2 == 0:
		m = Color(1, 1, 1, 0.4)
	visual.modulate = m
	queue_redraw()


func _laser_hits_fighter(p: Vector2) -> bool:
	for o in arena.fighters:
		if o != self and o.alive() and o.hitbox().has_point(p):
			return true
	return false


func _draw() -> void:
	if gibbed or state == S.DEAD:
		return
	# Little marker above the head so you can find yourself.
	var top := -height() - 7.0
	if not source.is_bot:
		draw_colored_polygon(PackedVector2Array([Vector2(-2, top + 1), Vector2(2, top + 1), Vector2(0, top + 3)]), color.lightened(0.25))
	# Laser sight while aiming: runs until it hits a wall or a fighter.
	if aiming and weapon:
		var from := muzzle_pos()
		var end := from
		var hit := false
		var step := aim_dir * 2.0
		for i in 130:
			end += step
			if arena.terrain.is_solid_at(end):
				hit = true
				break
			if i > 3 and _laser_hits_fighter(end):
				hit = true
				break
		var lc := Color(color.lightened(0.45), 0.55)
		draw_line(from - global_position, end - global_position, lc, -1.0)
		draw_line(from - global_position, from.lerp(end, 0.25) - global_position, Color(lc, 0.35), 1.0)
		if hit:
			draw_rect(Rect2(end - global_position - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.9))
	if weapon and (weapon.charge > 0.0 or weapon.spin > 0.0):
		var pct := weapon.charge / weapon.def.charge_time if weapon.def.charge_time > 0.0 else weapon.spin / weapon.def.spin_up
		draw_rect(Rect2(-6, top - 4, 12, 1.5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-6, top - 4, 12.0 * pct, 1.5), Color(0.5, 1, 0.5) if pct >= 1.0 else Color(1, 0.8, 0.3))
