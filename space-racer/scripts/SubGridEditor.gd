extends Control

# A component's own sub-grid. The core (the component itself) sits on the
# left; place nodes from the palette and wire output ports (right side) to
# other nodes. Only nodes wired back to the core do anything. For tools the
# wiring is the program: mods change the shot as it passes, Split sends one
# shot down each branch, payloads go off where it lands and launch whatever
# is wired after them.
#
# Click a palette card, then a cell, to place it (it wires itself onto the end
# of the chain, so cards go in series in the order you place them). Drag from
# a port to a node to wire it. Right-click a node or a wire to remove it.
# Select, then act, as in the garage: a palette card, a placed card or a
# preset is selected with a click and the action bar along the bottom (Bar.gd)
# lists what you can do with it; with nothing selected it saves or clears the
# wiring. Esc drops the selection, then closes.

const Parts = preload("res://scripts/Parts.gd")
const Ui = preload("res://scripts/Ui.gd")
const ToolDemo = preload("res://scripts/ToolDemo.gd")
const Sfx = preload("res://scripts/Sfx.gd")
const Bar = preload("res://scripts/Bar.gd")

# Which numbers to compare live for each kind of component.
const STAT_ROWS = {
	"engine": [["POWER", "power", "%.0f"], ["TOP SPEED", "top", "%.1f"], ["ACCEL", "accel", "%.1f"], ["FUEL / S", "fuel_burn", "%.1f"]],
	"thruster": [["THRUST", "thrust_raw", "%.0f"], ["USABLE", "thrust", "%.0f"], ["TOP SPEED", "top", "%.1f"], ["TURN", "turn", "%.2f"]],
	"shield": [["SHIELD", "shield", "%.0f"], ["REGEN", "regen", "%.1f"]],
	"utility": [["MAGNET", "magnet", "%.1f"], ["FUEL", "fuel", "%.0f"], ["SCOOP", "scoop", "%.1f"]],
}

const CELL = 88.0
const PAL_W = 230.0
const INFO_W = 320.0
const TYPE_COLORS = {"mod": Color(0.25, 0.5, 0.95), "split": Color(0.6, 0.35, 0.95), "payload": Color(0.95, 0.5, 0.15), "upgrade": Color(0.3, 0.75, 0.4)}

var garage
var idx = -1
var pid = ""
var sub = {}
var gsize = Vector2i.ZERO
var placing = ""        # the palette card selected, ready to place
var sel_node = -2       # the placed card selected
var sel_preset = -1     # the preset selected (index into presets())
var bar = Bar.new()
var drag_from = -2
var mouse = Vector2.ZERO
var hover_node = -2
var hover_pal = -1
var t = 0.0
var base = {}       # ship stats when the editor opened
var base_part = {}  # the component as it was when the editor opened
var demo: SubViewport
var demo_rect: TextureRect

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	demo = ToolDemo.new()
	add_child(demo)
	demo_rect = TextureRect.new()
	demo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	demo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	demo_rect.texture = demo.get_texture()
	demo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(demo_rect)

func open(g, part_index: int) -> void:
	garage = g
	idx = part_index
	pid = garage.lo.parts[idx].id
	sub = Parts.sub_of(garage.lo.parts[idx]).duplicate(true)
	gsize = Parts.sub_size(pid)
	_deselect()
	drag_from = -2
	t = 0.0
	base = Parts.stats(garage.lo)
	base_part = garage.lo.parts[idx].duplicate(true)
	visible = true

func close() -> void:
	var p = garage.lo.parts[idx]
	p.sub = sub
	p.erase("cards")
	visible = false
	demo_rect.visible = false
	garage._commit()

func _process(delta):
	if visible:
		t += delta
		_fill_bar()
		queue_redraw()

func _deselect() -> void:
	placing = ""
	sel_node = -2
	sel_preset = -1

