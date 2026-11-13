class_name ArenaNet
extends RefCounted
## Arena <-> network glue.
##
## Our own fighter is predicted: simulated locally from our input every tick, then checked
## against the server's state for the last input it applied (`ack`). If they disagree (we got
## hit, or the world differed) we snap to the server's state and replay the unconfirmed inputs.
##
## Server: every Net.SNAP_EVERY ticks packs the world into a snapshot: fighter rows, items,
## grenades, props, tiles that changed, and the events (particles, sounds, shots, kill feed)
## recorded since the last one. Everything is reliable and ordered, so events are never lost.
##
## Client: buffers snapshots and plays them back INTERP ticks in the past, interpolating
## positions between the two around the playback time. Entities are puppets (no physics of
## their own); bullets and particles are simulated locally but purely cosmetic.

const INTERP := 4.0 # ticks behind the newest snapshot we draw (2 snapshots at 30 Hz)
const MOVES := ["", "punch", "hook", "lunge", "kick", "swing"]
const PROP_KINDS := ["crate", "barrel"]

var a: Arena
var tick := 0
var events: Array = [] # server: [kind, args] since the last snapshot

# client
var snaps: Array = []
var last: Dictionary = {}
var render_t := -1.0
var round_num := -1
var map_key := ""
var roster := {} # pid -> [name, color html, is_bot]
var puppets := {"p": {}, "g": {}, "o": {}} # kind -> net id -> node
var input_buf := PackedInt32Array()
var input_n := 0
var rx_bytes := 0 # stats
# client prediction of our own fighter
var my_seq := 0
var history: Array = [] # {seq, bits, pos, state} for frames the server hasn't confirmed yet
var pending_me := PackedFloat32Array() # newest server row for our fighter
var pending_tick := -1
var corrections := 0


func _init(arena: Arena) -> void:
	a = arena


# ================================================================ server

func server_tick() -> void:
	tick += 1
	if tick % Net.SNAP_EVERY != 0:
		return
	var data := var_to_bytes(build()).compress(FileAccess.COMPRESSION_DEFLATE)
	Net.broadcast_snapshot(data)
	events.clear()
	a.terrain.net_changes.clear()


func build() -> Dictionary:
	var f := []
	for fi in a.fighters:
		f.append(_fighter_row(fi))
	var p := []
	for it in a.pickups():
		p.append(PackedFloat32Array([it.net_id, Net.item_index(it.def.id), it.global_position.x, it.global_position.y,
			it.angle, 1.0 if it.chute else 0.0, it.chute_t, it.empty_t, it.count, 1.0 if it.is_empty_gun() else 0.0]))
	var g := []
	for gr in a.grenades():
		g.append(PackedFloat32Array([gr.net_id, Net.item_index(gr.def.id), gr.global_position.x, gr.global_position.y,
			gr.fuse, gr.age, gr.vel.x, 1.0 if (gr.stuck_to or gr.stuck_cell.x != -9999) else 0.0]))
	var o := []
	for pr in a.props():
		o.append(PackedFloat32Array([pr.net_id, PROP_KINDS.find(pr.kind), pr.global_position.x, pr.global_position.y, pr.flash]))
	var c := PackedInt32Array()
	for cell in a.terrain.net_changes:
		c.append_array([cell.x, cell.y, int(a.terrain.net_changes[cell])])
	return {"t": tick, "m": a.map_key, "f": f, "p": p, "g": g, "o": o, "c": c, "e": events.duplicate(),
		"rs": [a.round_num, a.round_over_t, a.intro_t, a.round_t, _pid(a.round_winner), _pid(a.match_winner)],
		"sc": Game.scores}


func full_state() -> Dictionary:
	var c := PackedInt32Array()
	for cell in a.terrain.round_changes:
		c.append_array([cell.x, cell.y, int(a.terrain.round_changes[cell])])
	var s := build()
	s["e"] = []
	s["c"] = PackedInt32Array()
	return {"map": a.map_key, "round": a.round_num, "tiles": c, "roster": roster_list(), "snap": s}


func roster_list() -> Array:
	var out := []
	for f in a.fighters:
		out.append([f.player_index, f.display_name, f.color.to_html(), f.source.is_bot])
	return out


func _pid(f: Fighter) -> int:
	return f.player_index if f else -1


