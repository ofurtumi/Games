extends CanvasLayer

# All UI: in-run HUD plus one modal panel that is rebuilt for the menu,
# upgrade choices, the shop, pause and the end-of-run screens.

const Data = preload("res://scripts/Data.gd")

var game = null

var hud_root: Control
var hp_bar: ProgressBar
var hp_label: Label
var xp_bar: ProgressBar
var level_label: Label
var crumbs_label: Label
var objective_label: Label
var boss_name: Label
var boss_bar: ProgressBar
var zone_label: Label
var ability_label: Label
var prompt_label: Label
var announce_label: Label
var boss_marker: Label
var nest_marker: Label
var flash_rect: ColorRect
var dim: ColorRect
var panel: PanelContainer
var panel_box: VBoxContainer

var announce_t = 0.0
var hit_marks = []
var hit_t = 0.0

func _ready():
	# Above the outline post-process layer (10) so UI text isn't outlined.
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func setup(g):
	game = g

# --- construction --------------------------------------------------------------

func _place(c: Control, ax: float, ay: float, ox: float, oy: float):
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	if ax < 0.25:
		c.grow_horizontal = Control.GROW_DIRECTION_END
	elif ax > 0.75:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if ay < 0.25:
		c.grow_vertical = Control.GROW_DIRECTION_END
	elif ay > 0.75:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		c.grow_vertical = Control.GROW_DIRECTION_BOTH

func _make_label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_bar(width: float, height: float, fill: Color) -> ProgressBar:
	var b = ProgressBar.new()
	b.custom_minimum_size = Vector2(width, height)
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.001
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	var fg = StyleBoxFlat.new()
	fg.bg_color = fill
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b

func _build():
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.8, 0.0, 0.0, 0.0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.visible = false
	add_child(hud_root)

	var left = VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(left, 0.0, 0.0, 16.0, 16.0)
	hud_root.add_child(left)
	hp_label = _make_label("HP", 18)
	left.add_child(hp_label)
	hp_bar = _make_bar(280.0, 20.0, Color(0.85, 0.15, 0.2))
	left.add_child(hp_bar)
	level_label = _make_label("Level 1", 16)
	left.add_child(level_label)
	xp_bar = _make_bar(280.0, 10.0, Color(0.3, 0.7, 1.0))
	left.add_child(xp_bar)
	crumbs_label = _make_label("Crumbs: 0", 18, Color(1.0, 0.85, 0.4))
	left.add_child(crumbs_label)

	var top = VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(top, 0.5, 0.0, 0.0, 16.0)
	hud_root.add_child(top)
	objective_label = _make_label("", 20)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(objective_label)
	boss_name = _make_label("", 22, Color(1.0, 0.4, 0.3))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(boss_name)
	boss_bar = _make_bar(460.0, 18.0, Color(0.9, 0.3, 0.1))
	top.add_child(boss_bar)

	zone_label = _make_label("", 18)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(zone_label, 1.0, 0.0, -16.0, 16.0)
	hud_root.add_child(zone_label)

	var bottom = VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(bottom, 0.5, 1.0, 0.0, -16.0)
	hud_root.add_child(bottom)
	prompt_label = _make_label("", 22, Color(0.7, 1.0, 0.8))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(prompt_label)
	ability_label = _make_label("", 16)
	ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(ability_label)

	announce_label = _make_label("", 30, Color(1.0, 0.95, 0.7))
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(announce_label, 0.5, 0.25, 0.0, 0.0)
	hud_root.add_child(announce_label)

	boss_marker = _make_label("", 18, Color(1.0, 0.4, 0.3))
	boss_marker.visible = false
	hud_root.add_child(boss_marker)
	nest_marker = _make_label("NEST", 14, Color(0.7, 1.0, 0.8))
	nest_marker.visible = false
	hud_root.add_child(nest_marker)

	# Hit marker: an X around the crosshair that flashes on every hit.
	for i in 4:
		var m = ColorRect.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.size = Vector2(3, 12)
		m.pivot_offset = Vector2(1.5, 6)
		m.rotation_degrees = 45.0 + 90.0 * i
		var dir = Vector2(1, -1).rotated(deg_to_rad(90.0 * i)).normalized()
		_place(m, 0.5, 0.5, 0.0, 0.0)
		m.offset_left = dir.x * 13.0 - 1.5
		m.offset_right = dir.x * 13.0 + 1.5
		m.offset_top = dir.y * 13.0 - 6.0
		m.offset_bottom = dir.y * 13.0 + 6.0
		m.visible = false
		add_child(m)
		hit_marks.append(m)

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	add_child(dim)

	panel = PanelContainer.new()
	_place(panel, 0.5, 0.5, 0.0, 0.0)
	panel.visible = false
	add_child(panel)
	var margin = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	panel_box = VBoxContainer.new()
	panel_box.custom_minimum_size = Vector2(560.0, 0.0)
	panel_box.add_theme_constant_override("separation", 8)
	margin.add_child(panel_box)

