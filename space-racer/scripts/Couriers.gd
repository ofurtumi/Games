extends Node3D

# Parts you've ordered from another outpost, on their way to your station in
# small courier ships. Some never make it: pirates jump them somewhere along
# the route, and what's left is a courier wreck with your parts in it and a
# couple of drones guarding it. Rix lets you know where. Salvage it to get
# the parts back.
#
# Orders live in the save (save_data.couriers), so a courier in flight or a
# wreck waiting for you survives quitting:
#   {part, n, from, to, pos, travelled, intercept, state}
#   state: "flying" | "lost" (a wreck at pos)

const Parts = preload("res://scripts/Parts.gd")
const ShipBuilder = preload("res://scripts/ShipBuilder.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")
const Sfx = preload("res://scripts/Sfx.gd")

const SPEED = 18.0
const INTERCEPT_CHANCE = 0.3
const FEE = 0.25           # on top of the price, at least MIN_FEE
const MIN_FEE = 20

var mining
var ships = {}             # order id -> the courier's node

func setup(m) -> void:
	mining = m
	for o in orders():
		if o.state == "lost":
			_wreck_site(o, false)

func orders() -> Array:
	if not mining.main.save_data.has("couriers"):
		mining.main.save_data.couriers = []
	return mining.main.save_data.couriers

static func fee(id: String) -> int:
	return maxi(MIN_FEE, int(Parts.credit_price(id).credits * FEE))

# A new order: paid for already; the courier sets off from `from`'s pad.
func send(id: String, from: int, to: int) -> Dictionary:
	var start = mining.outposts[from].pad
	var o = {"id": randi(), "part": id, "n": 1, "from": from, "to": to, "pos": start, "travelled": 0.0, "state": "flying",
		"intercept": randf_range(0.35, 0.75) if randf() < INTERCEPT_CHANCE else -1.0}
	orders().append(o)
	mining.main.save_game()
	return o

func _model() -> Node3D:
	var lo = {"name": "", "frame": "needle", "paint": {"primary": Color(0.95, 0.75, 0.15), "secondary": Color(0.1, 0.1, 0.12), "pattern": "nose"},
		"parts": [{"id": "engine_v", "cell": Vector2i(1, 6), "rot": 2}, {"id": "thruster_v", "cell": Vector2i(1, 8), "rot": 0}]}
	var node = Node3D.new()
	var model = ShipBuilder.build(lo, Parts.stats(lo))
	model.get_meta("rig").shield.visible = false
	model.scale = Vector3.ONE * 0.7
	node.add_child(model)
	add_child(node)
	return node

func step(delta: float) -> void:
	var done = []
	for o in orders():
		if o.state != "flying":
			continue
		if not ships.has(o.id):
			ships[o.id] = _model()
		var goal = mining.outposts[o.to].pad + Vector2(0, 1.0)
		var total = mining.outposts[o.from].pad.distance_to(goal)
		var want = (goal - o.pos).normalized() * SPEED
		for pl in mining.planets:
			var away = o.pos - pl.centre
			var gap = away.length() - pl.def.radius
			if gap < 40.0:
				want += away.normalized() * SPEED * (1.0 - gap / 40.0) * 1.5
		var v = want.limit_length(SPEED)
		o.pos += v * delta
		o.travelled += v.length() * delta
		var node = ships[o.id]
		node.position = Vector3(o.pos.x, o.pos.y, 0.2)
		var f = Vector3(v.x, v.y, 0.0).normalized()
		if f.length() > 0.1:
			node.get_child(0).transform.basis = Basis(Vector3(0, 0, 1).cross(f), Vector3(0, 0, 1), f)
		if o.intercept > 0.0 and o.travelled >= o.intercept * total:
			_intercepted(o)
		elif o.pos.distance_to(goal) < 5.0:
			done.append(o)
	for o in done:
		_arrived(o)

func _arrived(o: Dictionary) -> void:
	var main = mining.main
	main.owned()[o.part] = main.owned().get(o.part, 0) + o.n
	main.notify("COURIER  +%d %s" % [o.n, Parts.PARTS[o.part].name.to_upper()], Color(1.0, 0.82, 0.25))
	Sfx.play("coins")
	_drop(o)

func _intercepted(o: Dictionary) -> void:
	o.state = "lost"
	if ships.has(o.id):
		mining.main.fx.burst(Vector3(o.pos.x, o.pos.y, 1.0), Color(1.0, 0.5, 0.15), 40, 12.0, 1.2, 0.2, 0.7, 0.0)
		ships[o.id].queue_free()
		ships.erase(o.id)
	_wreck_site(o, true)
	mining.main.save_game()
	var near = mining.nearest_planet(o.pos)
	var main = mining.main
	if main.terminal != null and not main.terminal.visible:
		main.terminal.show_message(main.CONTACT, [
			"bad news. pirates jumped our courier out past " + near.def.name.to_lower() + ".",
			"",
			"the " + Parts.PARTS[o.part].name.to_lower() + " is still in the wreck, and so are they. it's on your map. go get it.",
		], [{"label": "OK", "action": func(): pass}])
	else:
		main.notify("COURIER INTERCEPTED  -  ON YOUR MAP", Color(1.0, 0.4, 0.3))

# The wreck: a salvage site holding the parts, found already, with pirates.
func _wreck_site(o: Dictionary, fresh: bool) -> void:
	mining._site(o.pos, "wreck", {"parts": {o.part: o.n}, "courier": o, "loot": {}})
	mining.sites[-1].found = true
	if fresh:
		for k in 2:
			mining.drones.spawn(o.pos, 6.0 + k * 4.0)

# A courier wreck salvaged: the parts are yours, the order's closed.
func recovered(o: Dictionary) -> void:
	var main = mining.main
	main.owned()[o.part] = main.owned().get(o.part, 0) + o.n
	main.notify("RECOVERED  %s" % Parts.PARTS[o.part].name.to_upper(), Color(1.0, 0.82, 0.25))
	# The first courier wreck you pick over: its frame's yours (battered).
	if Parts.is_locked(Parts.FRAMES.courier, main.unlocks()):
		main.break_frame("courier")
		main.unlock(Parts.FRAMES.courier.name)
	_drop(o)

func _drop(o: Dictionary) -> void:
	if ships.has(o.id):
		ships[o.id].queue_free()
		ships.erase(o.id)
	for i in orders().size():
		if orders()[i].id == o.id:
			orders().remove_at(i)
			break
	mining.main.save_game()
