"""Generates the starter maps into data/maps/*.json.

Run:  python3 tools/gen_maps.py [--print]

Maps are plain ASCII grids (legend in README.md), so you can also edit the JSON by hand.
Helpers here (building, fire_escape, ...) make it quick to sketch new ones.
"""
import json
import os
import random
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "maps")


class Map:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [["."] * w for _ in range(h)]

    def fill(self, x0, y0, x1, y1, ch):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
                if 0 <= x < self.w and 0 <= y < self.h:
                    self.g[y][x] = ch

    def put(self, x, y, ch):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = ch

    def get(self, x, y):
        return self.g[y][x] if 0 <= x < self.w and 0 <= y < self.h else "."

    def save(self, name, title, show=False):
        rows = ["".join(r) for r in self.g]
        with open(os.path.join(OUT, name + ".json"), "w") as f:
            json.dump({"name": title, "size": [self.w, self.h], "tiles": rows}, f, indent=1)
        if show:
            print(title)
            print("\n".join(rows))
            print()

    # ---- building blocks -------------------------------------------------

    def building(self, x0, x1, top, ground, spacing=8, wall="S", floor="W", back="s",
                 windows=True, doors="b", hatch=True):
        """Walls, roof, floors every `spacing`, ladders alternating sides, body-height windows."""
        self.fill(x0 + 1, top + 1, x1 - 1, ground - 1, back)
        self.fill(x0, top, x1, top, wall)
        self.fill(x0, top, x0, ground - 1, wall)
        self.fill(x1, top, x1, ground - 1, wall)
        floors = list(range(top + spacing, ground - 2, spacing))
        for fy in floors:
            self.fill(x0 + 1, fy, x1 - 1, fy, floor)
        levels = [top] + floors + [ground]
        for i, (a, b) in enumerate(zip(levels, levels[1:])):
            lx = x0 + 2 if i % 2 == 0 else x1 - 2
            self.fill(lx, a + 1, lx, b - 1, "H")
            if a != top or hatch:
                self.put(lx, a, "-")
            if windows and b - a >= 5:
                wy0, wy1 = max(a + 1, b - 3), b - 1
                if i < len(levels) - 2 or doors not in ("l", "b"):
                    self.fill(x0, wy0, x0, wy1, "G")
                if i < len(levels) - 2 or doors not in ("r", "b"):
                    self.fill(x1, wy0, x1, wy1, "G")
        if doors in ("l", "b"):
            self.fill(x0, ground - 3, x0, ground - 1, ".")
        if doors in ("r", "b"):
            self.fill(x1, ground - 3, x1, ground - 1, ".")
        return levels

    def fire_escape(self, x, top, ground, side):
        """Zig-zag platforms + ladders down the outside of a wall. side: -1 left, +1 right."""
        y = top + 4
        i = 0
        while y < ground - 2:
            xa, xb = (x - 5, x - 1) if side < 0 else (x + 1, x + 5)
            self.fill(xa, y, xb, y, "-")
            lx = xa + 1 if i % 2 == 0 else xb - 1
            self.fill(lx, y + 1, lx, min(y + 6, ground - 1), "H")
            y += 6
            i += 1

    def scatter(self, ch, spots):
        for x, y in spots:
            self.put(x, y, ch)


def warehouse():
    m = Map(60, 34)
    m.fill(1, 1, 58, 30, "s")
    m.fill(0, 0, 59, 0, "M"); m.fill(0, 0, 0, 33, "M"); m.fill(59, 0, 59, 33, "M")
    m.fill(1, 31, 58, 33, "S")
    m.fill(0, 33, 59, 33, "M")
    m.fill(26, 31, 33, 33, ".")
    m.fill(25, 31, 25, 33, "M"); m.fill(34, 31, 34, 33, "M")
    m.fill(6, 24, 20, 24, "-"); m.fill(39, 24, 53, 24, "-")
    m.fill(21, 17, 38, 17, "-")
    m.fill(1, 10, 14, 10, "W"); m.fill(45, 10, 58, 10, "W")
    m.fill(15, 10, 17, 10, "-"); m.fill(42, 10, 44, 10, "-")
    m.fill(8, 25, 8, 30, "H"); m.fill(51, 25, 51, 30, "H")
    m.fill(22, 18, 22, 30, "H"); m.fill(37, 18, 37, 30, "H")
    m.fill(16, 11, 16, 23, "H"); m.fill(43, 11, 43, 23, "H")
    m.fill(1, 4, 13, 4, "W"); m.fill(13, 4, 13, 6, "W"); m.fill(13, 5, 13, 6, "G"); m.fill(13, 7, 13, 9, "w")
    m.fill(46, 4, 58, 4, "W"); m.fill(46, 4, 46, 6, "W"); m.fill(46, 5, 46, 6, "G"); m.fill(46, 7, 46, 9, "w")
    m.fill(2, 5, 12, 9, "w"); m.fill(47, 5, 57, 9, "w")
    m.fill(28, 18, 31, 22, "K")
    m.scatter("P", [(4, 30), (55, 30), (13, 23), (46, 23), (25, 16), (34, 16), (5, 9), (54, 9)])
    m.scatter("X", [(19, 30), (40, 30), (29, 16), (9, 9), (50, 9), (14, 23), (45, 23)])
    m.scatter("C", [(2, 30), (3, 30), (2, 29), (57, 30), (56, 30)])
    m.scatter("B", [(23, 30), (36, 30), (20, 23), (39, 23)])
    return m


