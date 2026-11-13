extends Node2D
## Title menu. W/S (or arrows / D-pad) to move, J/K/Enter/Space (or A) to pick,
## A/D (left/right) to change values, H/Esc (or B) to go back.

const DIFFS := [["EASY", 0.35], ["NORMAL", 0.65], ["HARD", 0.95]]

var page := "main"
var sel := 0
var t := 0.0
var prev := {}
var bots := 3
var diff := 1
var ui: Node2D
var bg_arena: Arena
var slide := {} # item index -> animated x offset
const CFG := "user://online.cfg"
var addr := "localhost"
var pname := "PLAYER"


func _ready() -> void:
	_load_online()
	if Net.status != "":
		page = "online"
		sel = 2
	# Attract mode: a live bot match plays behind the menu.
	if DisplayServer.get_name() != "headless" and not Game.maps.is_empty():
		var parts := []
		for i in 4:
			parts.append({"source": BotSource.new(i + 1, 0.6), "name": "BOT%d" % (i + 1), "color": Game.COLORS[i * 2 % Game.COLORS.size()]})
		var pick := ["warehouse", "rooftops"]
		var md: Dictionary = Game.maps[0]["data"]
		for m in Game.maps:
			if m["name"] == pick[randi() % pick.size()]:
				md = m["data"]
		bg_arena = Arena.new()
		bg_arena.attract = true
		bg_arena.setup(parts, md)
		add_child(bg_arena)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Node2D.new()
	ui.draw.connect(_draw_ui)
	layer.add_child(ui)


func _items() -> Array:
	if page == "main":
		return ["SINGLE PLAYER", "LOCAL MULTIPLAYER", "ONLINE", "QUIT"]
	if page == "online":
		var cur := "_" if int(t * 2.0) % 2 == 0 else " "
		return ["SERVER: %s%s" % [addr, cur if sel == 0 else ""], "NAME: %s%s" % [pname, cur if sel == 1 else ""], "CONNECT"]
	var mname := "-" if Game.maps.is_empty() else String(Game.maps[Game.map_index]["data"].get("name", Game.maps[Game.map_index]["name"]))
	return ["BOTS: < %d >" % bots, "DIFFICULTY: < %s >" % DIFFS[diff][0], "MAP: < %s >" % mname, "FIGHT!"]


func _load_online() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		addr = cf.get_value("online", "address", addr)
		pname = cf.get_value("online", "name", pname)


func _save_online() -> void:
	var cf := ConfigFile.new()
	cf.set_value("online", "address", addr)
	cf.set_value("online", "name", pname)
	cf.save(CFG)


## Typing into the online page's text fields.
func _unhandled_key_input(e: InputEvent) -> void:
	if page != "online" or sel > 1 or not (e is InputEventKey) or not e.pressed:
		return
	var k := e as InputEventKey
	if k.keycode == KEY_BACKSPACE:
		if sel == 0:
			addr = addr.left(-1)
		else:
			pname = pname.left(-1)
		get_viewport().set_input_as_handled()
		return
	if k.unicode < 32 or k.ctrl_pressed or k.meta_pressed:
		return
	var ch := char(k.unicode)
	if sel == 0 and addr.length() < 40 and (ch.is_valid_identifier() or ch in "0123456789.:-_/"):
		addr += ch.to_lower()
	elif sel == 1 and pname.length() < 10 and (ch.to_upper() in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"):
		pname += ch.to_upper()
	get_viewport().set_input_as_handled()


func _pressed(k: String, now: bool) -> bool:
	var was: bool = prev.get(k, false)
	prev[k] = now
	return now and not was


func _key(keys: Array) -> bool:
	for k in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func _pad(b: JoyButton) -> bool:
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, b):
			return true
	return false


