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
#
# Exploration sites (see _build_sites): crashed ships to salvage (materials,
# fuel, rockets, sometimes a blueprint), fuel canisters, derelict hulls to tow
# to an outpost (unlocks that frame), and a black market that sells
# blueprints. Hover slowly next to a site to work it. Sites only get a marker
# once you've been near them; buried ones are found by digging.

const Parts = preload("res://scripts/Parts.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const Ui = preload("res://scripts/Ui.gd")
const TerrainScript = preload("res://scripts/Terrain.gd")
const MinerScript = preload("res://scripts/Miner.gd")
const ShipBuilder = preload("res://scripts/ShipBuilder.gd")
const Sfx = preload("res://scripts/Sfx.gd")
const Contracts = preload("res://scripts/Contracts.gd")
const DronesScript = preload("res://scripts/Drones.gd")
const TradersScript = preload("res://scripts/Traders.gd")

# Each planet has an outpost above its north pole run by one mechanic, who
# sells program cards and parts for materials.
const PLANETS = [
	{"name": "Cinder", "palette": 0, "pos": Vector2(0, 0), "radius": 110, "gravity": 7.0, "gas": 0.02, "lava": true, "heat": 1.0,
		"mech": "grind", "offers": [{"name": "Excavate", "price": {"metal": 10, "rock": 20}}, {"name": "Cluster", "price": {"metal": 12, "crystal": 4}}]},
	{"name": "Rime", "palette": 1, "pos": Vector2(760, 260), "radius": 160, "gravity": 4.5, "gas": 0.06, "lava": false, "heat": 0.5,
		"mech": "vex", "offers": [{"name": "Phasing", "price": {"crystal": 10}}, {"name": "Orbit", "price": {"crystal": 6, "metal": 8}}]},
	{"name": "Moss", "palette": 2, "pos": Vector2(-640, 400), "radius": 80, "gravity": 11.0, "gas": 0.14, "lava": false, "heat": 1.5,
		"mech": "lode", "offers": [{"name": "Gravity well", "price": {"crystal": 8, "metal": 6}}, {"name": "Tractor beam", "price": {"crystal": 12, "metal": 10}}]},
	{"name": "Magma", "palette": 3, "pos": Vector2(220, -720), "radius": 130, "gravity": 8.0, "gas": 0.03, "lava": true, "lava_crust": true, "heat": 2.2,
		"mech": "arc", "offers": [{"name": "Quench", "price": {"metal": 10, "core": 1}}, {"name": "Homing", "price": {"crystal": 8}}]},
]
const LAYERS = [[0.28, "CRUST"], [0.55, "MANTLE"], [0.84, "DEEP"], [2.0, "CORE"]]
# What each layer holds and the drill tier it takes (the HUD shows it under
# the layer name): rock everywhere, metal veins in the crust, crystal in the
# mantle, core ore in the deep layer, and solid core at the centre.
const LAYER_FINDS = {"SURFACE": [["rock", "metal"], 1], "CRUST": [["rock", "metal"], 1], "MANTLE": [["rock", "crystal"], 2],
	"DEEP": [["rock", "core"], 3], "CORE": [["core"], 4]}
const DRILL_NAMES = ["", "Pilot drill", "Auger", "Maw", "Phase drill"]
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
# Fuel-only stops out between the planets.
const DEPOTS = [Vector2(380, 130), Vector2(-320, 200), Vector2(110, -360), Vector2(-900, -420)]
# Nine Fingers' stock.
const MARKET = [
	{"name": "Phase drill", "price": {"core": 6, "crystal": 10}},
	{"name": "Overdrive core", "price": {"core": 4, "metal": 20}},
	{"name": "Blink drive", "price": {"core": 5, "crystal": 8}},
	{"name": "Fuel scoop", "price": {"metal": 15, "crystal": 5}},
]
const SPACE_TOP = 70.0     # speed cap away from planets
const AIR_TOP = 32.0       # near a planet
var outposts = []          # {pad, planet}
var at_outpost = 0
const SITE_COLORS = {"wreck": Color(0.95, 0.6, 0.35), "hull": Color(0.92, 0.92, 0.95), "cache": Color(0.25, 0.95, 0.75), "market": Color(0.75, 0.35, 1.0)}

var sites = []           # {type, pos, vel, node, found, done, data}
var tow = null           # the hull on the cable
var rope: MeshInstance3D
var salvage = 0.0
var salvage_site = null
var _market_cool = false
var _dead_left = 0.0
var drones
var marker_rects = []   # where the marker labels went last frame (tests)
var hud_panels = []
var marker_arrows = []
var traders
var trader_cool = 0.0
var _trade_t = 0.0
var _own_wreck = null
const REPAIR_BILL = {"metal": 8, "rock": 10}
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
		t.cell_destroyed.connect(_on_cell_destroyed.bind(pl))
		pl.terrain = t
		planets.append(pl)
	_build_sites()
	for pl in planets:
		pl.terrain.rebuild()
	for i in PLANETS.size():
		_build_outpost(i)
	station_pad = outposts[0].pad
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
	cam.far = 5000.0
	add_child(cam)
	miner = MinerScript.new()
	miner.mining = self
	add_child(miner)
	miner.equip(main.loadout)
	drones = DronesScript.new()
	add_child(drones)
	drones.setup(self)
	traders = TradersScript.new()
	add_child(traders)
	traders.setup(self)
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

func _build_outpost(pi: int) -> void:
	var def = PLANETS[pi]
	var pad = def.pos + Vector2(0, def.radius + 16.0)
	outposts.append({"pad": pad, "planet": pi})
	var n = Node3D.new()
	n.position = Vector3(pad.x, pad.y, 0.0)
	add_child(n)
	var steel = MeshKit.mat(Color(0.55, 0.57, 0.62), 0.0, 0.4, 0.7)
	var dark = MeshKit.mat(Color(0.15, 0.16, 0.18), 0.0, 0.5, 0.5)
	var lamp = MeshKit.mat(Parts.MECHANICS[def.mech].accent, 1.0)
	MeshKit.part(n, MeshKit.box(Vector3(9.0, 0.5, 2.5)), steel, Vector3(0, -0.4, 0))
	MeshKit.part(n, MeshKit.box(Vector3(2.8, 3.4, 2.0)), dark, Vector3(-5.6, 1.0, -0.5))
	MeshKit.part(n, MeshKit.box(Vector3(2.4, 1.6, 1.8)), dark, Vector3(5.4, 0.3, -0.5))
	MeshKit.part(n, MeshKit.box(Vector3(2.6, 0.3, 0.3)), lamp, Vector3(-5.6, 2.8, 0.55), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.part(n, MeshKit.cyl(0.08, 0.08, 4.0, 6), steel, Vector3(-5.6, 4.6, -0.5))
	for x in [-3.6, -1.8, 0.0, 1.8, 3.6]:
		MeshKit.part(n, MeshKit.box(Vector3(0.3, 0.08, 0.3)), lamp, Vector3(x, -0.12, 1.1), Vector3.ZERO, Vector3.ONE, false)
	for x in [-3.0, 3.0]:
		MeshKit.part(n, MeshKit.box(Vector3(0.3, 18.0, 0.3)), steel, Vector3(x, -9.6, -1.0))

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
			miner.weapons.refill()
			miner.shield = miner.stats.shield
			miner.hull = 100.0
			miner.exposed = false
			main.notify("DEPOT  -  REFUELLED", Color(0.3, 1.0, 0.4))
			Sfx.play("gate")

func _unhandled_input(event):
	if main.mode != "mining" or main.menu_open():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(14.0, zoom - 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(260.0, zoom + 5.0)

func _build_stars() -> void:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshKit.box(Vector3.ONE)
	mm.instance_count = 2200
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	for i in mm.instance_count:
		var s = rng.randf_range(0.8, 2.6)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(rng.randf_range(-3000, 3000), rng.randf_range(-2400, 2400), rng.randf_range(-900, -400))))
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
	# Stream rock around the ship (even while a menu is up).
	var view = cam.position.z * 0.9 + 40.0
	for pl in planets:
		pl.terrain.focus = pl.local(miner.pos)
		pl.terrain.view_r = view
	if main.menu_open() or main.mode != "mining":
		hud.queue_redraw()
		return
	if _dead_left > 0.0:
		_dead_left -= delta / maxf(Engine.time_scale, 0.05)
		if _dead_left <= 0.0:
			miner.model.visible = true
			_dock()
			var bill = []
			for k in REPAIR_BILL:
				var paid = mini(main.inventory.get(k, 0), REPAIR_BILL[k])
				main.inventory[k] = main.inventory.get(k, 0) - paid
				if paid > 0:
					bill.append("-%d %s" % [paid, k])
			if bill.size() > 0:
				main.notify("REPAIRS  " + "  ".join(bill), Color(1.0, 0.4, 0.3))
		cam.position = cam.position + main.shake_offset()
		hud.queue_redraw()
		return
	if docked:
		miner.pos = outposts[at_outpost].pad + Vector2(0, 1.0)
		miner.vel = Vector2.ZERO
		miner.heading = PI * 0.5
		miner.step(0.0, false)
	else:
		miner.step(delta, true)
		# Docking: slow, over a pad, and not straight after launching.
		_undock_cd -= delta
		if _undock_cd <= 0.0 and miner.vel.length() < 6.0:
			for i in outposts.size():
				if miner.pos.distance_to(outposts[i].pad + Vector2(0, 1.0)) < 3.0:
					_dock(i)
					break
	_update_pickups(delta)
	traders.step(delta)
	if not docked:
		_service_depots()
		_update_sites(delta)
		drones.step(delta)
		_update_trading(delta)
		var pl = nearest_planet(miner.pos)
		var frac = pl.depth_frac(miner.pos)
		if frac > 0.25:
			main.contract_event("depth", {"planet": planets.find(pl), "frac": frac})
	var speed = miner.vel.length()
	# Keep moving and the view opens up; stop and it settles back in.
	if speed > 4.0:
		travel += speed * delta
	else:
		travel = maxf(0.0, travel - 60.0 * delta)
	var target = Vector3(miner.pos.x, miner.pos.y, 0.0) + Vector3(miner.vel.x, miner.vel.y, 0.0) * 0.25
	var dist = zoom + minf(travel * 0.15, 220.0) + speed * 0.3
	cam.position = cam.position.lerp(target + Vector3(0, -4.0, dist), minf(1.0, 3.0 * delta)) + main.shake_offset()
	cam.look_at(cam.position + Vector3(0, 0.12, -1.0), Vector3.UP)
	hud.queue_redraw()

func _dock(i: int = -1) -> void:
	if i >= 0:
		at_outpost = i
	station_pad = outposts[at_outpost].pad
	docked = true
	main.contract_event("dock", {"planet": outposts[at_outpost].planet, "cargo": cargo})
	var gained = []
	for k in cargo:
		if cargo[k] > 0:
			main.inventory[k] = main.inventory.get(k, 0) + cargo[k]
			gained.append("+%d %s" % [cargo[k], k])
	cargo.clear()
	miner.refill()
	miner.pos = station_pad + Vector2(0, 1.0)
	miner.vel = Vector2.ZERO
	miner.weapons.refill()
	cam.position = Vector3(miner.pos.x, miner.pos.y - 4.0, 30.0)
	if gained.size() > 0:
		main.notify("UNLOADED  " + "  ".join(gained), Color(0.5, 0.9, 1.0))
		Sfx.play("coins")
	Sfx.play("gate")
	main.save_game()
	open_menu()

func launch() -> void:
	docked = false
	_undock_cd = 2.5
	trader_cool = 3.0
	main.menu.hide_menu()
	miner.vel = Vector2(0, 7.0)
	miner.pos = station_pad + Vector2(0, 2.0)

# Wrecked: the ship comes apart, the hold stays in your wreck where you died
# (go back for it; die again first and that wreck is gone), the tow home
# takes a few seconds and the repairs come out of the bank.
func wrecked() -> void:
	if _dead_left > 0.0:
		return
	main.shatter(miner.model, Vector3(0, 0, 1), Vector3(miner.vel.x, miner.vel.y, 0.0), 0.0)
	miner.model.visible = false
	for tr in miner.trails:
		tr.clear_points()
	if _own_wreck != null:
		sites.erase(_own_wreck)
		_own_wreck.node.queue_free()
		_own_wreck = null
	var held = 0
	for k in cargo:
		held += cargo[k]
	if held > 0:
		_site(miner.pos, "wreck", {"loot": cargo.duplicate(), "own": true})
		_own_wreck = sites[-1]
		_own_wreck.found = true
	cargo.clear()
	if tow != null:
		tow = null
	main.overlay.show_death("WRECKED", "your cargo is in the wreck  ·  towing you home" if held > 0 else "towing you home")
	_dead_left = 2.6

func open_menu() -> void:
	if docked:
		var def = PLANETS[outposts[at_outpost].planet]
		var mech = Parts.MECHANICS[def.mech].name
		main.menu.show_menu(def.name.to_upper() + " OUTPOST", [
			{"label": "Launch", "action": launch},
			{"label": "Contracts", "value": func(): return "%d / %d active" % [main.contracts().size(), Contracts.MAX_ACTIVE], "action": open_contracts},
			{"label": "Shop", "value": "parts", "action": func(): open_shop(def.mech, def.name.to_upper() + " SHOP")},
			{"label": "Blueprints", "value": mech, "action": func(): open_market(def.offers, mech.to_upper())},
			{"label": "Garage", "action": func(): main.menu.hide_menu(); main.open_garage()},
			{"label": "Race here", "value": def.name, "action": func(): main.menu.hide_menu(); main.race_on(def.palette)},
			{"label": "Controls", "action": func(): main.open_controls(open_menu)},
			{"label": "Sound", "action": func(): main.open_sound(open_menu)},
			{"label": "Quit", "action": func(): main.save_game(); get_tree().quit()},
		], launch)
	else:
		main.menu.show_menu("EXPEDITION", [
			{"label": "Resume", "action": main.menu.hide_menu},
			{"label": "Tow home", "value": "lose cargo", "action": func(): main.menu.hide_menu(); cargo.clear(); _dock()},
			{"label": "Controls", "action": func(): main.open_controls(open_menu)},
			{"label": "Sound", "action": func(): main.open_sound(open_menu)},
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
	if k == t.FUEL:
		miner.fuel = minf(miner.stats.fuel, miner.fuel + 12.0)
		main.fx.burst(Vector3(w.x, w.y, 1.2), Color(0.25, 0.95, 0.75), 16, 6.0, 1.2, 0.16, 0.5, 0.0)
		return
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
		else:
			hold_full()
		return
	if not main.save_data.get("ore_hint", false):
		# The first ore you break: say how it's collected.
		main.save_data.ore_hint = true
		hint("ore", "%s  -  FLY CLOSE TO PICK IT UP" % mat.to_upper(), MAT_COLORS[mat], 0.0)
	if not _pickup_mats.has(mat):
		_pickup_mats[mat] = MeshKit.mat(MAT_COLORS[mat], 0.6)
	for n in 1 + randi() % 2:
		var node = MeshKit.part(self, _pickup_mesh, _pickup_mats[mat], Vector3(w.x, w.y, 0.8), Vector3.ZERO, Vector3.ONE, false)
		pickups.append({"node": node, "pos": w, "vel": Vector2(randf_range(-3, 3), randf_range(-3, 3)), "mat": mat, "age": 0.0})

# Banners for the two silent stops: a drill too weak for what it's on, and a
# full hold. Each one at most every few seconds.
var _hint_cd = {}

func hint(key: String, text: String, color: Color, every: float = 4.0) -> void:
	var now = Time.get_ticks_msec() * 0.001
	if now < _hint_cd.get(key, 0.0):
		return
	_hint_cd[key] = now + every
	main.notify(text, color, key)

func drill_blocked(kind: int) -> void:
	var t = TerrainScript
	if kind == t.BEDROCK or kind == t.LAVA or kind == t.EMPTY:
		return
	var need = t.KINDS[kind].hardness
	if need < DRILL_NAMES.size():
		hint("drill", "TOO HARD  -  NEEDS %s" % DRILL_NAMES[need].to_upper(), Color(1.0, 0.45, 0.3))

func hold_full() -> void:
	hint("hold", "HOLD FULL  -  DOCK TO UNLOAD", Color(1.0, 0.45, 0.3))

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
		elif not room and d < miner.stats.magnet:
			hold_full()
			pk.vel *= 1.0 - 2.0 * delta
		else:
			pk.vel *= 1.0 - 2.0 * delta
		pk.pos += pk.vel * delta
		pk.node.position = Vector3(pk.pos.x, pk.pos.y, 0.8)
		pk.node.rotation = Vector3(pk.age * 2.0, pk.age * 3.0, 0)
		if room and d < miner.stats.radius + 0.5:
			cargo[pk.mat] = cargo.get(pk.mat, 0) + 1
			main.contract_event("mined", {"mat": pk.mat, "n": 1})
			Sfx.play("pickup", -4.0)
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
	var hy = 104
	if LAYER_FINDS.has(layer):
		# What's down here and whether your drill can cut it.
		var f = LAYER_FINDS[layer]
		var ok = st.drill_tier >= f[1]
		Ui.segment(hud, Rect2(-20, hy, 360, 30), panel)
		var fx = 28.0
		for m in f[0]:
			draw_rect_on(Rect2(fx, hy + 9, 12, 12), MAT_COLORS[m])
			Ui.text(hud, Vector2(fx + 18, hy + 21), m.to_upper(), 14, Color.WHITE, true)
			fx += 30.0 + Ui.font(true).get_string_size(m.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		Ui.text(hud, Vector2(28, hy + 21), ("" if ok else "NEED ") + DRILL_NAMES[f[1]].to_upper(), 14,
			Ui.DIM if ok else Color(1.0, 0.35, 0.3), true, HORIZONTAL_ALIGNMENT_RIGHT, 290)
		hy += 38
	if miner.heat > 0.0:
		var a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		Ui.segment(hud, Rect2(-20, hy, 200, 30), Color(0.8, 0.15, 0.05, a))
		Ui.text(hud, Vector2(28, hy + 22), "HEAT", 18, Color.WHITE, true)
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
		Ui.segment(hud, Rect2(bx + 330 - (i + 1) * 14, by + 14, 9, 9), Color(0.45, 1.0, 0.45) if i < miner.weapons.ammo else Color(1, 1, 1, 0.15), 2.0)
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
	# Active contracts, top right under the hold.
	var cy = 96.0
	for c in main.contracts():
		var line = Contracts.title(c)
		var prog = Contracts.progress(c)
		Ui.segment(hud, Rect2(vp.x - 380, cy, 360, 28), Color(0.03, 0.035, 0.045, 0.78), 6.0)
		Ui.segment(hud, Rect2(vp.x - 380, cy, 4, 28), Color(0.95, 0.85, 0.3), 0.0)
		Ui.text(hud, Vector2(vp.x - 366, cy + 20), line.to_upper(), 14, Color.WHITE, true)
		if prog != "":
			Ui.text(hud, Vector2(vp.x - 366, cy + 20), prog, 14, Color(0.95, 0.85, 0.3), true, HORIZONTAL_ALIGNMENT_RIGHT, 336)
		cy += 32
	# Salvage progress around the ship, and what's on the cable.
	if salvage_site != null:
		var sp2 = cam.unproject_position(Vector3(miner.pos.x, miner.pos.y, 0.0))
		var need = 0.4 if salvage_site.type == "cache" else 1.4
		hud.draw_arc(sp2, 46, -PI * 0.5, -PI * 0.5 + TAU * clampf(salvage / need, 0.0, 1.0), 32, SITE_COLORS[salvage_site.type], 6.0)
		Ui.text(hud, sp2 + Vector2(-100, -58), _site_label(salvage_site), 16, SITE_COLORS[salvage_site.type], true, HORIZONTAL_ALIGNMENT_CENTER, 200)
	if tow != null:
		Ui.segment(hud, Rect2(vp.x * 0.5 - 150, 18, 300, 34), Color(0.03, 0.035, 0.045, 0.8))
		Ui.text(hud, Vector2(vp.x * 0.5 - 150, 42), "TOWING  " + _site_label(tow), 17, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, 300)
	# Off-screen markers: planets and the station.
	var marks = []
	for o in outposts:
		marks.append([o.pad, "OUTPOST", Parts.MECHANICS[PLANETS[o.planet].mech].accent])
	for d in depots:
		marks.append([d, "DEPOT", Color(0.3, 1.0, 0.4)])
	for s in sites:
		if s.found and not s.done and s != tow:
			marks.append([s.pos, _site_label(s), SITE_COLORS[s.type]])
	for t in traders.traders:
		if t.pos.distance_to(miner.pos) < 500.0:
			marks.append([t.pos, "TRADER", Color(0.6, 0.85, 1.0)])
	for d in drones.drones:
		if d.hp > 0.0 and d.state == "chase":
			marks.append([d.pos, "!", Color(1.0, 0.25, 0.2)])
	for p2 in planets:
		if miner.pos.distance_to(p2.centre) > p2.def.radius * 1.6:
			marks.append([p2.centre, p2.def.name.to_upper(), p2.terrain.planet.rock.lightened(0.3)])
	# Keep them off the panels and off each other: closest first; a label that
	# would overlap slides along the edge, and if there's no room the arrow
	# goes alone.
	var panels = [Rect2(0, 0, 370, 140), Rect2(vp.x - 400, 0, 400, cy + 10), Rect2(vp.x - 380, vp.y - 185, 380, 185)]
	marks.sort_custom(func(x, y): return miner.pos.distance_squared_to(x[0]) < miner.pos.distance_squared_to(y[0]))
	var placed = []
	marker_rects = []
	hud_panels = panels
	# Arrows first, then labels round them.
	var arrows = []
	for mk in marks:
		var sp = cam.unproject_position(Vector3(mk[0].x, mk[0].y, 0.0))
		var inside = Rect2(Vector2.ZERO, vp).grow(-40).has_point(sp)
		if inside and not cam.is_position_behind(Vector3(mk[0].x, mk[0].y, 0.0)):
			continue
		var c = vp * 0.5
		var d = (sp - c)
		var k = minf((vp.x * 0.5 - 50) / maxf(absf(d.x), 1.0), (vp.y * 0.5 - 50) / maxf(absf(d.y), 1.0))
		var at = marker_spot(c + d * minf(k, 1.0), vp, panels)
		var dir = (sp - at).normalized()
		var n = Vector2(-dir.y, dir.x)
		hud.draw_colored_polygon(PackedVector2Array([at + dir * 12, at - dir * 6 + n * 9, at - dir * 6 - n * 9]), mk[2])
		arrows.append([mk, at])
		placed.append(Rect2(at - Vector2(12, 12), Vector2(24, 24)))
	var blocked = placed.duplicate()
	for ar in arrows:
		var mk = ar[0]
		var at = ar[1]
		# On the top/bottom edges the label goes under/over the arrow and slides
		# sideways; on the side edges it goes inward and slides up and down.
		var top_bottom = at.y < 140.0 or at.y > vp.y - 140.0
		var base: Vector2
		var along: Vector2
		if top_bottom:
			base = at + Vector2(-60, 16 if at.y < vp.y * 0.5 else -34)
			along = Vector2(126, 0)
		else:
			base = at + Vector2(18 if at.x < vp.x * 0.5 else -138, -9)
			along = Vector2(0, 20)
		var spot = null
		for step in [0, 1, -1, 2, -2, 3, -3]:
			var r = Rect2(base + along * step, Vector2(120, 18))
			if not Rect2(Vector2.ZERO, vp).encloses(r) or panels.any(func(p): return p.intersects(r)) or blocked.any(func(p): return p.intersects(r)):
				continue
			spot = r
			break
		if spot == null:
			continue
		blocked.append(spot)
		marker_rects.append(spot)
		var dist = int(miner.pos.distance_to(mk[0]))
		Ui.text(hud, spot.position + Vector2(0, 14), "%s %dm" % [mk[1], dist], 13, mk[2], true, HORIZONTAL_ALIGNMENT_CENTER, 120)
	marker_arrows = placed
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

# A marker that lands on a HUD panel moves to the nearest side of it that's
# still on screen.
static func marker_spot(at: Vector2, vp: Vector2, panels: Array) -> Vector2:
	for p in panels:
		if not p.grow(14).has_point(at):
			continue
		var g = p.grow(24)
		var best = at
		var bd = INF
		for q in [Vector2(at.x, g.end.y), Vector2(at.x, g.position.y), Vector2(g.position.x, at.y), Vector2(g.end.x, at.y)]:
			if Rect2(Vector2.ZERO, vp).grow(-20).has_point(q) and q.distance_to(at) < bd:
				bd = q.distance_to(at)
				best = q
		at = best
	return at

func draw_rect_on(r: Rect2, c: Color) -> void:
	hud.draw_rect(r, c)

# ---------------------------------------------------------------- exploration

func _build_sites() -> void:
	var P = planets
	_site_on(P[0], 200.0, 1.0, "wreck", {"blueprint": "Fuel scoop"})
	_site_on(P[0], 300.0, 0.5, "wreck", {"loot": {"crystal": 6, "metal": 4}})
	_site(Vector2(300, -260), "wreck", {})
	_site_on(P[1], 120.0, 1.0, "wreck", {"blueprint": "Tractor beam"})
	_site_on(P[1], 30.0, 0.35, "wreck", {"loot": {"core": 3, "crystal": 4}})
	_site_on(P[2], 250.0, 1.0, "wreck", {"loot": {"metal": 6}})
	_site(Vector2(-420, -500), "wreck", {"blueprint": "Overdrive core"})
	_site(Vector2(1150, -150), "hull", {"frame": "manta"})
	_site_on(P[1], 330.0, 1.0, "hull", {"frame": "needle"})
	_site_on(P[2], 200.0, 0.4, "hull", {"frame": "brick"})
	for c in [Vector2(200, -60), Vector2(450, 60), Vector2(-330, 240), Vector2(800, -150)]:
		_site(c, "cache", {})
	_site(Vector2(-1300, -900), "market", {})
	_site_on(P[3], 200.0, 1.0, "wreck", {"loot": {"core": 2, "metal": 4}})
	_site_on(P[3], 60.0, 0.45, "wreck", {"blueprint": "Homing"})
	_site(Vector2(600, -480), "wreck", {"blueprint": "Orbit"})
	_site_on(P[0], 30.0, 0.3, "wreck", {"blueprint": "Phasing", "loot": {"core": 2}})

# On or in a planet: depth 1.0 sits on the surface in a little crater, less
# than that is buried in a pocket that far out from the centre.
func _site_on(pl, angle_deg: float, depth: float, type: String, data: Dictionary) -> void:
	var dir = Vector2(cos(deg_to_rad(angle_deg)), sin(deg_to_rad(angle_deg)))
	var pos = pl.centre + dir * (pl.def.radius * depth - (0.5 if depth >= 1.0 else 0.0))
	var hole = (4.5 if type == "hull" else 3.0) if depth < 1.0 else 2.6
	var t = pl.terrain
	var c0 = t.world_to_cell(pl.local(pos))
	var r = ceili(hole) + 1
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var c = c0 + Vector2i(di, dj)
			if t.in_bounds(c) and pl.cell_world(c).distance_to(pos) < hole:
				t.set_kind(c, t.EMPTY)
	_site(pos, type, data)

func _site(pos: Vector2, type: String, data: Dictionary) -> void:
	var node = Node3D.new()
	node.position = Vector3(pos.x, pos.y, 0.3)
	add_child(node)
	var rng = RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31 + pos.y * 17)
	match type:
		"wreck", "hull":
			var lo = Parts.random_loadout(rng) if type == "wreck" else {"name": "", "frame": data.frame, "parts": []}
			if data.get("own", false):
				lo = main.loadout.duplicate(true)
			lo.paint = {"primary": Color(0.28, 0.22, 0.18) if type == "wreck" else Color(0.5, 0.36, 0.24), "secondary": Color(0.12, 0.1, 0.1), "pattern": "stripe"}
			var m = ShipBuilder.build(lo, Parts.stats(lo))
			var rig = m.get_meta("rig")
			rig.shield.visible = false
			for f in rig.flames:
				f.visible = false
			var h = rng.randf() * TAU
			var f3 = Vector3(cos(h), sin(h), 0.0)
			var up = Vector3(0, 0, 1)
			m.transform = Transform3D(Basis(up.cross(f3), up, f3).rotated(f3, rng.randf_range(-0.4, 0.4)), Vector3.ZERO)
			node.add_child(m)
		"cache":
			MeshKit.part(node, MeshKit.cyl(0.45, 0.45, 1.3, 8), MeshKit.mat(Color(0.2, 0.22, 0.25), 0.0, 0.4, 0.6), Vector3.ZERO, Vector3(90, 0, 0))
			MeshKit.part(node, MeshKit.cyl(0.47, 0.47, 0.3, 8), MeshKit.mat(SITE_COLORS.cache, 1.0), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
		"market":
			var dark = MeshKit.mat(Color(0.1, 0.09, 0.12), 0.0, 0.5, 0.6)
			var lamp = MeshKit.mat(SITE_COLORS.market, 1.2)
			MeshKit.part(node, MeshKit.box(Vector3(9.0, 0.6, 3.0)), dark, Vector3(0, -0.6, 0))
			MeshKit.part(node, MeshKit.box(Vector3(3.0, 4.0, 2.5)), dark, Vector3(-2.5, 1.4, -0.5))
			MeshKit.part(node, MeshKit.box(Vector3(2.0, 2.5, 2.0)), dark, Vector3(2.8, 0.8, -0.5), Vector3(0, 0, 12))
			for x in [-4.0, -1.0, 1.5, 4.0]:
				MeshKit.part(node, MeshKit.box(Vector3(0.3, 0.1, 0.3)), lamp, Vector3(x, -0.25, 1.4), Vector3.ZERO, Vector3.ONE, false)
			MeshKit.part(node, MeshKit.sphere(0.35, 8, 4), lamp, Vector3(-2.5, 3.8, -0.5), Vector3.ZERO, Vector3.ONE, false)
	sites.append({"type": type, "pos": pos, "vel": Vector2.ZERO, "node": node, "found": false, "done": false, "data": data})

func _site_label(s: Dictionary) -> String:
	match s.type:
		"wreck": return "YOUR WRECK" if s.data.get("own", false) else "WRECK"
		"hull": return Parts.FRAMES[s.data.frame].name.to_upper()
		"cache": return "FUEL"
		"market": return "NINE FINGERS"
	return ""

func _update_sites(delta: float) -> void:
	var near = null
	for s in sites:
		var d = miner.pos.distance_to(s.pos)
		if not s.found and d < 45.0:
			s.found = true
			if s.type in ["wreck", "hull", "market"]:
				main.notify("FOUND  " + _site_label(s), SITE_COLORS[s.type])
		if s.done or s == tow:
			continue
		if s.type == "market" and _market_cool:
			if d > 12.0:
				_market_cool = false
			continue
		var reach = 5.0 if s.type in ["hull", "market"] else 3.2
		if d < reach and miner.vel.length() < 5.0:
			near = s
		if s.type == "wreck" and randf() < 4.0 * delta:
			main.fx.spawn(Vector3(s.pos.x, s.pos.y, 1.0) + Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), 0), Vector3(0, 0, 1.5), Color(0.2, 0.2, 0.2), 0.0, 0.35, 1.2, 0.0)
	if near != salvage_site:
		salvage = 0.0
		salvage_site = near
	if near != null:
		salvage += delta
		if salvage >= (0.4 if near.type == "cache" else 1.4):
			salvage = 0.0
			salvage_site = null
			_work_site(near)
	_update_tow(delta)

func _work_site(s: Dictionary) -> void:
	match s.type:
		"wreck":
			s.done = true
			if s == _own_wreck:
				_own_wreck = null
			var loot = s.data.get("loot", {"metal": 2 + randi() % 5, "crystal": randi() % 3})
			var bits = []
			for k in loot:
				if loot[k] <= 0:
					continue
				cargo[k] = cargo.get(k, 0) + loot[k]
				bits.append("+%d %s" % [loot[k], k])
			miner.fuel = minf(miner.stats.fuel, miner.fuel + miner.stats.fuel * 0.3)
			miner.weapons.refill()
			main.notify("SALVAGED  " + "  ".join(bits), SITE_COLORS.wreck)
			main.contract_event("salvage", {})
			Sfx.play("coins")
			if s.data.has("blueprint"):
				main.unlock(s.data.blueprint)
		"cache":
			s.done = true
			s.node.visible = false
			miner.fuel = miner.stats.fuel
			main.notify("FUEL  +%d" % int(miner.stats.fuel), SITE_COLORS.cache)
		"hull":
			if main.unlocks().has(Parts.FRAMES[s.data.frame].name):
				s.done = true
				return
			tow = s
			main.notify("TOWING  -  BRING IT TO AN OUTPOST", Color.WHITE)
		"market":
			_market_cool = true
			main.menu.show_menu("NINE FINGERS", [
				{"label": "Blueprints", "action": func(): open_market()},
				{"label": "Parts", "action": func(): open_shop("nine", "NINE FINGERS PARTS")},
				{"label": "Leave", "action": main.menu.hide_menu},
			], main.menu.hide_menu)

# The hull hangs off a cable: a distance limit between ship and hull, split
# by their masses, so a heavy hull drags a light ship around. The Tractor beam
# makes hulls feel lighter. Space drops it. Any outpost (the station or a
# depot) takes delivery.
func _update_tow(delta: float) -> void:
	if tow == null:
		if rope != null:
			rope.visible = false
		return
	if Input.is_action_just_pressed("hop"):
		tow = null
		return
	var hm = (5.0 if tow.data.frame == "brick" else 3.0) / miner.stats.tow
	tow.vel += gravity_at(tow.pos) * delta
	tow.vel *= 1.0 - 0.2 * delta
	tow.pos += tow.vel * delta
	var d = tow.pos - miner.pos
	var dist = d.length()
	var L = 5.5
	if dist > L:
		var n = d / dist
		var wm = 1.0 / miner.stats.mass
		var wh = 1.0 / hm
		var sum = wm + wh
		miner.pos += n * (dist - L) * wm / sum
		tow.pos -= n * (dist - L) * wh / sum
		var rel = (tow.vel - miner.vel).dot(n)
		if rel > 0.0:
			miner.vel += n * rel * wm / sum
			tow.vel -= n * rel * wh / sum
		miner.position = Vector3(miner.pos.x, miner.pos.y, 0.0)
	# Rock pushes the hull back out toward the surface.
	for pl in planets_near(tow.pos, 2.0):
		if pl.terrain.is_solid(pl.terrain.world_to_cell(pl.local(tow.pos))):
			var out = (tow.pos - pl.centre).normalized()
			tow.pos += out * 6.0 * delta
			tow.vel = tow.vel.lerp(out * 2.0, minf(1.0, 4.0 * delta))
	tow.node.position = Vector3(tow.pos.x, tow.pos.y, 0.3)
	if rope == null:
		rope = MeshInstance3D.new()
		rope.mesh = MeshKit.box(Vector3(0.08, 0.08, 1.0))
		rope.material_override = MeshKit.mat(Color(0.15, 0.15, 0.17))
		add_child(rope)
	rope.visible = true
	var a = Vector3(miner.pos.x, miner.pos.y, 0.5)
	var b = Vector3(tow.pos.x, tow.pos.y, 0.5)
	if a.distance_to(b) > 0.1:
		rope.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3(0, 0, 1)) * Basis.from_scale(Vector3(1, 1, a.distance_to(b))), (a + b) * 0.5)
	var drop = depots.duplicate()
	for o in outposts:
		drop.append(o.pad)
	for o in drop:
		if tow.pos.distance_to(o) < 10.0:
			main.unlock(Parts.FRAMES[tow.data.frame].name)
			tow.node.queue_free()
			tow.done = true
			tow = null
			main.notify("HULL DELIVERED", Color.WHITE)
			return

