class_name TileMats
extends RefCounted
## Terrain materials. Index in LIST == row in the generated atlas.
## Map chars: uppercase = solid tile, lowercase = background wall of that material.
## hp < 0 means indestructible.

static var LIST: Array = [
	{"id": "dirt", "char": "D", "hp": 30.0, "solid": true, "pattern": "dirt",
		"color": Color(0.46, 0.31, 0.19), "bg": true},
	{"id": "brick", "char": "S", "hp": 90.0, "solid": true, "pattern": "brick",
		"color": Color(0.55, 0.36, 0.32), "bg": true},
	{"id": "wood", "char": "W", "hp": 28.0, "solid": true, "pattern": "wood",
		"color": Color(0.62, 0.42, 0.22), "bg": true, "flammable": true},
	{"id": "glass", "char": "G", "hp": 4.0, "solid": true, "pattern": "glass",
		"color": Color(0.62, 0.86, 0.96, 0.55), "bg": false, "shatter": true},
	{"id": "metal", "char": "M", "hp": -1.0, "solid": true, "pattern": "metal",
		"color": Color(0.36, 0.39, 0.44), "bg": false},
	{"id": "platform", "char": "-", "hp": 16.0, "solid": true, "one_way": true, "pattern": "platform",
		"color": Color(0.66, 0.46, 0.24), "bg": false, "flammable": true},
	{"id": "ladder", "char": "H", "hp": -1.0, "solid": false, "pattern": "ladder",
		"color": Color(0.7, 0.52, 0.28), "bg": false},
	{"id": "concrete", "char": "K", "hp": 140.0, "solid": true, "pattern": "concrete",
		"color": Color(0.52, 0.53, 0.55), "bg": true},
]

static var _by_char := {}


static func index_of_char(c: String) -> int:
	if _by_char.is_empty():
		for i in LIST.size():
			_by_char[LIST[i]["char"]] = i
	return _by_char.get(c, -1)


static func get_mat(i: int) -> Dictionary:
	return LIST[i]
