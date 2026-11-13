class_name Scenarios
extends RefCounted
## Scripted mechanic tests: `godot --headless --fixed-fps 60 -- --scenario NAME`
## Each scenario: map, spawn cell(s) per fighter, input timeline(s), and a check.
## Prints "[scenario] NAME PASS/FAIL ..." and quits.

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const RIGHT := Vector2i(1, 0)
const LEFT := Vector2i(-1, 0)

static var ALL := {
	"ladder_up": {"map": "warehouse", "spawn": [Vector2i(8, 30)], "time": 3.0,
		"input": [[0.3, {}], [2.5, {"move": UP}]],
		"expect": "cell_y", "value": 23},
	"roof_hatch": {"map": "rooftops", "spawn": [Vector2i(5, 21)], "time": 4.0,
		"input": [[0.3, {}], [3.7, {"move": UP}]],
		"expect": "cell_y", "value": 12},
	"bot_roof": {"map": "rooftops", "spawn": [Vector2i(5, 21), Vector2i(10, 12)], "time": 8.0, "bot": true,
		"input": [], "input2": [],
		"expect": "near_target"},
	"bot_cross": {"map": "warehouse", "spawn": [Vector2i(4, 30), Vector2i(55, 30)], "time": 14.0, "bot": true,
		"input": [], "input2": [],
		"expect": "near_target"},
	"hatch_down": {"map": "rooftops", "spawn": [Vector2i(24, 22)], "time": 3.0,
		"input": [[0.3, {}], [2.7, {"move": DOWN}]],
		"expect": "cell_y", "value": 30},
	"bot_corner": {"map": "rooftops", "spawn": [Vector2i(41, 11), Vector2i(10, 30)], "offset": Vector2(3.5, 0), "time": 6.0, "bot": true,
		"input": [], "input2": [],
		"expect": "near_target"},
	"dt_drop": {"map": "downtown", "spawn": [Vector2i(49, 39)], "time": 1.5,
		"input": [[0.3, {}], [0.1, {"move": DOWN, "jump": true}], [1.1, {}]],
		"expect": "cell_y", "value": 45},
	"ledge_grab": {"map": "factory", "spawn": [Vector2i(12, 65)], "time": 2.2,
		"input": [[0.2, {}], [0.3, {"move": RIGHT, "jump": true}], [0.5, {"move": RIGHT}], [0.1, {}], [1.1, {"move": UP}]],
		"expect": "cell_y", "value": 59},
	"vault": {"map": "downtown", "spawn": [Vector2i(107, 51)], "time": 1.2,
		"input": [[1.2, {"move": RIGHT}]],
		"expect": "min_x", "value": 111},
	"ladder_down": {"map": "warehouse", "spawn": [Vector2i(8, 23)], "time": 3.0,
		"input": [[0.3, {}], [2.7, {"move": DOWN}]],
		"expect": "cell_y", "value": 30},
	"platform_drop": {"map": "warehouse", "spawn": [Vector2i(12, 23)], "time": 1.5,
		"input": [[0.3, {}], [0.3, {"move": DOWN, "jump": true}]],
		"expect": "cell_y", "value": 30},
	"jump_height": {"map": "warehouse", "spawn": [Vector2i(40, 30)], "time": 1.2,
		"input": [[0.3, {}], [0.5, {"jump": true}]],
		"expect": "min_y_rise", "value": 30.0},
	"dive_tackle": {"map": "warehouse", "spawn": [Vector2i(38, 30), Vector2i(50, 30)], "time": 1.6,
		"input": [[0.45, {"move": RIGHT, "sprint": true}], [0.1, {"move": RIGHT, "sprint": true, "jump": true}], [0.9, {}]],
		"input2": [],
		"expect": "victim_state", "value": "DOWN"},
	"disarm": {"map": "warehouse", "spawn": [Vector2i(40, 30), Vector2i(41, 30)], "time": 1.0, "give2": "pistol",
		"input": [[0.3, {}], [0.1, {"attack": true}], [0.6, {}]],
		"input2": [[1.0, {"aim": true, "move": LEFT}]],
		"expect": "victim_unarmed"},
	"shoot_wall": {"map": "warehouse", "spawn": [Vector2i(4, 30)], "time": 3.0, "give": "assault",
		"input": [[0.2, {}], [2.8, {"aim": true, "move": DOWN, "attack": true}]],
		"expect": "tiles_destroyed", "value": 1},
	"slide_tackle": {"map": "warehouse", "spawn": [Vector2i(37, 30), Vector2i(49, 30)], "time": 1.4,
		"input": [[0.4, {"move": RIGHT, "sprint": true}], [0.6, {"move": Vector2i(1, 1), "sprint": true}], [0.4, {}]],
		"input2": [],
		"expect": "victim_state", "value": "DOWN"},
	"aim_sweep": {"map": "warehouse", "spawn": [Vector2i(40, 30)], "time": 1.0, "give": "pistol",
		"input": [[0.2, {}], [0.5, {"aim": true, "move": UP}], [0.5, {"aim": true, "move": LEFT}]],
		"expect": "aim_up_left"},
	"punch_glass": {"map": "rooftops", "spawn": [Vector2i(4, 21)], "time": 1.5,
		"input": [[0.2, {}], [0.05, {"move": LEFT}], [0.1, {"attack": true}], [0.1, {}], [0.1, {"attack": true}], [0.1, {}], [0.1, {"attack": true}]],
		"expect": "tiles_destroyed", "value": 1},
}


