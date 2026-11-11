extends Node3D

# The mining mode: a small system of round planets seen from the side. Each
# planet is a Terrain grid (crust, mantle, deep layer, core) turned to face
# the camera. Dig down for better ore; the deeper you go the hotter it gets.
# Each planet has its own pull and its own trouble:
#   Cinder - home; lava pockets in the mantle
#   Rime   - big, weak gravity, cold (less heat), crystal-rich, gas pockets
#   Moss   - small, heavy gravity, riddled with gas pockets, hot
# Cargo only counts once you dock at the station above Cinder, which also
# refuels and repairs. Fuel depots out in the system refill fuel and rockets
# and patch you up, but don't take cargo. Wreck the ship and the tow home
# costs you the cargo. The camera pulls back the longer you keep moving
# (mouse wheel sets the base zoom).

const Parts = preload("res://scripts/Parts.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const Ui = preload("res://scripts/Ui.gd")
const TerrainScript = preload("res://scripts/Terrain.gd")
const MinerScript = preload("res://scripts/Miner.gd")

const PLANETS = [
	{"name": "Cinder", "palette": 0, "pos": Vector2(0, 0), "radius": 34, "gravity": 7.0, "gas": 0.02, "lava": true, "heat": 1.0},
	{"name": "Rime", "palette": 1, "pos": Vector2(160, 50), "radius": 44, "gravity": 4.5, "gas": 0.06, "lava": false, "heat": 0.5},
	{"name": "Moss", "palette": 2, "pos": Vector2(-150, 95), "radius": 26, "gravity": 11.0, "gas": 0.14, "lava": false, "heat": 1.5},
]
const LAYERS = [[0.28, "CRUST"], [0.55, "MANTLE"], [0.84, "DEEP"], [2.0, "CORE"]]
const MAT_COLORS = {"rock": Color(0.7, 0.6, 0.5), "metal": Color(1.0, 0.6, 0.25), "crystal": Color(0.5, 0.9, 1.0), "core": Color(0.95, 0.3, 0.9)}

var main
var planets = []
var miner
var cam: Camera3D
var light: DirectionalLight3D
var station: Node3D
var station_pad = Vector2.ZERO
var hud: Control
var cargo = {}
var docked = false
var lava_contact = false
var _undock_cd = 0.0
var depots = []          # Vector2 pad positions
var _depot_used = -1     # last depot serviced; resets once you fly off
var zoom = 30.0
var travel = 0.0
const DEPOTS = [Vector2(160, 50 + 44 + 12), Vector2(-150, 95 + 26 + 12), Vector2(80, 70)]
var pickups = []
var _env_saved = {}
var _pickup_mesh: Mesh
var _pickup_mats = {}

# ---------------------------------------------------------------- planets

class Planet:
	var def: Dictionary
	var node: Node3D
	var terrain
	var centre: Vector2
	func local(p: Vector2) -> Vector3:
		return node.to_local(Vector3(p.x, p.y, 0.0))
	func cell_world(c: Vector2i) -> Vector2:
		var g = node.to_global(terrain.cell_center(c))
		return Vector2(g.x, g.y)
	func depth_frac(p: Vector2) -> float:
		return (def.radius - p.distance_to(centre)) / float(def.radius)

func setup(m) -> void:
	main = m
	_pickup_mesh = MeshKit.box(Vector3.ONE * 0.32)
	for i in PLANETS.size():
		var def = PLANETS[i]
		var pl = Planet.new()
		pl.def = def
		pl.centre = def.pos
		pl.node = Node3D.new()
		pl.node.position = Vector3(def.pos.x, def.pos.y, 0.0)
		pl.node.rotation_degrees.x = 90.0
		add_child(pl.node)
		var t = TerrainScript.new()
		t.w = def.radius * 2 + 8
		t.h = def.radius * 2 + 8
		pl.node.add_child(t)
		t.generate_planet(9000 + i * 77, def)
		t.rebuild()
		t.cell_destroyed.connect(_on_cell_destroyed.bind(pl))
		pl.terrain = t
		planets.append(pl)
	_build_station()
	for d in DEPOTS:
		_build_depot(d)
	_build_stars()
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 25, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	add_child(light)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 600.0
	add_child(cam)
	miner = MinerScript.new()
	miner.mining = self
	add_child(miner)
	miner.equip(main.loadout)
	var layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_enter_env()
	_dock()

func _enter_env() -> void:
	var env = main.env
	_env_saved = {"fog": env.fog_enabled, "bg": env.background_color, "amb": env.ambient_light_color, "amb_e": env.ambient_light_energy}
	env.fog_enabled = false
	env.background_color = Color(0.01, 0.012, 0.02)
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.ambient_light_energy = 0.5
	main.sun.visible = false
	main.fx.floor_enabled = false
	cam.current = true

func leave() -> void:
	var env = main.env
	env.fog_enabled = _env_saved.fog
	env.background_color = _env_saved.bg
	env.ambient_light_color = _env_saved.amb
	env.ambient_light_energy = _env_saved.amb_e
	main.sun.visible = true
	main.fx.floor_enabled = true
	for pk in pickups:
		pk.node.queue_free()
	queue_free()

func _build_station() -> void:
	var home = PLANETS[0]
	station_pad = home.pos + Vector2(0, home.radius + 14.0)
	station = Node3D.new()
	station.position = Vector3(station_pad.x, station_pad.y, 0.0)
	add_child(station)
	var steel = MeshKit.mat(Color(0.55, 0.57, 0.62), 0.0, 0.4, 0.7)
	var dark = MeshKit.mat(Color(0.15, 0.16, 0.18), 0.0, 0.5, 0.5)
	var lamp = MeshKit.mat(Color(1.0, 0.75, 0.3), 1.0)
	MeshKit.part(station, MeshKit.box(Vector3(7.0, 0.5, 2.5)), steel, Vector3(0, -0.4, 0))
	MeshKit.part(station, MeshKit.box(Vector3(2.5, 3.0, 2.0)), dark, Vector3(-4.6, 0.8, -0.5))
	MeshKit.part(station, MeshKit.box(Vector3(2.0, 1.4, 1.8)), dark, Vector3(4.4, 0.2, -0.5))
	MeshKit.part(station, MeshKit.cyl(0.08, 0.08, 4.0, 6), steel, Vector3(-4.6, 4.2, -0.5))
	for x in [-3.2, -1.6, 0.0, 1.6, 3.2]:
		MeshKit.part(station, MeshKit.box(Vector3(0.3, 0.08, 0.3)), lamp, Vector3(x, -0.12, 1.1), Vector3.ZERO, Vector3.ONE, false)
	for x in [-2.5, 2.5]:
		MeshKit.part(station, MeshKit.box(Vector3(0.25, 14.0, 0.25)), steel, Vector3(x, -7.6, -1.0))

func _build_depot(at: Vector2) -> void:
	depots.append(at)
	var n = Node3D.new()
	n.position = Vector3(at.x, at.y, 0.0)
	add_child(n)
	var steel = MeshKit.mat(Color(0.5, 0.52, 0.56), 0.0, 0.4, 0.7)
	MeshKit.part(n, MeshKit.box(Vector3(4.0, 0.4, 2.0)), steel, Vector3(0, -0.4, 0))
	MeshKit.part(n, MeshKit.sphere(0.9, 10, 6), MeshKit.mat(Color(0.85, 0.55, 0.15), 0.0, 0.4, 0.3), Vector3(-2.6, 0.4, -0.4))
	MeshKit.part(n, MeshKit.cyl(0.06, 0.06, 2.4, 6), steel, Vector3(2.0, 0.8, -0.4))
	MeshKit.part(n, MeshKit.sphere(0.15, 6, 3), MeshKit.mat(Color(0.3, 1.0, 0.4), 1.5), Vector3(2.0, 2.1, -0.4), Vector3.ZERO, Vector3.ONE, false)

func _service_depots() -> void:
	for i in depots.size():
		var d = miner.pos.distance_to(depots[i] + Vector2(0, 1.0))
		if i == _depot_used:
			if d > 8.0:
				_depot_used = -1
			continue
		if d < 3.5 and miner.vel.length() < 6.0:
			_depot_used = i
			miner.fuel = miner.stats.fuel
			miner.ammo = miner.stats.ammo
			miner.shield = miner.stats.shield
			miner.hull = 100.0
			miner.exposed = false
			main.notify("DEPOT  -  REFUELLED", Color(0.3, 1.0, 0.4))

func _unhandled_input(event):
	if main.mode != "mining" or main.menu_open():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(14.0, zoom - 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(110.0, zoom + 3.0)

func _build_stars() -> void:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshKit.box(Vector3.ONE)
	mm.instance_count = 900
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	for i in mm.instance_count:
		var s = rng.randf_range(0.25, 0.7)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(rng.randf_range(-600, 600), rng.randf_range(-400, 500), rng.randf_range(-260, -120))))
		var b = rng.randf_range(0.4, 1.0)
		mm.set_instance_color(i, Color(b, b, b * rng.randf_range(0.9, 1.1)))
	var node = MultiMeshInstance3D.new()
	node.multimesh = mm
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