# What the action bar offers for the selection.
func _fill_bar() -> void:
	var m = garage.main
	var acts = []
	var title = ""
	var hint = ""
	var back = {"label": "DESELECT", "action": _deselect}
	if placing != "":
		var id = placing
		var pr = Parts.card_price(id)
		title = "%s  %d / %d" % [Parts.NODES[id].name.to_upper(), maxi(_free(id), 0), m.cards().get(id, 0)]
		if m.cards_sold_here():
			acts.append({"label": "BUY 1  ·  " + m._price_text(pr).to_upper(), "can": func(): return m.can_afford(pr),
				"action": func(): m.buy_cards({id: 1})})
		hint = "CLICK A FREE CELL TO PLACE IT" if _free(id) > 0 else ("NONE FREE" if m.cards_sold_here() else "NONE FREE  -  CARDS ARE SOLD AT OUTPOSTS")
		back.label = "PUT DOWN"
	elif sel_node >= 0 and sel_node < sub.nodes.size():
		var n = sel_node
		title = Parts.NODES[sub.nodes[n].id].name.to_upper() + " CARD"
		acts.append({"label": "REMOVE (DEL)", "action": func(): _remove_node(n); Sfx.play("scrap", -4.0, 1.3)})
		acts.append({"label": "CUT ITS WIRES", "can": sub.wires.any(func(w): return w[0] == n or w[1] == n),
			"action": func(): sub.wires = sub.wires.filter(func(w): return w[0] != n and w[1] != n)})
	elif sel_preset >= 0 and sel_preset < presets().size():
		var i = sel_preset
		var short = _preset_short(presets()[i])
		title = "PRESET  " + presets()[i].name.to_upper()
		acts.append({"label": "LOAD", "can": short.is_empty(), "action": func(): _load_preset(i)})
		if not short.is_empty() and m.cards_sold_here() and not _preset_locked(presets()[i]):
			var cost = 0
			for id in short:
				cost += Parts.card_price(id).credits * short[id]
			acts.append({"label": "BUY MISSING CARDS  ·  %d CR" % cost, "can": m.credits() >= cost, "action": func(): m.buy_cards(short)})
		acts.append({"label": "FORGET", "action": func(): _forget_preset(i)})
	else:
		title = "WIRING"
		acts.append({"label": "SAVE AS PRESET", "can": not sub.nodes.is_empty(), "action": _save_preset})
		acts.append({"label": "CLEAR", "can": not sub.nodes.is_empty(), "action": func(): sub = {"nodes": [], "wires": []}; Sfx.play("scrap", -4.0, 1.3)})
		hint = "PICK A CARD ON THE LEFT, THEN A CELL"
		back = {"label": "DONE", "action": close}
	bar.fill(title, acts, back, hint)

# ---------------------------------------------------------------- layout

func _panel() -> Rect2:
	var gw = gsize.x * CELL
	var gh = gsize.y * CELL
	var w = PAL_W + gw + 90.0 + INFO_W
	var h = maxf(maxf(gh + 330.0, 560.0), 110.0 + _palette().size() * 36.0 + 24.0 + PRESET_H)
	# Centred in what the action bar leaves.
	return Rect2((size.x - w) * 0.5, maxf(8.0, (size.y - Bar.RESERVED - h) * 0.5), w, h)

func _origin() -> Vector2:
	var pr = _panel()
	return Vector2(pr.position.x + PAL_W + 50.0, pr.position.y + 110.0)

func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(c) * CELL, Vector2(CELL, CELL))

func _cell_of(i: int) -> Vector2i:
	return Parts.core_cell(pid) if i == -1 else sub.nodes[i].cell

func _node_rect(i: int) -> Rect2:
	return _cell_rect(_cell_of(i)).grow(-12)

func _out_port(i: int, k: int) -> Vector2:
	var r = _node_rect(i)
	var n = Parts.node_outs("" if i == -1 else sub.nodes[i].id)
	return Vector2(r.end.x + 2, r.position.y + r.size.y * (k + 1) / (n + 1))

func _in_port(i: int) -> Vector2:
	var r = _node_rect(i)
	return Vector2(r.position.x - 2, r.get_center().y)

# Copies of a card not in use anywhere on the build (this part's grid as it
# stands in the editor).
func _free(id: String) -> int:
	var used = Parts.count_cards(garage.lo, idx)
	for nd in sub.nodes:
		if nd.id == id:
			used[id] = used.get(id, 0) + 1
	return garage.main.cards().get(id, 0) - used.get(id, 0)

func _palette() -> Array:
	return Parts.NODES.keys().filter(func(n): return Parts.node_allowed(pid, n))

func _pal_rect(i: int) -> Rect2:
	var pr = _panel()
	return Rect2(pr.position.x + 24, pr.position.y + 110 + i * 36, PAL_W - 40, 30)

func _info_rect() -> Rect2:
	var pr = _panel()
	return Rect2(pr.end.x - INFO_W - 10, pr.position.y + 80, INFO_W - 20, pr.size.y - 100)

func _demo_area() -> Rect2:
	var ir = _info_rect()
	return Rect2(ir.position.x + 10, ir.end.y - 200, ir.size.x - 20, 186)

# The ship's stats with this component wired the way it is right now.
func _live_stats() -> Dictionary:
	var lo = garage.lo.duplicate(true)
	lo.parts[idx].sub = sub
	lo.parts[idx].erase("cards")
	return Parts.stats(lo)