static func run(name: String) -> void:
	var sc: Dictionary = ALL[name]
	var parts := []
	var spawns: Array = sc["spawn"]
	for i in spawns.size():
		var steps: Array = sc["input"] if i == 0 else sc.get("input2", [])
		var src: InputSource = BotSource.new(1, 0.7) if i == 0 and sc.get("bot", false) else ScriptedSource.new(steps)
		parts.append({"source": src, "name": "T%d" % (i + 1), "color": Game.COLORS[i]})
	Game.participants = parts
	for j in Game.maps.size():
		if Game.maps[j]["name"] == sc["map"]:
			Game.map_index = j
	Game.goto_match()
	var a: Arena = Game.current
	await a.get_tree().process_frame
	for i in spawns.size():
		var f: Fighter = a.fighters[i]
		f.global_position = a.terrain.cell_bottom(spawns[i]) + (sc.get("offset", Vector2.ZERO) if i == 0 else Vector2.ZERO)
		f.velocity = Vector2.ZERO
		f.facing = 1 if i == 0 else -1
	for k in [["give", 0], ["give2", 1]]:
		if sc.has(k[0]):
			a.fighters[k[1]].weapon = WeaponState.new(Items.get_def(sc[k[0]]))
	# Strip pickups so nothing interferes.
	for p in a.pickups():
		p.queue_free()
	a.spawners.clear()
	var start_y: float = a.fighters[0].global_position.y
	var min_y := start_y
	var tiles0: int = Game.stats.get("tiles_destroyed", 0)
	var t := 0.0
	while t < float(sc["time"]):
		await a.get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		min_y = minf(min_y, a.fighters[0].global_position.y)
	var f0: Fighter = a.fighters[0]
	var cell := Nav.feet_cell(a.terrain, f0.global_position)
	var ok := false
	var info := ""
	match String(sc["expect"]):
		"cell_y":
			ok = cell.y == int(sc["value"])
			info = "cell=%s state=%s" % [cell, Fighter.S.keys()[f0.state]]
		"min_y_rise":
			ok = start_y - min_y >= float(sc["value"])
			info = "rise=%.1fpx" % (start_y - min_y)
		"victim_state":
			var v: Fighter = a.fighters[1]
			ok = Fighter.S.keys()[v.state] == sc["value"] or v.hp < 100.0
			info = "victim state=%s hp=%.0f" % [Fighter.S.keys()[v.state], v.hp]
		"min_x":
			ok = cell.x >= int(sc["value"])
			info = "cell=%s" % cell
		"near_target":
			var d: float = f0.global_position.distance_to(a.fighters[1].global_position)
			ok = d < 24.0 or a.fighters[1].hp < 100.0
			info = "dist=%.0f victim_hp=%.0f" % [d, a.fighters[1].hp]
		"victim_unarmed":
			ok = a.fighters[1].weapon == null
			info = "victim weapon=%s" % (a.fighters[1].weapon.def.id if a.fighters[1].weapon else "none")
		"aim_up_left":
			ok = f0.aiming and f0.facing == -1 and f0.aim_dir.y < -0.6
			info = "aim_dir=%s" % f0.aim_dir
		"tiles_destroyed":
			var n: int = Game.stats.get("tiles_destroyed", 0) - tiles0
			ok = n >= int(sc["value"])
			info = "destroyed=%d" % n
	print("[scenario] %s %s %s" % [name, "PASS" if ok else "FAIL", info])
	Game.scenario_done()