# ---------------------------------------------------------------- queries

func nearest_planet(p: Vector2) -> Planet:
	var best = planets[0]
	var bd = INF
	for pl in planets:
		var d = p.distance_to(pl.centre) - pl.def.radius
		if d < bd:
			bd = d
			best = pl
	return best

func planets_near(p: Vector2, margin: float) -> Array:
	var out = []
	for pl in planets:
		if p.distance_to(pl.centre) < pl.def.radius + 4.0 + margin:
			out.append(pl)
	return out

# Pull toward the nearest planet, fading out at three radii.
func gravity_at(p: Vector2) -> Vector2:
	var g = Vector2.ZERO
	for pl in planets:
		var to = pl.centre - p
		var d = to.length()
		var reach = pl.def.radius * 3.0
		if d < reach and d > 0.5:
			g += to / d * pl.def.gravity * clampf((reach - d) / (reach - pl.def.radius), 0.0, 1.0)
	return g

# ---------------------------------------------------------------- loop

func _process(delta):
	delta = minf(delta, 1.0 / 30.0)
	if main.menu_open() or main.mode != "mining":
		hud.queue_redraw()
		return
	if docked:
		miner.pos = station_pad + Vector2(0, 1.0)
		miner.vel = Vector2.ZERO
		miner.heading = PI * 0.5
		miner.step(0.0, false)
	else:
		miner.step(delta, true)
		# Docking: slow, over the pad, and not straight after launching.
		_undock_cd -= delta
		if _undock_cd <= 0.0 and miner.pos.distance_to(station_pad + Vector2(0, 1.0)) < 3.0 and miner.vel.length() < 6.0:
			_dock()
	_update_pickups(delta)
	if not docked:
		_service_depots()
	var speed = miner.vel.length()
	# Keep moving and the view opens up; stop and it settles back in.
	if speed > 4.0:
		travel += speed * delta
	else:
		travel = maxf(0.0, travel - 60.0 * delta)
	var target = Vector3(miner.pos.x, miner.pos.y, 0.0) + Vector3(miner.vel.x, miner.vel.y, 0.0) * 0.25
	var dist = zoom + minf(travel * 0.12, 70.0) + speed * 0.3
	cam.position = cam.position.lerp(target + Vector3(0, -4.0, dist), minf(1.0, 3.0 * delta))
	cam.look_at(cam.position + Vector3(0, 0.12, -1.0), Vector3.UP)
	hud.queue_redraw()

