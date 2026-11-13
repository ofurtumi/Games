extends RefCounted

# Shared UI look: fonts and the slanted segment shape every panel uses.
#
# Two styles (the Interface setting): "classic" (blue and white slabs, a
# condensed italic) and "terminal" (green phosphor on dark, monospace,
# square boxes and scanlines). Screens that should follow the setting wrap
# their _draw in begin() / end(); the race and expedition HUDs don't, so they
# stay classic. Inside, segment() and text() swap the classic palette for
# the terminal one.

const INK = Color(0.08, 0.09, 0.11)
const PAPER = Color(0.9, 0.91, 0.93)
const HILITE = Color(0.16, 0.38, 0.82)
const DIM = Color(0.55, 0.58, 0.63)
const SKEW = 14.0

# Terminal palette.
const T_BG = Color(0.008, 0.03, 0.012)
const T_PANEL = Color(0.03, 0.1, 0.045)
const T_SEL = Color(0.1, 0.38, 0.15)
const T_GREEN = Color(0.35, 1.0, 0.45)
const T_MID = Color(0.22, 0.62, 0.3)
const T_EDGE = Color(0.16, 0.45, 0.22)

static var style = "terminal"   # the setting
static var _on = false          # inside a begin() / end()

static func begin() -> void:
	_on = style == "terminal"

static func end() -> void:
	_on = false

static func terminal() -> bool:
	return _on

static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.06

# For screens' own rects: the terminal version of a fill colour.
static func fill(c: Color) -> Color:
	return _fill(c) if _on else c

static func _grey(c: Color) -> bool:
	return absf(c.r - c.g) < 0.07 and absf(c.g - c.b) < 0.09

static func _fill(c: Color) -> Color:
	if _near(c, HILITE):
		return Color(T_SEL, c.a)
	var lum = (c.r + c.g + c.b) / 3.0
	if _grey(c):
		if lum > 0.6:
			return Color(T_PANEL, c.a)
		if lum > 0.25:
			return Color(0.015, 0.05, 0.025, c.a)   # greyed out: darker than a panel
		return Color(T_BG, c.a)
	if lum < 0.2:
		return Color(T_BG, c.a)
	# A coloured chip (amber rule, red warning...): dark, its colour kept as
	# the border (see segment()).
	return Color(T_BG, c.a)

static func ink(c: Color) -> Color:
	return _ink(c) if _on else c

static func _ink(c: Color) -> Color:
	if _near(c, INK) or _near(c, Color.WHITE) or _near(c, PAPER):
		return Color(T_GREEN, c.a)
	if _grey(c):
		return Color(T_MID if (c.r + c.g + c.b) / 3.0 > 0.45 else T_EDGE, c.a)
	return c

# Faint scanlines over a screen (terminal style only).
static func scanlines(ci: CanvasItem, r: Rect2) -> void:
	if not _on:
		return
	var y = r.position.y
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0, 0, 0, 0.18), 1.0)
		y += 3.0

static var _fonts = {}

# A condensed italic sans if the system has one, else the default font.
static func font(bold: bool = false) -> Font:
	if _on:
		if not _fonts.has("mono"):
			var m = SystemFont.new()
			m.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New", "monospace"])
			_fonts["mono"] = m
		return _fonts["mono"]
	var key = "b" if bold else "r"
	if not _fonts.has(key):
		var f = SystemFont.new()
		f.font_names = PackedStringArray(["Eurostile", "Microgramma", "Avenir Next Condensed", "DIN Condensed", "Futura", "Helvetica Neue", "Arial"])
		f.font_italic = true
		f.font_weight = 700 if bold else 500
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_fonts[key] = f
	return _fonts[key]

# Parallelogram leaning right: the basic panel shape.
static func segment(ci: CanvasItem, r: Rect2, color: Color, skew: float = SKEW) -> void:
	if _on:
		# Square boxes, a thin phosphor edge.
		ci.draw_rect(r, _fill(color))
		var chip = not _grey(color) and not _near(color, HILITE) and (color.r + color.g + color.b) / 3.0 >= 0.2
		if chip:
			ci.draw_rect(r, color, false, 2.0)
		elif r.size.y > 6.0 and color.a > 0.3:
			ci.draw_rect(r, Color(T_EDGE, color.a), false, 1.0)
		return
	ci.draw_colored_polygon(PackedVector2Array([
		r.position + Vector2(skew, 0), Vector2(r.end.x + skew, r.position.y),
		r.end - Vector2(skew, 0) + Vector2(0, 0), Vector2(r.position.x - skew, r.end.y),
	]), color)

static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color, bold: bool = false, align = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1) -> void:
	if _on:
		# Monospace runs wide: a size down keeps labels in their boxes.
		ci.draw_string(font(bold), pos, s, align, width, maxi(9, int(size * 0.84)), _ink(color))
		return
	ci.draw_string(font(bold), pos, s, align, width, size, color)

# How wide text() draws `s` under the Interface setting: for layout worked out
# away from a _draw (hit tests), where begin() isn't in force.
static func measure(s: String, size: int, bold: bool = false) -> float:
	var was = _on
	_on = style == "terminal"
	var w = font(bold).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(size * 0.84)) if _on else size).x
	_on = was
	return w

static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
