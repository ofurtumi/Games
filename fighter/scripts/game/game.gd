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
var next_pid := 0 # stable participant ids (scores, online identity)


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
	elif args.has("server"):
		Net.fill = clampi(int(args.get("fill", 4)), 2, 8)
		if Net.host(int(args.get("port", Net.PORT))) != OK:
			get_tree().quit(1)
			return
		participants.clear()
		fill_bots(Net.fill)
		goto_match(Net.SERVER)
	elif args.has("connect"):
		Net.join(String(args["connect"]), String(args.get("name", "PLAYER")))
		goto_menu()
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
	participants.append({"source": src, "name": "P%d" % (idx + 1), "color": _free_color(), "pid": _pid()})


func _pid() -> int:
	next_pid += 1
	return next_pid


func participant(pid: int) -> Dictionary:
	for p in participants:
		if p["pid"] == pid:
			return p
	return {}


## Online server: a remote player's fighter. Returns its pid.
func add_remote(src: InputSource, nm: String) -> int:
	var pid := _pid()
	participants.append({"source": src, "name": nm, "color": _free_color(), "pid": pid})
	return pid


func remove_participants(pids: Array) -> void:
	participants = participants.filter(func(p): return not (p["pid"] in pids))
	var a := current as Arena
	if a:
		a.net_leave(pids)


## Online server: drop bots until there are at most `n` participants.
func trim_bots(n: int) -> void:
	while participants.size() > n:
		var bot := -1
		for i in range(participants.size() - 1, -1, -1):
			if participants[i]["source"].is_bot:
				bot = i
				break
		if bot < 0:
			return
		remove_participants([participants[bot]["pid"]])


## Online server: add bots (straight into the round) until there are `n` participants.
func fill_bots(n: int) -> void:
	var added := []
	while participants.size() < n:
		add_bot()
		added.append(participants[-1]["pid"])
	var a := current as Arena
	if a and not added.is_empty():
		a.net_join(added)


func map_by_name(key: String) -> Dictionary:
	for m in maps:
		if m["name"] == key:
			return m["data"]
	return {}


func add_bot(skill := 0.65) -> void:
	var n := 1
	for p in participants:
		if p["source"].is_bot:
			n += 1
	participants.append({"source": BotSource.new(n, skill), "name": "BOT%d" % n, "color": _free_color(), "pid": _pid()})


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
	if Net.is_client() and current is Arena:
		Net.leave()
	var m := Node2D.new()
	m.set_script(load("res://scripts/game/menu.gd"))
	_swap(m)


func goto_lobby() -> void:
	var l := Node2D.new()
	l.set_script(load("res://scripts/game/lobby.gd"))
	_swap(l)


func goto_match(net_mode := Net.OFFLINE) -> void:
	scores.clear()
	Sfx.music(not args.has("scenario") and not args.has("mute-music") and net_mode != Net.SERVER)
	var a := Arena.new()
	a.net_mode = net_mode
	a.setup(participants, maps[map_index]["data"] if not maps.is_empty() else {})
	a.map_key = maps[map_index]["name"] if not maps.is_empty() else ""
	_swap(a)


## Online client: the server welcomed us; show its match.
func start_online_client(state: Dictionary) -> void:
	scores.clear()
	Sfx.music(not args.has("mute-music"))
	var a := Arena.new()
	a.net_mode = Net.CLIENT
	a.setup([], map_by_name(state["map"]))
	a.map_key = state["map"]
	_swap(a)
	a.anet.apply_full(state)


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
	if current is Arena and (current as Arena).net_mode == Net.CLIENT:
		var c: Arena = current
		var me: Fighter = c.anet._fighter(Net.my_pids[0]) if not Net.my_pids.is_empty() else null
		print("[net-client] round=%d fighters=%d pickups=%d props=%d rx=%.1fKB (%.1f KB/s) me=%s hp=%d scores=%s" % [c.round_num,
			c.fighters.size(), c.pickups().size(), c.props().size(), c.anet.rx_bytes / 1024.0,
			c.anet.rx_bytes / 1024.0 / maxf(game_time, 1.0), me.global_position if me else "-", me.hp if me else -1, scores])
		print("[net-client] names=%s corrections=%d unconfirmed=%d" % [c.fighters.map(func(f): return f.display_name),
			c.anet.corrections, c.anet.history.size()])
	elif current is Arena:
		var a: Arena = current
		print("[test] rounds=%d time=%.1f scores=%s pickups=%d tiles=%d" % [a.round_num, game_time, scores, a.pickups().size(), a.terrain.mats.size()])
		var keys := stats.keys()
		keys.sort()
		for k in keys:
			print("[stat] %s = %s" % [k, stats[k]])
	get_tree().quit()
