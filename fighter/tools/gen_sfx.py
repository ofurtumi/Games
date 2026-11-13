#!/usr/bin/env python3
"""Synthesizes every sound effect + the music loop into assets/sfx/ (16-bit mono 22050 Hz WAV).

No dependencies (stdlib only). Every sound uses a fixed random seed, so re-running produces
byte-identical files. Run from anywhere:  python3 tools/gen_sfx.py

Building blocks: noise bursts through time-varying filters, pitch-swept oscillators, transient
clicks, inharmonic partials for metal, and tanh saturation to glue the layers together.
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
TAU = math.tau


# ---------------------------------------------------------------- primitives

def buf(sec):
    return [0.0] * int(sec * SR)


def secs(n):
    return n / SR


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def _coef(fc):
    fc = max(10.0, min(fc, SR * 0.45))
    return 1.0 - math.exp(-TAU * fc / SR)


def lowpass(x, fc):
    """One-pole lowpass. fc: Hz or function(t_seconds) -> Hz."""
    out = [0.0] * len(x)
    y = 0.0
    f = fc if callable(fc) else None
    a = _coef(fc) if f is None else 0.0
    for i, v in enumerate(x):
        if f is not None and (i & 15) == 0:
            a = _coef(f(i / SR))
        y += a * (v - y)
        out[i] = y
    return out


def lowpass2(x, fc):
    return lowpass(lowpass(x, fc), fc)


def highpass(x, fc):
    lp = lowpass(x, fc)
    return [a - b for a, b in zip(x, lp)]


def bandpass(x, fc, q=1.0):
    """Chamberlin state-variable bandpass, fc may be a function of time. Higher q = more ring."""
    out = [0.0] * len(x)
    low = band = 0.0
    damp = 1.0 / max(q, 0.5)
    f = fc if callable(fc) else None
    k = 2.0 * math.sin(math.pi * min(fc, SR * 0.2) / SR) if f is None else 0.0
    for i, v in enumerate(x):
        if f is not None and (i & 15) == 0:
            k = 2.0 * math.sin(math.pi * min(max(f(i / SR), 20.0), SR * 0.2) / SR)
        high = v - low - damp * band
        band += k * high
        low += k * band
        out[i] = band
    return out


def env_exp(n, tau, attack=0.0):
    """Exponential decay with optional linear attack (seconds)."""
    out = [0.0] * n
    na = int(attack * SR)
    for i in range(n):
        t = i / SR
        a = min(1.0, i / na) if na > 0 else 1.0
        out[i] = a * math.exp(-max(0.0, t - attack) / tau)
    return out


def env_bell(n, peak=0.3, shape=2.0):
    """Rise to a peak at `peak` (fraction of length), fall to zero: whoosh shape."""
    out = [0.0] * n
    for i in range(n):
        p = i / max(1, n - 1)
        if p < peak:
            out[i] = (p / peak) ** shape
        else:
            out[i] = ((1.0 - p) / (1.0 - peak)) ** shape
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def gain(x, g):
    return [v * g for v in x]


def osc(n, freq, wave_="sine", duty=0.5, phase=0.0):
    """freq: Hz or function(t) -> Hz (pitch sweeps)."""
    out = [0.0] * n
    ph = phase
    f = freq if callable(freq) else None
    for i in range(n):
        fr = f(i / SR) if f is not None else freq
        ph = (ph + fr / SR) % 1.0
        if wave_ == "sine":
            v = math.sin(TAU * ph)
        elif wave_ == "square":
            v = 1.0 if ph < duty else -1.0
        elif wave_ == "saw":
            v = 2.0 * ph - 1.0
        elif wave_ == "tri":
            v = 4.0 * abs(ph - 0.5) - 1.0
        else:
            raise ValueError(wave_)
        out[i] = v
    return out


def sweep_exp(f0, f1, dur):
    """Exponential pitch glide f0 -> f1 over dur seconds, then holds f1."""
    r = math.log(f1 / f0)
    return lambda t: f0 * math.exp(r * min(t / dur, 1.0))


def saturate(x, drive=2.0):
    d = math.tanh(drive)
    return [math.tanh(v * drive) / d for v in x]


def mix(*layers, length=None):
    """layers: (signal, offset_seconds, gain) tuples or plain signals."""
    norm = []
    for l in layers:
        if isinstance(l, tuple):
            s, off, g = (l + (1.0,))[:3] if len(l) == 2 else l
        else:
            s, off, g = l, 0.0, 1.0
        norm.append((s, int(off * SR), g))
    n = length if length is not None else max(len(s) + o for s, o, _ in norm)
    out = [0.0] * n
    for s, o, g in norm:
        for i, v in enumerate(s):
            j = i + o
            if j >= n:
                break
            out[j] += v * g
    return out


def click(rng, ms=2.5, fc=3000.0):
    n = int(ms / 1000.0 * SR)
    return mul(highpass(noise(n, rng), fc), env_exp(n, ms / 1000.0 / 3.0))


def metal(n, freqs, taus, amps, rng=None, detune=0.0):
    """Inharmonic decaying partials (clang / ping / ring)."""
    out = [0.0] * n
    for f, tau, a in zip(freqs, taus, amps):
        if rng and detune:
            f *= 1.0 + rng.uniform(-detune, detune)
        ph = rng.random() if rng else 0.0
        for i in range(n):
            t = i / SR
            out[i] += a * math.sin(TAU * (f * t + ph)) * math.exp(-t / tau)
    return out


def finish(x, peak=0.9, fade_ms=6.0, dc=True):
    """Remove DC, fade the tail, normalize to `peak`."""
    if dc:
        x = highpass(x, 25.0)
    n = len(x)
    nf = min(n, int(fade_ms / 1000.0 * SR))
    for i in range(nf):
        x[n - 1 - i] *= i / nf
    m = max((abs(v) for v in x), default=0.0)
    if m > 0:
        x = [v * peak / m for v in x]
    return x


def write(name, x):
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in x))
    return path


# ---------------------------------------------------------------- recipes

def gunshot(seed, dur, crack=1.0, body_hi=6000, body_lo=500, body_tau=0.05, thump_f=(160, 45),
            thump_tau=0.05, thump_amt=0.8, tail_tau=0.12, tail_amt=0.25, drive=2.5, mech=0.0):
    rng = random.Random(seed)
    n = int(dur * SR)
    nz = noise(n, rng)
    # Crack: very short bright burst.
    c = mul(highpass(nz, 2500), env_exp(n, 0.006))
    # Body: noise with a closing filter.
    body = mul(lowpass2(noise(n, rng), lambda t: body_lo + (body_hi - body_lo) * math.exp(-t / (body_tau * 0.8))),
               env_exp(n, body_tau, attack=0.001))
    # Thump: low sine pitch drop.
    th = mul(osc(n, sweep_exp(thump_f[0], thump_f[1], thump_tau * 1.5)), env_exp(n, thump_tau, attack=0.0015))
    # Tail: dark room noise.
    tail = mul(lowpass(noise(n, rng), 900), env_exp(n, tail_tau, attack=0.01))
    layers = [(c, 0, crack), (body, 0, 1.0), (th, 0, thump_amt), (tail, 0, tail_amt), (click(rng, 2.0, 4000), 0, 0.8)]
    if mech:
        m = metal(int(0.06 * SR), [2900, 4700], [0.01, 0.008], [1, 0.6], rng)
        layers.append((m, 0.004, mech))
    return finish(saturate(mix(*layers, length=n), drive))


def whoosh(seed, dur, f0, f1, f2, q=1.4, peak=0.45, lo_amt=0.3):
    """Band-passed noise with cutoff sweeping f0 -> f1 (at peak) -> f2."""
    rng = random.Random(seed)
    n = int(dur * SR)

    def fc(t):
        p = t / dur
        if p < peak:
            return f0 * (f1 / f0) ** (p / peak)
        return f1 * (f2 / f1) ** ((p - peak) / (1.0 - peak))
    nz = noise(n, rng)
    w = bandpass(nz, fc, q)
    w = mix((w, 0, 1.0), (lowpass(nz, 400), 0, lo_amt))
    return finish(mul(w, env_bell(n, peak, 1.6)))


def thud(seed, dur, f0, f1, tau, lp=700, noise_amt=0.8, drive=2.0, click_amt=0.4):
    rng = random.Random(seed)
    n = int(dur * SR)
    s = mul(osc(n, sweep_exp(f0, f1, tau * 2)), env_exp(n, tau, attack=0.001))
    nz = mul(lowpass2(noise(n, rng), lambda t: lp * (0.3 + 0.7 * math.exp(-t / (tau * 0.7)))), env_exp(n, tau * 0.8))
    return finish(saturate(mix((s, 0, 1.0), (nz, 0, noise_amt), (click(rng, 3.0, 1500), 0, click_amt), length=n), drive))


def blip(freqs, note_dur, wave_="square", duty=0.5, tau=None, gap=0.0, vib=0.0, peak=0.7):
    out = []
    for f in freqs:
        n = int(note_dur * SR)
        fn = (lambda t, f=f: f * (1 + vib * math.sin(TAU * 18 * t))) if vib else f
        s = osc(n, fn, wave_, duty)
        e = env_exp(n, tau or note_dur * 0.5, attack=0.002)
        out += mul(s, e) + [0.0] * int(gap * SR)
    return finish(lowpass(out, 6000), peak, dc=False)


def grains(seed, dur, rate0, rate1, gdur=(0.004, 0.02), fc=(400, 2500), q=2.0, decay=0.15):
    """Scatter short filtered noise grains with falling density: crumble / crackle / debris."""
    rng = random.Random(seed)
    n = int(dur * SR)
    out = [0.0] * n
    t = 0.0
    while t < dur:
        p = t / dur
        rate = rate0 + (rate1 - rate0) * p
        t += rng.expovariate(max(rate, 1.0))
        if t >= dur:
            break
        gl = int(rng.uniform(*gdur) * SR)
        g = bandpass(noise(gl, rng), rng.uniform(*fc), q)
        g = mul(g, env_exp(gl, gl / SR / 3.0))
        amp = math.exp(-t / decay) * rng.uniform(0.4, 1.0)
        o = int(t * SR)
        for i, v in enumerate(g):
            if o + i < n:
                out[o + i] += v * amp
    return out


# ---------------------------------------------------------------- sound list

def make_all():
    S = {}
    # Guns -----------------------------------------------------------
    S["pistol"] = gunshot(1, 0.32, body_hi=7000, body_lo=600, body_tau=0.045, thump_f=(190, 55),
                          thump_tau=0.04, tail_tau=0.1, mech=0.25)
    S["rifle"] = gunshot(2, 0.22, crack=1.2, body_hi=8000, body_lo=900, body_tau=0.03, thump_f=(220, 70),
                         thump_tau=0.03, thump_amt=0.6, tail_tau=0.07, tail_amt=0.2, drive=3.0)
    S["smg"] = gunshot(3, 0.16, crack=1.0, body_hi=8500, body_lo=1200, body_tau=0.022, thump_f=(240, 90),
                       thump_tau=0.022, thump_amt=0.5, tail_tau=0.05, tail_amt=0.15, drive=2.5)
    S["minigun"] = gunshot(4, 0.085, crack=0.9, body_hi=7000, body_lo=1400, body_tau=0.014, thump_f=(200, 90),
                           thump_tau=0.015, thump_amt=0.6, tail_tau=0.03, tail_amt=0.1, drive=2.2)
    S["shotgun"] = gunshot(5, 0.5, crack=1.0, body_hi=5000, body_lo=250, body_tau=0.09, thump_f=(140, 38),
                           thump_tau=0.08, thump_amt=1.1, tail_tau=0.2, tail_amt=0.4, drive=3.5)
    S["magnum"] = gunshot(6, 0.45, crack=1.3, body_hi=6500, body_lo=350, body_tau=0.07, thump_f=(150, 40),
                          thump_tau=0.07, thump_amt=1.0, tail_tau=0.18, tail_amt=0.35, drive=3.2, mech=0.2)
    # Sniper: huge crack + long rolling tail.
    sn = gunshot(7, 0.85, crack=1.6, body_hi=9000, body_lo=300, body_tau=0.06, thump_f=(130, 35),
                 thump_tau=0.09, thump_amt=1.0, tail_tau=0.32, tail_amt=0.55, drive=3.5)
    rng = random.Random(70)
    roll = mul(lowpass2(noise(len(sn), rng), lambda t: 1200 * math.exp(-t / 0.3) + 150), env_exp(len(sn), 0.25, attack=0.05))
    S["sniper"] = finish(mix((sn, 0, 1.0), (roll, 0.03, 0.35)))
    # Laser: falling saw zap + ring-modded shimmer.
    n = int(0.3 * SR)
    z = osc(n, sweep_exp(2400, 180, 0.22), "saw")
    z2 = osc(n, lambda t: sweep_exp(3600, 300, 0.2)(t) * (1 + 0.04 * math.sin(TAU * 60 * t)), "square", 0.3)
    zap = mul(mix((z, 0, 0.6), (z2, 0, 0.35)), env_exp(n, 0.08, attack=0.002))
    zap = bandpass(zap, sweep_exp(4000, 500, 0.25), 0.9)
    S["laser"] = finish(saturate(mix((zap, 0, 1.0), (click(random.Random(8), 2.0, 5000), 0, 0.4)), 1.8))

    # Weapon handling -----------------------------------------------
    rng = random.Random(10)
    m1 = metal(int(0.05 * SR), [3100, 5200, 7400], [0.006, 0.004, 0.003], [1, 0.6, 0.4], rng)
    S["empty_click"] = finish(mix((click(rng, 1.5, 5000), 0, 0.8), (m1, 0, 0.6), (click(rng, 1.0, 6000), 0.018, 0.3)), 0.6)
    rng = random.Random(11)
    def clack(f, seed):
        r = random.Random(seed)
        n = int(0.09 * SR)
        m = metal(n, [f, f * 1.73, f * 2.61], [0.02, 0.012, 0.008], [1, 0.5, 0.35], r)
        th = mul(lowpass(noise(n, r), 1200), env_exp(n, 0.01))
        return mix((click(r, 2.0, 3500), 0, 1.0), (m, 0, 0.5), (th, 0, 0.8))
    S["reload"] = finish(saturate(mix((clack(1500, 12), 0), (clack(1100, 13), 0.13, 0.8), (clack(1900, 14), 0.26, 1.1),
                                      length=int(0.4 * SR)), 1.5), 0.8)
    S["pickup"] = finish(saturate(mix((clack(1300, 15), 0), (clack(2100, 16), 0.06, 0.9),
                                      (blip([660, 990], 0.05, "square", 0.25), 0.02, 0.15), length=int(0.2 * SR)), 1.5), 0.8)
    S["pickup_small"] = blip([880, 1320, 1760], 0.045, "square", 0.25, tau=0.03, peak=0.38)
    S["throw"] = whoosh(17, 0.28, 300, 1600, 500, q=1.2, peak=0.4)
    S["swing"] = whoosh(18, 0.2, 500, 2800, 900, q=1.6, peak=0.35, lo_amt=0.15)

    # Melee -----------------------------------------------------------
    S["punch"] = thud(20, 0.16, 180, 70, 0.035, lp=1800, noise_amt=0.9, drive=2.5, click_amt=0.5)
    S["punch_heavy"] = thud(21, 0.3, 140, 42, 0.065, lp=1400, noise_amt=1.0, drive=3.5, click_amt=0.6)
    rng = random.Random(22)
    n = int(0.35 * SR)
    ring = metal(n, [1850, 3120, 4410, 6020], [0.12, 0.08, 0.05, 0.04], [1, 0.7, 0.5, 0.3], rng, 0.01)
    slice_ = mul(highpass(noise(n, rng), 2500), env_exp(n, 0.02))
    S["blade_hit"] = finish(saturate(mix((ring, 0, 0.5), (slice_, 0, 0.8), (thud(23, 0.15, 160, 60, 0.03), 0, 0.6), length=n), 1.8))
    rng = random.Random(24)
    n = int(0.45 * SR)
    clang = metal(n, [520, 1235, 1870, 2640, 3710], [0.2, 0.14, 0.1, 0.07, 0.05], [1, 0.8, 0.6, 0.45, 0.3], rng, 0.01)
    S["block"] = finish(saturate(mix((clang, 0, 0.6), (click(rng, 3.0, 2000), 0, 1.0),
                                     (mul(lowpass(noise(n, rng), 2500), env_exp(n, 0.015)), 0, 0.6), length=n), 2.2))

    # Bodies ---------------------------------------------------------
    S["hurt"] = thud(30, 0.2, 120, 50, 0.045, lp=1700, noise_amt=1.1, drive=2.8, click_amt=0.3)
    d1 = thud(31, 0.55, 90, 32, 0.11, lp=1300, noise_amt=1.2, drive=3.0, click_amt=0.3)
    d2 = thud(32, 0.25, 70, 35, 0.05, lp=600, noise_amt=1.0, drive=2.0, click_amt=0.1)
    S["death"] = finish(mix((d1, 0, 1.0), (d2, 0.17, 0.45)))
    # Gib: wet squelch (resonant filter wobbling down) + droplets.
    rng = random.Random(33)
    n = int(0.5 * SR)
    sq = bandpass(noise(n, rng), lambda t: (900 + 500 * math.sin(TAU * 23 * t)) * math.exp(-t / 0.25) + 150, 3.5)
    sq = mul(sq, env_exp(n, 0.09, attack=0.003))
    drops = [0.0] * n
    for k in range(7):
        t0 = rng.uniform(0.05, 0.4)
        dn = int(0.04 * SR)
        d = mul(osc(dn, sweep_exp(rng.uniform(500, 900), rng.uniform(1200, 2000), 0.03)), env_exp(dn, 0.01))
        o = int(t0 * SR)
        for i, v in enumerate(d):
            if o + i < n:
                drops[o + i] += v * 0.25 * math.exp(-t0 / 0.3)
    S["gib"] = finish(saturate(mix((sq, 0, 1.0), (thud(34, 0.2, 110, 45, 0.04), 0, 0.7), (drops, 0, 1.0), length=n), 2.5))

    # Movement -------------------------------------------------------
    rng = random.Random(40)
    n = int(0.14 * SR)
    j = mul(bandpass(noise(n, rng), sweep_exp(400, 1500, 0.12), 1.0), env_bell(n, 0.25, 1.5))
    jt = mul(osc(n, sweep_exp(160, 320, 0.1)), env_exp(n, 0.03, attack=0.003))
    S["jump"] = finish(mix((j, 0, 0.8), (jt, 0, 0.5), (click(rng, 2.0, 1500), 0, 0.2)), 0.5)
    S["land"] = finish(thud(41, 0.12, 110, 55, 0.025, lp=900, noise_amt=1.2, drive=1.6, click_amt=0.2), 0.55)
    lh = thud(42, 0.35, 90, 35, 0.07, lp=1000, noise_amt=1.3, drive=3.0, click_amt=0.4)
    deb = grains(43, 0.35, 120, 10, fc=(800, 3000), decay=0.1)
    S["land_heavy"] = finish(mix((lh, 0, 1.0), (deb, 0.02, 0.6)))
    rng = random.Random(44)
    n = int(0.05 * SR)
    fs = mul(bandpass(noise(n, rng), 1200, 1.2), env_exp(n, 0.008))
    S["footstep"] = finish(mix((fs, 0, 1.0), (thud(45, 0.05, 120, 70, 0.01, lp=700, drive=1.2), 0, 0.5)), 0.3)
    S["dive"] = whoosh(46, 0.32, 250, 1300, 400, q=1.0, peak=0.3, lo_amt=0.5)
    # Roll: tumbling cloth/body rustle.
    rng = random.Random(47)
    n = int(0.32 * SR)
    r = lowpass(noise(n, rng), 1500)
    tum = [0.55 + 0.45 * math.sin(TAU * 11 * i / SR) ** 2 for i in range(n)]
    S["roll"] = finish(mix((mul(mul(r, tum), env_bell(n, 0.2, 1.2)), 0, 1.0), (thud(48, 0.08, 110, 60, 0.02), 0, 0.5), length=n), 0.5)
    # Ledge grab: hand slap.
    rng = random.Random(49)
    n = int(0.12 * SR)
    slap = mul(bandpass(noise(n, rng), 1800, 1.0), env_exp(n, 0.012))
    S["ledge_grab"] = finish(mix((slap, 0, 1.0), (thud(50, 0.1, 150, 80, 0.02, lp=1200), 0, 0.6)), 0.6)
    rng = random.Random(51)
    n = int(0.16 * SR)
    scr = mul(bandpass(noise(n, rng), sweep_exp(900, 2000, 0.15), 2.0), env_bell(n, 0.3, 1.0))
    S["climb"] = finish(mix((scr, 0, 0.7), (click(rng, 2.0, 1500), 0, 0.4), (click(rng, 2.0, 1200), 0.07, 0.3)), 0.4)

    # Impacts / destruction -------------------------------------------
    rng = random.Random(60)
    n = int(0.18 * SR)
    wh = mul(osc(n, lambda t: 3600 * math.exp(-t * 2.5) * (1 + 0.02 * math.sin(TAU * 40 * t))), env_exp(n, 0.05, attack=0.01))
    hit = mul(bandpass(noise(n, rng), 2200, 1.0), env_exp(n, 0.012))
    S["bullet_hit_wall"] = finish(mix((hit, 0, 1.0), (click(rng, 2.0, 3000), 0, 0.7), (wh, 0.006, 0.18),
                                      (grains(61, 0.18, 150, 20, fc=(1500, 4000), decay=0.05), 0.005, 0.4), length=n), 0.6)
    rng = random.Random(62)
    n = int(0.35 * SR)
    ping = metal(n, [2380, 3960, 5870], [0.09, 0.05, 0.03], [1, 0.45, 0.25], rng)
    S["bullet_hit_metal"] = finish(mix((ping, 0, 0.6), (click(rng, 2.0, 4000), 0, 1.0)), 0.6)
    # Glass: initial crash + scattered tinkles.
    rng = random.Random(63)
    n = int(0.55 * SR)
    crash = mul(highpass(noise(n, rng), 3000), env_exp(n, 0.04))
    tink = [0.0] * n
    for k in range(26):
        t0 = rng.uniform(0.0, 0.42) ** 1.4
        f = rng.uniform(2800, 7800)
        tn = int(0.08 * SR)
        s = mul(osc(tn, f), env_exp(tn, rng.uniform(0.01, 0.03)))
        o = int(t0 * SR)
        a = rng.uniform(0.3, 1.0) * math.exp(-t0 / 0.25)
        for i, v in enumerate(s):
            if o + i < n:
                tink[o + i] += v * a
    S["glass_break"] = finish(saturate(mix((crash, 0, 1.0), (tink, 0, 0.5), (click(rng, 2.0, 2000), 0, 0.6), length=n), 1.5), 0.75)
    cr = grains(64, 0.4, 260, 15, gdur=(0.005, 0.025), fc=(250, 1600), q=1.5, decay=0.14)
    S["tile_break"] = finish(saturate(mix((cr, 0, 1.0), (thud(65, 0.2, 100, 45, 0.04, lp=900), 0, 0.8)), 2.0), 0.8)
    # Wood: sharp crack + splintering resonances + thunk.
    rng = random.Random(66)
    n = int(0.4 * SR)
    crk = mul(bandpass(noise(n, rng), 1400, 3.0), env_exp(n, 0.03))
    spl = grains(67, 0.35, 160, 10, gdur=(0.003, 0.012), fc=(700, 2600), q=4.0, decay=0.09)
    S["wood_break"] = finish(saturate(mix((click(rng, 2.0, 2500), 0, 1.0), (crk, 0, 0.8), (spl, 0.01, 0.8),
                                          (thud(68, 0.2, 180, 80, 0.04, lp=1000), 0, 0.6), length=n), 2.2), 0.85)

    # Explosives ------------------------------------------------------
    rng = random.Random(80)
    n = int(1.25 * SR)
    boom = mul(lowpass2(noise(n, rng), lambda t: 150 + 5500 * math.exp(-t / 0.08)), env_exp(n, 0.3, attack=0.002))
    sub = mul(osc(n, sweep_exp(85, 28, 0.6)), env_exp(n, 0.3, attack=0.003))
    rum = mul(lowpass2(noise(n, rng), 220), env_exp(n, 0.45, attack=0.05))
    crackle = grains(81, 1.0, 90, 10, gdur=(0.002, 0.01), fc=(1200, 4500), q=1.5, decay=0.35)
    S["explosion"] = finish(saturate(mix((click(rng, 3.0, 1000), 0, 1.0), (boom, 0, 1.2), (sub, 0, 1.0), (rum, 0, 0.9),
                                         (crackle, 0.04, 0.5), length=n), 3.0))
    rng = random.Random(82)
    n = int(0.15 * SR)
    clink = metal(n, [1720, 4130, 6280], [0.04, 0.025, 0.015], [1, 0.5, 0.3], rng)
    S["grenade_bounce"] = finish(mix((clink, 0, 0.6), (thud(83, 0.08, 220, 120, 0.012, lp=1500), 0, 0.6),
                                     (click(rng, 1.5, 3000), 0, 0.5), length=n), 0.55)
    rng = random.Random(84)
    n = int(0.3 * SR)
    pin = metal(int(0.25 * SR), [3300, 5100], [0.06, 0.04], [1, 0.5], rng)
    spring = mul(osc(n, lambda t: 2500 + 400 * math.sin(TAU * 35 * t)), env_exp(n, 0.04))
    S["grenade_pin"] = finish(mix((click(rng, 1.5, 4000), 0, 0.8), (pin, 0.01, 0.5), (spring, 0.01, 0.15),
                                  (click(rng, 2.0, 2500), 0.16, 0.9), (thud(85, 0.06, 300, 180, 0.01), 0.16, 0.4), length=n), 0.7)
    # Fire crackle: roaring bed + pops, faded at both ends so it can be re-triggered.
    rng = random.Random(86)
    n = int(0.6 * SR)
    bed = lowpass2(noise(n, rng), lambda t: 500 + 200 * math.sin(TAU * 3 * t))
    bed = mul(bed, [0.6 + 0.4 * math.sin(TAU * 7 * i / SR + 1.3) for i in range(n)])
    pops = grains(87, 0.6, 45, 45, gdur=(0.001, 0.005), fc=(1500, 5000), q=1.2, decay=99.0)
    fire = mix((bed, 0, 1.0), (pops, 0, 0.9), length=n)
    e = [min(1.0, i / (0.06 * SR), (n - i) / (0.12 * SR)) for i in range(n)]
    S["fire_loop_short"] = finish(saturate(mul(fire, e), 1.5), 0.55)

    # UI / round flow -------------------------------------------------
    S["ui_move"] = blip([1046], 0.045, "square", 0.25, tau=0.02, peak=0.3)
    S["ui_select"] = blip([784, 1175], 0.06, "square", 0.5, tau=0.04, peak=0.35)
    S["ui_back"] = blip([880, 587], 0.06, "square", 0.5, tau=0.04, peak=0.32)
    S["countdown_beep"] = blip([880], 0.14, "square", 0.5, tau=0.07, peak=0.4)
    rs = blip([523, 659, 784, 1046], 0.07, "square", 0.5, tau=0.06, peak=1.0)
    rs_hit = gunshot(90, 0.5, crack=0.5, body_hi=4000, body_lo=200, body_tau=0.09, thump_f=(120, 40), thump_tau=0.1,
                     tail_tau=0.25, tail_amt=0.5, drive=2.0)
    rs_tail = blip([1046], 0.4, "tri", tau=0.15, peak=1.0)
    S["round_start"] = finish(mix((rs, 0, 0.7), (rs_hit, 0.28, 0.6), (rs_tail, 0.28, 0.5)), 0.8)
    # Fanfare: C E G | C' held, with triangle bass and a light hit.
    lead = blip([523, 659, 784], 0.11, "square", 0.5, tau=0.1, peak=1.0) + blip([1046], 0.6, "square", 0.5, tau=0.3, vib=0.006, peak=1.0)
    harm = blip([392, 523, 659], 0.11, "square", 0.25, tau=0.1, peak=1.0) + blip([784], 0.6, "square", 0.25, tau=0.3, peak=1.0)
    bass = blip([131], 0.33, "tri", tau=0.2, peak=1.0) + blip([131], 0.6, "tri", tau=0.35, peak=1.0)
    S["round_win"] = finish(mix((lead, 0, 0.55), (harm, 0, 0.25), (bass, 0, 0.5),
                                (thud(91, 0.3, 100, 40, 0.06), 0.33, 0.4)), 0.8)
    # Slowmo: descending whoosh with a dropping tone.
    rng = random.Random(92)
    n = int(0.85 * SR)
    sw = mul(bandpass(noise(n, rng), sweep_exp(3500, 180, 0.75), 2.0), env_bell(n, 0.12, 1.2))
    tone = mul(osc(n, sweep_exp(700, 70, 0.8), "tri"), env_bell(n, 0.1, 1.0))
    S["slowmo"] = finish(mix((sw, 0, 1.0), (tone, 0, 0.35), (lowpass(noise(n, rng), 200), 0, 0.0)), 0.75)
    return S


# ---------------------------------------------------------------- music

def music_loop():
    """16 bars @ 128 BPM = exactly 30 s. Notes that ring past the end wrap to the start."""
    bpm = 128.0
    beat = 60.0 / bpm
    bars = 16
    total = int(round(bars * 4 * beat * SR))
    out = [0.0] * total
    rng = random.Random(100)

    def put(sig, t, g):
        o = int(round(t * SR))
        for i, v in enumerate(sig):
            out[(o + i) % total] += v * g

    def midi(m):
        return 440.0 * 2 ** ((m - 69) / 12.0)

    # Pre-rendered drum hits.
    kn = int(0.22 * SR)
    kick = finish(saturate(mix((mul(osc(kn, sweep_exp(150, 45, 0.06)), env_exp(kn, 0.07, attack=0.001)), 0, 1.0),
                               (click(random.Random(101), 2.0, 1500), 0, 0.3), length=kn), 2.0), 1.0, fade_ms=10)
    sn_ = int(0.18 * SR)
    snare = finish(mix((mul(bandpass(noise(sn_, rng), 2500, 0.8), env_exp(sn_, 0.05)), 0, 1.0),
                       (mul(osc(sn_, sweep_exp(240, 170, 0.03)), env_exp(sn_, 0.03)), 0, 0.5), length=sn_), 1.0)
    hn = int(0.04 * SR)
    hat = finish(mul(highpass(noise(hn, rng), 7000), env_exp(hn, 0.01)), 1.0, fade_ms=3)
    on = int(0.16 * SR)
    ohat = finish(mul(highpass(noise(on, rng), 6000), env_exp(on, 0.05)), 1.0)

    # A minor: Am F C G (2 bars each), twice. Roots in MIDI.
    prog = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [48, 52, 55]), (55, [55, 59, 62])]
    s16 = beat / 4.0
    bass_pat = [0, 0, 12, 0, 0, 12, 0, 7]  # 8th notes, semitones above root
    arp_pat = [0, 1, 2, 1, 0, 1, 2, 3]
    for bar in range(bars):
        t_bar = bar * 4 * beat
        root, chord = prog[(bar // 2) % 4]
        # Drums: four-on-the-floor, snare on 2 & 4, 8th hats, open hat on offbeats in second half.
        for b in range(4):
            put(kick, t_bar + b * beat, 0.9)
            if b in (1, 3):
                put(snare, t_bar + b * beat, 0.45)
            put(hat, t_bar + b * beat, 0.12)
            if bar >= 8:
                put(ohat, t_bar + b * beat + beat / 2, 0.09)
            else:
                put(hat, t_bar + b * beat + beat / 2, 0.18)
        if bar % 4 == 3:  # small fill
            put(snare, t_bar + 3.5 * beat, 0.25)
            put(snare, t_bar + 3.75 * beat, 0.3)
        # Bass: pulse wave, filtered.
        for k in range(8):
            f = midi(root - 12 + bass_pat[k])
            n = int(beat / 2 * SR * 0.9)
            s = mul(osc(n, f, "square", 0.3), env_exp(n, 0.12, attack=0.003))
            put(lowpass2(s, 700), t_bar + k * beat / 2, 0.28)
        # Lead arpeggio: enters at bar 4, triangle+pulse 16ths, an octave up.
        if bar >= 4:
            notes = chord + [chord[0] + 12]
            for k in range(16):
                m = notes[arp_pat[k % 8]] + 12 + (12 if bar >= 12 and k % 4 == 3 else 0)
                n = int(s16 * SR * 0.85)
                s = mix((osc(n, midi(m), "tri"), 0, 0.7), (osc(n, midi(m), "square", 0.125), 0, 0.15), length=n)
                s = mul(s, env_exp(n, 0.06, attack=0.002))
                put(s, t_bar + k * s16, 0.11)
        # Pad-ish long note on chord change (soft).
        if bar % 2 == 0:
            n = int(8 * beat * SR)
            pad = [0.0] * n
            for m in chord:
                p = osc(n, midi(m), "saw")
                pad = [a + b for a, b in zip(pad, p)]
            pad = lowpass2(pad, 900)
            pad = mul(pad, [min(1.0, i / (0.3 * SR), (n - i) / (0.4 * SR)) for i in range(n)])
            put(pad, t_bar, 0.025)
    # No final fade: the loop wraps seamlessly. Gentle normalize/saturate, peak ~ -4 dBFS.
    out = saturate(out, 1.2)
    m = max(abs(v) for v in out)
    return [v * 0.6 / m for v in out]


def main():
    os.makedirs(OUT, exist_ok=True)
    sounds = make_all()
    for name, x in sorted(sounds.items()):
        write(name, x)
        print("%-18s %.2fs" % (name, len(x) / SR))
    ml = music_loop()
    write("music_loop", ml)
    print("%-18s %.2fs" % ("music_loop", len(ml) / SR))


if __name__ == "__main__":
    main()