# --- per-frame HUD -------------------------------------------------------------

func _process(delta):
	if game == null:
		return
	flash_rect.color.a = move_toward(flash_rect.color.a, 0.0, delta * 1.2)
	hit_t -= delta
	for m in hit_marks:
		m.visible = hit_t > 0.0
	var s = game.state
	var in_run = s == "playing" or s == "choice" or s == "shop" or s == "paused"
	hud_root.visible = in_run
	if not in_run:
		return

	var st = game.st
	hp_bar.value = clampf(game.hp / st["max_hp"], 0.0, 1.0)
	hp_label.text = "HP %d / %d" % [int(ceil(game.hp)), int(st["max_hp"])]
	xp_bar.value = clampf(game.xp / game.xp_needed(), 0.0, 1.0)
	level_label.text = "Level %d" % game.level
	crumbs_label.text = "Crumbs: %d" % game.crumbs

	var info = game.act_info()
	var boss = game.boss
	var boss_alive = boss != null and is_instance_valid(boss) and not boss.dead
	if boss_alive:
		if boss.is_capture():
			objective_label.text = "Act %d - wrap %s in web to net him!" % [game.act, boss.cfg["name"]]
			boss_name.text = "%s - net" % boss.cfg["name"]
			boss_bar.value = clampf(1.0 - boss.hp / boss.max_hp, 0.0, 1.0)
		else:
			objective_label.text = "Act %d - defeat the boss!" % game.act
			boss_name.text = boss.cfg["name"]
			boss_bar.value = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
	else:
		objective_label.text = "Act %d - bugs hunted %d / %d" % [game.act, mini(game.act_kills, info["quota"]), info["quota"]]
	boss_name.visible = boss_alive
	boss_bar.visible = boss_alive

	var zone = game.zone_at(game.player.global_position)
	zone_label.text = "%s\n%s" % [zone["name"], zone["bonus_text"]]

	ability_label.text = "Web shot [RMB]    Grapple [LMB]    Pounce [Shift] %s    Web burst [Q] %s" % [
		_cd_text(game.player.pounce_cd), _cd_text(game.burst_cd)]
	if game.near_nest:
		prompt_label.text = "[E] Enter the nest (shop)"
	else:
		prompt_label.text = ""

	if s == "playing" and announce_t > 0.0:
		announce_t -= delta
	announce_label.visible = announce_t > 0.0

	var cam = get_viewport().get_camera_3d()
	boss_marker.visible = false
	nest_marker.visible = false
	if cam != null:
		if boss_alive:
			boss_marker.text = "v %s" % boss.cfg["name"]
			_put_marker(cam, boss_marker, boss.center() + Vector3.UP * (boss.hit_height * 0.5 + boss.radius + 0.2))
		if not game.near_nest and game.crumbs >= game.shop_price() and not game.shop_offers.is_empty():
			_put_marker(cam, nest_marker, game.nest.global_position + Vector3.UP * 0.25)

func _cd_text(cd: float) -> String:
	if cd <= 0.0:
		return "ready"
	return "%.1fs" % cd

func _put_marker(cam: Camera3D, marker: Label, world_pos: Vector3):
	var size = get_viewport().get_visible_rect().size
	var sp = cam.unproject_position(world_pos)
	if cam.is_position_behind(world_pos):
		sp.x = size.x - sp.x
		sp.y = size.y - 80.0
	sp.x = clampf(sp.x, 20.0, size.x - 160.0)
	sp.y = clampf(sp.y, 70.0, size.y - 80.0)
	marker.position = sp
	marker.visible = true

func flash():
	flash_rect.color.a = 0.35

func hitmarker(killed: bool, crit: bool):
	var c = Color.WHITE
	if killed:
		c = Color(1.0, 0.25, 0.2)
	elif crit:
		c = Color(1.0, 0.85, 0.2)
	hit_t = 0.22 if killed else 0.12
	for m in hit_marks:
		m.color = c

func announce(text: String, time: float):
	announce_label.text = text
	announce_t = time

# --- modal panel ---------------------------------------------------------------

func on_state_changed(s: String):
	for c in panel_box.get_children():
		panel_box.remove_child(c)
		c.queue_free()
	var modal = s != "playing"
	dim.visible = modal
	panel.visible = modal
	match s:
		"menu":
			_build_menu()
		"choice":
			_build_choice()
		"shop":
			_build_shop()
		"paused":
			_build_pause()
		"dead":
			_build_end(false)
		"victory":
			_build_end(true)

func _text(text: String, size: int = 16, color: Color = Color.WHITE) -> Label:
	var l = _make_label(text, size, color)
	panel_box.add_child(l)
	return l

