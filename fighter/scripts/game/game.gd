extends Node
## Autoload: scene flow, participants, scores, maps, and command-line test hooks.
##
## User args (after `--`):
##   --quick              KB1 + 3 bots, straight into a match
##   --bots N             all-bot match with N bots (great for testing)
##   --map NAME           pick map by file name (without .json)
##   --quit-after SECS    quit after SECS of game time (headless tests)
##   --screenshot PATH    save a screenshot just before quitting
##   --scenario NAME|all  run scripted mechanic tests (see scenarios.gd)
##   --trace              print bot positions/paths every 3s

const MAP_DIRS := ["res://data/maps", "user://maps"]
const COLORS := [
	Color(0.92, 0.26, 0.24), Color(0.27, 0.52, 0.95), Color(0.32, 0.82, 0.35), Color(0.97, 0.8, 0.22),
	Color(0.7, 0.36, 0.9), Color(0.98, 0.55, 0.18), Color(0.3, 0.85, 0.85), Color(0.95, 0.45, 0.7),
]

var root: Node
var participants: Array = [] # {source, name, color}
var scores := {}
var maps: Array = [] # {name, path, data}
var map_index := 0
var args := {}
var game_time := 0.0
var current: Node
var scenario_queue: Array = []
var stats := {} # debug counters, printed by headless test runs


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Items.load_all()
	scan_maps()
	_parse_args()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := a[i].trim_prefix("--")
		if i + 1 < a.size() and not a[i + 1].begins_with("--"):
			args[k] = a[i + 1]
			i += 2
		else:
			args[k] = true
			i += 1
	if args.has("map"):
		for j in maps.size():
			if maps[j]["name"] == args["map"]:
				map_index = j


func scan_maps() -> void:
	maps.clear()
	for dir in MAP_DIRS:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		var files := da.get_files()
		files.sort()
		for f in files:
			if not f.ends_with(".json"):
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + f))
			if data is Dictionary and data.has("tiles"):
				maps.append({"name": f.get_basename(), "path": dir + "/" + f, "data": data})
			else:
				push_error("Bad map file: %s/%s" % [dir, f])


func boot(main: Node) -> void:
	root = main
	if args.has("scenario"):
		var n := String(args["scenario"])
		scenario_queue = Scenarios.ALL.keys() if n == "all" else n.split(",")
		scenario_done()
	elif args.has("bots"):
		var n := int(args["bots"])
		participants.clear()
		for i in maxi(n, 2):
			add_bot()
		goto_match()
	elif args.has("quick"):
		start_single(3, 0.65)
	else:
		goto_menu()


func add_human(src: InputSource) -> void:
	var idx := participants.size()
	participants.append({"source": src, "name": "P%d" % (idx + 1), "color": _free_color()})


func add_bot(skill := 0.65) -> void:
	var n := 1
	for p in participants:
		if p["source"].is_bot:
			n += 1
	participants.append({"source": BotSource.new(n, skill), "name": "BOT%d" % n, "color": _free_color()})


## You on WASD+HJKL against bots.
func start_single(bot_count: int, skill: float) -> void:
	participants.clear()
	add_human(KeyboardSource.new(0))
	participants[0]["name"] = "YOU"
	for i in bot_count:
		add_bot(skill)
	goto_match()


func _free_color() -> Color:
	for c in COLORS:
		var used := false
		for p in participants:
			if p["color"] == c:
				used = true
		if not used:
			return c
	return Color(randf(), randf(), randf())


func renumber() -> void:
	var h := 0
	for p in participants:
		if not p["source"].is_bot:
			h += 1
			p["name"] = "P%d" % h


func stat(key: String, n := 1) -> void:
	stats[key] = stats.get(key, 0) + n


func add_score(idx: int) -> void:
	scores[idx] = scores.get(idx, 0) + 1


func score_of(idx: int) -> int:
	return scores.get(idx, 0)


## Runs the next queued scenario, or quits when none are left.
func scenario_done() -> void:
	if scenario_queue.is_empty():
		get_tree().quit()
		return
	Scenarios.run(scenario_queue.pop_front())


func _swap(n: Node) -> void:
	if current:
		current.queue_free()
	current = n
	root.add_child(n)


func goto_menu() -> void:
	var m := Node2D.new()
	m.set_script(load("res://scripts/game/menu.gd"))
	_swap(m)


func goto_lobby() -> void:
	var l := Node2D.new()
	l.set_script(load("res://scripts/game/lobby.gd"))
	_swap(l)


func goto_match() -> void:
	scores.clear()
	Sfx.music(not args.has("scenario") and not args.has("mute-music"))
	var a := Arena.new()
	a.setup(participants, maps[map_index]["data"] if not maps.is_empty() else {})
	_swap(a)


func _physics_process(dt: float) -> void:
	game_time += dt
	if args.has("quit-after") and game_time >= float(args["quit-after"]):
		args.erase("quit-after")
		_finish()


func _finish() -> void:
	if args.has("screenshot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(args["screenshot"]))
	if current is Arena:
		var a: Arena = current
		print("[test] rounds=%d time=%.1f scores=%s pickups=%d tiles=%d" % [a.round_num, game_time, scores, a.pickups().size(), a.terrain.mats.size()])
		var keys := stats.keys()
		keys.sort()
		for k in keys:
			print("[stat] %s = %s" % [k, stats[k]])
	get_tree().quit()
