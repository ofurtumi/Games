extends Node
## Autoload `Net`: online play.
##
## A dedicated server (`--server`, usually headless on a home box) runs the real match, bots
## included. Clients only send InputFrames (10 bits per player per tick) and draw what the
## server sends back: ~30 snapshots/s with fighter/item state, destroyed tiles, and the
## effects/sounds that happened (see ArenaNet). WebSockets, so browser builds can join too.
##
##   godot --headless --path . -- --server [--port 7350] [--bind 127.0.0.1] [--fill 4] [--map downtown]
##   godot --path . -- --connect address [--name TUMI]   (see server_url for address forms)

enum { OFFLINE, SERVER, CLIENT }

const PORT := 7350
const VERSION := 1
const SNAP_EVERY := 2 # physics ticks between snapshots (30 Hz)
const INPUT_EVERY := 1 # physics ticks of input batched per packet (1 = lowest latency)

var mode := OFFLINE
var peer: WebSocketMultiplayerPeer
var fill := 4 # server: bots top the match up to this many fighters
var clients := {} # server: peer id -> {name, pids}
var my_pids: Array = [] # client: participant ids this machine controls
var local_sources: Array = [] # client: one InputSource per entry in my_pids
var item_ids: Array = [] # weapon id table, server order (index <-> id on the wire)
var status := "" # client: shown in the menu
var address := ""
var player_name := "PLAYER"
var fake_lag_ms := 0 # client testing: delay every packet each way (`--fake-lag 60`)
var _lag_out: Array = [] # [due msec, packet]
var _lag_in: Array = [] # [due msec, Callable]


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	while not _lag_out.is_empty() and _lag_out[0][0] <= now:
		_send_now(_lag_out.pop_front()[1])
	while not _lag_in.is_empty() and _lag_in[0][0] <= now:
		(_lag_in.pop_front()[1] as Callable).call()


func is_server() -> bool:
	return mode == SERVER


func is_client() -> bool:
	return mode == CLIENT


## Fingerprint of items + maps: both sides must have the same content to play together.
func content_hash() -> int:
	var ids := Items.defs.keys()
	ids.sort()
	var s := ",".join(ids)
	for m in Game.maps:
		s += "|%s:%s" % [m["name"], str(m["data"].get("tiles", [])).hash()]
	return s.hash()


func item_index(id: String) -> int:
	return item_ids.find(id)


func item_def(i: int) -> WeaponDef:
	return Items.get_def(item_ids[i]) if i >= 0 and i < item_ids.size() else null


# ---------------------------------------------------------------- server