# The program as numbered steps in plain words: what the shot does, where
# each payload goes off and what flies on after it.
const PAYLOAD_WORDS = {
	"bomb": "BOMB goes off: a blast that breaks up to hard rock",
	"mini": "a small blast",
	"dig": "EXCAVATE goes off: a smaller blast that breaks deep rock",
	"cluster": "CLUSTER goes off: a small blast and 5 homing bomblets (other cards after it don't change them)",
	"gravity": "GRAVITY WELL opens: a few seconds of pull",
	"quench": "QUENCH goes off: lava and gas around it turn to rock",
}

static func explain(prog: Dictionary, kind: String, depth: int = 0, lead: String = "") -> Array:
	var out = []
	var pad = " ".repeat(lead.length())   # continuation lines line up under the step
	var mods = []
	for k in ["fast", "homing", "phase", "timer", "orbit"]:
		if prog.get(k, false):
			mods.append(Parts.NODES[k].name.to_lower())
	var with = (", " + ", ".join(mods)) if not mods.is_empty() else ""
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		out.append(lead + ("fires, then SPLITS into %d shots" % forks.size()) + with)
		for i in forks.size():
			out.append_array(explain(forks[i], kind, depth, pad + "  branch %d: " % (i + 1)))
		return out
	var what = {"laser": "beam", "rocket": "missile", "dropper": "bomb", "drill": "drill"}.get(kind, "shot")
	if depth == 0:
		out.append(lead + "fires a " + what + with)
	else:
		out.append(lead + "a new shot flies on from there" + with)
	var pay = prog.get("payload", "")
	if pay == "":
		if kind == "laser":
			out.append(pad + "  burns along the beam (nothing wired after the core)")
			return out
		pay = "bomb" if depth == 0 else "mini"
		out.append(pad + "  lands: " + PAYLOAD_WORDS[pay] + " (nothing wired: the default)")
	else:
		out.append(pad + "  lands: " + PAYLOAD_WORDS.get(pay, pay))
	var n = prog.get("power", 1)
	if n > 1:
		out[-1] += "  x%d: %s" % [n, {"cluster": "%d bomblets" % (5 * n), "gravity": "pulls %d times as long" % n}.get(prog.payload, "%d%% wider blast" % int(40 * (n - 1)))]
	var kids = prog.get("children", [])
	if not kids.is_empty():
		if depth >= 3:
			out.append(pad + "  (the chain stops here: three hops at most)")
		else:
			for c in kids:
				out.append_array(explain(c, kind, depth + 1, pad + "  then "))
	return out

func _describe(prog: Dictionary) -> String:
	var bits = []
	for k in ["homing", "phase", "fast", "timer", "orbit"]:
		if prog.get(k, false):
			bits.append(Parts.NODES[k].tag)
	var head = " ".join(bits)
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		var parts = []
		for f in forks:
			parts.append(_describe(f))
		return (head + " " if head != "" else "") + "SPLIT ( " + "  |  ".join(parts) + " )"
	# Missiles and bombs go off as a plain bomb by default; a beam just burns.
	var dflt = "" if Parts.PARTS[pid].kind == "laser" else "BMB"
	var pay = Parts.NODES[prog.payload].tag if prog.get("payload", "") != "" else dflt
	var out = head + (" " if head != "" and pay != "" else "") + pay
	if out == "":
		out = "BEAM"
	var kids = prog.get("children", [])
	if not kids.is_empty():
		var parts = []
		for c in kids:
			parts.append(_describe(c))
		out += " > " + "  |  ".join(parts)
	return out

# ---------------------------------------------------------------- presets

# Saved wirings, under the palette: the ones that fit this component (same
# family, cards allowed, fits the grid). Select one to load or forget it;
# save this wiring from the bar with nothing selected. Kept in the save as
# {name, family, part, sub}.
const PRESET_H = 236.0
const PRESETS_SHOWN = 6

func presets() -> Array:
	if not garage.main.save_data.has("programs"):
		garage.main.save_data.programs = []
	return garage.main.save_data.programs

func _fits(pr: Dictionary) -> bool:
	if pr.family != Parts.node_family(pid):
		return false
	for nd in pr.sub.nodes:
		if not Parts.node_allowed(pid, nd.id) or not Rect2i(Vector2i.ZERO, gsize).has_point(nd.cell):
			return false
	return true

func _compat() -> Array:
	var out = []
	for i in presets().size():
		if _fits(presets()[i]):
			out.append(i)
	return out.slice(-PRESETS_SHOWN)

func _presets_top() -> float:
	var pr = _panel()
	return pr.position.y + 110 + _palette().size() * 36 + 24

func _preset_rect(k: int) -> Rect2:
	var pr = _panel()
	return Rect2(pr.position.x + 24, _presets_top() + 14 + k * 34, PAL_W - 40, 30)

