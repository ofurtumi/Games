extends Node2D
## Join screen. Every device's InputFrame is polled; press JUMP to join.
##   JUMP: join      THROW: leave      PICKUP: add bot      AIM: remove bot
##   LEFT/RIGHT: change map            ATTACK (or Enter/Start): start

var candidates: Array = [] # InputSource
var prev := {} # device_key -> InputFrame
var scan_t := 0.0
var t := 0.0


func _ready() -> void:
	_scan()


func _scan() -> void:
	var keep := {}
	for p in Game.participants:
		keep[p["source"].device_key()] = p["source"]
	candidates = [KeyboardSource.new(0), KeyboardSource.new(1)]
	for dev in Input.get_connected_joypads():
		candidates.append(GamepadSource.new(dev))
	# Reuse joined sources so their identity is stable.
	for i in candidates.size():
		var k: String = candidates[i].device_key()
		if keep.has(k):
			candidates[i] = keep[k]


func _joined(src: InputSource) -> bool:
	for p in Game.participants:
		if p["source"].device_key() == src.device_key():
			return true
	return false


func _process(dt: float) -> void:
	t += dt
	scan_t -= dt
	if scan_t <= 0.0:
		scan_t = 1.0
		_scan()
	for src in candidates:
		var k: String = src.device_key()
		var f: InputFrame = src.sample(null, null)
		var pf: InputFrame = prev.get(k, InputFrame.new())
		prev[k] = f
		var joined := _joined(src)
		if f.jump and not pf.jump and not joined:
			Game.add_human(src)
			Game.renumber()
			Sfx.play("ui_select")
		elif f.throw and not pf.throw and joined:
			Game.participants = Game.participants.filter(func(p): return p["source"].device_key() != k)
			Game.renumber()
			Sfx.play("ui_back")
		elif f.interact and not pf.interact and Game.participants.size() < 8:
			Game.add_bot()
			Sfx.play("ui_move")
		elif f.aim and not pf.aim:
			for i in range(Game.participants.size() - 1, -1, -1):
				if Game.participants[i]["source"].is_bot:
					Game.participants.remove_at(i)
					break
		elif f.move.x != pf.move.x and f.move.x != 0 and not Game.maps.is_empty():
			Game.map_index = posmod(Game.map_index + f.move.x, Game.maps.size())
			Sfx.play("ui_move")
		elif joined and f.attack and not pf.attack:
			_start()
			return
		if src is GamepadSource and (src as GamepadSource).start_pressed() and joined:
			_start()
			return
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_start()
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		Game.goto_menu()


func _start() -> void:
	if Game.participants.size() >= 1 and not Game.maps.is_empty():
		Game.goto_match()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.06, 0.06, 0.1))
	for i in 24:
		var y := fmod(i * 23.0 + t * 8.0, view.y)
		draw_rect(Rect2(0, y, view.x, 1), Color(1, 1, 1, 0.03))
	Txt.draw_centered(self, view.x / 2, 18, "ARENA FIGHTER", Color(0.95, 0.4, 0.3), 4)
	Txt.draw_centered(self, view.x / 2, 42, "WORKING TITLE", Color(1, 1, 1, 0.3))

	# Map selector
	var mname := "NO MAPS" if Game.maps.is_empty() else String(Game.maps[Game.map_index]["data"].get("name", Game.maps[Game.map_index]["name"]))
	Txt.draw_centered(self, view.x / 2, 58, "< MAP: %s >" % mname, Color(0.9, 0.9, 0.6), 1)

	# Slots
	var cols := 4
	var sw := 104.0
	var sh := 40.0
	var x0 := (view.x - cols * sw) / 2.0
	for i in 8:
		var x := x0 + (i % cols) * sw
		var y := 74.0 + (i / cols) * (sh + 6)
		var r := Rect2(x + 3, y, sw - 6, sh)
		if i < Game.participants.size():
			var p: Dictionary = Game.participants[i]
			var c: Color = p["color"]
			draw_rect(r, Color(c, 0.18))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), c)
			Txt.draw(self, r.position + Vector2(6, 8), p["name"], c, 2)
			Txt.draw(self, r.position + Vector2(6, 26), p["source"].label, Color(1, 1, 1, 0.6))
			# Little guy
			var gx := r.end.x - 14
			var gy := r.end.y - 6
			draw_rect(Rect2(gx - 2, gy - 18, 5, 5), Color(0.96, 0.8, 0.62))
			draw_rect(Rect2(gx - 2, gy - 17, 5, 1), c.darkened(0.35))
			draw_rect(Rect2(gx - 2, gy - 13, 5, 7), c)
			draw_rect(Rect2(gx - 2, gy - 6, 2, 6), Color(0.16, 0.18, 0.28))
			draw_rect(Rect2(gx + 1, gy - 6, 2, 6), Color(0.16, 0.18, 0.28))
		else:
			draw_rect(r, Color(1, 1, 1, 0.04))
			var blink := int(t * 2.0) % 2 == 0
			Txt.draw_centered(self, r.get_center().x, r.position.y + 17, "PRESS JUMP" if blink else "", Color(1, 1, 1, 0.3))

	var help := [
		"JUMP: JOIN   THROW: LEAVE   E / PAD Y: ADD BOT   AIM: REMOVE BOT   LEFT/RIGHT: MAP",
		"ATTACK / ENTER / START: FIGHT      ESC: BACK",
		"",
		"KB1: WASD MOVE  J ATTACK  K JUMP  L AIM/BLOCK  H THROW/PICKUP  SHIFT SPRINT",
		"KB2: ARROWS  NUMPAD 1 ATTACK  2 JUMP  3 AIM  0 THROW  ENTER SPRINT",
		"PAD: A JUMP  X ATTACK  RB AIM  LB SPRINT  B THROW  Y PICKUP",
		"",
		"SPRINT+JUMP: DIVE/TACKLE   AIR ATTACK: KICK   DOWN+AIR ATTACK: STOMP",
		"HIT SOMEONE WHO IS AIMING TO DISARM   AIM WITHOUT A GUN: BLOCK",
	]
	var hy := 172.0
	for line in help:
		Txt.draw_centered(self, view.x / 2, hy, line, Color(1, 1, 1, 0.55))
		hy += 9.0
