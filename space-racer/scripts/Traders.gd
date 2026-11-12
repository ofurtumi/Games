extends Node3D

# Friendly traders flying between outposts. Slow down next to one and it
# stops to deal: material swaps, a refuel, and one part at a discount. They
# steer around planets on the way and take a breather at each outpost, where
# they restock: three new swaps at new rates and a different part.

const Parts = preload("res://scripts/Parts.gd")
const ShipBuilder = preload("res://scripts/ShipBuilder.gd")
const MeshKit = preload("res://scripts/MeshKit.gd")

const SPEED = 15.0
const NAMES = ["HOLLIS", "PIM", "MARGO"]
# Swaps a trader might offer: give / get at the usual rate. Each restock
# picks three and nudges what they ask by up to a quarter either way.
const SWAP_POOL = [
	[{"rock": 12}, {"metal": 3}],
	[{"rock": 20}, {"crystal": 2}],
	[{"metal": 6}, {"crystal": 2}],
	[{"metal": 14}, {"core": 1}],
	[{"crystal": 4}, {"core": 1}],
	[{"metal": 3}, {"rock": 14}],
	[{"crystal": 2}, {"metal": 7}],
	[{"core": 1}, {"crystal": 5}],
]
const DEALS = 3

var mining
var traders = []   # {name, pos, vel, to, wait, node, beacon, part, swaps, trading}
var rng = RandomNumberGenerator.new()

func setup(m) -> void:
	mining = m
	rng.seed = 77
	for i in NAMES.size():
		var lo = Parts.presets()[[0, 3, 2][i]].duplicate(true)
		lo.paint = {"primary": Color(0.9, 0.9, 0.85), "secondary": Color(0.2, 0.55, 0.95), "pattern": "twin"}
		var node = Node3D.new()
		var model = ShipBuilder.build(lo, Parts.stats(lo))
		model.get_meta("rig").shield.visible = false
		node.add_child(model)
		var beacon = MeshKit.part(node, MeshKit.sphere(0.3, 6, 3), MeshKit.mat(Color(0.3, 0.7, 1.0), 2.0), Vector3(0, 1.4, 0), Vector3.ZERO, Vector3.ONE, false)
		add_child(node)
		var start = berth(i % mining.outposts.size(), i)
		var t = {"name": NAMES[i], "pos": start, "vel": Vector2.ZERO, "to": (i + 1) % mining.outposts.size(), "wait": rng.randf() * 4.0,
			"node": node, "model": model, "beacon": beacon, "part": "", "swaps": [], "trading": false}
		restock(t)
		traders.append(t)

# New stock: three swaps from the pool at today's rates, and a part (never
# the one it just had).
func restock(t: Dictionary) -> void:
	var pool = range(SWAP_POOL.size())
	var swaps = []
	for k in DEALS:
		var pick = pool.pop_at(rng.randi() % pool.size())
		var give = {}
		var sw = SWAP_POOL[pick]
		for m in sw[0]:
			give[m] = maxi(1, roundi(sw[0][m] * rng.randf_range(0.75, 1.25)))
		swaps.append([give, sw[1].duplicate()])
	t.swaps = swaps
	var ids = Parts.PARTS.keys().filter(func(id): return not Parts.PARTS[id].get("locked", false) and id != t.part)
	t.part = ids[rng.randi() % ids.size()]

func step(delta: float) -> void:
	for t in traders:
		if t.trading:
			t.vel = t.vel.lerp(Vector2.ZERO, minf(1.0, 4.0 * delta))
		elif t.wait > 0.0:
			t.wait -= delta
			t.vel = t.vel.lerp(Vector2.ZERO, minf(1.0, 2.0 * delta))
		else:
			var goal = berth(t.to, NAMES.find(t.name))
			var want = (goal - t.pos).normalized() * SPEED
			# Keep clear of planets on the way.
			for pl in mining.planets:
				var away = t.pos - pl.centre
				var gap = away.length() - pl.def.radius
				if gap < 40.0:
					want += away.normalized() * SPEED * (1.0 - gap / 40.0) * 1.5
			t.vel = t.vel.lerp(want.limit_length(SPEED), minf(1.0, 1.5 * delta))
			if t.pos.distance_to(goal) < 6.0:
				t.wait = 6.0
				t.to = (t.to + 1 + randi() % 2) % mining.outposts.size()
				restock(t)
		t.pos += t.vel * delta
		var f = t.vel.normalized() if t.vel.length() > 0.5 else Vector2(0, 1)
		var f3 = Vector3(f.x, f.y, 0.0)
		var up = Vector3(0, 0, 1)
		t.model.transform = Transform3D(Basis(up.cross(f3), up, f3), Vector3.ZERO)
		t.node.position = Vector3(t.pos.x, t.pos.y, 0.2)
		t.beacon.visible = fmod(Time.get_ticks_msec() * 0.001, 1.2) < 0.6

# Where a trader parks at an outpost: off to one side of the pad, clear of
# ships launching and docking.
func berth(outpost: int, who: int) -> Vector2:
	return mining.outposts[outpost].pad + Vector2(16.0 if who % 2 == 0 else -16.0, 5.0)

func near(p: Vector2, r: float):
	for t in traders:
		if t.pos.distance_to(p) < r:
			return t
	return null

# The deals menu. Paid from the hold, then the bank; goods go to the bank.
func open_deals(t: Dictionary) -> void:
	t.trading = true
	var main = mining.main
	var rows = []
	for sw in t.swaps:
		var give = sw[0]
		var take = sw[1]
		rows.append({"label": "Swap  " + mining._price_text(give), "value": "> " + mining._price_text(take),
			"action": func(): _swap(t, give, take)})
	var fuel_price = {"credits": 15}
	rows.append({"label": "Refuel", "value": mining._price_text(fuel_price), "action": func():
		if mining._can_pay(fuel_price):
			mining._pay(fuel_price)
			mining.miner.fuel = mining.miner.stats.fuel
			preload("res://scripts/Sfx.gd").play("coins")})
	var part_price = {"credits": int(Parts.credit_price(t.part).credits * 0.75)}
	rows.append({"label": Parts.PARTS[t.part].name, "value": "%d owned   %s" % [main.owned().get(t.part, 0), mining._price_text(part_price)], "part": t.part,
		"action": func(): _buy(t, part_price)})
	rows.append({"label": "Leave", "action": func(): close(t)})
	main.menu.show_menu("TRADER  " + t.name, rows, func(): close(t), main.menu.title == "TRADER  " + t.name)
	main.menu.wallet = mining.wallet

func _swap(t: Dictionary, give: Dictionary, take: Dictionary) -> void:
	if not mining._can_pay(give):
		mining.main.notify("NOT ENOUGH", Color(1.0, 0.3, 0.3))
		return
	mining._pay(give)
	for k in take:
		mining.main.inventory[k] = mining.main.inventory.get(k, 0) + take[k]
	preload("res://scripts/Sfx.gd").play("coins")
	open_deals(t)

func _buy(t: Dictionary, price: Dictionary) -> void:
	if not mining._can_pay(price):
		mining.main.notify("NOT ENOUGH", Color(1.0, 0.3, 0.3))
		return
	mining._pay(price)
	var o = mining.main.owned()
	o[t.part] = o.get(t.part, 0) + 1
	preload("res://scripts/Sfx.gd").play("coins")
	open_deals(t)

func close(t: Dictionary) -> void:
	t.trading = false
	t.wait = 2.0
	mining.main.menu.hide_menu()
	mining.trader_cool = 3.0