func _save_preset() -> void:
	if sub.nodes.is_empty():
		garage.main.notify("NOTHING WIRED TO SAVE", Color(1.0, 0.4, 0.3), "preset")
		return
	var n = presets().filter(func(p): return p.part == pid).size() + 1
	presets().append({"name": "%s %d" % [Parts.PARTS[pid].name, n], "family": Parts.node_family(pid), "part": pid, "sub": sub.duplicate(true)})
	while presets().size() > 24:
		presets().pop_front()
	garage.main.notify("PRESET SAVED  " + presets()[-1].name.to_upper(), Color.WHITE, "preset")
	Sfx.play("ui_select")
	garage.main.save_game()

# Cards you'd have to buy to load a preset here (this part's own are freed
# first): {id: how many}.
func _preset_short(pr: Dictionary) -> Dictionary:
	var need = {}
	for nd in pr.sub.nodes:
		need[nd.id] = need.get(nd.id, 0) + 1
	var elsewhere = Parts.count_cards(garage.lo, idx)
	var short = {}
	for id in need:
		var have = garage.main.cards().get(id, 0) - elsewhere.get(id, 0)
		if need[id] > have:
			short[id] = need[id] - have
	return short

func _preset_locked(pr: Dictionary) -> bool:
	return pr.sub.nodes.any(func(nd): return Parts.is_locked(Parts.NODES[nd.id], garage.main.unlocks()))

func _load_preset(i: int) -> void:
	var pr = presets()[i]
	var short = _preset_short(pr)
	if not short.is_empty():
		var names = []
		for id in short:
			names.append("%d %s" % [short[id], Parts.NODES[id].name])
		garage.main.notify("MISSING CARDS  " + ", ".join(names).to_upper(), Color(1.0, 0.4, 0.3), "preset")
		return
	sub = pr.sub.duplicate(true)
	sel_node = -2
	Sfx.play("clunk", -4.0, 1.4)

func _forget_preset(i: int) -> void:
	garage.main.notify("PRESET REMOVED  " + presets()[i].name.to_upper(), Color(0.8, 0.8, 0.8), "preset")
	presets().remove_at(i)
	sel_preset = -1
	garage.main.save_game()

# ---------------------------------------------------------------- graph

func _node_at(c: Vector2i) -> int:
	if c == Parts.core_cell(pid):
		return -1
	for i in sub.nodes.size():
		if sub.nodes[i].cell == c:
			return i
	return -2

# A new card joins the end of the chain: follow the core's first output to
# the last card and wire that to it, if it has an output free. Cards placed
# one after another make a series in the order you put them down; drag
# wires (or right-click them away) to do anything else.
func _auto_wire(i: int) -> void:
	var cur = -1
	var seen = []
	while true:
		var outs = Parts.wires_from(sub, cur)
		if outs.is_empty() or seen.has(cur):
			break
		seen.append(cur)
		cur = outs[0]
	if cur == i:
		return
	var free = Parts.node_outs("" if cur == -1 else sub.nodes[cur].id) - Parts.wires_from(sub, cur).size()
	if free > 0 and not _has_input(i):
		sub.wires.append([cur, i])
		Sfx.play("wire")

func _has_input(i: int) -> bool:
	for w in sub.wires:
		if w[1] == i:
			return true
	return false

func _reaches(from: int, target: int) -> bool:
	var todo = [from]
	var seen = []
	while not todo.is_empty():
		var n = todo.pop_back()
		if n == target:
			return true
		for o in Parts.wires_from(sub, n):
			if not seen.has(o):
				seen.append(o)
				todo.append(o)
	return false

func _remove_node(i: int) -> void:
	sel_node = -2
	sub.nodes.remove_at(i)
	var keep = []
	for w in sub.wires:
		if w[0] == i or w[1] == i:
			continue
		keep.append([w[0] - (1 if w[0] > i else 0), w[1] - (1 if w[1] > i else 0)])
	sub.wires = keep

func _wire_near(p: Vector2) -> int:
	for k in sub.wires.size():
		var w = sub.wires[k]
		var pts = _wire_points(w[0], w[1], _port_index(w[0], w[1]))
		for s in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[s], pts[s + 1]).distance_to(p) < 8.0:
				return k
	return -1

func _port_index(from: int, to: int) -> int:
	var outs = Parts.wires_from(sub, from)
	return maxi(outs.find(to), 0)

func _wire_points(from: int, to: int, k: int) -> PackedVector2Array:
	var a = _out_port(from, k)
	var b = _in_port(to)
	var mx = (a.x + b.x) * 0.5 if b.x > a.x + 20 else a.x + 18
	return PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b])

# ---------------------------------------------------------------- input

func _cell_under(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - _origin()) / CELL).floor())

