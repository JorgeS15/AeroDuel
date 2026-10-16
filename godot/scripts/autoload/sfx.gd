extends Node
## Autoload "Sfx": sons gerados por código no arranque (sem ficheiros de áudio).
## Mais tarde podem ser trocados por ficheiros .wav/.ogg com o mesmo nome.

const RATE := 22050
const VOICES := 10

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["shoot_me"] = _wav(_tone(900, 0.05, "square", 0.25, -350))
	_streams["shoot_foe"] = _wav(_tone(640, 0.05, "square", 0.12, -350))
	_streams["hit"] = _wav(_noise(0.15, 0.6, 2500))
	_streams["boom"] = _wav(_mix(_noise(0.7, 0.9, 700), _tone(90, 0.5, "sine", 0.5, -50)))
	_streams["eject"] = _wav(_tone(320, 0.2, "triangle", 0.4, 400))
	_streams["chute"] = _wav(_tone(520, 0.15, "sine", 0.3, -200))
	_streams["land"] = _wav(_tone(200, 0.08, "triangle", 0.3, -60))
	_streams["repair"] = _wav(_seq([[600, 0.08], [900, 0.1]], "square", 0.2, 0.09))
	_streams["win"] = _wav(_seq([[523, 0.18], [659, 0.18], [784, 0.18], [1046, 0.25]], "square", 0.22, 0.13))
	_streams["lose"] = _wav(_seq([[400, 0.25], [330, 0.25], [260, 0.35]], "triangle", 0.35, 0.18))


func play(sound: String) -> void:
	if not Game.sound_on or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.play()


# ---------- síntese ----------

func _tone(freq: float, dur: float, wave: String, vol: float, slide: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += maxf(30.0, freq + slide * k) / RATE
		var f := fmod(phase, 1.0)
		var s: float
		match wave:
			"square":
				s = 1.0 if f < 0.5 else -1.0
			"triangle":
				s = 4.0 * absf(f - 0.5) - 1.0
			_:
				s = sin(TAU * phase)
		out[i] = s * vol * pow(0.0001 / vol, k)
	return out


func _noise(dur: float, vol: float, cutoff: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var alpha := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		y += alpha * (randf_range(-1.0, 1.0) - y)
		out[i] = y * 2.0 * vol * pow(0.0001 / vol, float(i) / n)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


## Notas seguidas: cada nota começa `gap` segundos depois da anterior.
func _seq(notes: Array, wave: String, vol: float, gap: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in notes.size():
		var note := _tone(notes[i][0], notes[i][1], wave, vol, 0)
		var start := int(i * gap * RATE)
		if out.size() < start + note.size():
			out.resize(start + note.size())
		for j in note.size():
			out[start + j] += note[j]
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