func _process(dt: float) -> void:
	t += dt
	var typing := page == "online"
	var up := _pressed("up", _key([KEY_UP] if typing else [KEY_W, KEY_UP]) or _pad(JOY_BUTTON_DPAD_UP))
	var down := _pressed("down", _key([KEY_DOWN, KEY_TAB] if typing else [KEY_S, KEY_DOWN]) or _pad(JOY_BUTTON_DPAD_DOWN))
	var left := _pressed("left", _key([KEY_LEFT] if typing else [KEY_A, KEY_LEFT]) or _pad(JOY_BUTTON_DPAD_LEFT))
	var right := _pressed("right", _key([KEY_RIGHT] if typing else [KEY_D, KEY_RIGHT]) or _pad(JOY_BUTTON_DPAD_RIGHT))
	var ok := _pressed("ok", _key([KEY_ENTER, KEY_KP_ENTER] if typing else [KEY_J, KEY_K, KEY_ENTER, KEY_SPACE]) or _pad(JOY_BUTTON_A) or _pad(JOY_BUTTON_START))
	var back := _pressed("back", _key([KEY_ESCAPE] if typing else [KEY_H, KEY_ESCAPE]) or _pad(JOY_BUTTON_B))
	var n := _items().size()
	if up:
		sel = posmod(sel - 1, n)
	if down:
		sel = posmod(sel + 1, n)
	if up or down or left or right:
		Sfx.play("ui_move")
	if ok:
		Sfx.play("ui_select")
	elif back and page != "main":
		Sfx.play("ui_back")
	var dx := int(right) - int(left)
	if page == "main":
		if ok:
			match sel:
				0:
					page = "single"
					sel = 3
				1: Game.goto_lobby()
				2:
					page = "online"
					sel = 2
				3: get_tree().quit()
	elif page == "online":
		if ok and sel < 2:
			sel += 1
		elif ok and sel == 2 and not Net.is_client():
			_save_online()
			Net.join(addr, pname)
		if back:
			if Net.is_client():
				Net.leave()
				Net.status = "CANCELLED"
			else:
				page = "main"
				sel = 2
				Net.status = ""
	else:
		if dx != 0:
			match sel:
				0: bots = clampi(bots + dx, 1, 7)
				1: diff = clampi(diff + dx, 0, DIFFS.size() - 1)
				2:
					if not Game.maps.is_empty():
						Game.map_index = posmod(Game.map_index + dx, Game.maps.size())
		if ok and sel == 3:
			Game.start_single(bots, DIFFS[diff][1])
			return
		if back:
			page = "main"
			sel = 0
	for i in n:
		slide[i] = lerpf(slide.get(i, 0.0), 8.0 if i == sel else 0.0, 1.0 - exp(-dt * 16.0))
	ui.queue_redraw()


func _draw_ui() -> void:
	var view := get_viewport_rect().size
	if bg_arena == null:
		ui.draw_rect(Rect2(Vector2.ZERO, view), Color(0.06, 0.06, 0.1))
	# Dark fade from the left so the menu reads over the live match.
	for i in 24:
		var x := i * 12.0
		ui.draw_rect(Rect2(x, 0, 12.5, view.y), Color(0.03, 0.03, 0.07, clampf(0.92 - i * 0.045, 0.0, 0.92)))
	ui.draw_rect(Rect2(0, view.y - 40, view.x, 40), Color(0.03, 0.03, 0.07, 0.6))
	var x0 := 28.0
	Txt.draw(ui, Vector2(x0, 30), "ARENA FIGHTER", Color(0.97, 0.42, 0.3), 4)
	Txt.draw(ui, Vector2(x0 + 2, 58), "WORKING TITLE  -  A COUCH BRAWLER", Color(1, 1, 1, 0.35), 1, false)
	if page == "single":
		Txt.draw(ui, Vector2(x0, 86), "SINGLE PLAYER", Color(1, 1, 1, 0.55), 1)
	elif page == "online":
		Txt.draw(ui, Vector2(x0, 86), "ONLINE  -  TYPE THE SERVER ADDRESS, ENTER TO CONFIRM", Color(1, 1, 1, 0.55), 1)
		if Net.status != "":
			Txt.draw(ui, Vector2(x0, 166), Net.status, Color(1, 0.85, 0.4), 1)
	var items := _items()
	for i in items.size():
		var y := 104.0 + i * 18.0
		var s: String = items[i]
		var on := i == sel
		var ox: float = slide.get(i, 0.0)
		if on:
			var w := Txt.width(s, 2) + 14.0
			ui.draw_rect(Rect2(x0 - 6 + ox, y - 3, w, 15), Color(0.97, 0.42, 0.3, 0.18))
			ui.draw_rect(Rect2(x0 - 6 + ox, y - 3, 2, 15), Color(1, 0.85, 0.35))
		Txt.draw(ui, Vector2(x0 + ox, y), s, Color(1, 0.88, 0.4) if on else Color(1, 1, 1, 0.65), 2)
	var help := [
		"WASD MOVE    K / SPACE JUMP    J ATTACK / FIRE    SHIFT SPRINT    H THROW / PICK UP",
		"HOLD L TO AIM, THEN W / S TO SWEEP THE LASER    SPRINT + JUMP: DIVE    DOWN + AIR ATTACK: STOMP",
	]
	for i in help.size():
		Txt.draw(ui, Vector2(x0, view.y - 30 + i * 11), help[i], Color(1, 1, 1, 0.5), 1, false)
