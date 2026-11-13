class_name Nav
extends RefCounted
## Platformer pathfinding over the live tile grid (no baked graph, so it adapts to
## destroyed terrain). Nodes are "stand cells": the cell a fighter's feet occupy.
## Edges: walk, jump, drop (walk off a ledge), pdrop (through a platform), climb.

const MAX_NODES := 2500
const JUMP_UP := 4 # tiles
const JUMP_ACROSS := 6


static func open_cell(t: Terrain, c: Vector2i) -> bool:
	return not t.is_solid(c) and c.x >= 0 and c.x < t.width


static func has_floor(t: Terrain, c: Vector2i) -> bool:
	return t.mats.has(c + Vector2i(0, 1))


## Fighter fits here (3 cells tall, since a fighter is 18px) and is supported.
static func standable(t: Terrain, c: Vector2i) -> bool:
	if c.y < 0 or c.y >= t.height:
		return false
	if not (open_cell(t, c) and open_cell(t, c + Vector2i(0, -1)) and open_cell(t, c + Vector2i(0, -2))):
		return false
	return has_floor(t, c) or t.ladders.has(c)


static func feet_cell(t: Terrain, pos: Vector2) -> Vector2i:
	return t.cell_of(pos + Vector2(0, -1))


## Project a world position down to the nearest stand cell (for airborne targets).
static func ground_cell(t: Terrain, pos: Vector2) -> Vector2i:
	var c := feet_cell(t, pos)
	for i in 12:
		if standable(t, c):
			return c
		if t.is_solid(c + Vector2i(0, 1)):
			break # never project through a floor
		c.y += 1
	return feet_cell(t, pos)


static func _fall(t: Terrain, c: Vector2i) -> Vector2i:
	# Fall straight down from c until standable. Returns y=-1 if bottomless.
	var p := c
	while p.y < t.height + 2:
		if standable(t, p):
			return p
		if t.is_solid(p):
			return Vector2i(0, -1)
		p.y += 1
	return Vector2i(0, -1)


static func neighbors(t: Terrain, c: Vector2i) -> Array:
	var out := []
	var on_ladder := t.ladders.has(c)
	for dx in [-1, 1]:
		var n := c + Vector2i(dx, 0)
		if standable(t, n):
			out.append([n, "walk"])
		elif open_cell(t, n) and open_cell(t, n + Vector2i(0, -1)) and open_cell(t, n + Vector2i(0, -2)) and not on_ladder:
			var land := _fall(t, n)
			if land.y >= 0:
				out.append([land, "drop"])
		# Step up one tile.
		var up := c + Vector2i(dx, -1)
		if standable(t, up) and open_cell(t, c + Vector2i(0, -3)):
			out.append([up, "jump"])
	# Ladders
	if on_ladder or t.ladders.has(c + Vector2i(0, -1)):
		var u := c + Vector2i(0, -1)
		if t.ladders.has(u) or standable(t, u):
			out.append([u, "climb"])
		elif t.is_platform_at(t.cell_center(u)) and standable(t, u + Vector2i(0, -1)):
			out.append([u + Vector2i(0, -1), "climb"])
	if on_ladder:
		var d := c + Vector2i(0, 1)
		if t.ladders.has(d) or (standable(t, d) and not t.is_solid(d)):
			out.append([d, "climb"])
	# Standing on a platform: ladder underneath, or drop through.
	var below := c + Vector2i(0, 1)
	if t.is_platform_at(t.cell_center(below)):
		if t.ladders.has(below + Vector2i(0, 1)):
			out.append([below + Vector2i(0, 1), "climbdown"])
		else:
			var land := _fall(t, below + Vector2i(0, 1))
			if land.y >= 0:
				out.append([land, "pdrop"])
	# Jumps (only from real floor).
	if has_floor(t, c):
		for dy in range(1, JUMP_UP + 1):
			if not open_cell(t, c + Vector2i(0, -2 - dy)):
				break
			for dx in range(-3, 4):
				var n := c + Vector2i(dx, -dy)
				if dx == 0 and dy == 0:
					continue
				if standable(t, n) and has_floor(t, n) and _arc_clear(t, c, n, n.y - 2):
					out.append([n, "jump"])
		# Higher ledges: jump, grab the lip, pull up (fighter.gd _try_ledge).
		for dx in [-1, 1]:
			for dy in range(JUMP_UP + 1, JUMP_UP + 3):
				var n := c + Vector2i(dx, -dy)
				if not (standable(t, n) and t.is_solid(n + Vector2i(0, 1))):
					continue
				var clear := true
				for y in range(n.y - 1, c.y):
					if t.is_solid(Vector2i(c.x, y)):
						clear = false
						break
				if clear:
					out.append([n, "ledge"])
		# Long jumps across gaps, level or downward.
		for dy in range(0, 4):
			for dx in [-JUMP_ACROSS, -5, -4, -3, 3, 4, 5, JUMP_ACROSS]:
				# Only leap when there's a gap; otherwise walking is better.
				if standable(t, c + Vector2i(signi(dx), 0)):
					continue
				var n := c + Vector2i(dx, dy)
				if standable(t, n) and has_floor(t, n) and _arc_clear(t, c, n, mini(c.y, n.y) - 2):
					out.append([n, "leap"])
	return out


## Jump path: rise straight up from a to top_y, cross over at that height (3 cells tall,
## the fighter's height), then come down onto b.
static func _arc_clear(t: Terrain, a: Vector2i, b: Vector2i, top_y: int) -> bool:
	for y in range(top_y - 1, a.y):
		if t.is_solid(Vector2i(a.x, y)):
			return false
	var step := 1 if b.x >= a.x else -1
	var x := a.x
	while true:
		for y in range(top_y - 1, top_y + 2):
			if t.is_solid(Vector2i(x, y)):
				return false
		if x == b.x:
			break
		x += step
	for y in range(top_y - 1, b.y):
		if t.is_solid(Vector2i(b.x, y)):
			return false
	return true


## BFS. Returns [[cell, edge], ...] starting at `from` (edge "start"), or [] if unreachable.
static func find_path(t: Terrain, from: Vector2i, to: Vector2i) -> Array:
	if from == to:
		return [[from, "start"]]
	var came := {from: null}
	var edge := {from: "start"}
	var q: Array[Vector2i] = [from]
	var head := 0
	var best := from
	var best_d := absi(from.x - to.x) + absi(from.y - to.y) * 2
	while head < q.size() and q.size() < MAX_NODES:
		var c: Vector2i = q[head]
		head += 1
		if c == to:
			best = c
			break
		for ne in neighbors(t, c):
			var n: Vector2i = ne[0]
			if came.has(n):
				continue
			came[n] = c
			edge[n] = ne[1]
			q.append(n)
			var d := absi(n.x - to.x) + absi(n.y - to.y) * 2
			if d < best_d:
				best_d = d
				best = n
	# Path to the goal, or to the closest reachable cell.
	var path := []
	var p = best
	while p != null:
		path.push_front([p, edge[p]])
		p = came[p]
	return path
