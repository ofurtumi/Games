extends Node2D
## Per-player status panels, kill feed and round banner.

var arena: Node


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var shown: Array = arena.fighters.filter(func(f): return not f.left)
	var n: int = shown.size()
	if n == 0:
		return
	var w := minf(96.0, (view.x - 8.0) / n)
	for i in n:
		var f: Fighter = shown[i]
		var x := 4.0 + i * w
		var y := 3.0
		var dead := not f.alive()
		var c := f.color if not dead else f.color.darkened(0.6)
		draw_rect(Rect2(x, y, w - 4, 19), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(x, y, 2, 19), c)
		Txt.draw(self, Vector2(x + 4, y + 2), f.display_name, c)
		var score := "%d" % Game.score_of(f.player_index)
		Txt.draw(self, Vector2(x + w - 6 - Txt.width(score), y + 2), score, Color(1, 0.9, 0.4))
		var hpw := (w - 10) * clampf(f.hp / f.max_hp, 0.0, 1.0)
		draw_rect(Rect2(x + 4, y + 8, w - 10, 2), Color(0.25, 0.05, 0.05))
		draw_rect(Rect2(x + 4, y + 8, hpw, 2), Color(0.3, 0.9, 0.35) if f.hp > 35.0 else Color(0.95, 0.3, 0.2))
		var item := ""
		if f.weapon:
			item = f.weapon.def.name
			if f.weapon.def.kind == "gun":
				item += " %d" % f.weapon.ammo
		if f.throwable:
			item += ("  " if item != "" else "") + "*%d" % f.throw_count
		if dead:
			item = "DEAD"
		Txt.draw(self, Vector2(x + 4, y + 12), item, Color(0.85, 0.85, 0.9), 1, false)

	var vr: Rect2 = arena.camera.view_rect()
	var z: float = arena.camera.zoom.x
	# Name tags + health over heads (Superfighters style).
	for f in arena.fighters:
		if not f.alive() or not vr.grow(20).has_point(f.center()):
			continue
		var hp_pct := clampf(f.hp / f.max_hp, 0.0, 1.0)
		var head: Vector2 = (f.global_position + Vector2(0, -f.height() - 9.0) - vr.position) * z
		head = Vector2(roundf(head.x), maxf(roundf(head.y), 30.0))
		var nm: String = f.display_name
		Txt.draw_outlined(self, head - Vector2(Txt.width(nm, 0) / 2.0, 6), nm, Color(f.color.lightened(0.35), 0.9), 0)
		var bw := 14.0
		draw_rect(Rect2(head.x - bw / 2 - 0.5, head.y + 0.5, bw + 1, 2.5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(head.x - bw / 2, head.y + 1, bw * hp_pct, 1.5), Color(0.35, 0.9, 0.35) if hp_pct > 0.35 else Color(0.95, 0.3, 0.2))
	# Red edge flash when the followed player gets hurt / is nearly dead.
	var humans: Array = arena.fighters.filter(func(f): return not f.source.is_bot and not f.source.remote and not (f.source is ScriptedSource))
	if humans.size() == 1 and humans[0].alive():
		var me: Fighter = humans[0]
		var a: float = me.hurt_flash * 4.0 + (0.25 + 0.15 * sin(arena.time * 6.0) if me.hp < 30.0 else 0.0)
		if a > 0.0:
			for k in 6:
				var c := Color(0.8, 0.0, 0.0, a * (0.18 - k * 0.028))
				draw_rect(Rect2(0, 0, view.x, 2 + k * 2), c)
				draw_rect(Rect2(0, view.y - 2 - k * 2, view.x, 2 + k * 2), c)
				draw_rect(Rect2(0, 0, 2 + k * 2, view.y), c)
				draw_rect(Rect2(view.x - 2 - k * 2, 0, 2 + k * 2, view.y), c)

	# Arrows at the screen edge for fighters out of view.
	for f in arena.fighters:
		if not f.alive() or vr.has_point(f.center()):
			continue
		var sp: Vector2 = (f.center() - vr.position) * z
		var mid := view / 2.0
		var dir := (sp - mid).normalized()
		var edge := Rect2(Vector2(10, 30), view - Vector2(20, 44))
		var p := Vector2(clampf(sp.x, edge.position.x, edge.end.x), clampf(sp.y, edge.position.y, edge.end.y))
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 5.0, p - dir * 2.0 + perp * 3.5, p - dir * 2.0 - perp * 3.5]), Color(0, 0, 0, 0.6))
		draw_colored_polygon(PackedVector2Array([p + dir * 4.0, p - dir * 1.5 + perp * 2.5, p - dir * 1.5 - perp * 2.5]), f.color.lightened(0.15))
		var dist := "%dM" % int(f.center().distance_to(vr.get_center()) / 16.0)
		Txt.draw(self, p - dir * 9.0 - Vector2(Txt.width(dist) / 2.0, 2), dist, Color(f.color.lightened(0.3), 0.8))

	# Kill feed
	var fy := 26.0
	for e in arena.feed:
		var s: String = e[0]
		var a := clampf(float(e[2]), 0.0, 1.0)
		Txt.draw(self, Vector2(view.x - 4 - Txt.width(s), fy), s, Color(e[1], a))
		fy += 7.0

	# Round intro
	if arena.intro_t > 0.0:
		var p: float = 1.0 - arena.intro_t / arena.INTRO
		Txt.draw_outlined(self, Vector2(view.x / 2 - Txt.width("READY", 3) / 2.0, view.y / 2 - 30), "READY", Color(1, 1, 1, minf(1.0, p * 4.0)), 3)
		Txt.draw_centered(self, view.x / 2, view.y / 2 - 6, "ROUND %d" % arena.round_num, Color(1, 1, 1, 0.7), 1)
	elif arena.round_t < arena.INTRO + 0.7 and arena.round_over_t < 0.0 and arena.round_t > 0.0 and not Game.args.has("scenario"):
		var k: float = clampf((arena.round_t - arena.INTRO) / 0.7, 0.0, 1.0) if arena.round_t >= arena.INTRO else 0.0
		Txt.draw_outlined(self, Vector2(view.x / 2 - Txt.width("FIGHT!", 3) / 2.0, view.y / 2 - 30 - k * 6.0), "FIGHT!",
			Color(1, 0.85, 0.3, 1.0 - k * k), 3)

	if arena.round_over_t >= 0.0:
		var txt := "DRAW"
		var col := Color(0.9, 0.9, 0.9)
		var sub := "ROUND %d" % (arena.round_num + 1)
		if arena.match_winner:
			txt = "%s WINS THE MATCH!" % arena.match_winner.display_name
			col = arena.match_winner.color.lightened(0.25)
			sub = "FIRST TO %d   -   NEW MATCH STARTING" % arena.WIN_SCORE
		elif arena.round_winner:
			txt = "%s WINS THE ROUND" % arena.round_winner.display_name
			col = arena.round_winner.color.lightened(0.2)
			sub = "%d / %d   -   NEXT: ROUND %d" % [Game.score_of(arena.round_winner.player_index), arena.WIN_SCORE, arena.round_num + 1]
		draw_rect(Rect2(0, view.y / 2 - 20, view.x, 36), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(0, view.y / 2 - 20, view.x, 1), Color(col, 0.6))
		draw_rect(Rect2(0, view.y / 2 + 15, view.x, 1), Color(col, 0.6))
		Txt.draw_outlined(self, Vector2(view.x / 2 - Txt.width(txt, 2) / 2.0, view.y / 2 - 14), txt, col, 2)
		Txt.draw_centered(self, view.x / 2, view.y / 2 + 4, sub, Color(0.85, 0.85, 0.85))
	Txt.draw(self, Vector2(4, view.y - 8), "ESC: MENU", Color(1, 1, 1, 0.35), 1, false)
	# Controls reminder at the start of a match with a keyboard player.
	if arena.time < 10.0 and arena.round_num == 1:
		for f in arena.fighters:
			if f.source is KeyboardSource and f.source.layout == 0:
				var a := clampf(10.0 - arena.time, 0.0, 1.0)
				draw_rect(Rect2(0, view.y - 22, view.x, 12), Color(0, 0, 0, 0.5 * a))
				Txt.draw_centered(self, view.x / 2, view.y - 19,
					"WASD MOVE   J ATTACK   K JUMP   HOLD L + W/S AIM   H THROW/PICK UP   SHIFT SPRINT (+S SLIDE)", Color(1, 0.9, 0.5, a))
				break
