class_name NavGraph
extends RefCounted
## Shared bot navigation graph on Godot's AStar2D (pathfinding runs in C++).
## Nodes = Nav.standable cells, directed edges = Nav.neighbors (walk/jump/leap/drop/climb...).
## Built incrementally over a few frames, and patched locally when terrain breaks,
## so big maps stay cheap.

const BATCH := 160 # cells (re)connected per physics frame

var t: Terrain
var astar := AStar2D.new()
var edge_type := {} # int(a * 65536 + b) -> String
var outgoing := {} # id -> PackedInt64Array of targets
var _pending: Array[Vector2i] = []
var _pending_set := {}


func _init(terrain: Terrain) -> void:
	t = terrain
	var all: Array[Vector2i] = []
	for y in t.height:
		for x in t.width:
			all.append(Vector2i(x, y))
	_invalidate(all)


func id(c: Vector2i) -> int:
	return c.x + c.y * t.width


func cell(i: int) -> Vector2i:
	return Vector2i(i % t.width, i / t.width)


func ready() -> bool:
	return _pending.is_empty()


## A tile changed: everything that could path through or onto it needs a refresh.
func on_tile_changed(c: Vector2i, _m = null) -> void:
	var cells: Array[Vector2i] = []
	for x in range(c.x - 7, c.x + 8):
		for y in range(c.y - 7, c.y + 3):
			cells.append(Vector2i(x, y))
	for x in range(c.x - 1, c.x + 2): # drops into this column from anywhere above
		for y in range(0, c.y - 7):
			cells.append(Vector2i(x, y))
	_invalidate(cells)


func _invalidate(cells: Array[Vector2i]) -> void:
	# Phase 1 (immediate, cheap): fix which cells are nodes.
	for c in cells:
		if c.x < 0 or c.y < 0 or c.x >= t.width or c.y >= t.height:
			continue
		var i := id(c)
		var st := Nav.standable(t, c)
		if astar.has_point(i) and not st:
			astar.remove_point(i)
			outgoing.erase(i)
		elif st and not astar.has_point(i):
			astar.add_point(i, Vector2(c))
		if st and not _pending_set.has(i):
			_pending_set[i] = true
			_pending.append(c)


## Phase 2 (spread over frames): rebuild outgoing edges of queued cells.
func step() -> void:
	var n := 0
	while not _pending.is_empty() and n < BATCH:
		var c: Vector2i = _pending.pop_back()
		_pending_set.erase(id(c))
		_connect(c)
		n += 1


func _connect(c: Vector2i) -> void:
	var a := id(c)
	if not astar.has_point(a):
		return
	if outgoing.has(a):
		for b in outgoing[a]:
			if astar.has_point(b) and astar.are_points_connected(a, b, false):
				astar.disconnect_points(a, b, false)
			edge_type.erase(a * 65536 + b)
	var outs := PackedInt64Array()
	for ne in Nav.neighbors(t, c):
		var b := id(ne[0])
		if b == a or not astar.has_point(b):
			continue
		if not astar.are_points_connected(a, b, false):
			astar.connect_points(a, b, false)
		edge_type[a * 65536 + b] = ne[1]
		outs.append(b)
	outgoing[a] = outs


## Same shape as the old Nav.find_path: [[cell, edge], ...] starting at `from`.
## Unreachable goals give a path to the closest reachable node.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	var a := id(from)
	if not astar.has_point(a):
		a = astar.get_closest_point(Vector2(from))
	var b := id(to)
	if not astar.has_point(b):
		b = astar.get_closest_point(Vector2(to))
	if a < 0 or b < 0:
		return [[from, "start"]]
	var ids := astar.get_id_path(a, b, true)
	if ids.is_empty():
		return [[from, "start"]]
	var path := [[cell(ids[0]), "start"]]
	for k in range(1, ids.size()):
		path.append([cell(ids[k]), edge_type.get(ids[k - 1] * 65536 + ids[k], "walk")])
	return path
