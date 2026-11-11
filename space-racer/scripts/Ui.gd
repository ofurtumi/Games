extends RefCounted

# Shared UI look: fonts and the slanted segment shape every panel uses.

const INK = Color(0.08, 0.09, 0.11)
const PAPER = Color(0.9, 0.91, 0.93)
const HILITE = Color(0.16, 0.38, 0.82)
const DIM = Color(0.55, 0.58, 0.63)
const SKEW = 14.0

static var _fonts = {}

# A condensed italic sans if the system has one, else the default font.
static func font(bold: bool = false) -> Font:
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
	ci.draw_colored_polygon(PackedVector2Array([
		r.position + Vector2(skew, 0), Vector2(r.end.x + skew, r.position.y),
		r.end - Vector2(skew, 0) + Vector2(0, 0), Vector2(r.position.x - skew, r.end.y),
	]), color)

static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color, bold: bool = false, align = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1) -> void:
	ci.draw_string(font(bold), pos, s, align, width, size, color)

static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
