class_name FX
extends Node2D
## Particles (debris, blood, sparks, smoke), flashes, floating text, and flames.
## Flames are gameplay too: they hurt fighters and burn flammable tiles.

const MAX_PARTS := 3000

var arena: Node
var rng := RandomNumberGenerator.new()
# part: [pos, vel, color, life, max_life, size, gravity, collide, sticks]
var parts: Array = []
var flashes: Array = [] # [pos, radius, color, life, max]
var puffs: Array = [] # fireball / smoke balls: [pos, vel, radius, life, max, smoke]
var texts: Array = [] # [pos, text, color, life]
var flames: Array = [] # {pos, vel, owner, dps, life, grounded}


## Online server: effects aren't drawn here, they're sent to clients. Returns true if recorded.
func _rec(kind: String, args: Array) -> bool:
	if arena and arena.net_mode == Net.SERVER:
		arena.record(kind, args)
		return true
	return arena != null and arena.fx_mute > 0 # client: predicted fighter's effects come from the server


func clear() -> void:
	parts.clear()
	flashes.clear()
	puffs.clear()
	texts.clear()
	flames.clear()


func burst(pos: Vector2, color: Color, n: int, speed: float, life := 0.6, grav := 500.0,
		collide := true, size := 1.0, sticks := false) -> void:
	if _rec("burst", [pos, color, n, speed, life, grav, collide, size, sticks]):
		return
	for i in n:
		if parts.size() >= MAX_PARTS:
			parts.pop_front()
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.0) * speed
		var l := life * rng.randf_range(0.6, 1.2)
		parts.append([pos, v, color, l, l, size, grav, collide, sticks])


## Ejected shell casing: tumbles, bounces a bit, then lies on the floor.
func shell(pos: Vector2, vel: Vector2, color: Color) -> void:
	if _rec("shell", [pos, vel, color]):
		return
	if parts.size() >= MAX_PARTS:
		parts.pop_front()
	parts.append([pos, vel, color, 3.0, 3.0, 1.0, 600.0, true, false])


func debris(pos: Vector2, color: Color, n: int) -> void:
	if _rec("debris", [pos, color, n]):
		return
	burst(pos, color, n, 110.0, 1.4, 600.0, true, 1.0)
	burst(pos, color.darkened(0.3), n / 2, 80.0, 1.4, 600.0, true, 2.0)
	burst(pos, Color(0.6, 0.6, 0.6, 0.5), 2, 20.0, 0.6, -20.0, false, 2.0)


func blood(pos: Vector2, dir: Vector2, n: int) -> void:
	if _rec("blood", [pos, dir, n]):
		return
	for i in n:
		if parts.size() >= MAX_PARTS:
			parts.pop_front()
		var v := (dir * rng.randf_range(40, 160) + Vector2.from_angle(rng.randf() * TAU) * 50.0)
		var l := rng.randf_range(4.0, 7.0)
		parts.append([pos, v, Color(0.65 + rng.randf() * 0.15, 0.04, 0.04), l, l, 1.0, 500.0, true, true])


## Chunky fireball: solid balls that go white -> yellow -> orange -> smoke and shrink.
func fireball(pos: Vector2, radius: float) -> void:
	if _rec("fireball", [pos, radius]):
		return
	var n := int(clampf(radius / 4.0, 4, 18))
	for i in n:
		var a := rng.randf() * TAU
		var d := rng.randf() * radius * 0.6
		var l := rng.randf_range(0.25, 0.5)
		puffs.append([pos + Vector2.from_angle(a) * d, Vector2.from_angle(a) * rng.randf_range(10, 40) + Vector2(0, -20),
			rng.randf_range(radius * 0.25, radius * 0.5), l, l, false])
	for i in n / 2 + 2:
		var l := rng.randf_range(0.8, 1.6)
		puffs.append([pos + Vector2(rng.randf_range(-radius, radius) * 0.5, rng.randf_range(-radius, 0) * 0.5),
			Vector2(rng.randf_range(-15, 15), rng.randf_range(-35, -15)), rng.randf_range(3.0, radius * 0.35), l, l, true])


func flash(pos: Vector2, radius: float, color: Color, life: float) -> void:
	if _rec("flash", [pos, radius, color, life]):
		return
	flashes.append([pos, radius, color, life, life])


func text(pos: Vector2, s: String, color: Color) -> void:
	if _rec("text", [pos, s, color]):
		return
	texts.append([pos, s, color, 0.9])


func spawn_flame(pos: Vector2, vel: Vector2, owner: Fighter, dps: float, life: float) -> void:
	_rec("flame", [pos, vel, life]) # server keeps simulating it (it burns things)
	flames.append({"pos": pos, "vel": vel, "owner": owner, "dps": dps, "life": life * rng.randf_range(0.8, 1.2), "grounded": false})


