extends Node

# Tiny synthesised sound effects so the game has audio feedback without any
# sound files. Replace the entries in `streams` with real samples any time.

const RATE = 22050
const VOICES = 10

var streams = {}
var players = []
var next_voice = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	# name: duration, start Hz, end Hz, wave, volume, noise mix
	streams["shoot"] = _synth(0.09, 950.0, 260.0, "sine", 0.45, 0.35)
	streams["hit"] = _synth(0.07, 320.0, 140.0, "square", 0.35, 0.25)
	streams["crit"] = _synth(0.12, 700.0, 240.0, "square", 0.4, 0.2)
	streams["kill"] = _synth(0.18, 240.0, 50.0, "saw", 0.55, 0.5)
	streams["hurt"] = _synth(0.28, 170.0, 60.0, "saw", 0.7, 0.3)
	streams["pickup"] = _synth(0.07, 880.0, 1500.0, "sine", 0.3, 0.0)
	streams["blip"] = _synth(0.12, 660.0, 660.0, "sine", 0.4, 0.0)
	streams["pounce"] = _synth(0.2, 200.0, 700.0, "saw", 0.4, 0.6)
	streams["burst"] = _synth(0.4, 500.0, 60.0, "sine", 0.6, 0.7)
	streams["warn"] = _synth(0.1, 1100.0, 900.0, "square", 0.18, 0.0)
	streams["spawn"] = _synth(0.25, 90.0, 220.0, "sine", 0.35, 0.3)
	streams["boss"] = _synth(0.9, 110.0, 45.0, "saw", 0.7, 0.2)
	streams["grapple"] = _synth(0.06, 1400.0, 500.0, "sine", 0.25, 0.5)

func _synth(dur: float, f0: float, f1: float, wave: String, vol: float, noise: float) -> AudioStreamWAV:
	var n = int(dur * RATE)
	var data = PackedByteArray()
	data.resize(n * 2)
	var phase = 0.0
	for i in n:
		var t = float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var frac = fmod(phase, 1.0)
		var s = 0.0
		match wave:
			"square":
				s = 1.0 if frac < 0.5 else -1.0
			"saw":
				s = frac * 2.0 - 1.0
			_:
				s = sin(phase * TAU)
		s = lerpf(s, randf_range(-1.0, 1.0), noise)
		var env = (1.0 - t) * (1.0 - t) * minf(1.0, i / 40.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func play(sound: String, pitch: float = 1.0, pitch_spread: float = 0.08):
	if not streams.has(sound):
		return
	var p = players[next_voice]
	next_voice = (next_voice + 1) % VOICES
	p.stream = streams[sound]
	p.pitch_scale = maxf(0.1, pitch + randf_range(-pitch_spread, pitch_spread))
	p.volume_db = -6.0
	p.play()

# Rising three-note jingle for level ups and relics.
func jingle():
	for i in 3:
		get_tree().create_timer(0.09 * i, true, false, true).timeout.connect(play.bind("blip", 1.0 + 0.25 * i, 0.0))