func _price_text(price: Dictionary) -> String:
	var bits = []
	for k in price:
		bits.append("%d %s" % [price[k], k])
	return "  ".join(bits)

func _can_pay(price: Dictionary) -> bool:
	for k in price:
		if cargo.get(k, 0) + main.inventory.get(k, 0) < price[k]:
			return false
	return true

# Pays from the hold first, then from what's banked.
func _pay(price: Dictionary) -> void:
	for k in price:
		var from_cargo = mini(cargo.get(k, 0), price[k])
		cargo[k] = cargo.get(k, 0) - from_cargo
		main.inventory[k] = main.inventory.get(k, 0) - (price[k] - from_cargo)

func open_market(offers: Array = MARKET, title: String = "NINE FINGERS") -> void:
	var rows = []
	for offer in offers:
		var o = offer
		rows.append({"label": o.name,
			"value": func(): return "OWNED" if main.unlocks().has(o.name) else _price_text(o.price),
			"action": func(): _buy(o, offers, title)})
	var back = open_menu if docked else main.menu.hide_menu
	rows.append({"label": "Leave", "action": back})
	main.menu.show_menu(title, rows, back, main.menu.title == title)
	main.menu.wallet = wallet

func _buy(o: Dictionary, offers: Array = MARKET, title: String = "NINE FINGERS") -> void:
	if main.unlocks().has(o.name):
		return
	if not _can_pay(o.price):
		main.notify("NOT ENOUGH", Color(1.0, 0.3, 0.3))
		return
	_pay(o.price)
	main.unlock(o.name)
	Sfx.play("coins")
	open_market(offers, title)