func _fighter_row(f: Fighter) -> PackedFloat32Array:
	var flags := int(f.aiming) | int(f.blocking) << 1 | int(f.crouching) << 2 | int(f.is_on_floor()) << 3 \
		| int(f.gibbed) << 4 | int(f.jumping) << 5 | int(f.left) << 6
	var widx := Net.item_index(f.weapon.def.id) if f.weapon else -1
	var tidx := Net.item_index(f.throwable.id) if f.throwable else -1
	var ack: int = f.source.ack if f.source is NetSource else -1
	return PackedFloat32Array([f.player_index, f.global_position.x, f.global_position.y, f.velocity.x, f.velocity.y,
		f.state, f.state_t, f.facing, f.aim_ang, flags, f.hp, widx,
		f.weapon.ammo if f.weapon else 0, f.weapon.charge if f.weapon else 0.0, f.weapon.spin if f.weapon else 0.0,
		tidx, f.throw_count, MOVES.find(f.cur_move_name), f.hurt_flash, f.invuln_t, f.arm_kick, f.vault_t,
		f.max_hp, f.state_len, ack, f.drop_t, f.hitstop_t, f.ledge_cd, f.coyote_t, f.buffer_t,
		1.0 if f.get_collision_mask_value(Layers.PLATFORM_BIT) else 0.0, f.combo, f.combo_t])


# ================================================================ client

func apply_full(st: Dictionary) -> void:
	set_roster(st["roster"])
	round_num = st["round"]
	map_key = st["map"]
	a.round_num = round_num
	_apply_tiles(st["tiles"])
	receive_decoded(st["snap"])


func receive(data: PackedByteArray) -> void:
	rx_bytes += data.size()
	var s = bytes_to_var(data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE))
	if s is Dictionary:
		receive_decoded(s)


func receive_decoded(s: Dictionary) -> void:
	# Index rows by id once, for interpolation lookups.
	for k in ["f", "p", "g", "o"]:
		var idx := {}
		for r in s[k]:
			idx[int(r[0])] = r
		s[k + "i"] = idx
	snaps.append(s)
	for pid in Net.my_pids:
		if s["fi"].has(pid) and int(s["t"]) > pending_tick:
			pending_me = s["fi"][pid]
			pending_tick = int(s["t"])
	if render_t < 0.0:
		render_t = float(s["t"]) - INTERP


func set_roster(list: Array) -> void:
	for r in list:
		roster[int(r[0])] = [r[1], Color.html(r[2]), r[3]]


func client_tick(dt: float) -> void:
	if not snaps.is_empty():
		render_t += 1.0
		var target := float(snaps[-1]["t"]) - INTERP
		if absf(render_t - target) > 20.0:
			render_t = target
		else:
			render_t += (target - render_t) * 0.05
	while not snaps.is_empty() and float(snaps[0]["t"]) <= render_t:
		var s: Dictionary = snaps.pop_front()
		_apply(s)
		last = s
	if not last.is_empty():
		var k := 0.0
		var nxt: Dictionary = snaps[0] if not snaps.is_empty() else last
		if not snaps.is_empty():
			k = clampf((render_t - float(last["t"])) / maxf(float(nxt["t"]) - float(last["t"]), 1.0), 0.0, 1.0)
		_interpolate(last, nxt, k)
	for f in a.fighters:
		if not f.predicted:
			f.puppet_visual(dt)
	_predict(dt)


## Sample our input, send it, and run our fighter forward immediately.
func _predict(dt: float) -> void:
	var n: int = Net.local_sources.size()
	if n == 0:
		return
	var me := _fighter(Net.my_pids[0]) if not Net.my_pids.is_empty() else null
	var frames := []
	for i in n:
		var f: Fighter = _fighter(Net.my_pids[i]) if i < Net.my_pids.size() else null
		frames.append(Net.local_sources[i].sample(f, a))
	var live := me != null and me.alive() and a.intro_t <= 0.0 and a.round_over_t < 0.0
	if not live:
		# Nothing to predict (dead, intro, round over): just show the server's state.
		history.clear()
		if me and not pending_me.is_empty():
			me.net_apply(pending_me)
			_place(me, Vector2(pending_me[1], pending_me[2]))
			me.puppet_visual(dt)
		return
	my_seq += 1
	input_buf.append(my_seq)
	for fr in frames:
		input_buf.append(fr.to_bits())
	input_n += 1
	if input_n >= Net.INPUT_EVERY:
		var pk := PackedInt32Array([n])
		pk.append_array(input_buf)
		Net.send_input(pk)
		input_buf.clear()
		input_n = 0
	_reconcile_me(me, dt)
	var fr0: InputFrame = frames[0]
	Sfx.muted_depth += 1
	Sfx.allow = Fighter.LOCAL_SFX
	a.fx_mute += 1
	me.tick(dt, fr0)
	a.fx_mute -= 1
	Sfx.muted_depth -= 1
	history.append({"seq": my_seq, "bits": fr0.to_bits(), "pos": me.global_position, "state": me.state})
	if history.size() > 120:
		history.pop_front()


