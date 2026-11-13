"""Generates the game's pixel art into assets/sprites/.

Run:  python3 tools/gen_art.py           (writes PNGs + atlas.json, and a zoomed preview)

Fighters are a small puppet: hand-pixeled head/torso, limbs rasterized from joint
angles so animation stays consistent. Team-colored pixels use magenta keys
(r == b, g == 0) that the game recolors per player.
After generating, the PNGs are plain files — touch them up in Aseprite if you like.
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from png import Canvas  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "sprites")
os.makedirs(OUT, exist_ok=True)

OUTLINE = (24, 18, 30, 255)

PAL = {
    "h": (58, 40, 32), "H": (92, 64, 46),          # hair
    "s": (238, 182, 140), "S": (198, 138, 104),    # skin
    "k": (24, 18, 30),                             # eye
    "c": (204, 0, 204), "v": (128, 0, 128), "u": (255, 0, 255),  # team keys
    "p": (84, 94, 60), "P": (62, 70, 46), "q": (56, 63, 44),     # pants
    "b": (46, 38, 34), "B": (78, 64, 54),          # boots
    "w": (40, 32, 28), "y": (214, 176, 74),        # belt, buckle
    "x": (255, 255, 255), "K": (24, 18, 30),
    # weapon / prop materials
    "m": (118, 128, 140), "n": (70, 76, 88), "l": (176, 186, 198), "N": (44, 48, 58),
    "r": (140, 92, 50), "R": (92, 60, 34), "t": (30, 28, 32),
    "g": (90, 160, 80), "G": (60, 110, 56), "e": (130, 255, 140), "E": (60, 200, 90),
    "z": (100, 210, 255), "Z": (200, 240, 255),
    "o": (240, 140, 40), "O": (255, 210, 80), "f": (250, 90, 40),
    "j": (210, 60, 50), "J": (150, 36, 32), "i": (250, 210, 60),
    "a": (120, 170, 110), "A": (170, 210, 160),
    "d": (230, 190, 80), "D": (170, 130, 40),
    "w2": (0, 0, 0),
}


def grid(rows, ox=0, oy=0):
    """ASCII rows -> list of (x, y, color)."""
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in PAL:
                out.append((ox + x, oy + y, PAL[ch] + (255,)))
    return out


def outline(cv, col=OUTLINE):
    add = []
    for y in range(cv.h):
        for x in range(cv.w):
            if cv.get(x, y)[3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c = cv.get(x + dx, y + dy)
                if c[3] and c != col:
                    add.append((x, y))
                    break
    for x, y in add:
        cv.set(x, y, col)
    return cv


def thick_line(cv, a, b, col, w=2):
    ax, ay = a
    bx, by = b
    n = int(max(abs(bx - ax), abs(by - ay)) * 4) + 1
    for i in range(n + 1):
        t = i / n
        x = ax + (bx - ax) * t
        y = ay + (by - ay) * t
        for dx in range(w):
            for dy in range(w):
                cv.set(int(math.floor(x - w / 2 + 0.5)) + dx, int(math.floor(y - w / 2 + 0.5)) + dy, col)


def polar(origin, ang_deg, length):
    """0 deg = straight down, +deg rotates toward +x (forward)."""
    a = math.radians(ang_deg)
    return (origin[0] + math.sin(a) * length, origin[1] + math.cos(a) * length)


# ------------------------------------------------------------------ fighter

FW = FH = 24
HEAD = [
    "..hhhh..",
    ".hHHHhh.",
    ".hhhhhhh",
    ".ccccccu",
    ".hhssskS",
    "..ssssss",
    "...sSss.",
]
TORSO = [
    "vcccc.",
    "vccucc",
    "vccccc",
    "vvcccc",
    "vvcccc",
    "wwwwyw",
]
TAILS = [
    [(-1, 0), (-2, 0), (-2, 1)],
    [(-1, 0), (-2, 0), (-3, 1)],
    [(-1, 0), (-2, -1), (-3, -1)],
]

THIGH, SHIN = 3.0, 3.0
UPPER, FORE = 2.4, 2.4


def leg(cv, hip, thigh, knee, far):
    pc = PAL["q"] if far else PAL["p"]
    kneep = polar(hip, thigh, THIGH)
    shin_ang = thigh - knee
    foot = polar(kneep, shin_ang, SHIN)
    thick_line(cv, hip, kneep, pc + (255,))
    thick_line(cv, kneep, foot, (PAL["P"] if not far else PAL["q"]) + (255,))
    # Boot: points along +x (forward), rotated a bit with the shin.
    fx, fy = int(round(foot[0])), int(round(foot[1]))
    bcol = (PAL["b"] if far else PAL["B"]) + (255,)
    for dx in range(-1, 2):
        cv.set(fx + dx, fy, bcol)
    cv.set(fx - 1, fy - 1, bcol)
    cv.set(fx, fy - 1, bcol)


def arm(cv, shoulder, upper, elbow, far, k=1.0):
    sleeve = PAL["v"] if far else PAL["c"]
    skin = PAL["S"] if far else PAL["s"]
    el = polar(shoulder, upper, UPPER * k)
    hand = polar(el, upper + elbow, FORE * k)
    thick_line(cv, shoulder, el, sleeve + (255,))
    thick_line(cv, el, hand, skin + (255,))
    return hand


def fighter_frame(pose, with_near_arm=True):
    cv = Canvas(FW, FH)
    bob = pose.get("bob", 0)
    lean = pose.get("lean", 0)
    hip_y = 17 + bob
    torso_x, torso_y = 9 + (lean // 2), 12 + bob
    head_x, head_y = 8 + lean, 5 + bob + pose.get("head_dy", 0)
    far_sh = (torso_x + 1.5, torso_y + 1.5)
    near_sh = (torso_x + 3.5, torso_y + 1.5)
    # far limbs
    leg(cv, (11, hip_y), *pose["far_leg"], far=True)
    arm(cv, far_sh, *pose["far_arm"], far=True, k=pose.get("arm_len", 1.0))
    # body
    for x, y, c in grid(TORSO, torso_x, torso_y):
        cv.set(x, y, c)
    leg(cv, (12.5, hip_y), *pose["near_leg"], far=False)
    # re-draw belt over leg tops
    for x, y, c in grid([TORSO[-1]], torso_x, torso_y + 5):
        cv.set(x, y, c)
    for x, y, c in grid(HEAD, head_x, head_y):
        cv.set(x, y, c)
    for dx, dy in TAILS[pose.get("tail", 0)]:
        cv.set(head_x + 1 + dx, head_y + 3 + dy, PAL["v"] + (255,))
    hand = None
    if with_near_arm:
        hand = arm(cv, near_sh, *pose["near_arm"], far=False, k=pose.get("arm_len", 1.0))
    return cv, near_sh


def rotate90(cv, cw=True):
    out = Canvas(cv.h, cv.w)
    for y in range(cv.h):
        for x in range(cv.w):
            if cw:
                out.set(cv.h - 1 - y, x, cv.px[y][x])
            else:
                out.set(y, cv.w - 1 - x, cv.px[y][x])
    return out


def settle(cv, bottom=FH - 1, cx=FW // 2):
    """Shift so lowest opaque pixel sits on `bottom` and bbox is centered on cx."""
    xs = [x for y in range(cv.h) for x in range(cv.w) if cv.px[y][x][3]]
    ys = [y for y in range(cv.h) for x in range(cv.w) if cv.px[y][x][3]]
    if not xs:
        return cv
    dx = cx - (min(xs) + max(xs) + 1) // 2
    dy = bottom - max(ys)
    out = Canvas(cv.w, cv.h)
    out.blit(cv, dx, dy)
    return out


def run_pose(p):
    s = math.sin(2 * math.pi * p)
    c = math.cos(2 * math.pi * p)
    s2 = math.sin(2 * math.pi * (p + 0.5))
    c2 = math.cos(2 * math.pi * (p + 0.5))
    return {
        "near_leg": (38 * s, 15 + 55 * max(0.0, -c)),
        "far_leg": (38 * s2, 15 + 55 * max(0.0, -c2)),
        "near_arm": (-35 * s, 50),
        "far_arm": (-35 * s2, 50),
        "bob": 0 if abs(s) > 0.6 else 1 if abs(s) < 0.25 else 0,
        "lean": 1,
        "tail": 1 + int(p * 4) % 2,
    }


POSES = {
    "idle0": {"near_leg": (8, 8), "far_leg": (-8, 8), "near_arm": (6, 20), "far_arm": (-6, 20)},
    "idle1": {"near_leg": (8, 8), "far_leg": (-8, 8), "near_arm": (8, 26), "far_arm": (-4, 26), "bob": 1, "tail": 0},
    **{f"run{i}": run_pose(i / 8) for i in range(8)},
    "jump": {"near_leg": (55, 85), "far_leg": (-10, 50), "near_arm": (140, 20), "far_arm": (110, 30), "tail": 2},
    "fall": {"near_leg": (25, 20), "far_leg": (-30, 30), "near_arm": (155, 10), "far_arm": (130, 20), "tail": 2},
    "crouch": {"near_leg": (75, 140), "far_leg": (45, 130), "near_arm": (40, 60), "far_arm": (20, 60), "bob": 3, "lean": 1},
    "punch0": {"near_leg": (20, 10), "far_leg": (-20, 10), "near_arm": (-30, 120), "far_arm": (40, 90)},
    "punch1": {"near_leg": (25, 5), "far_leg": (-25, 10), "near_arm": (92, 0), "far_arm": (-20, 60), "lean": 1},
    "hook": {"near_leg": (30, 10), "far_leg": (-30, 10), "near_arm": (110, -10), "far_arm": (-40, 50), "lean": 2},
    "kick": {"near_leg": (95, 5), "far_leg": (-15, 15), "near_arm": (-50, 30), "far_arm": (50, 40), "lean": -1, "tail": 2},
    "guard": {"near_leg": (15, 10), "far_leg": (-15, 10), "near_arm": (60, 120), "far_arm": (40, 110)},
    "climb0": {"near_leg": (20, 50), "far_leg": (-5, 10), "near_arm": (170, 0), "far_arm": (150, 30)},
    "climb1": {"near_leg": (-5, 10), "far_leg": (20, 50), "near_arm": (150, 30), "far_arm": (170, 0)},
    "hurt": {"near_leg": (-10, 15), "far_leg": (20, 25), "near_arm": (-60, 30), "far_arm": (-90, 20), "lean": -1, "head_dy": 0, "tail": 2},
    "stomp": {"near_leg": (6, 0), "far_leg": (-6, 0), "near_arm": (160, 0), "far_arm": (145, 15), "tail": 2},
    "lunge": {"near_leg": (45, 20), "far_leg": (-40, 15), "near_arm": (92, 0), "far_arm": (-50, 40), "lean": 2, "tail": 1},
    "aim": {"near_leg": (12, 8), "far_leg": (-12, 8), "near_arm": (90, 0), "far_arm": (60, 60)},
    "hang": {"near_leg": (-4, 12), "far_leg": (-14, 22), "near_arm": (158, 0), "far_arm": (150, 0), "tail": 0, "arm_len": 1.7},
    "ledgeup": {"near_leg": (95, 125), "far_leg": (15, 45), "near_arm": (140, 70), "far_arm": (120, 50), "lean": 2, "bob": 2, "tail": 1},
    "vault": {"near_leg": (70, 110), "far_leg": (-30, 60), "near_arm": (100, 20), "far_arm": (-40, 40), "lean": 1, "tail": 2},
    "slide": {"near_leg": (86, 0), "far_leg": (78, 12), "near_arm": (-110, 30), "far_arm": (-130, 20), "lean": -2, "bob": 6, "tail": 2},
    "dive_src": {"near_leg": (-5, 0), "far_leg": (5, 10), "near_arm": (175, 0), "far_arm": (170, 0), "tail": 2},
    "ball_src": {"near_leg": (100, 160), "far_leg": (80, 150), "near_arm": (70, 100), "far_arm": (60, 100), "bob": 3},
}


def build_fighter():
    names = []
    frames_full, frames_noarm, shoulders = [], [], []

    def add(name, full, noarm, sh):
        names.append(name)
        frames_full.append(outline(full))
        frames_noarm.append(outline(noarm))
        shoulders.append(sh)

    for name, pose in POSES.items():
        if name.endswith("_src"):
            continue
        full, sh = fighter_frame(pose, True)
        noarm, _ = fighter_frame(pose, False)
        add(name, full, noarm, sh)
    # Lying (down/dead): idle rotated onto its back.
    idle, _ = fighter_frame(POSES["idle0"], True)
    lying = settle(rotate90(idle, cw=False))
    add("down", lying, lying, (12, 20))
    # Dive: arms-up pose rotated forward.
    d, _ = fighter_frame(POSES["dive_src"], True)
    dive = settle(rotate90(d, cw=True), bottom=FH - 6)
    add("dive", dive, dive, (12, 16))
    # Roll: curled ball, four 90-degree turns (lossless).
    b, _ = fighter_frame(POSES["ball_src"], True)
    b = settle(b, bottom=FH - 4)
    for i in range(4):
        r = b
        for _ in range(i):
            r = rotate90(r, cw=True)
        r = settle(r, bottom=FH - 1)
        add(f"roll{i}", r, r, (12, 18))

    sheet = Canvas(FW * len(names), FH * 2)
    for i, (f, n) in enumerate(zip(frames_full, frames_noarm)):
        sheet.blit(f, i * FW, 0)
        sheet.blit(n, i * FW, FH)
    sheet.save(os.path.join(OUT, "fighter.png"))

    # Arm used when holding weapons: points along +x from the shoulder.
    armc = Canvas(8, 4)
    for x, y, c in grid(["ccss.", "ccsss"], 1, 1):
        armc.set(x, y, c)
    outline(armc)
    armc.save(os.path.join(OUT, "arm.png"))

    return {
        "frame_size": [FW, FH],
        "origin": [FW // 2, FH],  # feet
        "frames": names,
        "shoulders": [[round(s[0] - FW / 2, 1), round(s[1] - FH, 1)] for s in shoulders],
        "arm": {"pivot": [2, 2], "hand": [6, 2]},
    }, sheet


# ------------------------------------------------------------------ weapons

WEAPONS = {
    # name: (rows, grip(x,y), muzzle(x,y))
    "pistol": ([
        "lmmmmml",
        "nnnmnnn",
        "Rr.....",
        "Rr.....",
    ], (1, 2), (7, 0)),
    "derringer": ([
        "dlll",
        "Dmmn",
        "Rr..",
    ], (1, 2), (4, 0)),
    "shotgun": ([
        "....lllllllll",
        "rrRRmmmmmmmmm",
        "rR..nnnnRRr..",
        "R............",
    ], (4, 2), (13, 0)),
    "blunderbuss": ([
        "...........ll",
        "rr.lllllllmml",
        "rRRmmmmmmmmmm",
        "R..RRr.....ll",
    ], (4, 3), (13, 1)),
    "assault": ([
        "....nnnn.....",
        "rnnnmmmmmmmml",
        "rR.nnnNnn....",
        "....Nn.n.....",
        ".....n.......",
    ], (4, 2), (13, 1)),
    "minigun": ([
        "..nnnnnnnn....",
        "NNmmmmmmmmllll",
        "NNnnnnnnnnmmmm",
        "NNmmmmmmmmllll",
        "..nN.nnnnn....",
    ], (3, 3), (14, 2)),
    "bfg": ([
        "...nnnnnnn....",
        "..nmmmmmmmnn..",
        "NNmEeeeeEmmmnl",
        "NNmeeeeeemmmnl",
        "..nmmmmmmmnn..",
        "...nNn.nnn....",
    ], (4, 4), (14, 2)),
    "sling": ([
        "R..R",
        "rRRr",
        ".rr.",
        ".rr.",
    ], (1, 3), (2, 0)),
    "knife": ([
        "RR.llll",
        "RRnmmmm",
    ], (1, 1), (7, 0)),
    "sword": ([
        "..n...........",
        "RRnlllllllllll",
        "RRnmmmmmmmmmm.",
        "..n...........",
    ], (1, 1), (14, 1)),
    "bigsword": ([
        "...nn..............",
        "RRRnnllllllllllllll",
        "RRRnnmmmmmmmmmmmmml",
        "RRRnnmmmmmmmmmmmmm.",
        "...nnnnnnnnnnnnnn..",
    ], (1, 2), (18, 2)),
    "lightsaber": ([
        "lllnZZZZZZZZZZZZ",
        "mmmnzzzzzzzzzzz.",
    ], (1, 1), (16, 0)),
    "grenade": ([
        ".ll.",
        "gGGg",
        "gggG",
        "GggG",
        ".GG.",
    ], (2, 2), (2, 0)),
    "sticky": ([
        ".a.",
        "aAa",
        "aaa",
    ], (1, 1), (1, 0)),
    "holy": ([
        "..d..",
        ".ddd.",
        "..d..",
        ".dDd.",
        "dddDd",
        ".dDd.",
    ], (2, 3), (2, 0)),
    "molotov": ([
        ".o.",
        ".f.",
        ".A.",
        "aAa",
        "aaa",
        "aaa",
        "aaa",
    ], (1, 4), (1, 0)),
}


def build_weapons():
    entries = {}
    cells = []
    for name, (rows, grip, muzzle) in WEAPONS.items():
        w = max(len(r) for r in rows) + 2
        h = len(rows) + 2
        cv = Canvas(w, h)
        for x, y, c in grid(rows, 1, 1):
            cv.set(x, y, c)
        outline(cv)
        cells.append((name, cv, grip, muzzle))
    sheet_w = 128
    x = y = row_h = 0
    placed = []
    for name, cv, grip, muzzle in cells:
        if x + cv.w > sheet_w:
            x, y = 0, y + row_h
            row_h = 0
        placed.append((name, cv, x, y, grip, muzzle))
        x += cv.w
        row_h = max(row_h, cv.h)
    sheet = Canvas(sheet_w, y + row_h)
    for name, cv, px, py, grip, muzzle in placed:
        sheet.blit(cv, px, py)
        entries[name] = {"rect": [px, py, cv.w, cv.h], "grip": [grip[0] + 1, grip[1] + 1],
                         "muzzle": [muzzle[0] + 1, muzzle[1] + 1]}
    sheet.save(os.path.join(OUT, "weapons.png"))
    return entries, sheet


# ------------------------------------------------------------------ props

PROPS = {
    "crate": [
        "RRRRRRRRRR",
        "RrrrrrrrrR",
        "RrRrrrrRrR",
        "RrrRrrRrrR",
        "RrrrRRrrrR",
        "RrrrRRrrrR",
        "RrrRrrRrrR",
        "RrRrrrrRrR",
        "RrrrrrrrrR",
        "RRRRRRRRRR",
    ],
    "barrel": [
        ".JJJJJJ.",
        "JjjjjjjJ",
        "JJJJJJJJ",
        "jjjiijjj",
        "jjiKKijj",
        "jjiKKijj",
        "jjjiijjj",
        "JJJJJJJJ",
        "jjjjjjjj",
        "JjjjjjjJ",
        ".JJJJJJ.",
    ],
}


def build_props():
    entries = {}
    x = 0
    cvs = []
    for name, rows in PROPS.items():
        w, h = len(rows[0]) + 2, len(rows) + 2
        cv = Canvas(w, h)
        for px, py, c in grid(rows, 1, 1):
            cv.set(px, py, c)
        outline(cv)
        cvs.append((name, cv, x))
        entries[name] = {"rect": [x, 0, w, h]}
        x += w
    sheet = Canvas(x, max(c.h for _, c, _ in cvs))
    for name, cv, px in cvs:
        sheet.blit(cv, px, 0)
    sheet.save(os.path.join(OUT, "props.png"))
    return entries, sheet


# ------------------------------------------------------------------ tiles (16x16 seamless textures)

def clamp(v):
    return max(0, min(255, int(v)))


def shade(c, f):
    return (clamp(c[0] * f), clamp(c[1] * f), clamp(c[2] * f), 255)


def tex_brick(rng):
    cv = Canvas(16, 16)
    mortar = (70, 56, 54, 255)
    for by in range(4):
        off = 0 if by % 2 == 0 else 4
        for bx in range(-1, 3):
            base = (150 + rng.randint(-14, 14), 84 + rng.randint(-10, 8), 70 + rng.randint(-8, 8))
            x0 = bx * 8 + off
            for y in range(by * 4, by * 4 + 4):
                for x in range(x0, x0 + 8):
                    xx = x % 16
                    ly, lx = y - by * 4, x - x0
                    if ly == 3 or lx == 7:
                        c = mortar
                    elif ly == 0:
                        c = shade(base, 1.18)
                    elif ly == 2 or lx == 6:
                        c = shade(base, 0.86)
                    else:
                        c = shade(base, 1.0 + rng.uniform(-0.05, 0.05))
                    cv.set(xx, y, c)
    return cv


def tex_dirt(rng):
    cv = Canvas(16, 16)
    base = (112, 76, 50)
    for y in range(16):
        for x in range(16):
            f = 1.0 + rng.uniform(-0.07, 0.07)
            c = shade(base, f)
            r = rng.random()
            if r < 0.07:
                c = shade(base, 0.72)
            elif r < 0.11:
                c = shade(base, 1.22)
            cv.set(x, y, c)
    for _ in range(4):  # pebbles
        px, py = rng.randint(0, 14), rng.randint(0, 14)
        g = rng.randint(120, 150)
        cv.set(px, py, (g, g - 8, g - 16, 255))
        cv.set(px + 1, py, (g - 30, g - 36, g - 40, 255))
    return cv


def tex_wood(rng):
    cv = Canvas(16, 16)
    for plank in range(4):
        base = (150 + rng.randint(-12, 12), 100 + rng.randint(-8, 8), 56 + rng.randint(-6, 6))
        seam = rng.randint(3, 12)
        for y in range(plank * 4, plank * 4 + 4):
            ly = y - plank * 4
            for x in range(16):
                if ly == 3:
                    c = shade(base, 0.55)
                elif ly == 0:
                    c = shade(base, 1.15)
                else:
                    c = shade(base, 1.0 + 0.08 * math.sin(x * 0.9 + plank * 2 + ly))
                if x == seam and ly < 3:
                    c = shade(base, 0.6)
                cv.set(x, y, c)
        cv.set((seam + 2) % 16, plank * 4 + 1, (60, 50, 44, 255))  # nail
    return cv


def tex_concrete(rng):
    cv = Canvas(16, 16)
    base = (140, 142, 146)
    for y in range(16):
        for x in range(16):
            c = shade(base, 1.0 + rng.uniform(-0.04, 0.04))
            if rng.random() < 0.05:
                c = shade(base, 0.8)
            if x == 0 or y == 0:
                c = shade(base, 0.82)
            if x == 1 or y == 1:
                c = shade(base, 1.1)
            cv.set(x, y, c)
    return cv


def tex_metal(rng):
    cv = Canvas(16, 16)
    base = (98, 106, 118)
    for y in range(16):
        for x in range(16):
            c = shade(base, 1.0 + 0.04 * ((x + y) % 3 == 0))
            if x == 0 or y == 0:
                c = shade(base, 1.3)
            elif x == 15 or y == 15:
                c = shade(base, 0.6)
            cv.set(x, y, c)
    for (rx, ry) in ((3, 3), (12, 3), (3, 12), (12, 12)):
        cv.set(rx, ry, shade(base, 1.45))
        cv.set(rx + 1, ry + 1, shade(base, 0.55))
    for x in range(5, 11):
        cv.set(x, 8, shade(base, 0.8))
    return cv


def tex_glass(rng):
    cv = Canvas(16, 16)
    for y in range(16):
        for x in range(16):
            c = (150, 210, 235, 120)
            d = (x + y) % 16
            if d in (3, 4) or d == 9:
                c = (230, 248, 255, 190)
            cv.set(x, y, c)
    return cv


def build_tiles():
    rng = random.Random(42)
    texs = {
        "dirt": tex_dirt(rng), "brick": tex_brick(rng), "wood": tex_wood(rng),
        "concrete": tex_concrete(rng), "metal": tex_metal(rng), "glass": tex_glass(rng),
    }
    # Platform and ladder: 8x8 sprites.
    plat = Canvas(16, 8)
    for x in range(16):
        plat.set(x, 0, (196, 146, 86, 255))
        plat.set(x, 1, (160, 110, 60, 255))
        plat.set(x, 2, (150, 102, 56, 255))
        plat.set(x, 3, (90, 60, 34, 255))
    for x in (2, 13):
        for y in range(4, 7):
            plat.set(x, y, (90, 60, 34, 255))
        plat.set(x + (1 if x == 2 else -1), 4, (90, 60, 34, 255))
    lad = Canvas(8, 8)
    for y in range(8):
        lad.set(1, y, (120, 84, 46, 255))
        lad.set(6, y, (120, 84, 46, 255))
        lad.set(0, y, (70, 48, 28, 255))
        lad.set(7, y, (70, 48, 28, 255))
    for y in (2, 6):
        for x in range(2, 6):
            lad.set(x, y, (170, 124, 72, 255))
            lad.set(x, y + 1, (90, 60, 34, 255))
    texs["platform"] = plat
    texs["ladder"] = lad
    sheet = Canvas(16 * len(texs), 16)
    entries = {}
    for i, (name, cv) in enumerate(texs.items()):
        sheet.blit(cv, i * 16, 0)
        entries[name] = [i * 16, 0, cv.w, cv.h]
    sheet.save(os.path.join(OUT, "tiles.png"))
    return entries, sheet


def main():
    fighter, fsheet = build_fighter()
    weapons, wsheet = build_weapons()
    props, psheet = build_props()
    tiles, tsheet = build_tiles()
    with open(os.path.join(OUT, "atlas.json"), "w") as f:
        json.dump({"fighter": fighter, "weapons": weapons, "props": props, "tiles": tiles}, f, indent=1)
    # Zoomed preview for eyeballing (not used by the game).
    prev_dir = sys.argv[1] if len(sys.argv) > 1 else OUT
    tinted = Canvas(fsheet.w, fsheet.h)
    for y in range(fsheet.h):
        for x in range(fsheet.w):
            c = fsheet.px[y][x]
            if c[3] and c[0] == c[2] and c[1] == 0 and c[0] > 0:
                f = c[0] / 204
                c = (clamp(220 * f), clamp(60 * f), clamp(50 * f), 255)
            tinted.px[y][x] = c
    prev = Canvas(max(fsheet.w, 300), fsheet.h + wsheet.h + psheet.h + tsheet.h + 12)
    bg = (60, 64, 80, 255)
    for y in range(prev.h):
        for x in range(prev.w):
            prev.px[y][x] = bg
    prev.blit(tinted, 0, 0)
    prev.blit(wsheet, 0, fsheet.h + 4)
    prev.blit(psheet, 140, fsheet.h + 4)
    prev.blit(tsheet, 0, fsheet.h + wsheet.h + 8)
    prev.scaled(4).save(os.path.join(prev_dir, "preview.png"))
    print("frames:", len(fighter["frames"]), fighter["frames"])


if __name__ == "__main__":
    main()
