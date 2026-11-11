extends RefCounted

# Adapters that let Weapons.gd work the same in both modes. Points are 2D:
# (x, z) on the race track, (x, y) in the side-view mining mode.

class RaceWorld:
	var main
	func _init(m):
		main = m
	func _cell(p: Vector2) -> Vector2i:
		return main.terrain.world_to_cell(Vector3(p.x, 0.0, p.y))
	func up() -> Vector3:
		return Vector3.UP
	func to3(p: Vector2, h: float) -> Vector3:
		return Vector3(p.x, h, p.y)
	func solid(p: Vector2) -> bool:
		var c = _cell(p)
		return main.terrain.is_solid(c) and main.terrain.top_of(c) > 0.5
	func hit(p: Vector2, amount: float, tier: int) -> int:
		return main.terrain.damage(_cell(p), amount, tier)
	func blast(p: Vector2, r: float, tier: int) -> void:
		main._explode(Vector3(p.x, 0.6, p.y), r, tier)
	# Things a shot sets off just by touching them: mines.
	func touch(p: Vector2, r: float) -> bool:
		for m in main.track.mines:
			if m.timer <= 0.0 and Vector2(m.pos.x - p.x, m.pos.z - p.y).length() < r:
				main.detonate_mine(m)
				return true
		for rv in main.rivals:
			if rv.down_left <= 0.0 and Vector2(rv.position.x - p.x, rv.position.z - p.y).length() < r + rv.stats.radius:
				rv.take_hit(25.0)
				return true
		return false
	func target(p: Vector2, r: float):
		var best = null
		var bd = r
		for m in main.track.mines:
			if m.timer <= 0.0:
				var q = Vector2(m.pos.x, m.pos.z)
				if q.distance_to(p) < bd:
					bd = q.distance_to(p)
					best = q
		for rv in main.rivals:
			var q = Vector2(rv.position.x, rv.position.z)
			if q.distance_to(p) < bd:
				bd = q.distance_to(p)
				best = q
		return best
	func pull(p: Vector2, r: float, k: float) -> void:
		for pk in main.pickups:
			var q = Vector2(pk.pos.x, pk.pos.z)
			if q.distance_to(p) < r:
				var d = (p - q).normalized() * k
				pk.vel += Vector3(d.x, 0.0, d.y)
	func quench(_p: Vector2, _r: float) -> void:
		pass
	func burst(p: Vector2, c: Color, n: int, speed: float, h: float) -> void:
		main.fx.burst(Vector3(p.x, h, p.y), c, n, speed, 1.2, 0.12, 0.5, 4.0)
	func spark(p: Vector2, c: Color, h: float) -> void:
		main.fx.spawn(Vector3(p.x, h, p.y), Vector3(randf_range(-3, 3), 4.0, randf_range(-3, 3)), c, 1.2, 0.08, 0.3)
	func smoke(p: Vector2, h: float) -> void:
		main.fx.spawn(Vector3(p.x, h, p.y), Vector3(0, 1.0, 0), Color(0.35, 0.35, 0.35), 0.0, 0.18, 0.5, -1.0)
	func swirl(p: Vector2, a: float, h: float) -> void:
		var q = p + Vector2(cos(a), sin(a)) * 6.0
		main.fx.spawn(Vector3(q.x, h, q.y), Vector3(-cos(a) * 6.0 - sin(a) * 4.0, 0.0, -sin(a) * 6.0 + cos(a) * 4.0), Color(0.7, 0.5, 1.0), 1.2, 0.1, 0.8, 0.0)