func _reconcile_me(me: Fighter, dt: float) -> void:
	if pending_me.is_empty():
		return
	var r := pending_me
	pending_me = PackedFloat32Array()
	me.net_apply_status(r)
	var ack := int(r[24])
	var pred: Dictionary = {}
	while not history.is_empty() and int(history[0]["seq"]) <= ack:
		pred = history.pop_front()
	if pred.is_empty() or int(pred["seq"]) != ack:
		return # server hasn't applied any of our current inputs yet
	var spos := Vector2(r[1], r[2])
	if (pred["pos"] as Vector2).distance_to(spos) < 2.5 and int(pred["state"]) == int(r[5]):
		return
	# Mispredicted: rewind to the server's state at `ack` and replay what it hasn't seen.
	corrections += 1
	me.net_apply(r)
	me.global_position = spos
	me.inp = InputFrame.from_bits(int(pred["bits"]))
	Sfx.muted_depth += 1
	Sfx.allow = []
	a.fx_mute += 1
	for h in history:
		me.tick(dt, InputFrame.from_bits(int(h["bits"])))
		h["pos"] = me.global_position
		h["state"] = me.state
	a.fx_mute -= 1
	Sfx.muted_depth -= 1


func _fighter(pid: int) -> Fighter:
	for f in a.fighters:
		if f.player_index == pid:
			return f
	return null


func _apply(s: Dictionary) -> void:
	var rs: Array = s["rs"]
	if int(rs[0]) != round_num or String(s["m"]) != map_key:
		round_num = int(rs[0])
		map_key = String(s["m"])
		a.client_new_round(map_key, round_num)
	a.round_over_t = rs[1]
	a.intro_t = rs[2]
	a.round_t = rs[3]
	Game.scores = s["sc"]
	_apply_tiles(s["c"])
	_reconcile_fighters(s)
	_reconcile(s, "p")
	_reconcile(s, "g")
	_reconcile(s, "o")
	a.round_winner = _fighter(int(rs[4]))
	a.match_winner = _fighter(int(rs[5]))
	for e in s["e"]:
		_event(e[0], e[1], e[2] if e.size() > 2 else -1)


func _apply_tiles(c: PackedInt32Array) -> void:
	var i := 0
	while i + 2 < c.size():
		a.terrain.apply_net_cell(Vector2i(c[i], c[i + 1]), c[i + 2])
		i += 3


func _reconcile_fighters(s: Dictionary) -> void:
	var rows: Dictionary = s["fi"]
	var keep: Array = []
	for r in s["f"]:
		var pid := int(r[0])
		var f := _fighter(pid)
		if f == null:
			f = _make_fighter(pid, Vector2(r[1], r[2]))
		if f.predicted:
			f.net_apply_status(r)
		else:
			f.net_apply(r)
		keep.append(f)
	for f in a.fighters:
		if not rows.has(f.player_index):
			f.queue_free()
	a.fighters = keep


func _make_fighter(pid: int, pos: Vector2) -> Fighter:
	var info: Array = roster.get(pid, ["?", Color.GRAY, true])
	var src: InputSource
	var mine: int = Net.my_pids.find(pid)
	if mine >= 0 and mine < Net.local_sources.size():
		src = Net.local_sources[mine]
	else:
		src = RemoteSource.new(info[0], info[2])
	var f := Fighter.new()
	f.setup(pid, info[0], info[1], src, a)
	f.predicted = mine >= 0
	f.puppet = not f.predicted
	f.position = pos
	a.fighters_node.add_child(f)
	f.reset_physics_interpolation()
	return f