func _dock() -> void:
	docked = true
	var gained = []
	for k in cargo:
		if cargo[k] > 0:
			main.inventory[k] = main.inventory.get(k, 0) + cargo[k]
			gained.append("+%d %s" % [cargo[k], k])
	cargo.clear()
	miner.refill()
	miner.pos = station_pad + Vector2(0, 1.0)
	miner.vel = Vector2.ZERO
	cam.position = Vector3(miner.pos.x, miner.pos.y - 4.0, 30.0)
	if gained.size() > 0:
		main.notify("UNLOADED  " + "  ".join(gained), Color(0.5, 0.9, 1.0))
	main.save_game()
	open_menu()

func launch() -> void:
	docked = false
	_undock_cd = 2.5
	main.menu.hide_menu()
	miner.vel = Vector2(0, 7.0)
	miner.pos = station_pad + Vector2(0, 2.0)

func wrecked() -> void:
	cargo.clear()
	main.notify("WRECKED  -  CARGO LOST", Color(1.0, 0.3, 0.3))
	main.fx.burst(Vector3(miner.pos.x, miner.pos.y, 1.0), Color(1.0, 0.5, 0.15), 40, 12.0, 1.2, 0.2, 0.8, 0.0)
	_dock()

func open_menu() -> void:
	if docked:
		main.menu.show_menu("STATION", [
			{"label": "Launch", "action": launch},
			{"label": "Garage", "action": func(): main.menu.hide_menu(); main.open_garage()},
			{"label": "Race", "action": func(): main.menu.hide_menu(); main.leave_mining()},
			{"label": "Controls", "action": func(): main.open_controls(open_menu)},
			{"label": "Quit", "action": func(): main.save_game(); get_tree().quit()},
		], launch)
	else:
		main.menu.show_menu("EXPEDITION", [
			{"label": "Resume", "action": main.menu.hide_menu},
			{"label": "Tow home", "value": "lose cargo", "action": func(): main.menu.hide_menu(); cargo.clear(); _dock()},
			{"label": "Controls", "action": func(): main.open_controls(open_menu)},
			{"label": "Quit", "action": func(): main.save_game(); get_tree().quit()},
		], main.menu.hide_menu)