# Hooks for the weapons adapter.
func touch_enemies(p: Vector2, r: float) -> bool:
	return drones != null and drones.touch(p, r)

func nearest_enemy(p: Vector2, r: float):
	return drones.nearest(p, r) if drones != null else null

func pull_enemies(p: Vector2, r: float, k: float) -> void:
	if drones != null:
		drones.pull(p, r, k)

func blast_enemies(p: Vector2, r: float) -> void:
	if drones != null:
		drones.blast(p, r)

func solid_at(p: Vector2) -> bool:
	for pl in planets_near(p, 1.0):
		if pl.terrain.is_solid(pl.terrain.world_to_cell(pl.local(p))):
			return true
	return false

func spawn_pickup(w: Vector2, mat: String) -> void:
	if not _pickup_mats.has(mat):
		_pickup_mats[mat] = MeshKit.mat(MAT_COLORS[mat], 0.6)
	var node = MeshKit.part(self, _pickup_mesh, _pickup_mats[mat], Vector3(w.x, w.y, 0.8), Vector3.ZERO, Vector3.ONE, false)
	pickups.append({"node": node, "pos": w, "vel": Vector2(randf_range(-3, 3), randf_range(-3, 3)), "mat": mat, "age": 0.0})

# Pull up slowly beside a trader to deal.
func _update_trading(delta: float) -> void:
	trader_cool -= delta
	var t = traders.near(miner.pos, 6.0)
	if t != null and miner.vel.length() < 4.0 and trader_cool <= 0.0:
		_trade_t += delta
		if _trade_t > 0.6:
			_trade_t = 0.0
			traders.open_deals(t)
	else:
		_trade_t = 0.0