class MineWorld:
	var mining
	func _init(m):
		mining = m
	func _at(p: Vector2) -> Array:
		for pl in mining.planets_near(p, 1.0):
			var c = pl.terrain.world_to_cell(pl.local(p))
			if pl.terrain.is_solid(c):
				return [pl, c]
		return []
	func up() -> Vector3:
		return Vector3(0, 0, 1)
	func to3(p: Vector2, _h: float) -> Vector3:
		return Vector3(p.x, p.y, 0.5)
	func solid(p: Vector2) -> bool:
		return not _at(p).is_empty()
	func hit(p: Vector2, amount: float, tier: int) -> int:
		var a = _at(p)
		if a.is_empty():
			return 0
		return a[0].terrain.damage(a[1], amount, tier)
	func blast(p: Vector2, r: float, tier: int) -> void:
		preload("res://scripts/Sfx.gd").play("small_boom" if r < 2.0 else "boom")
		for pl in mining.planets_near(p, r + 2.0):
			pl.terrain.blast(pl.local(p), r, tier)
		mining.blast_enemies(p, r)
		mining.main.fx.burst(Vector3(p.x, p.y, 1.0), Color(1.0, 0.55, 0.15), 30, 10.0, 1.2, 0.18, 0.5, 0.0)
	func touch(p: Vector2, r: float) -> bool:
		return mining.touch_enemies(p, r)
	# Homing in the field goes for ore (or anything hostile).
	func target(p: Vector2, r: float):
		var e = mining.nearest_enemy(p, r)
		if e != null:
			return e
		for pl in mining.planets_near(p, r):
			var t = pl.terrain
			var c0 = t.world_to_cell(pl.local(p))
			var best = null
			var bd = r * r
			var rr = int(r)
			for dj in range(-rr, rr + 1, 2):
				for di in range(-rr, rr + 1, 2):
					var c = c0 + Vector2i(di, dj)
					var k = t.get_kind(c)
					if k == t.ORE_A or k == t.ORE_B or k == t.ORE_C:
						var w = pl.cell_world(c)
						var d = w.distance_squared_to(p)
						if d < bd:
							bd = d
							best = w
			if best != null:
				return best
		return null
	func pull(p: Vector2, r: float, k: float) -> void:
		for pk in mining.pickups:
			if pk.pos.distance_to(p) < r:
				pk.vel += (p - pk.pos).normalized() * k
		mining.pull_enemies(p, r, k)
	func quench(p: Vector2, r: float) -> void:
		for pl in mining.planets_near(p, r + 2.0):
			var t = pl.terrain
			var c0 = t.world_to_cell(pl.local(p))
			var rr = ceili(r)
			for dj in range(-rr, rr + 1):
				for di in range(-rr, rr + 1):
					var c = c0 + Vector2i(di, dj)
					var k = t.get_kind(c)
					if (k == t.LAVA or k == t.GAS) and pl.cell_world(c).distance_to(p) < r:
						t.set_kind(c, t.ROCK)
	func burst(p: Vector2, c: Color, n: int, speed: float, _h: float) -> void:
		mining.main.fx.burst(Vector3(p.x, p.y, 1.0), c, n, speed, 1.2, 0.12, 0.5, 0.0)
	func spark(p: Vector2, c: Color, _h: float) -> void:
		mining.main.fx.spawn(Vector3(p.x, p.y, 1.0), Vector3(randf_range(-3, 3), randf_range(-3, 3), 3.0), c, 1.2, 0.08, 0.3, 0.0)
	func smoke(p: Vector2, _h: float) -> void:
		mining.main.fx.spawn(Vector3(p.x, p.y, 0.6), Vector3(0, 0, 1.0), Color(0.35, 0.35, 0.35), 0.0, 0.18, 0.5, 0.0)
	func swirl(p: Vector2, a: float, _h: float) -> void:
		var q = p + Vector2(cos(a), sin(a)) * 6.0
		mining.main.fx.spawn(Vector3(q.x, q.y, 0.8), Vector3(-cos(a) * 6.0 - sin(a) * 4.0, -sin(a) * 6.0 + cos(a) * 4.0, 0.0), Color(0.7, 0.5, 1.0), 1.2, 0.1, 0.8, 0.0)
