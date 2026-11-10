extends Node3D

const GameScript = preload("res://scripts/Game.gd")
const HudScript = preload("res://scripts/Hud.gd")

# The apartment model has no ceiling; a spider needs one to swing from.
@export var add_ceiling = true
# The model only ships with the kitchen lamp, so light the other rooms too.
@export var add_room_lights = true
# Photo floor textures are shiny and grainy, which the outline shader turns
# into black-and-white noise at spider height. Make them matte and smooth.
@export var soften_floors = true
# Floor textures are shrunk to this size; smaller = smoother.
@export var floor_texture_size = 128
# 1 keeps the texture's own contrast, 0 flattens it to a single colour.
@export var floor_contrast = 0.3
# The model's three lamp lights import as full-strength directional lights
# that stack on every floor in the apartment and wash it out to white.
@export var model_light_energy = 0.3

const CEILING_Y = 4.94
const ROOM_LIGHTS = [
	Vector3(0.0, 4.3, -4.5),   # living room
	Vector3(-7.0, 4.3, -4.0),  # bedroom
	Vector3(2.6, 4.3, -10.0),  # kitchen
	Vector3(-1.9, 4.2, -9.0),  # bathroom
	Vector3(6.5, 4.3, -6.5),   # entrance
]

# Called when the node enters the scene tree for the first time.
func _ready():
	if add_ceiling:
		_build_ceiling()
	if add_room_lights:
		_build_lights()
	for light in $"ibud-game".find_children("*", "DirectionalLight3D", true, false):
		light.light_energy = model_light_energy
	if soften_floors:
		_soften_floors($"ibud-game", {})
	var hud = HudScript.new()
	hud.name = "Hud"
	add_child(hud)
	var game = GameScript.new()
	game.name = "Game"
	add_child(game)
	hud.setup(game)
	game.setup($Player, hud)

func _build_ceiling():
	var size = Vector3(19.6, 0.2, 15.8)
	var body = StaticBody3D.new()
	body.name = "Ceiling"
	body.position = Vector3(-0.75, CEILING_Y + size.y * 0.5, -7.2)
	var shape = BoxShape3D.new()
	shape.size = size
	var col = CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh = BoxMesh.new()
	mesh.size = size
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = load("res://assets/materials/Ceiling_White.tres")
	body.add_child(mi)
	add_child(body)

func _build_lights():
	for pos in ROOM_LIGHTS:
		var light = OmniLight3D.new()
		light.position = pos
		light.omni_range = 9.0
		light.light_energy = 1.2
		light.light_color = Color(1.0, 0.93, 0.82)
		light.shadow_enabled = false
		add_child(light)

func _soften_floors(node: Node, done: Dictionary):
	if node is MeshInstance3D and node.name.begins_with("Floor"):
		for i in node.mesh.get_surface_count():
			var m = node.get_active_material(i)
			if not (m is BaseMaterial3D) or done.has(m):
				continue
			done[m] = true
			m.roughness = 1.0
			m.metallic = 0.0
			m.metallic_specular = 0.0
			m.roughness_texture = null
			m.normal_enabled = false
			if m.albedo_texture != null:
				var img = m.albedo_texture.get_image()
				if img.is_compressed():
					img.decompress()
				img.resize(floor_texture_size, floor_texture_size, Image.INTERPOLATE_LANCZOS)
				var avg_img = img.duplicate()
				avg_img.resize(1, 1, Image.INTERPOLATE_LANCZOS)
				var avg = avg_img.get_pixel(0, 0)
				for y in img.get_height():
					for x in img.get_width():
						img.set_pixel(x, y, avg.lerp(img.get_pixel(x, y), floor_contrast))
				img.generate_mipmaps()
				m.albedo_texture = ImageTexture.create_from_image(img)
	for c in node.get_children():
		_soften_floors(c, done)
