class_name Terrain
extends Node2D
## Destructible tile grid.
## Collision: an invisible TileMapLayer (8px tiles, per-tile HP in a dictionary).
## Looks: terrain.gdshader draws the map from a one-pixel-per-cell data texture (materials,
## damage, flags) — lit edges, grass, chipped corners, cracks, wall shadows — so any map size
## renders instantly and a destroyed tile only updates one pixel. A stain layer on top holds
## scorch marks and blood.

signal tile_destroyed(cell: Vector2i, mat: Dictionary)

const TILE := 8

var width := 0
var height := 0
var solid_layer: TileMapLayer
var hp := {} # Vector2i -> float
var mats := {} # Vector2i -> material row
var bg := {} # Vector2i -> material row (background wall)
var ladders := {} # Vector2i -> true
var arena: Node

var _cells_img: Image
var _cells_tex: ImageTexture
var _stain_img: Image
var _stain_tex: ImageTexture
var _view: ColorRect
var _stain_view: Sprite2D
var _dirty := {}
var _stain_dirty := false
var _stain_t := 0.0
var track_changes := false # online server: remember changed cells for snapshots
var net_changes := {} # cell -> hp (-1 = destroyed) since the last snapshot
var round_changes := {} # same, since the round started (for players joining mid-round)
var _break_sounds := {} # sound name -> [pos sum, count]; flushed once per frame (explosions break dozens)

static var _tileset: TileSet


static func tileset() -> TileSet:
	if _tileset:
		return _tileset
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, Layers.TERRAIN)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, Layers.PLATFORMS)
	ts.set_physics_layer_collision_mask(1, 0)
	var src := TileSetAtlasSource.new()
	var n := TileMats.LIST.size()
	src.texture = ImageTexture.create_from_image(Image.create(TILE, TILE * n, false, Image.FORMAT_RGBA8))
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var h := TILE / 2.0
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var top := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, 0), Vector2(-h, 0)])
	for row in n:
		var m: Dictionary = TileMats.LIST[row]
		var ac := Vector2i(0, row)
		src.create_tile(ac)
		if not m["solid"]:
			continue
		var td := src.get_tile_data(ac, 0)
		if m.get("one_way", false):
			td.add_collision_polygon(1)
			td.set_collision_polygon_points(1, 0, top)
			td.set_collision_polygon_one_way(1, 0, true)
		else:
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, full)
	_tileset = ts
	return ts


func _ready() -> void:
	solid_layer = TileMapLayer.new()
	solid_layer.tile_set = tileset()
	solid_layer.visible = false # collision only
	add_child(solid_layer)
	_view = ColorRect.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/terrain.gdshader")
	_view.material = mat
	add_child(_view)
	_stain_view = Sprite2D.new()
	_stain_view.centered = false
	add_child(_stain_view)