func _reconcile(s: Dictionary, kind: String) -> void:
	var rows: Dictionary = s[kind + "i"]
	var have: Dictionary = puppets[kind]
	for id in have.keys():
		if not rows.has(id) or not is_instance_valid(have[id]):
			if is_instance_valid(have[id]):
				have[id].queue_free()
			have.erase(id)
	for id in rows:
		var r: PackedFloat32Array = rows[id]
		var n: Node2D = have.get(id)
		if n == null:
			n = _make_puppet(kind, r)
			if n == null:
				continue
			have[id] = n
		match kind:
			"p":
				n.angle = r[4]
				n.chute = r[5] > 0.5
				n.chute_t = r[6]
				n.empty_t = r[7]
				n.count = int(r[8])
				n.net_empty = r[9] > 0.5
			"g":
				n.fuse = r[4]
				n.age = r[5]
				n.vel.x = r[6]
				n.stuck_cell = Vector2i(0, 0) if r[7] > 0.5 else Vector2i(-9999, -9999)
			"o":
				n.flash = r[4]
		n.queue_redraw()


func _make_puppet(kind: String, r: PackedFloat32Array) -> Node2D:
	var pos := Vector2(r[2], r[3])
	match kind:
		"p":
			var d := Net.item_def(int(r[1]))
			if d == null:
				return null
			var p := Pickup.new()
			p.setup(d, null, a, int(r[8]))
			p.puppet = true
			p.position = pos
			a.pickups_node.add_child(p)
			return p
		"g":
			var d := Net.item_def(int(r[1]))
			if d == null:
				return null
			var g := Grenade.new()
			g.def = d
			g.arena = a
			g.puppet = true
			g.position = pos
			a.grenades_node.add_child(g)
			return g
		"o":
			var o := Prop.new()
			o.setup(PROP_KINDS[clampi(int(r[1]), 0, 1)], a)
			o.puppet = true
			o.position = pos
			a.props_node.add_child(o)
			return o
	return null


func _interpolate(s0: Dictionary, s1: Dictionary, k: float) -> void:
	var f1: Dictionary = s1["fi"]
	for f in a.fighters:
		if f.predicted:
			continue
		var r0: PackedFloat32Array = s0["fi"].get(f.player_index, PackedFloat32Array())
		if r0.is_empty():
			continue
		var p := Vector2(r0[1], r0[2])
		var r1: PackedFloat32Array = f1.get(f.player_index, PackedFloat32Array())
		if not r1.is_empty():
			p = p.lerp(Vector2(r1[1], r1[2]), k)
		_place(f, p)
	for kind in ["p", "g", "o"]:
		var rows0: Dictionary = s0[kind + "i"]
		var rows1: Dictionary = s1[kind + "i"]
		var have: Dictionary = puppets[kind]
		for id in have:
			var n: Node2D = have[id]
			if not is_instance_valid(n) or not rows0.has(id):
				continue
			var r0: PackedFloat32Array = rows0[id]
			var p := Vector2(r0[2], r0[3])
			if rows1.has(id):
				var r1: PackedFloat32Array = rows1[id]
				p = p.lerp(Vector2(r1[2], r1[3]), k)
			_place(n, p)


func _place(n: Node2D, p: Vector2) -> void:
	var jump := n.global_position.distance_squared_to(p) > 48.0 * 48.0
	n.global_position = p
	if jump:
		n.reset_physics_interpolation()


func _event(kind: String, args: Array, owner := -1) -> void:
	if kind == "sfx" and owner in Net.my_pids and args[0] in Fighter.LOCAL_SFX:
		return # our predicted fighter already played it
	match kind:
		"sfx":
			Sfx.play(args[0], args[1], args[2], args[3])
		"shot":
			var d := Net.item_def(int(args[3]))
			if d:
				a.projectiles.spawn(_fighter(int(args[0])), args[1], args[2], d, args[4], args[5], true)
		"flame":
			a.fx.spawn_flame(args[0], args[1], null, 0.0, args[2])
		"shake":
			a.camera.add_shake(args[0])
		"scorch":
			a.terrain.scorch(args[0], args[1])
		"feed":
			a.feed.append([args[0], args[1], 4.0])
		"punch":
			a.camera.punch(args[0])
		_:
			if a.fx.has_method(kind):
				a.fx.callv(kind, args)
