extends Node

# Every sound in the game, synthesised at start-up (no audio files): short
# 22 kHz mono samples, a little crunchy on purpose. One-shots go through a
# small voice pool; loops (engine, laser, drill...) each have their own
# player and stop by themselves if nothing has asked for them this frame.
#
# Use the static helpers from anywhere: Sfx.play("boom"), Sfx.loop("engine",
# true, volume_db, pitch).

const RATE = 22050
const VOICES = 16

static var instance = null
static var fx_gain = 1.0      # one-shots (0..1, the Sound menu sets these)
static var loop_gain = 1.0    # engine, drill, laser... loops

static func _db(g: float) -> float:
	return linear_to_db(g) if g > 0.001 else -80.0

var sounds = {}       # name -> AudioStreamWAV
var voices = []
var loops = {}        # name -> {player, seen}
var plays = 0         # how many one-shots have played (tests read this)
var _next = 0

func _ready():
	instance = self
	_build()
	for i in VOICES:
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		voices.append(p)

func _exit_tree():
	if instance == self:
		instance = null

static func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if instance != null:
		instance._play(name, volume_db, pitch)

static func loop(name: String, on: bool, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if instance != null:
		instance._loop(name, on, volume_db, pitch)

func _play(name: String, volume_db: float, pitch: float) -> void:
	if not sounds.has(name):
		return
	var p: AudioStreamPlayer = voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = sounds[name]
	p.volume_db = volume_db - 6.0 + _db(fx_gain)
	p.pitch_scale = clampf(pitch * randf_range(0.96, 1.04), 0.2, 4.0)
	p.play()
	plays += 1

func _loop(name: String, on: bool, volume_db: float, pitch: float) -> void:
	if not sounds.has(name) and not loops.has(name):
		return
	if not loops.has(name):
		var p = AudioStreamPlayer.new()
		p.stream = sounds[name]
		add_child(p)
		loops[name] = {"player": p, "seen": 0.0}
	var l = loops[name]
	var p = l.player   # 2D or 3D player
	if on:
		l.seen = 0.0
		p.volume_db = volume_db - 8.0 + _db(loop_gain)
		p.pitch_scale = clampf(pitch, 0.2, 4.0)
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()

# A loop that sounds from somewhere in the world (a rival's engine): panned
# by where it is from the camera, volume set by the caller. `key` names this
# copy, `name` the sound.
static func loop_at(key: String, name: String, at: Vector3, on: bool, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if instance != null:
		instance._loop_at(key, name, at, on, volume_db, pitch)

func _loop_at(key: String, name: String, at: Vector3, on: bool, volume_db: float, pitch: float) -> void:
	if not sounds.has(name):
		return
	if not loops.has(key):
		var p = AudioStreamPlayer3D.new()
		p.stream = sounds[name]
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.panning_strength = 0.8
		add_child(p)
		loops[key] = {"player": p, "seen": 0.0, "placed": true}
	var l = loops[key]
	l.player.global_position = at
	_loop(key, on, volume_db, pitch)

func _process(delta):
	# Loops nobody refreshed lately (menus, garage, mode switches) go quiet;
	# placed ones whose owner is gone are dropped.
	var gone = []
	for name in loops:
		var l = loops[name]
		l.seen += delta / maxf(Engine.time_scale, 0.05)
		if l.seen > 0.15 and l.player.playing:
			l.player.stop()
		if l.get("placed", false) and l.seen > 5.0:
			gone.append(name)
	for name in gone:
		loops[name].player.queue_free()
		loops.erase(name)

func loop_playing(name: String) -> bool:
	return loops.has(name) and loops[name].player.playing

# ---------------------------------------------------------------- synthesis

func _build() -> void:
	sounds.boom = _wav(_explosion(0.9, 0.55))
	sounds.big_boom = _wav(_explosion(1.6, 0.8))
	sounds.small_boom = _wav(_explosion(0.45, 0.35))
	sounds.hit = _wav(_mix([_noise_burst(0.14, 0.5, 0.15), _sweep(130, 60, 0.16, "sine", 0.8)]))
	sounds.launch = _wav(_mix([_noise_sweep(0.4, 0.05, 0.5, 0.6), _sweep(300, 900, 0.3, "square", 0.25)]))
	sounds.warp = _wav(_mix([_sweep(200, 2200, 0.28, "sine", 0.6), _noise_burst(0.28, 0.25, 0.6)]))
	sounds.hop = _wav(_sweep(180, 520, 0.16, "square", 0.35))
	sounds.drop = _wav(_sweep(400, 200, 0.1, "square", 0.3))
	sounds.tick = _wav(_sweep(1500, 1500, 0.04, "square", 0.25))
	sounds.pickup = _wav(_seq([[880, 0.06], [1320, 0.08]], "square", 0.3))
	sounds.gate = _wav(_mix([_sweep(1047, 1047, 0.5, "sine", 0.5, 4.0), _sweep(1568, 1568, 0.5, "sine", 0.3, 5.0)]))
	sounds.lap = _wav(_seq([[523, 0.09], [659, 0.09], [784, 0.09], [1047, 0.25]], "square", 0.3))
	sounds.shield_down = _wav(_sweep(700, 140, 0.6, "saw", 0.45))
	sounds.ui_move = _wav(_sweep(1200, 1200, 0.025, "sine", 0.35))
	sounds.ui_select = _wav(_seq([[660, 0.04], [990, 0.06]], "square", 0.25))
	sounds.ui_back = _wav(_seq([[520, 0.04], [330, 0.06]], "square", 0.25))
	sounds.clunk = _wav(_mix([_noise_burst(0.08, 0.6, 0.08), _sweep(150, 90, 0.1, "sine", 0.7)]))
	sounds.scrap = _wav(_mix([_noise_sweep(0.22, 0.4, 0.05, 0.5), _sweep(300, 120, 0.2, "saw", 0.2)]))
	sounds.wire = _wav(_seq([[1800, 0.02], [2400, 0.03]], "square", 0.2))
	sounds.coins = _wav(_seq([[1319, 0.05], [1760, 0.05], [2093, 0.1]], "sine", 0.35))
	sounds.engine = _wav(_engine(), true)
	sounds.laser = _wav(_laser(), true)
	sounds.drill = _wav(_drill(), true)
	sounds.boost = _wav(_hiss(0.5, 0.25, 0.35), true)
	sounds.skid = _wav(_hiss(0.5, 0.7, 0.25), true)

func _wav(s: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var data = PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w

static func _osc(kind: String, ph: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		"saw":
			return fmod(ph, 1.0) * 2.0 - 1.0
	return sin(ph * TAU)

# A tone gliding from f0 to f1, decaying (decay = how fast it dies away).
func _sweep(f0: float, f1: float, dur: float, kind: String, amp: float, decay: float = 2.5) -> PackedFloat32Array:
	var n = int(dur * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var ph = 0.0
	for i in n:
		var t = float(i) / n
		ph += lerpf(f0, f1, t) / RATE
		var env = exp(-t * decay) * minf(1.0, i / 60.0)
		out[i] = _osc(kind, ph) * amp * env
	return out

func _seq(notes: Array, kind: String, amp: float) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	for nt in notes:
		out.append_array(_sweep(nt[0], nt[0], nt[1], kind, amp, 1.5))
	return out

# Noise through a one-pole low-pass that closes as it fades.
func _noise_burst(dur: float, amp: float, cutoff: float) -> PackedFloat32Array:
	var n = int(dur * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	for i in n:
		var t = float(i) / n
		var k = cutoff * (1.0 - t * 0.8)
		y += (randf_range(-1, 1) - y) * k
		out[i] = y * amp * exp(-t * 4.0) * 2.0
	return out

func _noise_sweep(dur: float, c0: float, c1: float, amp: float) -> PackedFloat32Array:
	var n = int(dur * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	for i in n:
		var t = float(i) / n
		y += (randf_range(-1, 1) - y) * lerpf(c0, c1, t)
		out[i] = y * amp * sin(PI * t) * 2.0
	return out

func _explosion(dur: float, amp: float) -> PackedFloat32Array:
	var n = int(dur * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	var ph = 0.0
	for i in n:
		var t = float(i) / n
		y += (randf_range(-1, 1) - y) * lerpf(0.5, 0.02, sqrt(t))
		ph += lerpf(70.0, 28.0, t) / RATE
		var env = exp(-t * 5.0) * minf(1.0, i / 40.0)
		out[i] = (y * 2.2 + sin(ph * TAU) * 0.7) * amp * env
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var n = 0
	for p in parts:
		n = maxi(n, p.size())
	var out = PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out

# Loops: whole numbers of cycles in each, so they loop without a click.
func _engine() -> PackedFloat32Array:
	var n = RATE
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	for i in n:
		var t = float(i) / RATE
		y += (randf_range(-1, 1) - y) * 0.05
		out[i] = (_osc("saw", 55.0 * t) * 0.35 + sin(110.0 * t * TAU) * 0.25 + y * 0.6) * (0.85 + 0.15 * sin(t * 6.0 * TAU))
	return out

func _laser() -> PackedFloat32Array:
	var n = RATE / 2
	var out = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t = float(i) / RATE
		out[i] = (_osc("saw", 180.0 * t) * 0.3 + _osc("square", 362.0 * t) * 0.15) * (0.8 + 0.2 * sin(t * 8.0 * TAU))
	return out

func _drill() -> PackedFloat32Array:
	var n = RATE / 2
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	for i in n:
		var t = float(i) / RATE
		y += (randf_range(-1, 1) - y) * 0.3
		out[i] = (y * 0.6 + _osc("square", 90.0 * t) * 0.2) * (0.6 + 0.4 * absf(sin(t * 30.0 * TAU)))
	return out

func _hiss(dur: float, cutoff: float, amp: float) -> PackedFloat32Array:
	var n = int(dur * RATE)
	var out = PackedFloat32Array()
	out.resize(n)
	var y = 0.0
	for i in n:
		y += (randf_range(-1, 1) - y) * cutoff
		out[i] = y * amp * 2.0
	# Fade the seam so the loop doesn't click.
	for i in 200:
		var k = i / 200.0
		out[i] *= k
		out[n - 1 - i] *= k
	return out