# ---------------------------------------------------------------- parts shop

# Stock parts everywhere, plus this outpost's mechanics. Locked parts need
# their blueprint first. Paid from the hold first, then the bank.
func open_shop(mech: String, title: String) -> void:
	var rows = []
	for id in Parts.shop_stock(mech):
		if Parts.is_locked(Parts.PARTS[id], main.unlocks()):
			continue
		var pid = id
		var pr = Parts.price(pid)
		rows.append({"label": Parts.PARTS[pid].name,
			"value": func(): return "%d owned   %s" % [main.owned().get(pid, 0), _price_text(pr)], "part": pid,
			"action": func(): _buy_part(pid, mech, title)})
	var back = open_menu if docked else main.menu.hide_menu
	rows.append({"label": "Sell parts", "value": func(): return "%d spare" % _spares().values().reduce(func(a, b): return a + b, 0),
		"action": func(): open_sell(mech, title)})
	rows.append({"label": "Leave", "action": back})
	main.menu.show_menu(title, rows, back, main.menu.title == title)
	main.menu.wallet = wallet

# Hold and bank, for the shop menus' wallet panel.
func wallet() -> Dictionary:
	return {"hold": cargo, "bank": main.inventory}

# Parts you own that the current build isn't using.
func _spares() -> Dictionary:
	return main.spare_parts()