func garage_closed() -> void:
	miner.equip(main.loadout)
	cam.current = true
	open_menu()

# ---------------------------------------------------------------- ore & gas

func _on_cell_destroyed(p: Vector3, k: int, pl) -> void:
	var t = pl.terrain
	var g = pl.node.to_global(p)
	var w = Vector2(g.x, g.y)
	main.fx.burst(Vector3(w.x, w.y, 1.2), t.kind_color(k), 5, 5.0, 0.0, 0.22, 0.6, 0.0)
	if k == t.GAS:
		main.fx.burst(Vector3(w.x, w.y, 1.2), Color(0.8, 0.9, 0.3), 30, 10.0, 1.2, 0.2, 0.6, 0.0)
		main.fx.burst(Vector3(w.x, w.y, 1.2), Color(1.0, 0.55, 0.15), 20, 7.0, 1.2, 0.16, 0.5, 0.0)
		var d = miner.pos.distance_to(w)
		if d < 4.5:
			miner.take_hit(30.0 * (1.0 - d / 4.5) + 10.0)
			miner.vel += (miner.pos - w).normalized() * 9.0
		t.blast(p, 2.5, 2)
		return
	var mat = t.MATERIAL.get(k, "")
	if mat == "":
		return
	if mat == "rock":
		if _cargo_used() < miner.stats.cargo:
			cargo["rock"] = cargo.get("rock", 0) + 1
		return
	if not _pickup_mats.has(mat):
		_pickup_mats[mat] = MeshKit.mat(MAT_COLORS[mat], 0.6)
	for n in 1 + randi() % 2:
		var node = MeshKit.part(self, _pickup_mesh, _pickup_mats[mat], Vector3(w.x, w.y, 0.8), Vector3.ZERO, Vector3.ONE, false)
		pickups.append({"node": node, "pos": w, "vel": Vector2(randf_range(-3, 3), randf_range(-3, 3)), "mat": mat, "age": 0.0})