## `bind` "127.0.0.1" when a reverse proxy (Caddy) sits in front and does TLS.
func host(port := PORT, bind := "*") -> Error:
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port, bind)
	if err != OK:
		push_error("[net] could not listen on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	mode = SERVER
	item_ids = Items.defs.keys()
	item_ids.sort()
	print("[net] server v%d listening on %s:%d, filling to %d fighters" % [VERSION, bind, port, fill])
	return OK


func _on_peer_connected(id: int) -> void:
	if mode == SERVER:
		print("[net] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if mode != SERVER or not clients.has(id):
		return
	var c: Dictionary = clients[id]
	clients.erase(id)
	print("[net] %s (peer %d) left" % [c["name"], id])
	Game.remove_participants(c["pids"])
	Game.fill_bots(fill)
	_arena_call("net_roster_changed")


@rpc("any_peer", "call_remote", "reliable")
func hello(ver: int, nm: String, n_local: int, content: int) -> void:
	if mode != SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		rejected.rpc_id(id, "SERVER IS VERSION %d, YOU HAVE %d" % [VERSION, ver])
		return
	if content != content_hash():
		rejected.rpc_id(id, "YOUR ITEMS/MAPS DIFFER FROM THE SERVER'S - UPDATE THE GAME")
		return
	nm = nm.strip_edges().to_upper().left(10)
	if nm == "":
		nm = "PLAYER"
	var pids := []
	for i in clampi(n_local, 1, 4):
		var src := NetSource.new(id, i)
		pids.append(Game.add_remote(src, nm if n_local == 1 else "%s%d" % [nm, i + 1]))
	clients[id] = {"name": nm, "pids": pids}
	print("[net] %s (peer %d) joined as %s" % [nm, id, pids])
	Game.trim_bots(fill)
	var a := Game.current as Arena
	if a:
		a.net_join(pids)
		welcome.rpc_id(id, pids, item_ids, a.anet.full_state())
		a.net_roster_changed()


@rpc("any_peer", "call_remote", "reliable")
func input(packet: PackedInt32Array) -> void:
	if mode != SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	if not clients.has(id) or packet.is_empty():
		return
	var pids: Array = clients[id]["pids"]
	var slots := packet[0]
	var a := Game.current as Arena
	if a == null or slots <= 0:
		return
	# [slots, seq, bits * slots, seq, bits * slots, ...]
	var i := 1
	while i + slots < packet.size():
		var seq := packet[i]
		for s in slots:
			if s < pids.size():
				var src := a.source_of(pids[s])
				if src is NetSource:
					(src as NetSource).push(seq, packet[i + 1 + s])
		i += slots + 1


func broadcast_snapshot(data: PackedByteArray) -> void:
	for id in clients:
		snap.rpc_id(id, data)


func broadcast_roster(list: Array) -> void:
	for id in clients:
		roster.rpc_id(id, list)


# ---------------------------------------------------------------- client

func join(addr: String, nm: String, n_local := 1) -> void:
	leave()
	address = addr
	player_name = nm
	var url := server_url(addr)
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		status = "BAD ADDRESS"
		return
	multiplayer.multiplayer_peer = peer
	mode = CLIENT
	my_pids = []
	local_sources = []
	for i in n_local:
		local_sources.append(KeyboardSource.new(i))
	fake_lag_ms = int(Game.args.get("fake-lag", 0))
	if Game.args.has("test-input"): # headless loopback tests: wander, jump and punch
		var steps := []
		for k in 40:
			steps.append([0.6, {"move": Vector2i(1, 0), "sprint": true}])
			steps.append([0.1, {"jump": true, "move": Vector2i(1, 0)}])
			steps.append([0.4, {"attack": k % 2 == 0}])
			steps.append([0.6, {"move": Vector2i(-1, 0)}])
			steps.append([0.2, {"throw": true}])
		local_sources[0] = ScriptedSource.new(steps)
	status = "CONNECTING TO %s ..." % addr.strip_edges().to_upper()
	print("[net] connecting to ", url)


## What players type -> WebSocket URL:
##   fight.example.com        -> wss://fight.example.com      (behind Caddy/HTTPS, port 443)
##   example.com/fighter      -> wss://example.com/fighter
##   192.168.1.20, localhost  -> ws://192.168.1.20:7350       (LAN / direct, default port)
##   host:7351                -> ws://host:7351                (explicit port = direct, no TLS)
##   ws://... or wss://...    -> used as is
static func server_url(addr: String) -> String:
	var s := addr.strip_edges()
	if s.contains("://"):
		return s
	var slash := s.find("/")
	var host_part := s if slash < 0 else s.left(slash)
	var path := "" if slash < 0 else s.substr(slash)
	if host_part.contains(":"):
		return "ws://" + s
	var ip := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+\\.\\d+$").search(host_part) != null
	if ip or host_part == "localhost" or not host_part.contains(".") or host_part.ends_with(".local"):
		return "ws://%s:%d%s" % [host_part, PORT, path]
	return "wss://" + s


func leave() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	peer = null
	mode = OFFLINE
	clients.clear()


func send_input(packet: PackedInt32Array) -> void:
	if fake_lag_ms > 0:
		_lag_out.append([Time.get_ticks_msec() + fake_lag_ms, packet])
	else:
		_send_now(packet)


func _send_now(packet: PackedInt32Array) -> void:
	if mode == CLIENT and peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		input.rpc_id(1, packet)


func _on_connected() -> void:
	status = "JOINING ..."
	hello.rpc_id(1, VERSION, player_name, local_sources.size(), content_hash())


func _on_failed() -> void:
	status = "COULD NOT CONNECT"
	leave()


func _on_server_gone() -> void:
	status = "DISCONNECTED FROM SERVER"
	leave()
	Game.goto_menu()


@rpc("authority", "call_remote", "reliable")
func rejected(why: String) -> void:
	status = why
	leave()
	Game.goto_menu()


@rpc("authority", "call_remote", "reliable")
func welcome(pids: Array, ids: Array, state: Dictionary) -> void:
	my_pids = pids
	item_ids = ids
	status = ""
	print("[net] joined, controlling ", pids)
	Game.start_online_client(state)


@rpc("authority", "call_remote", "reliable")
func snap(data: PackedByteArray) -> void:
	if fake_lag_ms > 0:
		_lag_in.append([Time.get_ticks_msec() + fake_lag_ms, _snap_now.bind(data)])
	else:
		_snap_now(data)


func _snap_now(data: PackedByteArray) -> void:
	var a := Game.current as Arena
	if a and a.anet and mode == CLIENT:
		a.anet.receive(data)


@rpc("authority", "call_remote", "reliable")
func roster(list: Array) -> void:
	var a := Game.current as Arena
	if a and a.anet and mode == CLIENT:
		a.anet.set_roster(list)


func _arena_call(method: String) -> void:
	var a := Game.current as Arena
	if a:
		a.call(method)