func _gui_input(event):
	if event is InputEventMouseMotion:
		mouse = event.position
		bar.motion(size, mouse)
		var c = _cell_under(mouse)
		hover_node = _node_at(c) if Rect2i(Vector2i.ZERO, gsize).has_point(c) else -2
		hover_pal = -1
		var pal = _palette()
		for i in pal.size():
			if _pal_rect(i).has_point(mouse):
				hover_pal = i
	elif event is InputEventMouseButton:
		var pos = event.position
		var c = _cell_under(pos)
		var inside = Rect2i(Vector2i.ZERO, gsize).has_point(c)
		accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if bar.click(size, pos):
				return
			var comp = _compat()
			for k in comp.size():
				if _preset_rect(k).has_point(pos):
					_deselect()
					sel_preset = comp[k]
					Sfx.play("ui_move", -6.0)
					if event.double_click:
						_load_preset(comp[k])
					return
			var pal = _palette()
			for i in pal.size():
				if _pal_rect(i).has_point(pos):
					if not Parts.is_locked(Parts.NODES[pal[i]], garage.main.unlocks()) and placing != pal[i]:
						_deselect()
						placing = pal[i]
						Sfx.play("ui_move", -6.0)
					return
			# Ports first: start a wire.
			for i in range(-1, sub.nodes.size()):
				var outs = Parts.node_outs("" if i == -1 else sub.nodes[i].id)
				for k in outs:
					if _out_port(i, k).distance_to(pos) < 12.0 and Parts.wires_from(sub, i).size() < outs:
						drag_from = i
						return
			var n = _node_at(c) if inside else -2
			if n >= 0:
				_deselect()
				sel_node = n
				Sfx.play("ui_move", -6.0)
			elif placing != "" and inside and n == -2:
				if _free(placing) <= 0:
					garage.main.notify("NO " + Parts.NODES[placing].name.to_upper() + " CARDS FREE", Color(1.0, 0.4, 0.3), "cards")
					return
				sub.nodes.append({"id": placing, "cell": c})
				_auto_wire(sub.nodes.size() - 1)
				Sfx.play("clunk", -4.0, 1.4)
			else:
				_deselect()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and drag_from != -2:
			var target = _node_at(c) if inside else -2
			if target >= 0 and target != drag_from and not _has_input(target) and not _reaches(target, drag_from):
				sub.wires.append([drag_from, target])
				Sfx.play("wire")
			drag_from = -2
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var n = _node_at(c) if inside else -2
			if n >= 0 and _node_rect(n).has_point(pos):
				_remove_node(n)
				Sfx.play("scrap", -4.0, 1.3)
			else:
				var w = _wire_near(pos)
				if w >= 0:
					sub.wires.remove_at(w)
				else:
					_deselect()

func _unhandled_key_input(event):
	if not visible or not event.pressed or event.echo:
		return
	if bar.key(event):
		get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if placing != "" or sel_node >= 0 or sel_preset >= 0:
				_deselect()
			else:
				Sfx.play("ui_back")
				close()
		KEY_DELETE, KEY_BACKSPACE:
			if sel_node >= 0 and sel_node < sub.nodes.size():
				_remove_node(sel_node)
				Sfx.play("scrap", -4.0, 1.3)
		_:
			return
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- drawing