func _cargo_used() -> int:
	var n = 0
	for k in cargo:
		n += cargo[k]
	return n

func _update_pickups(delta: float) -> void:
	var keep = []
	for pk in pickups:
		pk.age += delta
		var to = miner.pos - pk.pos
		var d = to.length()
		var room = _cargo_used() < miner.stats.cargo
		if room and d < miner.stats.magnet and pk.age > 0.3:
			pk.vel = pk.vel.lerp(to.normalized() * (12.0 + 30.0 / maxf(d, 0.5)), minf(1.0, 6.0 * delta))
		else:
			pk.vel *= 1.0 - 2.0 * delta
		pk.pos += pk.vel * delta
		pk.node.position = Vector3(pk.pos.x, pk.pos.y, 0.8)
		pk.node.rotation = Vector3(pk.age * 2.0, pk.age * 3.0, 0)
		if room and d < miner.stats.radius + 0.5:
			cargo[pk.mat] = cargo.get(pk.mat, 0) + 1
			pk.node.queue_free()
			continue
		if pk.age > 60.0:
			pk.node.queue_free()
			continue
		keep.append(pk)
	pickups = keep

# ---------------------------------------------------------------- HUD

func _gauge(r: Rect2, frac: float, color: Color, segs: int = 16) -> void:
	var gap = 3.0
	var sw = (r.size.x - gap * (segs - 1)) / segs
	var lit = int(round(clampf(frac, 0.0, 1.0) * segs))
	for i in segs:
		Ui.segment(hud, Rect2(r.position.x + i * (sw + gap), r.position.y, sw, r.size.y), color if i < lit else Color(1, 1, 1, 0.1), 3.0)