def rooftops():
    m = Map(60, 34)
    m.fill(0, 31, 59, 33, "D")
    m.building(3, 17, 13, 31, spacing=9)
    m.building(22, 37, 7, 31, spacing=8)
    m.building(42, 56, 12, 31, spacing=9)
    m.fill(18, 20, 21, 20, "-"); m.fill(38, 19, 41, 19, "-")
    m.fill(27, 3, 32, 5, "W"); m.put(28, 6, "H"); m.put(31, 6, "H")
    m.scatter("P", [(6, 12), (14, 12), (25, 6), (34, 6), (46, 11), (53, 11), (10, 30), (49, 30), (29, 22), (10, 21)])
    m.scatter("X", [(9, 12), (29, 14), (49, 11), (19, 30), (40, 30), (30, 22), (50, 20), (30, 2)])
    m.scatter("C", [(26, 6), (35, 6), (12, 21), (47, 20)])
    m.scatter("B", [(33, 6), (26, 30), (33, 30), (55, 30)])
    return m


def downtown():
    W, H = 160, 64
    m = Map(W, H)
    street = 52
    # Ground, a subway tunnel underneath, side walls so nobody runs off the world.
    m.fill(0, street, W - 1, H - 1, "D")
    m.fill(0, street, W - 1, street, "K")
    m.fill(8, 56, 152, 59, "k")
    m.fill(8, 60, 152, 60, "K")
    m.fill(8, 55, 152, 55, "K")
    for mx in (14, 60, 100, 146):  # manholes with ladders down
        m.put(mx, street, "-")
        m.fill(mx, street + 1, mx, street + 3, "H")
        m.put(mx, street + 3, "-") if False else None
        m.fill(mx, 55, mx, 55, "-")
        m.fill(mx, 56, mx, 59, "H")
    m.fill(76, street, 83, street + 3, ".")  # construction hole into the tunnel
    m.fill(76, 55, 83, 55, ".")
    m.fill(0, 20, 1, street - 1, "M"); m.fill(W - 2, 20, W - 1, street - 1, "M")
    m.fill(0, 56, 7, 60, "D"); m.fill(153, 56, W - 1, 60, "D")
    # Buildings
    m.building(4, 26, 28, street, spacing=8)
    m.building(32, 48, 40, street, spacing=6, wall="W", floor="W", back="w")
    m.building(54, 72, 12, street, spacing=8, wall="K", back="k")
    m.building(88, 106, 30, street, spacing=11, wall="S")
    m.building(112, 132, 20, street, spacing=8)
    m.building(138, 155, 36, street, spacing=8, wall="W", back="w")
    # Water tower and billboard on the roofs
    # Water tower / billboard on stilts: 3 tiles of headroom underneath
    m.fill(59, 5, 66, 8, "W"); m.fill(60, 9, 60, 11, "H"); m.fill(65, 9, 65, 11, "H")
    m.fill(116, 14, 126, 16, "W"); m.fill(118, 17, 118, 19, "H"); m.fill(124, 17, 124, 19, "H")
    # Fire escapes and roof bridges
    m.fire_escape(26, 28, street, +1)
    m.fire_escape(54, 12, street, -1)
    m.fire_escape(72, 12, street, +1)
    m.fire_escape(132, 20, street, +1)
    m.fill(27, 34, 31, 34, "-")
    m.fill(107, 28, 111, 28, "-")
    m.fill(49, 40, 53, 40, "-")
    # Big hall in building 4: catwalk and crates
    m.fill(92, 41, 102, 41, "-")
    m.fill(97, 42, 97, 51, "H") if m.get(97, 42) == "s" else None
    # Entities
    m.scatter("P", [(10, 51), (40, 51), (63, 51), (95, 51), (120, 51), (145, 51), (15, 27), (63, 11),
                    (122, 19), (146, 35), (40, 39), (30, 59), (130, 59), (66, 35), (120, 43)])
    m.scatter("X", [(20, 51), (52, 51), (86, 51), (110, 51), (135, 51), (11, 43), (61, 27), (69, 43),
                    (97, 40), (125, 35), (147, 43), (40, 45), (50, 59), (110, 59), (70, 11), (20, 27)])
    m.scatter("C", [(28, 51), (29, 51), (28, 50), (92, 51), (93, 51), (92, 50), (101, 51), (84, 51), (150, 51),
                    (58, 35), (128, 27), (8, 35)])
    m.scatter("K", [(109, 51), (44, 59), (45, 59), (120, 59)])  # knee-high barriers to vault
    m.scatter("B", [(30, 51), (74, 51), (136, 51), (94, 40), (65, 19), (16, 43), (126, 51), (35, 59), (90, 59)])
    return m