# Half the shop price, into the bank.
static func sell_price(id: String) -> Dictionary:
	var out = {}
	var pr = Parts.price(id)
	for k in pr:
		if pr[k] / 2 > 0:
			out[k] = pr[k] / 2
	return out

func open_sell(mech: String, title: String) -> void:
	var rows = []
	var spares = _spares()
	for id in spares:
		var pid = id
		rows.append({"label": Parts.PARTS[pid].name, "value": "%d spare   +%s" % [spares[pid], _price_text(sell_price(pid))], "part": pid,
			"action": func(): _sell_part(pid, mech, title)})
	var back = func(): open_shop(mech, title)
	rows.append({"label": "Back", "action": back})
	main.menu.show_menu("SELL", rows, back, main.menu.title == "SELL")
	main.menu.wallet = wallet

func _sell_part(id: String, mech: String, title: String) -> void:
	if _spares().get(id, 0) <= 0:
		return
	var o = main.owned()
	o[id] -= 1
	if o[id] <= 0:
		o.erase(id)
	var pay = sell_price(id)
	for k in pay:
		main.inventory[k] = main.inventory.get(k, 0) + pay[k]
	main.notify("SOLD  " + Parts.PARTS[id].name.to_upper(), Color.WHITE)
	Sfx.play("coins")
	main.save_game()
	open_sell(mech, title)

func _buy_part(id: String, mech: String, title: String) -> void:
	var pr = Parts.price(id)
	if not _can_pay(pr):
		main.notify("NOT ENOUGH", Color(1.0, 0.3, 0.3))
		return
	_pay(pr)
	var o = main.owned()
	o[id] = o.get(id, 0) + 1
	main.notify("BOUGHT  " + Parts.PARTS[id].name.to_upper(), Color.WHITE)
	Sfx.play("coins")
	main.save_game()
	open_shop(mech, title)

# ---------------------------------------------------------------- contracts

func open_contracts() -> void:
	main.open_board(outposts[at_outpost].planet, open_menu)
