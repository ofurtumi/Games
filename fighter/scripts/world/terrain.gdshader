shader_type canvas_item;
// Draws the whole destructible map from a tiny per-cell data texture:
//   R = solid tile atlas column + 1 (0 = none)
//   G = background wall atlas column + 1
//   B = flags: 1 ladder, 2|4 damage stage, 8 platform, 16 chippable, 32 dirt, 64 glass
// Everything else (lit edges, grass, chipped corners, cracks, wall shadows) is computed here.

uniform sampler2D cells : filter_nearest;
uniform sampler2D tiles : filter_nearest;
uniform vec2 map_cells;
uniform int ladder_col;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

ivec4 cell(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(map_cells.x) || c.y >= int(map_cells.y)) {
		return ivec4(0);
	}
	return ivec4(round(texelFetch(cells, c, 0) * 255.0));
}

bool solid_at(ivec2 c) {
	ivec4 d = cell(c);
	return d.r > 0 && (d.b & 8) == 0;
}

vec4 tex(int col, vec2 wp) {
	return texelFetch(tiles, ivec2(col * 16 + int(mod(wp.x, 16.0)), int(mod(wp.y, 16.0))), 0);
}

bool crack(ivec2 c, ivec2 l, int stage) {
	vec2 cf = vec2(c);
	float x0 = 1.0 + floor(hash(cf) * 6.0);
	float x = x0 + round(sin(float(l.y) * 1.3 + hash(cf + 3.0) * 6.0) * 1.2);
	bool a = abs(float(l.x) - x) < 0.5 && (stage == 2 || (l.y > 1 && l.y < 6));
	float y0 = 1.0 + floor(hash(cf + 9.0) * 6.0);
	float y = y0 + round(sin(float(l.x) * 1.1 + hash(cf + 5.0) * 6.0) * 1.0);
	bool b = stage == 2 && abs(float(l.y) - y) < 0.5 && l.x > 2;
	return a || b;
}

void fragment() {
	vec2 wp = floor(UV * map_cells * 8.0);
	ivec2 c = ivec2(floor(wp / 8.0));
	ivec2 l = ivec2(wp) - c * 8;
	ivec4 d = cell(c);
	int fl = d.b;
	bool is_solid = d.r > 0 && (fl & 8) == 0;
	vec4 col = vec4(0.0);

	if (d.g > 0) {
		vec4 b = tex(d.g - 1, wp);
		float lum = (b.r + b.g + b.b) / 3.0;
		b.rgb = mix(b.rgb, vec3(lum), 0.35);
		float k = 0.36;
		ivec4 up = cell(c + ivec2(0, -1));
		if (up.r > 0) k -= max(0.0, float(3 - l.y) * 0.035);
		if (solid_at(c + ivec2(-1, 0))) k -= max(0.0, float(2 - l.x) * 0.03);
		if (solid_at(c + ivec2(1, 0))) k -= max(0.0, float(l.x - 5) * 0.03);
		col = vec4(b.r * k, b.g * k, b.b * k * 1.08, 1.0);
	}
	if ((fl & 1) != 0) {
		vec4 lp = texelFetch(tiles, ivec2(ladder_col * 16 + l.x, l.y), 0);
		if (lp.a > 0.0) col = lp;
	}
	if (!is_solid && l.y == 7) {
		ivec4 below = cell(c + ivec2(0, 1));
		if (below.r > 0 && (below.b & 32) != 0 && hash(wp) < 0.45) {
			col = hash(wp + vec2(0.0, 7.0)) < 0.5 ? vec4(0.36, 0.62, 0.26, 1.0) : vec4(0.28, 0.5, 0.2, 1.0);
		}
	}
	if (d.r > 0 && (fl & 8) != 0) {
		vec4 pp = texelFetch(tiles, ivec2((d.r - 1) * 16 + int(mod(wp.x, 16.0)), l.y), 0);
		if (pp.a > 0.0) col = pp;
	} else if (is_solid) {
		bool ou = !solid_at(c + ivec2(0, -1));
		bool od = !solid_at(c + ivec2(0, 1));
		bool ol = !solid_at(c + ivec2(-1, 0));
		bool orr = !solid_at(c + ivec2(1, 0));
		bool chip = (fl & 16) != 0;
		bool edge = (ou && l.y == 0) || (od && l.y == 7) || (ol && l.x == 0) || (orr && l.x == 7);
		bool corner = (ou || od) && (ol || orr) && (l.x == 0 || l.x == 7) && (l.y == 0 || l.y == 7);
		if (!(chip && ((edge && hash(wp) < 0.14) || corner))) {
			vec4 t = tex(d.r - 1, wp);
			float f = 1.0;
			if (ou && l.y == 0) f = 1.3;
			else if (ou && l.y == 1) f = 1.12;
			if (od && l.y == 7) f *= 0.55;
			else if (od && l.y == 6) f *= 0.8;
			if (orr && l.x == 7) f *= 0.7;
			if (ol && l.x == 0) f *= 0.88;
			t.rgb *= f;
			if ((fl & 32) != 0 && ou && float(l.y) <= 1.0 + floor(hash(vec2(wp.x, 3.0)) * 2.0)) {
				t = l.y == 0 ? vec4(0.36, 0.62, 0.26, 1.0) : vec4(0.27, 0.48, 0.2, 1.0);
			}
			int stage = (fl >> 1) & 3;
			if (stage > 0 && crack(c, l, stage)) t.rgb *= 0.45;
			col = (t.a >= 1.0 || col.a == 0.0) ? t : vec4(mix(col.rgb, t.rgb, t.a), 1.0);
		}
	}
	COLOR = col;
}
