extends "res://scripts/Enemy.gd"

# Mouse, Cat and Owner. Each is a small state machine driven from _think().
# Attacks are telegraphed with a red ghost sphere so they can be dodged.

var bstate = "idle"
var bt = 0.0
var atk_cd = 2.5
var special_cd = 7.0
var lock_dir = Vector3.FORWARD
var vel3 = Vector3.ZERO
var mark = Vector3.ZERO
var tele: MeshInstance3D = null
var puffs = 0
var puff_t = 0.0

func _think(delta, ppos, to_player, spd):
	bt -= delta
	atk_cd -= delta
	special_cd -= delta
	match kind:
		"mouse":
			_ai_mouse(delta, to_player, spd)
		"cat":
			_ai_cat(delta, ppos, to_player, spd)
		"owner":
			_ai_owner(delta, ppos, spd)

func _set_state(s: String, time: float):
	bstate = s
	bt = time

func _facing() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))

func _show_tele(pos: Vector3, r: float):
	if tele == null:
		tele = MeshInstance3D.new()
		tele.mesh = MeshKit.sphere(1.0)
		tele.material_override = MeshKit.ghost_mat(Color(1.0, 0.1, 0.05, 0.3))
		tele.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tele.top_level = true
		add_child(tele)
	tele.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r), pos)
	tele.visible = true

func _hide_tele():
	if tele != null:
		tele.visible = false

# --- navigation for the big bosses -----------------------------------------
# Cat and owner ignore wall collision and instead walk between rooms through
# the two doorways, staying inside safe boxes within each room.

func _big_zone(p: Vector3) -> String:
	if p.x < -4.2:
		return "bedroom"
	if p.z < -8.0:
		return "kitchen"
	return "living"

func _clamp_zone(p: Vector3, zone: String) -> Vector3:
	var out = p
	match zone:
		"bedroom":
			out.x = clampf(p.x, -9.0, -4.9)
			out.z = clampf(p.z, -7.0, -1.1)
		"kitchen":
			out.x = clampf(p.x, 1.7, 3.6)
			out.z = clampf(p.z, -11.9, -8.6)
		_:
			out.x = clampf(p.x, -3.6, 3.6)
			out.z = clampf(p.z, -7.3, -1.1)
	return out

func _nav_target(goal: Vector3) -> Vector3:
	var here = _big_zone(global_position)
	var there = _big_zone(goal)
	if here == there:
		return _clamp_zone(goal, here)
	if here == "bedroom" or (here == "living" and there == "bedroom"):
		# Bedroom door: line up on z = -5.25, then walk straight through.
		var near_x = -5.2 if here == "bedroom" else -3.3
		var far_x = -3.3 if here == "bedroom" else -5.2
		if absf(global_position.z + 5.25) < 0.25:
			return Vector3(far_x, 0.0, -5.25)
		return Vector3(near_x, 0.0, -5.25)
	# Living room <-> kitchen opening: line up on x = 2.4.
	var near_z = -7.0 if here == "living" else -9.0
	var far_z = -9.0 if here == "living" else -7.0
	if absf(global_position.x - 2.4) < 0.25:
		return Vector3(2.4, 0.0, far_z)
	return Vector3(2.4, 0.0, near_z)

func _floor_y() -> float:
	var from = global_position + Vector3.UP * 1.2
	var hit = game.ray(from, global_position + Vector3.DOWN * 1.5)
	if hit.is_empty():
		return 0.0
	return hit["position"].y

func _walk(delta, target: Vector3, spd: float, follow_floor: bool):
	var d = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var l = d.length()
	if l > 0.05 and spd > 0.0:
		global_position += d / l * minf(spd * delta, l)
		_face(d, delta)
	if follow_floor:
		global_position.y = move_toward(global_position.y, _floor_y(), 5.0 * delta)

# --- Mouse -------------------------------------------------------------------

func _ai_mouse(delta, to_player: Vector3, spd: float):
	var flat = Vector3(to_player.x, 0.0, to_player.z)
	var fd = flat.length()
	var rage = 1.3 if hp < max_hp * 0.4 else 1.0
	match bstate:
		"idle":
			_move_crawler(delta, to_player, spd * rage)
			_face(flat, delta)
			if special_cd <= 0.0:
				special_cd = 9.0
				for i in 3:
					game.spawn_enemy("ant", center() + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)), false)
			if atk_cd <= 0.0 and fd < 6.0:
				if to_player.y > 0.6 and fd < 3.0:
					# Leap at a spider hanging above.
					var t = 0.55
					vel3 = to_player / t + Vector3.UP * 0.5 * GRAVITY * t
					_set_state("leap", 1.6)
				elif fd > 0.05:
					lock_dir = flat / fd
					_set_state("windup", 0.6 / rage)
		"windup":
			visual.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.02
			_face(flat, delta)
			if fd > 0.05:
				lock_dir = flat / fd
			_move_crawler(delta, Vector3.ZERO, 0.0)
			if bt <= 0.0:
				visual.position = Vector3.ZERO
				_set_state("charge", 0.8)
		"charge":
			_move_crawler(delta, lock_dir * 5.0, 6.5 * (spd / speed))
			if bt <= 0.0:
				atk_cd = 2.5 / rage
				_set_state("rest", 0.9 / rage)
		"leap":
			vel3.y -= GRAVITY * delta
			var blocked = _try_move(vel3 * delta)
			if (blocked and vel3.y < 0.0) or bt <= 0.0:
				vy = 0.0
				atk_cd = 2.5 / rage
				_set_state("rest", 0.7)
		_:
			_move_crawler(delta, Vector3.ZERO, 0.0)
			if bt <= 0.0:
				_set_state("idle", 0.0)