def factory():
    W, H = 128, 72
    m = Map(W, H)
    m.fill(0, 0, W - 1, H - 1, "k")
    m.fill(0, 0, W - 1, 1, "M"); m.fill(0, 0, 1, H - 1, "M"); m.fill(W - 2, 0, W - 1, H - 1, "M")
    m.fill(2, 66, W - 3, H - 1, "K")
    m.fill(0, H - 1, W - 1, H - 1, "M")
    # Central death pit
    m.fill(56, 66, 71, H - 1, ".")
    m.fill(55, 66, 55, H - 1, "M"); m.fill(72, 66, 72, H - 1, "M")
    # Catwalk tiers (platforms) with ladders
    tiers = [58, 48, 38, 28, 18, 10]
    rng = random.Random(7)
    for i, y in enumerate(tiers):
        segs = [(4, 30), (36, 58), (68, 92), (98, 123)] if i % 2 == 0 else [(10, 44), (50, 78), (84, 118)]
        for a, b in segs:
            m.fill(a, y, b, y, "-")
            # ladder from this catwalk down to the one below (or the floor)
            below = tiers[i - 1] if i > 0 else 66
            lx = rng.randint(a + 2, b - 2)
            m.fill(lx, y + 1, lx, below - 1, "H")
    # Concrete pillars and machinery blocks
    for px in (33, 64, 95):
        m.fill(px, 19, px + 1, 27, "K")
        m.fill(px, 39, px + 1, 47, "K")
    m.fill(14, 60, 20, 65, "M"); m.fill(106, 60, 112, 65, "M")
    m.fill(42, 52, 47, 57, "K"); m.fill(80, 52, 85, 57, "K")
    m.scatter("K", [(30, 65), (31, 65), (96, 65), (97, 65)])  # floor steps
    # Glass-walled offices on top
    for x0 in (6, 104):
        m.fill(x0, 4, x0 + 16, 4, "W")
        m.fill(x0, 4, x0, 9, "W"); m.fill(x0 + 16, 4, x0 + 16, 9, "W")
        m.fill(x0, 6, x0, 9, "G"); m.fill(x0 + 16, 6, x0 + 16, 9, "G")
        m.fill(x0 + 1, 5, x0 + 15, 9, "w")
    # Entities
    m.scatter("P", [(8, 65), (30, 65), (90, 65), (118, 65), (20, 57), (110, 57), (45, 47), (82, 47),
                    (15, 37), (112, 37), (60, 27), (30, 17), (98, 17), (12, 9), (114, 9), (64, 9)])
    m.scatter("X", [(25, 65), (100, 65), (40, 57), (88, 57), (60, 47), (20, 47), (105, 47), (50, 37), (78, 37),
                    (16, 27), (110, 27), (64, 17), (14, 9), (112, 9), (40, 9), (88, 9)])
    m.scatter("C", [(4, 65), (5, 65), (4, 64), (122, 65), (123, 65), (123, 64), (44, 51), (83, 51), (30, 37), (96, 37)])
    m.scatter("B", [(35, 65), (92, 65), (50, 65), (77, 65), (26, 57), (100, 57), (64, 37), (8, 27), (119, 27), (64, 27)])
    return m


def main():
    show = "--print" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    warehouse().save("warehouse", "Warehouse", show)
    rooftops().save("rooftops", "Rooftops", show)
    downtown().save("downtown", "Downtown", show)
    factory().save("factory", "Factory", show)


if __name__ == "__main__":
    main()
