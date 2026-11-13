class_name Txt
extends RefCounted
## UI text. Uses real (open-licensed, see assets/fonts/OFL-*.txt) fonts rendered at
## the window's resolution, so it stays smooth even though the game draws at 480x270.
## `scale` keeps the old pixel-font sizing: 1 = small labels, 2 = headings, 4 = titles.

const SIZES := {0: 5, 1: 7, 2: 12, 3: 18, 4: 30}
## Glyphs are laid out at Q times the size and drawn scaled down, so spacing isn't
## rounded to whole 480x270 pixels (that made "MENU" look like "ME NU").
const Q := 4.0

static var _body: Font
static var _bold: Font
static var _title: Font


static func _fonts() -> void:
	if _body:
		return
	_body = _load("res://assets/fonts/ChakraPetch-SemiBold.ttf")
	_bold = _load("res://assets/fonts/ChakraPetch-Bold.ttf")
	_title = _load("res://assets/fonts/RussoOne-Regular.ttf")


static func _load(path: String) -> Font:
	var f := load(path) as FontFile
	if f == null:
		return ThemeDB.fallback_font
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


static func font(scale := 1) -> Font:
	_fonts()
	if scale >= 3:
		return _title
	return _bold if scale == 2 else _body


static func size(scale := 1) -> int:
	return SIZES.get(scale, 7 * scale)


static func width(s: String, scale := 1) -> float:
	return font(scale).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size(scale) * Q)).x / Q


static func _str(ci: CanvasItem, f: Font, base: Vector2, s: String, sz: int, color: Color, outline := 0) -> void:
	ci.draw_set_transform(base, 0.0, Vector2.ONE / Q)
	if outline > 0:
		ci.draw_string_outline(f, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sz * Q), int(outline * Q), color)
	else:
		ci.draw_string(f, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sz * Q), color)
	ci.draw_set_transform(Vector2.ZERO)


## `pos` is the top-left of the capital letters (same as the old pixel font).
static func draw(ci: CanvasItem, pos: Vector2, s: String, color: Color, scale := 1, shadow := true) -> void:
	var f := font(scale)
	var sz := size(scale)
	var base := pos + Vector2(0, roundf(sz * 0.72))
	if shadow:
		var off := Vector2(0.7, 0.7) * (1.0 if scale < 3 else 2.0)
		_str(ci, f, base + off, s, sz, Color(0, 0, 0, color.a * 0.75))
	_str(ci, f, base, s, sz, color)


static func draw_outlined(ci: CanvasItem, pos: Vector2, s: String, color: Color, scale := 1, outline := Color(0, 0, 0, 0.85)) -> void:
	var f := font(scale)
	var sz := size(scale)
	var base := pos + Vector2(0, roundf(sz * 0.72))
	_str(ci, f, base, s, sz, Color(outline, outline.a * color.a), maxi(1, sz / 6))
	_str(ci, f, base, s, sz, color)


static func draw_centered(ci: CanvasItem, cx: float, y: float, s: String, color: Color, scale := 1, shadow := true) -> void:
	draw(ci, Vector2(cx - width(s, scale) / 2.0, y), s, color, scale, shadow)
