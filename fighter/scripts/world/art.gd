class_name Art
extends RefCounted
## Loads the generated sprite sheets (assets/sprites, made by tools/gen_art.py) and
## hands out textures. Fighters are recolored per player from magenta key pixels.

const DIR := "res://assets/sprites/"
const SKINS := [Color(0.93, 0.71, 0.55), Color(0.78, 0.55, 0.38), Color(0.55, 0.36, 0.24), Color(0.98, 0.8, 0.66)]
const HAIRS := [Color(0.23, 0.16, 0.13), Color(0.55, 0.35, 0.16), Color(0.85, 0.7, 0.35), Color(0.12, 0.1, 0.1), Color(0.6, 0.2, 0.12)]

static var atlas: Dictionary = {}
static var _fighter_img: Image
static var _fighter_cache := {}
static var _weapons_tex: Texture2D
static var _props_tex: Texture2D
static var _weapon_cache := {}
static var _tiles: Dictionary = {} # name -> Image
static var frame_index := {}


static func ensure() -> void:
	if not atlas.is_empty():
		return
	atlas = JSON.parse_string(FileAccess.get_file_as_string(DIR + "atlas.json"))
	var names: Array = atlas["fighter"]["frames"]
	for i in names.size():
		frame_index[names[i]] = i
	_fighter_img = _img("fighter.png")
	_weapons_tex = load(DIR + "weapons.png")
	_props_tex = load(DIR + "props.png")
	var timg := _img("tiles.png")
	for tname in atlas["tiles"]:
		var r: Array = atlas["tiles"][tname]
		_tiles[tname] = timg.get_region(Rect2i(r[0], r[1], r[2], r[3]))


static func _img(file: String) -> Image:
	var tex: Texture2D = load(DIR + file)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func frame_count() -> int:
	ensure()
	return atlas["fighter"]["frames"].size()


static func frame(fname: String) -> int:
	ensure()
	return frame_index.get(fname, 0)


static func shoulder(frame_i: int) -> Vector2:
	var s: Array = atlas["fighter"]["shoulders"][frame_i]
	return Vector2(s[0], s[1])


## Fighter sheet recolored: team color, plus a skin/hair variant per player.
static func fighter_texture(team: Color, variant := 0) -> ImageTexture:
	ensure()
	var key := "%s_%d" % [team.to_html(), variant]
	if _fighter_cache.has(key):
		return _fighter_cache[key]
	var img: Image = _fighter_img.duplicate()
	var skin: Color = SKINS[variant % SKINS.size()]
	var hair: Color = HAIRS[(variant * 3 + 1) % HAIRS.size()]
	var skin_ref := Color8(238, 182, 140)
	var skin_sh := Color8(198, 138, 104)
	var hair_ref := Color8(58, 40, 32)
	var hair_hi := Color8(92, 64, 46)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			if is_equal_approx(c.r, c.b) and c.g == 0.0 and c.r > 0.0:
				var f := c.r / 0.8
				var t := team * minf(f, 1.0)
				if f > 1.0:
					t = team.lightened(0.3)
				t.a = 1.0
				img.set_pixel(x, y, t)
			elif c.is_equal_approx(skin_ref):
				img.set_pixel(x, y, skin)
			elif c.is_equal_approx(skin_sh):
				img.set_pixel(x, y, skin.darkened(0.2))
			elif c.is_equal_approx(hair_ref):
				img.set_pixel(x, y, hair)
			elif c.is_equal_approx(hair_hi):
				img.set_pixel(x, y, hair.lightened(0.2))
	var tex := ImageTexture.create_from_image(img)
	_fighter_cache[key] = tex
	return tex


static func team_arm(team: Color, variant := 0) -> ImageTexture:
	# Arm is recolored the same way; reuse the logic with a tiny image.
	ensure()
	var key := "arm_%s_%d" % [team.to_html(), variant]
	if _fighter_cache.has(key):
		return _fighter_cache[key]
	var img := _img("arm.png")
	var skin: Color = SKINS[variant % SKINS.size()]
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and is_equal_approx(c.r, c.b) and c.g == 0.0 and c.r > 0.0:
				img.set_pixel(x, y, Color(team * minf(c.r / 0.8, 1.0), 1.0))
			elif c.is_equal_approx(Color8(238, 182, 140)):
				img.set_pixel(x, y, skin)
	var tex := ImageTexture.create_from_image(img)
	_fighter_cache[key] = tex
	return tex


static func weapon_sprite_name(d: WeaponDef) -> String:
	ensure()
	for n in [d.sprite, d.id, d.style]:
		if n != "" and atlas["weapons"].has(n):
			return n
	return {"gun": "pistol", "melee": "knife", "throwable": "grenade"}.get(d.kind, "pistol")


## Returns {tex, grip, muzzle} with grip/muzzle relative to the texture's top-left.
static func weapon(d: WeaponDef) -> Dictionary:
	var n := weapon_sprite_name(d)
	if _weapon_cache.has(n):
		return _weapon_cache[n]
	var e: Dictionary = atlas["weapons"][n]
	var at := AtlasTexture.new()
	at.atlas = _weapons_tex
	var r: Array = e["rect"]
	at.region = Rect2(r[0], r[1], r[2], r[3])
	var out := {"tex": at, "grip": Vector2(e["grip"][0], e["grip"][1]), "muzzle": Vector2(e["muzzle"][0], e["muzzle"][1])}
	_weapon_cache[n] = out
	return out


static func prop(name: String) -> AtlasTexture:
	ensure()
	var r: Array = atlas["props"][name]["rect"]
	var at := AtlasTexture.new()
	at.atlas = _props_tex
	at.region = Rect2(r[0], r[1], r[2], r[3])
	return at


static var _tiles_tex: Texture2D


static func tiles_texture() -> Texture2D:
	ensure()
	if _tiles_tex == null:
		_tiles_tex = load(DIR + "tiles.png")
	return _tiles_tex


## Column (16px wide) of a material texture in tiles.png.
static func tile_column(name: String) -> int:
	ensure()
	var r: Array = atlas["tiles"].get(name, [0, 0, 16, 16])
	return int(r[0]) / 16


static func tile_image(name: String) -> Image:
	ensure()
	return _tiles.get(name)


## Draws a weapon centered on the origin of `xf` (pickups lying around).
static func draw_weapon_centered(ci: CanvasItem, d: WeaponDef, xf: Transform2D) -> void:
	var w := weapon(d)
	var tex: Texture2D = w["tex"]
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(tex, -tex.get_size() / 2.0)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Draws a weapon with its grip at the origin of `xf`. Used for pickups/grenades.
static func draw_weapon(ci: CanvasItem, d: WeaponDef, xf: Transform2D) -> void:
	var w := weapon(d)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(w["tex"], -w["grip"])
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