func _draw_hud() -> void:
	if main.mode != "mining" or main.grid_garage.visible:
		return
	var vp = hud.size
	var panel = Color(0.03, 0.035, 0.045, 0.78)
	var st = miner.stats
	# Where you are.
	var pl = nearest_planet(miner.pos)
	var depth_m = pl.def.radius - miner.pos.distance_to(pl.centre)
	var layer = "SPACE"
	if depth_m > -1.0:
		layer = "SURFACE"
		for l in LAYERS:
			if depth_m / pl.def.radius < l[0]:
				layer = l[1]
				break
	Ui.segment(hud, Rect2(-20, 18, 360, 78), panel)
	Ui.text(hud, Vector2(28, 46), pl.def.name.to_upper(), 18, Ui.DIM, true)
	Ui.text(hud, Vector2(28, 82), layer, 32, Color.WHITE, true)
	if depth_m > 0.0:
		Ui.text(hud, Vector2(210, 82), "%dm" % int(depth_m), 22, Color(0.95, 0.85, 0.4), true)
	if miner.heat > 0.0:
		var a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		Ui.segment(hud, Rect2(-20, 104, 200, 30), Color(0.8, 0.15, 0.05, a))
		Ui.text(hud, Vector2(28, 126), "HEAT", 18, Color.WHITE, true)
	# Gauges.
	var bx = vp.x - 360
	var by = vp.y - 170
	Ui.segment(hud, Rect2(bx, by, 380, 152), panel)
	Ui.text(hud, Vector2(bx + 30, by + 56), str(int(miner.vel.length() * 3.6)), 46, Color.WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	Ui.text(hud, Vector2(bx + 238, by + 56), "km/h", 16, Ui.DIM)
	var sh_col = Color(0.45, 0.6, 1.0) if not miner.exposed else Color(1.0, 0.25, 0.25)
	_gauge(Rect2(bx + 44, by + 72, 290, 12), miner.shield / st.shield if not miner.exposed else miner.hull / 100.0, sh_col)
	_gauge(Rect2(bx + 38, by + 92, 290, 12), miner.fuel / st.fuel, Color(1.0, 0.6, 0.2) if miner.fuel > st.fuel * 0.2 else Color(1.0, 0.2, 0.1))
	_gauge(Rect2(bx + 32, by + 112, 290, 12), miner.boost / (100.0 * st.boost), Color(0.3, 0.85, 1.0))
	for i in st.ammo:
		Ui.segment(hud, Rect2(bx + 330 - (i + 1) * 14, by + 14, 9, 9), Color(0.45, 1.0, 0.45) if i < miner.ammo else Color(1, 1, 1, 0.15), 2.0)
	Ui.text(hud, Vector2(bx + 8, by + 84), "S", 12, Ui.DIM, true)
	Ui.text(hud, Vector2(bx + 2, by + 104), "F", 12, Ui.DIM, true)
	# Cargo.
	var used = _cargo_used()
	var cx = vp.x - 40
	Ui.text(hud, Vector2(vp.x - 240, 72), "%d / %d" % [used, st.cargo], 16, Color(1, 0.4, 0.3) if used >= st.cargo else Ui.DIM, true, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	for m in ["core", "crystal", "metal", "rock"]:
		var s = str(cargo.get(m, 0))
		var w = Ui.font(true).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		cx -= w + 34
		draw_rect_on(Rect2(cx, 30, 12, 12), MAT_COLORS[m])
		Ui.text(hud, Vector2(cx + 18, 43), s, 20, Color.WHITE, true)
	# Off-screen markers: planets and the station.
	var marks = [[station_pad, "STATION", Color(1.0, 0.75, 0.3)]]
	for d in depots:
		marks.append([d, "DEPOT", Color(0.3, 1.0, 0.4)])
	for p2 in planets:
		if miner.pos.distance_to(p2.centre) > p2.def.radius * 1.6:
			marks.append([p2.centre, p2.def.name.to_upper(), p2.terrain.planet.rock.lightened(0.3)])
	for mk in marks:
		var sp = cam.unproject_position(Vector3(mk[0].x, mk[0].y, 0.0))
		var inside = Rect2(Vector2.ZERO, vp).grow(-40).has_point(sp)
		if inside and not cam.is_position_behind(Vector3(mk[0].x, mk[0].y, 0.0)):
			continue
		var c = vp * 0.5
		var d = (sp - c)
		var k = minf((vp.x * 0.5 - 50) / maxf(absf(d.x), 1.0), (vp.y * 0.5 - 50) / maxf(absf(d.y), 1.0))
		var at = c + d * minf(k, 1.0)
		var dir = d.normalized()
		var n = Vector2(-dir.y, dir.x)
		hud.draw_colored_polygon(PackedVector2Array([at + dir * 12, at - dir * 6 + n * 9, at - dir * 6 - n * 9]), mk[2])
		var dist = int(miner.pos.distance_to(mk[0]))
		Ui.text(hud, at - dir * 30 + Vector2(-60, 5), "%s %dm" % [mk[1], dist], 13, mk[2], true, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# Banners.
	var ny = vp.y * 0.24
	for msg in main.messages:
		var a = clampf(msg.t / 0.3, 0.0, 1.0)
		var bw = 560.0
		var r = Rect2((vp.x - bw) * 0.5, ny, bw, 42)
		Ui.segment(hud, r, Color(0.03, 0.035, 0.045, 0.8 * a))
		Ui.segment(hud, Rect2(r.position.x, r.end.y - 3, bw, 3), Color(msg.color, a), 0.0)
		Ui.text(hud, Vector2(r.position.x, r.position.y + 29), msg.text, 22, Color(1, 1, 1, a), true, HORIZONTAL_ALIGNMENT_CENTER, bw)
		ny += 50

func draw_rect_on(r: Rect2, c: Color) -> void:
	hud.draw_rect(r, c)