## Parses ASCII rows. Returns entity markers found in the grid.
func load_rows(rows: Array) -> Dictionary:
	height = rows.size()
	width = 0
	for r in rows:
		width = maxi(width, String(r).length())
	var ents := {"spawns": [], "spawners": [], "crates": [], "barrels": []}
	for y in height:
		var line: String = rows[y]
		for x in line.length():
			var ch := line[x]
			var c := Vector2i(x, y)
			match ch:
				".", " ":
					pass
				"P": ents["spawns"].append(cell_bottom(c))
				"X": ents["spawners"].append(cell_bottom(c))
				"C": ents["crates"].append(cell_bottom(c))
				"B": ents["barrels"].append(cell_bottom(c))
				_:
					var up := ch.to_upper()
					var row := TileMats.index_of_char(up)
					if row < 0:
						push_warning("Unknown map char '%s' at %s" % [ch, c])
						continue
					if ch != up:
						bg[c] = row
					else:
						set_tile(c, row)
	# Cells inside a wall (platforms, ladders, entity markers) borrow the wall behind them.
	for pass_i in 2:
		for y in height:
			for x in width:
				var c := Vector2i(x, y)
				if not bg.has(c) and not is_solid(c):
					_inherit_bg(c)
	_cells_img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	_stain_img = Image.create(width * TILE, height * TILE, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			_bake(Vector2i(x, y))
	_cells_tex = ImageTexture.create_from_image(_cells_img)
	_view.size = pixel_size()
	var sm: ShaderMaterial = _view.material
	sm.set_shader_parameter("cells", _cells_tex)
	sm.set_shader_parameter("tiles", Art.tiles_texture())
	sm.set_shader_parameter("map_cells", Vector2(width, height))
	sm.set_shader_parameter("ladder_col", Art.tile_column("ladder"))
	_stain_tex = ImageTexture.create_from_image(_stain_img)
	_stain_view.texture = _stain_tex
	return ents


func set_tile(c: Vector2i, row: int) -> void:
	var m: Dictionary = TileMats.LIST[row]
	if not m["solid"]:
		ladders[c] = true
		return
	solid_layer.set_cell(c, 0, Vector2i(0, row))
	mats[c] = row
	hp[c] = float(m["hp"])


func damage_cell(c: Vector2i, amount: float) -> bool:
	if amount <= 0.0 or not mats.has(c):
		return false
	var m: Dictionary = TileMats.LIST[mats[c]]
	var max_hp: float = m["hp"]
	if max_hp < 0.0:
		return false
	var before := _stage(c)
	hp[c] -= amount
	if hp[c] <= 0.0:
		destroy_cell(c)
		return true
	if _stage(c) != before:
		_mark(c)
		if track_changes:
			net_changes[c] = int(hp[c])
			round_changes[c] = int(hp[c])
	return false


func _stage(c: Vector2i) -> int:
	if not mats.has(c):
		return 0
	var max_hp: float = TileMats.LIST[mats[c]]["hp"]
	if max_hp <= 0.0:
		return 0
	var frac: float = hp[c] / max_hp
	return 2 if frac < 0.34 else (1 if frac < 0.67 else 0)


func destroy_cell(c: Vector2i) -> void:
	if not mats.has(c):
		return
	var row: int = mats[c]
	var m: Dictionary = TileMats.LIST[row]
	solid_layer.erase_cell(c)
	mats.erase(c)
	hp.erase(c)
	if m.get("bg", false) and not bg.has(c):
		bg[c] = row
	elif not bg.has(c):
		_inherit_bg(c)
	# Stains on a vanished tile go with it.
	for y in TILE:
		for x in TILE:
			_stain_img.set_pixel(c.x * TILE + x, c.y * TILE + y, Color(0, 0, 0, 0))
	_stain_dirty = true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_mark(c + Vector2i(dx, dy))
	if track_changes:
		net_changes[c] = -1
		round_changes[c] = -1
	if arena and arena.net_mode != Net.SERVER:
		var col: Color = m["color"]
		if m.get("shatter", false):
			arena.fx.burst(cell_center(c), Color(0.8, 0.95, 1.0), 10, 90.0, 0.7, 500.0)
		else:
			arena.fx.debris(cell_center(c), Color(col, 1.0), 6)
		_queue_break_sound(c, m)
	tile_destroyed.emit(c, m)


## Online client: the server says this cell now has `cell_hp` (-1 = destroyed).
func apply_net_cell(c: Vector2i, cell_hp: int) -> void:
	if not mats.has(c):
		return
	if cell_hp < 0:
		destroy_cell(c)
		return
	var before := _stage(c)
	hp[c] = float(cell_hp)
	if _stage(c) != before:
		_mark(c)


func _queue_break_sound(c: Vector2i, m: Dictionary) -> void:
	var snd := "glass_break" if m.get("shatter", false) else ("wood_break" if m.get("flammable", false) else "tile_break")
	if _break_sounds.is_empty():
		_flush_break_sounds.call_deferred()
	var e: Array = _break_sounds.get(snd, [Vector2.ZERO, 0])
	e[0] += cell_center(c)
	e[1] += 1
	_break_sounds[snd] = e


func _flush_break_sounds() -> void:
	for snd in _break_sounds:
		var e: Array = _break_sounds[snd]
		var n: int = e[1]
		Sfx.play(snd, e[0] / float(n), minf(6.0, 2.0 * log(float(n)) / log(2.0)) - 2.0)
	_break_sounds.clear()


## Takes the background wall of the neighbours if at least two of them have one.
func _inherit_bg(c: Vector2i) -> void:
	var votes := {}
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if bg.has(c + d):
			votes[bg[c + d]] = votes.get(bg[c + d], 0) + 1
	var best := -1
	var n := 0
	for k in votes:
		n += votes[k]
		if best < 0 or votes[k] > votes[best]:
			best = k
	if n >= 2:
		bg[c] = best


func damage_circle(center: Vector2, radius: float, amount: float) -> void:
	var c0 := cell_of(center - Vector2(radius, radius))
	var c1 := cell_of(center + Vector2(radius, radius))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var c := Vector2i(x, y)
			var d := cell_center(c).distance_to(center)
			if d <= radius:
				damage_cell(c, amount * (1.0 - 0.6 * d / radius))


func damage_rect(r: Rect2, amount: float) -> void:
	var c0 := cell_of(r.position)
	var c1 := cell_of(r.end - Vector2(0.01, 0.01))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			damage_cell(Vector2i(x, y), amount)


# ---------------------------------------------------------------- stains

## Scorch mark: darkens terrain pixels in a soft circle.
func scorch(center: Vector2, radius: float) -> void:
	var r := int(radius)
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d := Vector2(x, y).length()
			if d > radius:
				continue
			var p := Vector2i(int(center.x) + x, int(center.y) + y)
			if not _in_img(p) or not _has_look(cell_of(Vector2(p))):
				continue
			var k := (1.0 - d / radius) * 0.75 + _hash(p.x, p.y) * 0.2
			var cur := _stain_img.get_pixelv(p)
			_stain_img.set_pixelv(p, Color(0.05, 0.03, 0.03, clampf(maxf(cur.a, k), 0.0, 0.8)))
	_stain_dirty = true


## Paint one stain pixel (blood landing on a wall/floor).
func stain(p: Vector2, col: Color) -> void:
	var ip := Vector2i(p)
	if _in_img(ip) and _has_look(cell_of(p)):
		_stain_img.set_pixelv(ip, col)
		_stain_dirty = true


static func _hash(x: int, y: int) -> float:
	var h := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return h - floorf(h)


func _has_look(c: Vector2i) -> bool:
	return mats.has(c) or bg.has(c)


func _in_img(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width * TILE and p.y < height * TILE


# ---------------------------------------------------------------- baking

func _mark(c: Vector2i) -> void:
	if c.x >= 0 and c.y >= 0 and c.x < width and c.y < height:
		_dirty[c] = true


func _process(dt: float) -> void:
	if not _dirty.is_empty():
		for c in _dirty:
			_bake(c)
		_dirty.clear()
		_cells_tex.update(_cells_img)
	_stain_t -= dt
	if _stain_dirty and _stain_t <= 0.0:
		_stain_dirty = false
		_stain_t = 0.05
		_stain_tex.update(_stain_img)


## Writes one cell into the data texture the shader reads.
func _bake(c: Vector2i) -> void:
	var r := 0
	var fl := 0
	if mats.has(c):
		var m: Dictionary = TileMats.LIST[mats[c]]
		r = Art.tile_column(m["pattern"]) + 1
		fl |= _stage(c) << 1
		if m.get("one_way", false):
			fl |= 8
		if float(m["hp"]) > 0.0 and m["id"] != "glass":
			fl |= 16
		if m["id"] == "dirt":
			fl |= 32
		if m["id"] == "glass":
			fl |= 64
	var g := Art.tile_column(TileMats.LIST[bg[c]]["pattern"]) + 1 if bg.has(c) else 0
	if ladders.has(c):
		fl |= 1
	_cells_img.set_pixel(c.x, c.y, Color8(r, g, fl, 255))


# ---------------------------------------------------------------- queries

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)


func cell_bottom(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * TILE, (c.y + 1) * TILE)


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func is_solid(c: Vector2i) -> bool:
	return mats.has(c) and not TileMats.LIST[mats[c]].get("one_way", false)


func is_solid_at(p: Vector2) -> bool:
	return is_solid(cell_of(p))


func is_platform_at(p: Vector2) -> bool:
	var c := cell_of(p)
	return mats.has(c) and TileMats.LIST[mats[c]].get("one_way", false)


## Solid or platform: anything you can stand on.
func is_floor_at(p: Vector2) -> bool:
	return mats.has(cell_of(p))


func is_ladder_at(p: Vector2) -> bool:
	return ladders.has(cell_of(p))


func mat_at(p: Vector2) -> Dictionary:
	var c := cell_of(p)
	return TileMats.LIST[mats[c]] if mats.has(c) else {}


## Cheap grid line-of-sight (solid tiles only).
func line_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 4.0) + 1
	for i in range(1, steps):
		if is_solid_at(a.lerp(b, float(i) / steps)):
			return false
	return true