func _button(text: String, action: Callable, enabled: bool = true) -> Button:
	var b = Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(action)
	panel_box.add_child(b)
	return b

func _upgrade_text(id: String) -> String:
	var u = Data.UPGRADES[id]
	return "%s  (%d/%d)\n    %s" % [u["name"], game.owned.get(id, 0), u["max"], u["desc"]]

func _build_menu():
	_text("ÍBÚÐ", 44, Color(1.0, 0.95, 0.7))
	_text("You are a spider. This is Tumi's apartment. Take it.", 16)
	_text("Silk: %d      Wins: %d      Furthest act: %d" % [int(game.meta["silk"]), int(game.meta["wins"]), int(game.meta["best_act"])], 16, Color(0.7, 1.0, 0.8))
	_button("Start run", game.start_run)
	_text("Permanent upgrades (paid with silk, earned every run)", 15, Color(0.8, 0.8, 0.8))
	for id in Data.META:
		var m = Data.META[id]
		var lvl = game.meta_level(id)
		if lvl >= m["max"]:
			_button("%s  %d/%d  -  %s   [maxed]" % [m["name"], lvl, m["max"], m["desc"]], game.buy_meta.bind(id), false)
		else:
			var cost = game.meta_cost(id)
			_button("%s  %d/%d  -  %s   [%d silk]" % [m["name"], lvl, m["max"], m["desc"], cost], game.buy_meta.bind(id), int(game.meta["silk"]) >= cost)
	_text("WASD move   Space jump   LMB grapple   RMB web shot\nShift pounce   Q web burst   E nest   Esc pause   F fullscreen", 14, Color(0.8, 0.8, 0.8))
	_button("Quit", get_tree().quit)

func _build_choice():
	var kind = game.choice_kind
	if kind.begins_with("relic:"):
		_text("Boss relic - choose one", 28, Color(1.0, 0.6, 0.3))
	elif kind == "cache":
		_text("Cache - choose an upgrade", 28, Color(1.0, 0.9, 0.5))
	else:
		_text("Level %d - choose an upgrade" % game.level, 28, Color(0.5, 0.85, 1.0))
	var i = 0
	for id in game.choice_options:
		_button("[%d]  %s" % [i + 1, _upgrade_text(id)], game.pick_choice.bind(i))
		i += 1

func _build_shop():
	_text("The Nest", 28, Color(0.7, 1.0, 0.8))
	_text("Crumbs: %d       HP %d / %d" % [game.crumbs, int(ceil(game.hp)), int(game.st["max_hp"])], 18, Color(1.0, 0.85, 0.4))
	var price = game.shop_price()
	var i = 0
	for id in game.shop_offers:
		_button("%s\n    [%d crumbs]" % [_upgrade_text(id), price], game.shop_buy.bind(i), game.crumbs >= price)
		i += 1
	if game.shop_offers.is_empty():
		_text("Sold out - new stock after the next boss, or reroll.", 15, Color(0.8, 0.8, 0.8))
	_button("Heal 40 HP   [15 crumbs]", game.shop_heal, game.crumbs >= 15 and game.hp < game.st["max_hp"])
	_button("Reroll stock   [10 crumbs]", game.shop_reroll, game.crumbs >= 10)
	_button("Leave   [Esc]", game.close_shop)

func _build_pause():
	_text("Paused", 28)
	_text("Act %d   Level %d   Kills %d" % [game.act, game.level, game.kills], 16)
	var lines = []
	for id in game.owned:
		lines.append("%s x%d" % [Data.UPGRADES[id]["name"], game.owned[id]])
	if not lines.is_empty():
		_text(", ".join(lines), 14, Color(0.8, 0.8, 0.8)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("Resume   [Esc]", game.toggle_pause)
	_button("Abandon run (keep the silk earned so far)", game.abandon_run)
	_button("Quit game", get_tree().quit)

func _build_end(won: bool):
	if won:
		_text("The apartment is yours.", 32, Color(1.0, 0.95, 0.7))
		_text("Tumi has moved out. Long live the spider.", 16)
	else:
		_text("Squashed.", 32, Color(1.0, 0.4, 0.3))
		_text("Every spider leaves a little silk behind for the next one.", 16)
	var minutes = int(game.run_time) / 60
	var seconds = int(game.run_time) % 60
	_text("Act %d   Level %d   Kills %d   Bosses %d   Time %d:%02d" % [game.act, game.level, game.kills, game.bosses_killed, minutes, seconds], 16)
	_text("+%d silk" % game.last_silk, 22, Color(0.7, 1.0, 0.8))
	_button("Back to the menu", game.to_menu)

# --- input ---------------------------------------------------------------------

func _input(event):
	if game == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if game.state == "shop":
				game.close_shop()
			else:
				game.toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_F:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_1:
			game.pick_choice(0)
		KEY_2:
			game.pick_choice(1)
		KEY_3:
			game.pick_choice(2)