func _draw_node(i: int, live: bool) -> void:
	var r = _node_rect(i)
	var id = "" if i == -1 else sub.nodes[i].id
	var col: Color
	var tag: String
	if i == -1:
		var def = Parts.PARTS[pid]
		col = Parts.MECHANICS[def.mech].accent.darkened(0.2) if def.mech != "" else Color(0.6, 0.62, 0.66)
		tag = "CORE"
	else:
		var nd = Parts.NODES[id]
		col = TYPE_COLORS[nd.type]
		tag = nd.tag
	if not live:
		col = col.darkened(0.6)
	var hot = i == hover_node
	Ui.segment(self, Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.4), 8.0)
	Ui.segment(self, r, col.lightened(0.2) if hot else col, 8.0)
	if i >= 0 and i == sel_node:
		draw_rect(r.grow(4), Ui.ink(Color.WHITE), false, 3.0)
	Ui.text(self, r.position + Vector2(0, r.size.y * 0.5 + 8), tag, 20, Color.WHITE if live else Color(1, 1, 1, 0.5), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if i != -1:
		draw_circle(_in_port(i), 6.0, Color(0.9, 0.9, 0.95))
	for k in Parts.node_outs(id):
		draw_circle(_out_port(i, k), 7.0, Color(1, 1, 1) if live else Color(0.6, 0.6, 0.6))
		draw_circle(_out_port(i, k), 3.5, col)

func _draw():
	Ui.begin()
	_draw_screen()
	Ui.scanlines(self, Rect2(Vector2.ZERO, size))
	Ui.end()

func _draw_screen():
	if pid == "":
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var pr = _panel()
	Ui.segment(self, pr, Color(0.06, 0.065, 0.075, 0.97), 16.0)
	Ui.segment(self, Rect2(pr.position, Vector2(pr.size.x, 54)), Ui.INK, 16.0)
	Ui.segment(self, Rect2(pr.position.x, pr.position.y + 54, pr.size.x, 4), Ui.HILITE, 0.0)
	Ui.text(self, pr.position + Vector2(30, 38), Parts.PARTS[pid].name.to_upper(), 28, Color.WHITE, true)
	# Palette.
	var pal = _palette()
	for i in pal.size():
		var nd = Parts.NODES[pal[i]]
		var r = _pal_rect(i)
		if Parts.is_locked(nd, garage.main.unlocks()):
			Ui.segment(self, r, Color(0.14, 0.15, 0.17), 6.0)
			Ui.text(self, r.position + Vector2(14, 21), "? ? ?", 15, Color(0.4, 0.42, 0.46), true)
			continue
		var on = placing == pal[i]
		Ui.segment(self, r, Ui.HILITE if on else (Color.WHITE if i == hover_pal else Ui.PAPER), 6.0)
		draw_rect(Rect2(r.position.x + 4, r.position.y + 5, 5, r.size.y - 10), TYPE_COLORS[nd.type])
		Ui.text(self, r.position + Vector2(18, 21), nd.name, 15, Color.WHITE if on else Ui.INK, on)
		var free = _free(pal[i])
		Ui.text(self, r.position + Vector2(0, 21), "%d / %d" % [maxi(free, 0), garage.main.cards().get(pal[i], 0)], 13,
			Color.WHITE if on else (Color(0.8, 0.25, 0.2) if free <= 0 else Ui.DIM), true, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10)
	# Presets.
	var ptop = _presets_top()
	Ui.text(self, Vector2(_preset_rect(0).position.x, ptop), "PRESETS", 13, Ui.DIM, true)
	var comp = _compat()
	for k in comp.size():
		var p = presets()[comp[k]]
		var r = _preset_rect(k)
		var on = comp[k] == sel_preset
		Ui.segment(self, r, Ui.HILITE if on else Ui.PAPER, 6.0)
		if r.has_point(mouse) and not on:
			draw_rect(Rect2(r.position.x, r.position.y, 4, r.size.y), Ui.ink(Color.WHITE) if Ui.terminal() else Ui.HILITE)
		Ui.text(self, r.position + Vector2(12, 20), p.name, 14, Color.WHITE if on else Ui.INK, true)
		Ui.text(self, r.position + Vector2(0, 20), "%d" % p.sub.nodes.size(), 12, Color.WHITE if on else Ui.DIM, true, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10)
	if comp.is_empty():
		Ui.text(self, _preset_rect(0).position + Vector2(4, 20), "none saved for this kind yet", 13, Ui.DIM)
	# Grid.
	var o = _origin()
	draw_rect(Rect2(o - Vector2(10, 10), Vector2(gsize) * CELL + Vector2(20, 20)), Color(0.02, 0.025, 0.03))
	for y in gsize.y:
		for x in gsize.x:
			var cr = _cell_rect(Vector2i(x, y)).grow(-3)
			draw_rect(cr, Color(1, 1, 1, 0.05))
			if placing != "" and _node_at(Vector2i(x, y)) == -2 and cr.has_point(mouse):
				draw_rect(cr, Color(0.35, 0.85, 0.4, 0.3))
	var live = Parts.live_nodes(sub)
	# Wires under the nodes.
	for w in sub.wires:
		var pts = _wire_points(w[0], w[1], _port_index(w[0], w[1]))
		var on = w[0] == -1 or live.has(w[0])
		draw_polyline(pts, Color(0, 0, 0, 0.6), 7.0)
		draw_polyline(pts, Color(0.95, 0.95, 1.0) if on else Color(0.45, 0.45, 0.5), 3.0)
	if drag_from != -2:
		draw_line(_out_port(drag_from, Parts.wires_from(sub, drag_from).size()), mouse, Color(1, 1, 1, 0.8), 3.0)
	_draw_node(-1, true)
	for i in sub.nodes.size():
		_draw_node(i, live.has(i))
	_draw_info(pal, live)
	_draw_effect()
	bar.draw(self, size)

# Right-hand column: what the hovered node (or the component) does.
func _draw_info(pal: Array, live: Array) -> void:
	var ir = _info_rect()
	draw_rect(ir, Color(0.02, 0.025, 0.03))
	var id = ""
	if hover_pal >= 0 and not Parts.is_locked(Parts.NODES[pal[hover_pal]], garage.main.unlocks()):
		id = pal[hover_pal]
	elif hover_node >= 0:
		id = sub.nodes[hover_node].id
	elif placing != "":
		id = placing
	var x = ir.position.x + 20
	var y = ir.position.y + 40
	var wrap = ir.size.x - 40
	var font = Ui.font(false)
	if id == "":
		var def = Parts.PARTS[pid]
		Ui.text(self, Vector2(x, y), "CORE", 14, Ui.DIM, true)
		Ui.text(self, Vector2(x, y + 32), def.name.to_upper(), 24, Color.WHITE, true)
		draw_multiline_string(font, Vector2(x, y + 66), Parts.DESC.get(pid, ""), HORIZONTAL_ALIGNMENT_LEFT, wrap, 17, -1, Color(0.85, 0.87, 0.9))
		draw_multiline_string(font, Vector2(x, y + 150), "%d node%s wired to the core" % [live.size(), "" if live.size() == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, wrap, 15, -1, Ui.DIM)
		if Parts.node_family(pid) == "tool" and Parts.PARTS[pid].kind != "drill":
			# What the wiring does, step by step.
			var p = garage.lo.parts[idx].duplicate(true)
			p.sub = sub
			p.erase("cards")
			var steps = explain(Parts.program_of(p), Parts.PARTS[pid].kind)
			Ui.text(self, Vector2(x, y + 186), "WHAT IT DOES", 13, Ui.DIM, true)
			var ly = y + 206
			var n = 1
			for line in steps:
				if ly > _demo_area().position.y - 18:
					break
				var shown = ("%d. " % n + line) if not line.begins_with(" ") else ("  " + line)
				draw_multiline_string(font, Vector2(x, ly), shown, HORIZONTAL_ALIGNMENT_LEFT, wrap, 14, -1, Color(0.88, 0.9, 0.93))
				ly += 20 * maxi(1, ceili(font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / maxf(wrap, 1.0)))
				if not line.begins_with(" "):
					n += 1
		return
	var nd = Parts.NODES[id]
	var col = TYPE_COLORS[nd.type]
	var chip = {"mod": "MODIFIER", "split": "SPLIT", "payload": "PAYLOAD", "upgrade": "UPGRADE"}[nd.type]
	var cw = Ui.font(true).get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24
	Ui.segment(self, Rect2(x, y - 18, cw, 24), col, 6.0)
	Ui.text(self, Vector2(x + 12, y - 1), chip, 13, Color.WHITE, true)
	Ui.text(self, Vector2(x, y + 36), nd.name.to_upper(), 26, Color.WHITE, true)
	draw_multiline_string(font, Vector2(x, y + 72), nd.desc, HORIZONTAL_ALIGNMENT_LEFT, wrap, 18, -1, Color(0.88, 0.9, 0.93))
	var how = {"mod": "Changes the shot it's on, up to the next payload. Wired after a payload, it changes the new shot that flies on from there.",
		"split": "One shot becomes two. Each branch keeps the mods so far, then goes its own way. Wire both outputs.",
		"payload": "Goes off where its shot lands. The same payload wired straight on merges into one bigger one (Bomb > Bomb: a 40% wider blast; up to four). A different card after it launches a new shot from that spot, flying on (three hops at most).",
		"upgrade": "Counts once it's wired to the core."}[nd.type]
	if id == "cluster":
		how += " Cluster's own bomblets are fixed: other cards after it don't change them (more Clusters in a row add bomblets)."
	draw_multiline_string(font, Vector2(x, y + 150), how, HORIZONTAL_ALIGNMENT_LEFT, wrap, 15, -1, Ui.DIM)
	if hover_node >= 0 and not live.has(hover_node):
		Ui.text(self, Vector2(x, y + 210), "NOT WIRED TO THE CORE", 14, Color(1.0, 0.45, 0.35), true)

# Under the grid: what the wiring does to the ship, live. Tools also get a
# one-line read-out of their program; the test range runs it for real.
func _draw_effect() -> void:
	var fam = Parts.node_family(pid)
	var o = _origin()
	var y = o.y + gsize.y * CELL + 44
	var now = _live_stats()
	if fam == "tool":
		var p = garage.lo.parts[idx].duplicate(true)
		p.sub = sub
		p.erase("cards")
		var kind = Parts.PARTS[pid].kind
		var label = {"laser": "BEAM", "rocket": "MISSILE", "dropper": "BOMB", "drill": "DRILL"}.get(kind, "")
		var prog = Parts.program_of(p)
		var line = label + "  " + _describe(prog)
		if kind == "drill" and not prog.get("orbit", false):
			line = "DRILL  (wire ORB to swing it as a wrecking ball)"
		Ui.text(self, Vector2(o.x, y), "PROGRAM", 13, Ui.DIM, true)
		draw_multiline_string(Ui.font(true), Vector2(o.x, y + 24), line, HORIZONTAL_ALIGNMENT_LEFT, gsize.x * CELL, 17, -1, Color.WHITE)
		y += 70
		demo.show_tool(p)
	# [label, before, after, format, lower is better]
	var rows = []
	for r in STAT_ROWS.get(fam, []):
		rows.append([r[0], base.get(r[1], 0.0), now.get(r[1], 0.0), r[2], r[1] in ["fuel_burn", "mass"]])
	if fam == "tool":
		var now_part = garage.lo.parts[idx].duplicate(true)
		now_part.sub = sub
		now_part.erase("cards")
		var pa = Parts.program_of(base_part)
		var pb = Parts.program_of(now_part)
		var def = Parts.PARTS[pid]
		var yn = func(v): return 1.0 if v else 0.0
		match def.kind:
			"drill":
				rows.append(["TIER", def.tier, def.tier, "%d", false])
				rows.append(["CUTTING", def.power, def.power, "%.1f", false])
				rows.append(["WRECKING BALL", yn.call(pa.get("orbit", false)), yn.call(pb.get("orbit", false)), "%s", false])
			"laser":
				rows.append(["BEAMS", _shots(pa), _shots(pb), "%d", false])
				rows.append(["DAMAGE / S", def.dps * (1.0 if _shots(pa) == 1 else 0.7), def.dps * (1.0 if _shots(pb) == 1 else 0.7), "%.1f", false])
				rows.append(["REACH", _reach(pa), _reach(pb), "%.0f m", false])
				rows.append(["PHASING", _count(pa, "phase"), _count(pb, "phase"), "%d", false])
				rows.append(["BLASTS / PULSE", _laser_blasts(pa), _laser_blasts(pb), "%d", false])
			_:
				rows.append(["SHOTS", _shots(pa), _shots(pb), "%d", false])
				rows.append(["BLASTS", _blasts(pa), _blasts(pb), "%d", false])
				rows.append(["REACH", _reach(pa), _reach(pb), "%.0f m", false])
				rows.append(["HOMING", yn.call(_homes(pa)), yn.call(_homes(pb)), "%s", false])
	var x = o.x
	for r in rows:
		var a = float(r[1])
		var b = float(r[2])
		var d = b - a
		var better = d < 0.0 if r[4] else d > 0.0
		var col = Color.WHITE if absf(d) < 0.001 else (Color(0.45, 1.0, 0.5) if better else Color(1.0, 0.45, 0.35))
		Ui.text(self, Vector2(x, y), r[0], 13, Ui.DIM, true)
		var fa = ("yes" if a > 0.5 else "no") if r[3] == "%s" else (r[3] % (int(a) if r[3] == "%d" else a))
		var fb = ("yes" if b > 0.5 else "no") if r[3] == "%s" else (r[3] % (int(b) if r[3] == "%d" else b))
		Ui.text(self, Vector2(x, y + 26), fa + "  >  " + fb, 18, col, true)
		x += 150
		if x + 130 > o.x + gsize.x * CELL + 20:
			x = o.x
			y += 56
	demo_rect.visible = fam == "tool"
	var da = _demo_area()
	demo_rect.position = da.position
	demo_rect.size = da.size
	if fam == "tool":
		draw_rect(da.grow(2), Color(0.3, 0.32, 0.36))

# Read-outs of a tool program for the live numbers.
func _shots(prog: Dictionary) -> int:
	var forks = prog.get("forks", [])
	if forks.is_empty():
		return 1
	var n = 0
	for f in forks:
		n += _shots(f)
	return n

func _blasts(prog: Dictionary) -> int:
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		var n = 0
		for f in forks:
			n += _blasts(f)
		return n
	var n = 6 if prog.get("payload", "") == "cluster" else 1
	for c in prog.get("children", []):
		n += _blasts(c)
	return n

func _reach(prog: Dictionary) -> float:
	var kind = Parts.PARTS[pid].kind
	var fast = prog.get("fast", false)
	if kind == "laser":
		return Parts.PARTS[pid].range * (1.6 if fast else 1.0)
	if kind == "rocket":
		return 34.0 * 2.5 * (1.8 if fast else 1.0)
	if kind == "drill" and prog.get("orbit", false):
		return 3.2
	return 0.0

func _homes(prog: Dictionary) -> bool:
	if prog.get("homing", false):
		return true
	for f in prog.get("forks", []) + prog.get("children", []):
		if _homes(f):
			return true
	return prog.get("payload", "") == "cluster"

# Beams with a payload, counting through forks.
func _laser_blasts(prog: Dictionary) -> int:
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		var n = 0
		for f in forks:
			n += _laser_blasts(f)
		return n
	return 0 if prog.get("payload", "") == "" else _blasts(prog)

# Leaf shots/beams carrying a mod.
func _count(prog: Dictionary, mod: String) -> int:
	var forks = prog.get("forks", [])
	if not forks.is_empty():
		var n = 0
		for f in forks:
			n += _count(f, mod)
		return n
	return 1 if prog.get(mod, false) else 0