func _physics_process(dt: float) -> void:
	var t: Terrain = arena.terrain
	var i := parts.size() - 1
	while i >= 0:
		var p: Array = parts[i]
		p[3] -= dt
		if p[3] <= 0.0:
			parts.remove_at(i)
			i -= 1
			continue
		var v: Vector2 = p[1]
		v.y += p[6] * dt
		var pos: Vector2 = p[0]
		var np := pos + v * dt
		if p[7] and v != Vector2.ZERO:
			if t.is_floor_at(Vector2(pos.x, np.y)) and (v.y > 0 or t.is_solid_at(Vector2(pos.x, np.y))):
				if p[8]:
					t.stain(Vector2(pos.x, np.y), p[2])
					p[3] = 0.0
					v = Vector2.ZERO
					np = pos
				else:
					v.y *= -0.3
					v.x *= 0.6
					np.y = pos.y
			if t.is_solid_at(Vector2(np.x, pos.y)):
				if p[8]:
					t.stain(Vector2(np.x, pos.y), p[2])
					p[3] = 0.0
				v.x *= -0.4
				np.x = pos.x
		p[0] = np
		p[1] = v
		i -= 1
	i = puffs.size() - 1
	while i >= 0:
		var pf: Array = puffs[i]
		pf[3] -= dt
		pf[0] += pf[1] * dt
		pf[1] *= 0.92
		if pf[3] <= 0.0:
			puffs.remove_at(i)
		i -= 1
	i = flashes.size() - 1
	while i >= 0:
		flashes[i][3] -= dt
		if flashes[i][3] <= 0.0:
			flashes.remove_at(i)
		i -= 1
	i = texts.size() - 1
	while i >= 0:
		texts[i][3] -= dt
		texts[i][0] += Vector2(0, -15) * dt
		if texts[i][3] <= 0.0:
			texts.remove_at(i)
		i -= 1
	_update_flames(dt, t)
	queue_redraw()


func _update_flames(dt: float, t: Terrain) -> void:
	var i := flames.size() - 1
	while i >= 0:
		var f: Dictionary = flames[i]
		f["life"] -= dt
		if f["life"] <= 0.0:
			flames.remove_at(i)
			i -= 1
			continue
		var pos: Vector2 = f["pos"]
		if not f["grounded"]:
			f["vel"].y += 500.0 * dt
			var np: Vector2 = pos + f["vel"] * dt
			if t.is_floor_at(np + Vector2(0, 1)):
				f["grounded"] = true
				np.y = floorf(np.y / Terrain.TILE) * Terrain.TILE - 0.01
			elif t.is_solid_at(Vector2(np.x, pos.y)):
				f["vel"].x *= -0.3
				np.x = pos.x
			f["pos"] = np
		elif not t.is_floor_at(pos + Vector2(0, 2)):
			f["grounded"] = false
			f["vel"] = Vector2.ZERO
		pos = f["pos"]
		# Burn tiles beneath
		if arena.net_mode != Net.CLIENT: # client flames are a cosmetic copy of the server's
			var below := pos + Vector2(0, 2)
			var m := t.mat_at(below)
			if m.get("flammable", false):
				t.damage_cell(t.cell_of(below), 6.0 * dt)
			# Hurt fighters
			var r := Rect2(pos - Vector2(3, 6), Vector2(6, 7))
			for fi in arena.fighters:
				if fi.alive() and r.intersects(fi.hitbox()):
					fi.apply_hit({"dmg": f["dps"] * dt, "kb": Vector2.ZERO, "src": f["owner"], "kind": "fire"})
		if rng.randf() < dt * 6.0 and arena.net_mode != Net.SERVER:
			burst(pos + Vector2(rng.randf_range(-2, 2), -3), Color(0.3, 0.3, 0.3, 0.5), 1, 10.0, 0.8, -40.0, false, 2.0)
		i -= 1


func _draw() -> void:
	for p in parts:
		var c: Color = p[2]
		var a: float = clampf(p[3] / p[4] * 2.0, 0.0, 1.0)
		var s: float = p[5]
		draw_rect(Rect2((p[0] as Vector2).round(), Vector2(s, s)), Color(c, c.a * a))
	for pf in puffs:
		var k: float = pf[3] / pf[4] # 1 -> 0
		var r: float = pf[2] * (0.5 + 0.5 * sin(k * PI)) if not pf[5] else pf[2] * (1.4 - k * 0.6)
		var c: Color
		if pf[5]:
			c = Color(0.22, 0.2, 0.22, 0.55 * k)
		elif k > 0.8:
			c = Color(1, 1, 0.9)
		elif k > 0.55:
			c = Color(1, 0.85, 0.3)
		elif k > 0.3:
			c = Color(0.98, 0.5, 0.15)
		else:
			c = Color(0.45, 0.2, 0.12)
		draw_circle((pf[0] as Vector2).round(), roundf(r), c)
	for fl in flashes:
		var k: float = fl[3] / fl[4]
		draw_circle(fl[0], fl[1] * (1.2 - k * 0.2), Color(fl[2], k))
	for f in flames:
		var pos: Vector2 = (f["pos"] as Vector2).round()
		var flick := rng.randi_range(0, 2)
		draw_rect(Rect2(pos + Vector2(-2, -3 - flick), Vector2(4, 3 + flick)), Color(1, 0.45, 0.1))
		draw_rect(Rect2(pos + Vector2(-1, -2 - flick), Vector2(2, 2 + flick)), Color(1, 0.9, 0.3))
	for tx in texts:
		var a: float = clampf(tx[3] * 2.0, 0.0, 1.0)
		var s: String = tx[1]
		Txt.draw_outlined(self, (tx[0] as Vector2) - Vector2(Txt.width(s) / 2.0, 0), s, Color(tx[2], a))