# --- Cat ---------------------------------------------------------------------

func _ai_cat(delta, ppos: Vector3, to_player: Vector3, spd: float):
	var flat = Vector3(ppos.x - global_position.x, 0.0, ppos.z - global_position.z)
	var fd = flat.length()
	var rage = 1.35 if hp < max_hp * 0.4 else 1.0
	match bstate:
		"idle":
			_walk(delta, _nav_target(ppos), spd * rage, true)
			if atk_cd <= 0.0:
				if fd < 2.0 and to_player.y < 2.2:
					var fwd = flat / fd if fd > 0.05 else _facing()
					mark = global_position + fwd * 1.1 + Vector3.UP * 0.6
					_show_tele(mark, 1.4)
					_set_state("swipe", 0.55 / rage)
				elif fd < 9.0 and _big_zone(ppos) == _big_zone(global_position):
					_set_state("crouch", 0.8 / rage)
		"swipe":
			_face(flat, delta)
			if bt <= 0.0:
				_hide_tele()
				if ppos.distance_to(mark) < 1.4 + PLAYER_RADIUS:
					game.damage_player(damage * 1.4, mark)
				atk_cd = 1.6 / rage
				_set_state("rest", 0.6)
		"crouch":
			_face(flat, delta)
			visual.scale = Vector3(1.1, 0.6, 1.1)
			if bt <= 0.0:
				var target = _clamp_zone(ppos, _big_zone(global_position))
				target.y = clampf(ppos.y - 0.6, 0.0, 3.6)
				var d = target - global_position
				var t = clampf(d.length() / 8.0, 0.45, 0.9)
				vel3 = d / t + Vector3.UP * 0.5 * 12.0 * t
				_set_state("pounce", t + 0.8)
		"pounce":
			vel3.y -= 12.0 * delta
			global_position += vel3 * delta
			var landed = false
			if vel3.y < 0.0:
				var fy = _floor_y()
				if global_position.y <= fy:
					global_position.y = fy
					landed = true
			if landed or bt <= 0.0:
				atk_cd = 2.2 / rage
				_set_state("rest", 0.9 / rage)
		_:
			_walk(delta, global_position, 0.0, true)
			if bt <= 0.0:
				_set_state("idle", 0.0)

# --- Owner -------------------------------------------------------------------

func _ai_owner(delta, ppos: Vector3, spd: float):
	var flat = Vector3(ppos.x - global_position.x, 0.0, ppos.z - global_position.z)
	var fd = flat.length()
	var phase2 = hp < max_hp * 0.5
	var rage = 1.3 if phase2 else 1.0
	var hand = global_position + _facing() * 0.8 + Vector3.UP * 2.2
	match bstate:
		"idle":
			_walk(delta, _nav_target(ppos), spd * rage, false)
			if phase2 and special_cd <= 0.0 and fd < 9.0:
				special_cd = 14.0
				game.hud.announce("He got the vacuum cleaner! Grapple away!", 2.5)
				_set_state("vacuum", 3.5)
			elif atk_cd <= 0.0:
				if fd < 1.7 and ppos.y < 0.6:
					mark = global_position + Vector3.UP * 0.1
					_show_tele(mark, 2.0)
					_set_state("stomp", 0.6 / rage)
				elif fd < 2.6:
					mark = ppos
					_show_tele(mark, 1.0)
					_set_state("swat", 0.7 / rage)
				elif fd < 8.0 and game.ray(hand, ppos).is_empty():
					if randf() < 0.5:
						puffs = 6
						puff_t = 0.3
						_set_state("spray", 1.5)
					else:
						_set_state("throw", 0.5 / rage)
		"swat":
			_face(flat, delta)
			if bt <= 0.0:
				_hide_tele()
				if ppos.distance_to(mark) < 1.0 + PLAYER_RADIUS:
					game.damage_player(damage, mark)
				atk_cd = 1.8 / rage
				_set_state("rest", 0.5)
		"stomp":
			if bt <= 0.0:
				_hide_tele()
				if fd < 2.0 and ppos.y < 0.5:
					game.damage_player(damage * 0.8, global_position)
				atk_cd = 1.8 / rage
				_set_state("rest", 0.5)
		"spray":
			_face(flat, delta)
			puff_t -= delta
			if puff_t <= 0.0 and puffs > 0:
				puffs -= 1
				puff_t = 0.18
				var spread = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.15
				var dir = (ppos - hand).normalized() + spread
				game.spawn_cloud(hand, dir * 3.5, 12.0)
			if bt <= 0.0:
				atk_cd = 2.2 / rage
				_set_state("rest", 0.4)
		"throw":
			_face(flat, delta)
			if bt <= 0.0:
				var lead = ppos + game.player.velocity * 0.3
				game.spawn_enemy_shot(hand, (lead - hand).normalized() * 8.0, damage * 0.8, 0.22, true)
				atk_cd = 1.6 / rage
				_set_state("rest", 0.4)
		"vacuum":
			_face(flat, delta)
			var to_hand = hand - ppos
			var dist = to_hand.length()
			if dist > 0.05 and dist < 10.0 and game.ray(hand, ppos).is_empty():
				game.player.velocity += to_hand / dist * 14.0 * delta
				if dist < 0.6:
					game.damage_player(15.0, hand)
			if bt <= 0.0:
				atk_cd = 1.5
				_set_state("rest", 1.0)
		_:
			if bt <= 0.0:
				_set_state("idle", 0.0)

func _on_captured():
	_hide_tele()
	global_position.y = _floor_y()
	super._on_captured()
