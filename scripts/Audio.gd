extends Node
## Procedural sound. Every effect is synthesized into an AudioStreamWAV at
## runtime, so there are no audio files to import - it just works on launch.
##
## Looping beds (ambient drone, heartbeat, alert music) play continuously and
## are mixed in/out by set_tension() based on how close you are to being caught.

const RATE := 22050

var streams := {}
var ambient_player: AudioStreamPlayer
var heart_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var _tension := 0.0


func _ready() -> void:
	_build_all()


# ===========================================================================
# Playback
# ===========================================================================
func play(sfx: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sfx):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[sfx]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func get_stream(nm: String) -> AudioStream:
	return streams.get(nm, null)


func start_loops() -> void:
	ambient_player = _make_loop_player("ambient", -17.0)
	heart_player = _make_loop_player("heartbeat", -60.0)
	music_player = _make_loop_player("music", -60.0)


func _make_loop_player(nm: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = streams[nm]
	p.volume_db = vol
	add_child(p)
	p.play()
	return p


## Drives the heartbeat + alert music from current detection (0..1).
## When the game is not active (win/fail) tension is forced to 0 so the beds fade.
func set_tension(t: float, playing: bool) -> void:
	var goal: float = t if playing else 0.0
	_tension = lerp(_tension, goal, 0.12)
	if heart_player:
		heart_player.volume_db = lerp(-60.0, -3.0, smoothstep(0.20, 0.95, _tension))
		heart_player.pitch_scale = lerp(0.85, 1.7, _tension)
	if music_player:
		music_player.volume_db = lerp(-60.0, -9.0, smoothstep(0.30, 0.85, _tension))


# ===========================================================================
# Sound bank
# ===========================================================================
func _build_all() -> void:
	streams["ambient"] = _make_ambient()
	streams["heartbeat"] = _make_heartbeat()
	streams["music"] = _make_music()
	streams["footstep"] = _make_footstep()
	streams["alert"] = _make_alert()
	streams["alarm"] = _make_alarm()
	streams["takedown"] = _make_takedown()
	streams["emp"] = _make_emp()
	streams["vision"] = _make_vision()
	streams["hack_beep"] = _make_hack_beep()
	streams["hack_done"] = _make_hack_done()
	streams["success"] = _make_success()
	streams["fail"] = _make_fail()


func _make_ambient() -> AudioStreamWAV:
	var b := _buf(2.0)
	_add_drone(b, 55.0, 0.13, 0.5, 0.5)
	_add_drone(b, 110.0, 0.06, 1.0, 0.4)
	_add_drone(b, 82.5, 0.05, 1.5, 0.4)
	_add_drone(b, 220.0, 0.02, 2.0, 0.6)
	_add_noise(b, 0.0, 2.0, 0.012, 0.0, 0.6)
	return _to_wav(b, true)


func _make_heartbeat() -> AudioStreamWAV:
	# 1.0s loop: lub-dub then rest. set_tension() raises pitch+volume as you near capture.
	var b := _buf(1.0)
	_add_tone(b, 60.0, 0.0, 0.16, 0.9, "sine", 3.0)
	_add_noise(b, 0.0, 0.03, 0.3, 2.0, 0.2)
	_add_tone(b, 52.0, 0.20, 0.18, 0.7, "sine", 3.0)
	_add_noise(b, 0.20, 0.03, 0.2, 2.0, 0.2)
	return _to_wav(b, true)


func _make_music() -> AudioStreamWAV:
	# 2.0s tense A-minor loop: driving low pulse + arp ostinato + high stabs.
	var b := _buf(2.0)
	var arp := [220.0, 261.6, 329.6, 261.6, 220.0, 261.6, 329.6, 392.0]
	for k in range(8):
		var t0 := k * 0.25
		_add_tone(b, 55.0, t0, 0.18, 0.5, "square", 1.6)       # bass pulse
		_add_tone(b, arp[k], t0 + 0.02, 0.16, 0.16, "tri", 1.2)  # arpeggio
	for k in range(4):
		_add_tone(b, 880.0, k * 0.5, 0.06, 0.10, "square", 1.0)  # high stab
	return _to_wav(b, true)


func _make_footstep() -> AudioStreamWAV:
	var b := _buf(0.14)
	_add_noise(b, 0.0, 0.13, 0.45, 3.0, 0.45)
	_add_tone(b, 70.0, 0.0, 0.12, 0.35, "sine", 4.0)
	return _to_wav(b, false)


func _make_alert() -> AudioStreamWAV:
	var b := _buf(0.32)
	_add_tone(b, 680.0, 0.0, 0.11, 0.38, "sine", 1.6)
	_add_tone(b, 1020.0, 0.13, 0.16, 0.38, "sine", 1.6)
	return _to_wav(b, false)


func _make_alarm() -> AudioStreamWAV:
	var b := _buf(0.72)
	_add_tone(b, 520.0, 0.0, 0.17, 0.42, "square", 0.6)
	_add_tone(b, 720.0, 0.18, 0.17, 0.42, "square", 0.6)
	_add_tone(b, 520.0, 0.36, 0.17, 0.42, "square", 0.6)
	_add_tone(b, 720.0, 0.54, 0.17, 0.42, "square", 0.8)
	return _to_wav(b, false)


func _make_takedown() -> AudioStreamWAV:
	var b := _buf(0.32)
	_add_noise(b, 0.0, 0.06, 0.6, 1.5, 0.2)
	_add_sweep(b, 150.0, 55.0, 0.0, 0.3, 0.5, "sine", 2.5)
	_add_tone(b, 90.0, 0.0, 0.28, 0.4, "sine", 3.0)
	return _to_wav(b, false)


func _make_emp() -> AudioStreamWAV:
	var b := _buf(0.6)
	_add_sweep(b, 1500.0, 70.0, 0.0, 0.45, 0.42, "square", 1.4)
	_add_noise(b, 0.0, 0.45, 0.22, 1.2, 0.3)
	_add_tone(b, 55.0, 0.4, 0.18, 0.4, "sine", 2.5)
	return _to_wav(b, false)


func _make_vision() -> AudioStreamWAV:
	var b := _buf(0.16)
	_add_tone(b, 1600.0, 0.0, 0.05, 0.3, "square", 1.0)
	_add_tone(b, 2300.0, 0.05, 0.07, 0.26, "square", 1.2)
	_add_noise(b, 0.0, 0.02, 0.18, 1.0, 0.1)
	return _to_wav(b, false)


func _make_hack_beep() -> AudioStreamWAV:
	var b := _buf(0.1)
	_add_tone(b, 900.0, 0.0, 0.09, 0.32, "sine", 1.2)
	return _to_wav(b, false)


func _make_hack_done() -> AudioStreamWAV:
	var b := _buf(0.5)
	_add_tone(b, 660.0, 0.0, 0.16, 0.36, "sine", 1.4)
	_add_tone(b, 880.0, 0.13, 0.16, 0.36, "sine", 1.4)
	_add_tone(b, 1320.0, 0.26, 0.22, 0.38, "sine", 1.6)
	return _to_wav(b, false)


func _make_success() -> AudioStreamWAV:
	var b := _buf(1.5)
	_add_tone(b, 523.0, 0.0, 0.9, 0.30, "sine", 1.4)
	_add_tone(b, 659.0, 0.16, 0.9, 0.30, "sine", 1.4)
	_add_tone(b, 784.0, 0.32, 0.9, 0.30, "sine", 1.4)
	_add_tone(b, 1046.0, 0.48, 1.0, 0.32, "sine", 1.3)
	return _to_wav(b, false)


func _make_fail() -> AudioStreamWAV:
	var b := _buf(1.1)
	_add_tone(b, 440.0, 0.0, 0.45, 0.36, "tri", 1.6)
	_add_tone(b, 330.0, 0.32, 0.45, 0.36, "tri", 1.6)
	_add_tone(b, 220.0, 0.62, 0.5, 0.38, "tri", 1.8)
	return _to_wav(b, false)


# ===========================================================================
# Synthesis primitives
# ===========================================================================
func _buf(dur: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(dur * RATE))
	a.fill(0.0)
	return a


func _wave(kind: String, ph: float) -> float:
	var f := fmod(ph, 1.0)
	if f < 0.0:
		f += 1.0
	match kind:
		"square":
			return 1.0 if f < 0.5 else -1.0
		"saw":
			return 2.0 * f - 1.0
		"tri":
			return 2.0 * abs(2.0 * f - 1.0) - 1.0
		_:
			return sin(TAU * f)


func _add_tone(b: PackedFloat32Array, freq: float, start: float, dur: float, amp: float, kind: String = "sine", curve: float = 2.0) -> void:
	var n0 := int(start * RATE)
	var n1 := mini(b.size(), int((start + dur) * RATE))
	var denom := float(maxi(1, n1 - n0))
	for i in range(n0, n1):
		var t := float(i - n0) / RATE
		var lt := float(i - n0) / denom
		var atk: float = clamp(t / 0.006, 0.0, 1.0)
		var env := atk * pow(1.0 - lt, curve)
		b[i] += _wave(kind, freq * t) * amp * env


func _add_sweep(b: PackedFloat32Array, f0: float, f1: float, start: float, dur: float, amp: float, kind: String = "sine", curve: float = 2.0) -> void:
	var n0 := int(start * RATE)
	var n1 := mini(b.size(), int((start + dur) * RATE))
	var denom := float(maxi(1, n1 - n0))
	var phase := 0.0
	for i in range(n0, n1):
		var lt := float(i - n0) / denom
		var f: float = lerp(f0, f1, lt)
		phase += f / RATE
		var t := float(i - n0) / RATE
		var atk: float = clamp(t / 0.006, 0.0, 1.0)
		var env := atk * pow(1.0 - lt, curve)
		b[i] += _wave(kind, phase) * amp * env


func _add_noise(b: PackedFloat32Array, start: float, dur: float, amp: float, curve: float = 2.0, smooth: float = 0.0) -> void:
	var n0 := int(start * RATE)
	var n1 := mini(b.size(), int((start + dur) * RATE))
	var denom := float(maxi(1, n1 - n0))
	var prev := 0.0
	for i in range(n0, n1):
		var lt := float(i - n0) / denom
		var r := randf() * 2.0 - 1.0
		if smooth > 0.0:
			r = lerp(r, prev, smooth)
			prev = r
		var env := 1.0
		if curve > 0.0:
			env = pow(1.0 - lt, curve)
		b[i] += r * amp * env


func _add_drone(b: PackedFloat32Array, freq: float, amp: float, lfo_rate: float, lfo_depth: float) -> void:
	for i in b.size():
		var t := float(i) / RATE
		var lfo := 1.0 - lfo_depth + lfo_depth * 0.5 * (1.0 + sin(TAU * lfo_rate * t))
		b[i] += amp * lfo * sin(TAU * freq * t)


func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clamp(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = samples.size() - 1
	return st
