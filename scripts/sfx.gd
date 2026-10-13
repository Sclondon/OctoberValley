extends Node
## Every sound in the game. Nothing is loaded from disk: the effects and the music are built
## here out of square waves, triangles and noise, a little each frame after start-up, so a
## sound asked for before it is ready is simply skipped.
##
##     Sfx.play("levelup")                     # everywhere
##     Sfx.at("hit", enemy.global_position)    # quieter with distance from the camera
##     Sfx.music("graveyard")                  # cross-fades; "" stops it
##
## Headless runs (the tests) build nothing and play nothing.

const RATE := 22050
const MUSIC_RATE := 11025
const VOICES := 12
## The same sound will not start twice inside this many seconds.
const MIN_GAP := 0.045
const HEARING := 48.0
const SFX_DB := -7.0
const MUSIC_DB := -15.0

const SQUARE := 0
const TRIANGLE := 1
const NOISE := 2
const SAW := 3

# sound: voices as [start s, length s, from Hz, to Hz, wave, gain, duty]
const SOUNDS := {
	"hit": [[0.0, 0.05, 2600.0, 700.0, NOISE, 0.45, 0.5], [0.0, 0.06, 240.0, 120.0, SQUARE, 0.28, 0.5]],
	"kill": [[0.0, 0.13, 520.0, 90.0, SQUARE, 0.4, 0.25], [0.0, 0.08, 1800.0, 400.0, NOISE, 0.3, 0.5]],
	"candy": [[0.0, 0.07, 880.0, 1320.0, SQUARE, 0.3, 0.25]],
	"heart": [[0.0, 0.1, 523.0, 523.0, TRIANGLE, 0.5, 0.5], [0.09, 0.16, 784.0, 784.0, TRIANGLE, 0.5, 0.5]],
	"chest": [[0.0, 0.09, 392.0, 392.0, SQUARE, 0.3, 0.5], [0.08, 0.09, 523.0, 523.0, SQUARE, 0.3, 0.5],
		[0.16, 0.09, 659.0, 659.0, SQUARE, 0.3, 0.5], [0.24, 0.3, 784.0, 784.0, SQUARE, 0.32, 0.5]],
	"levelup": [[0.0, 0.1, 523.0, 523.0, SQUARE, 0.3, 0.25], [0.09, 0.1, 659.0, 659.0, SQUARE, 0.3, 0.25],
		[0.18, 0.1, 784.0, 784.0, SQUARE, 0.3, 0.25], [0.27, 0.45, 1047.0, 1047.0, SQUARE, 0.32, 0.25],
		[0.27, 0.45, 523.0, 523.0, TRIANGLE, 0.35, 0.5]],
	"hurt": [[0.0, 0.22, 190.0, 60.0, SAW, 0.5, 0.5], [0.0, 0.1, 900.0, 300.0, NOISE, 0.35, 0.5]],
	"jump": [[0.0, 0.1, 260.0, 520.0, SQUARE, 0.2, 0.5]],
	"jump2": [[0.0, 0.11, 390.0, 820.0, SQUARE, 0.2, 0.25]],
	"slash": [[0.0, 0.12, 5200.0, 700.0, NOISE, 0.38, 0.5]],
	"bolt": [[0.0, 0.07, 950.0, 320.0, SQUARE, 0.16, 0.25]],
	"fire": [[0.0, 0.24, 500.0, 1700.0, NOISE, 0.3, 0.5], [0.0, 0.2, 160.0, 90.0, TRIANGLE, 0.3, 0.5]],
	"boom": [[0.0, 0.42, 1000.0, 70.0, NOISE, 0.55, 0.5], [0.0, 0.35, 120.0, 36.0, TRIANGLE, 0.6, 0.5]],
	"zap": [[0.0, 0.13, 1900.0, 180.0, SQUARE, 0.25, 0.12], [0.0, 0.16, 4000.0, 900.0, NOISE, 0.3, 0.5]],
	"splash": [[0.0, 0.2, 1500.0, 320.0, NOISE, 0.32, 0.5]],
	"throw": [[0.0, 0.14, 300.0, 640.0, TRIANGLE, 0.35, 0.5]],
	"boss": [[0.0, 0.95, 96.0, 38.0, SAW, 0.5, 0.5], [0.0, 0.8, 300.0, 80.0, NOISE, 0.4, 0.5],
		[0.1, 0.8, 49.0, 49.0, SQUARE, 0.3, 0.5]],
	"warn": [[0.0, 0.1, 620.0, 620.0, SQUARE, 0.22, 0.5], [0.14, 0.1, 620.0, 620.0, SQUARE, 0.22, 0.5],
		[0.28, 0.2, 830.0, 830.0, SQUARE, 0.24, 0.5]],
	"ring": [[0.0, 0.5, 700.0, 50.0, NOISE, 0.5, 0.5], [0.0, 0.5, 90.0, 30.0, TRIANGLE, 0.65, 0.5]],
	"altar": [[0.0, 0.7, 110.0, 110.0, TRIANGLE, 0.5, 0.5], [0.0, 0.7, 165.0, 164.0, TRIANGLE, 0.4, 0.5],
		[0.0, 0.25, 1200.0, 200.0, NOISE, 0.25, 0.5]],
	"portal": [[0.0, 0.14, 440.0, 440.0, TRIANGLE, 0.4, 0.5], [0.12, 0.14, 554.0, 554.0, TRIANGLE, 0.4, 0.5],
		[0.24, 0.14, 659.0, 659.0, TRIANGLE, 0.4, 0.5], [0.36, 0.14, 880.0, 880.0, TRIANGLE, 0.4, 0.5],
		[0.48, 0.6, 1108.0, 1108.0, TRIANGLE, 0.4, 0.5], [0.48, 0.6, 1320.0, 1330.0, SQUARE, 0.12, 0.25]],
	"move": [[0.0, 0.03, 660.0, 660.0, SQUARE, 0.14, 0.5]],
	"pick": [[0.0, 0.05, 660.0, 660.0, SQUARE, 0.22, 0.5], [0.05, 0.09, 990.0, 990.0, SQUARE, 0.22, 0.5]],
	"death": [[0.0, 0.3, 440.0, 330.0, SQUARE, 0.3, 0.5], [0.28, 0.3, 330.0, 220.0, SQUARE, 0.3, 0.5],
		[0.56, 0.7, 220.0, 55.0, SQUARE, 0.32, 0.5], [0.56, 0.7, 110.0, 40.0, TRIANGLE, 0.4, 0.5]],
	"beat": [[0.0, 0.12, 75.0, 45.0, TRIANGLE, 0.8, 0.5], [0.2, 0.14, 65.0, 40.0, TRIANGLE, 0.6, 0.5]],
	"spawn": [[0.0, 0.18, 140.0, 320.0, TRIANGLE, 0.3, 0.5]],
}

## What a shot or a burst sounds like, by its sprite sheet.
const SHEET_SOUNDS := {
	"bearclaw": "slash", "crossbow_bolt": "bolt", "fireball": "fire", "fireball_explosion": "boom",
	"lightning": "zap", "boomerang": "throw", "cursed_sword": "slash", "acid_potion": "throw",
	"acid_pool": "splash", "bat": "throw", "wisp": "throw",
}

# track: beats a minute, the key (Hz of its root), the chords (semitones above the root, one a
# bar) and the feel. Minor keys throughout.
const TRACKS := {
	"graveyard": {"bpm": 104.0, "root": 110.0, "chords": [0, 8, 5, 7, 0, 8, 3, 7], "seed": 11, "drive": false},
	"patch": {"bpm": 120.0, "root": 146.83, "chords": [0, 3, 8, 7, 0, 3, 5, 7], "seed": 23, "drive": false},
	"mire": {"bpm": 92.0, "root": 92.5, "chords": [0, 0, 5, 3, 0, 0, 8, 7], "seed": 37, "drive": false},
	"boss": {"bpm": 148.0, "root": 98.0, "chords": [0, 0, 1, 0, 0, 0, 8, 7], "seed": 5, "drive": true},
}
const MINOR := [0, 2, 3, 5, 7, 8, 10]

static var instance: Node
## Where sounds are heard from: main points this at the hero the camera follows.
static var listener: Node3D

var _streams := {}
var _last := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _tracks := {}
var _wanted := ""
var _playing := ""
var _building := false
var _fade: Tween
var _silent := false


static func play(sound: String, volume := 1.0, pitch := 1.0) -> void:
	if instance:
		instance._play(sound, volume, pitch)


static func at(sound: String, where: Vector3, volume := 1.0, pitch := 1.0) -> void:
	if instance == null:
		return
	var gain := 1.0
	if is_instance_valid(listener):
		gain = clampf(1.0 - listener.global_position.distance_to(where) / HEARING, 0.0, 1.0)
		gain *= gain
	if gain > 0.03:
		instance._play(sound, volume * gain, pitch)


## The sound of a shot or a burst drawn with `sheet`, if it has one.
static func for_sheet(sheet: String, where: Vector3) -> void:
	if SHEET_SOUNDS.has(sheet):
		at(SHEET_SOUNDS[sheet], where, 0.8, randf_range(0.92, 1.08))


static func music(track: String) -> void:
	if instance:
		instance._want(track)


static func set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(0, muted)


static func muted() -> bool:
	return AudioServer.is_bus_mute(0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instance = self
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -60.0
	add_child(_music)
	_build_sounds()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _play(sound: String, volume: float, pitch: float) -> void:
	if _silent or not _streams.has(sound) or volume <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -1.0)) < MIN_GAP:
		return
	_last[sound] = now
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	voice.stream = _streams[sound]
	voice.volume_db = SFX_DB + linear_to_db(clampf(volume, 0.01, 1.5))
	voice.pitch_scale = pitch
	voice.play()


func _want(track: String) -> void:
	if _silent or track == _wanted:
		return
	_wanted = track
	if track == "" or _tracks.has(track):
		_switch()
	elif not _building:
		_build_track(track)


func _switch() -> void:
	if _playing == _wanted:
		return
	_playing = _wanted
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", -60.0, 0.5)
	_fade.tween_callback(func() -> void:
		_music.stop()
		if _playing != "":
			_music.stream = _tracks[_playing]
			_music.play())
	if _playing != "":
		_fade.tween_property(_music, "volume_db", MUSIC_DB, 0.8)


# ---------------------------------------------------------------- building

func _build_sounds() -> void:
	for sound: String in SOUNDS:
		var length := 0.0
		for voice: Array in SOUNDS[sound]:
			length = maxf(length, voice[0] + voice[1])
		var samples := PackedFloat32Array()
		samples.resize(int(length * RATE) + 8)
		for voice: Array in SOUNDS[sound]:
			_voice(samples, RATE, voice[0], voice[1], voice[2], voice[3], voice[4], voice[5], voice[6], 2.0)
		_streams[sound] = _stream(samples, RATE, false)
		await get_tree().process_frame


## Writes a track a few notes a frame, then starts it if it is still the one wanted.
func _build_track(track: String) -> void:
	_building = true
	var def: Dictionary = TRACKS[track]
	var rng := RandomNumberGenerator.new()
	rng.seed = def["seed"]
	var step: float = 60.0 / def["bpm"] / 4.0  # a sixteenth
	var chords: Array = def["chords"]
	var root: float = def["root"]
	var samples := PackedFloat32Array()
	samples.resize(int(chords.size() * 16 * step * MUSIC_RATE))
	var lead_from := 12
	for bar in chords.size():
		var chord: int = chords[bar]
		var at := bar * 16 * step
		var tones := [chord, chord + 3 + (1 if chord in [1, 3, 8, 10] else 0), chord + 7]
		if chord == 7:
			tones[1] = chord + 4  # the major dominant pulls back to the root
		# bass: root and octave
		var bass: Array = [0, 4, 8, 12] if not def["drive"] else [0, 2, 4, 6, 8, 10, 12, 14]
		for i in bass.size():
			var up := 12 if (i % 4 == 2 or (def["drive"] and i % 2 == 1)) else 0
			_voice(samples, MUSIC_RATE, at + bass[i] * step, step * (3.2 if not def["drive"] else 1.7), _hz(root, chord + up), _hz(root, chord + up), TRIANGLE, 0.42, 0.5, 0.6)
		# arpeggio
		for i in 16:
			if not def["drive"] and i % 2 == 1 and rng.randf() < 0.35:
				continue
			var tone: int = tones[[0, 1, 2, 1][i % 4]] + 12 + (12 if i % 8 >= 4 else 0)
			_voice(samples, MUSIC_RATE, at + i * step, step * 0.9, _hz(root, tone), _hz(root, tone), SQUARE, 0.11, 0.25, 1.5)
		# lead: long chord tones, with a step between now and then
		var slots: Array = [[0, 8], [8, 8]] if bar % 2 == 0 else [[0, 6], [6, 2], [8, 8]]
		for slot: Array in slots:
			var note: int = tones[rng.randi_range(0, 2)] + 24
			if slot[1] == 2:
				note = _scale_step(lead_from, 1 if rng.randf() < 0.5 else -1)
			lead_from = note
			_voice(samples, MUSIC_RATE, at + slot[0] * step, slot[1] * step * 0.92, _hz(root, note), _hz(root, note), SQUARE, 0.14, 0.5, 0.8)
		# a tick on the off-beats, a thump on the beats when driving
		for i in 16:
			if i % 4 == 2:
				_voice(samples, MUSIC_RATE, at + i * step, 0.04, 5000.0, 3000.0, NOISE, 0.12, 0.5, 2.0)
			elif def["drive"] and i % 4 == 0:
				_voice(samples, MUSIC_RATE, at + i * step, 0.12, 160.0, 45.0, TRIANGLE, 0.38, 0.5, 2.0)
		await get_tree().process_frame
	_tracks[track] = _stream(samples, MUSIC_RATE, true)
	_building = false
	if _wanted == track:
		_switch()
	elif _wanted != "" and not _tracks.has(_wanted):
		_build_track(_wanted)
	else:
		_switch()


func _hz(root: float, semitones: int) -> float:
	return root * pow(2.0, semitones / 12.0)


## The note of the minor scale next to `semitones`, one step up or down.
func _scale_step(semitones: int, direction: int) -> int:
	var note := semitones + direction
	while not posmod(note, 12) in MINOR:
		note += direction
	return note


## Adds one voice to `samples`. `fade` shapes how fast it dies away (higher = plucked).
func _voice(samples: PackedFloat32Array, rate: int, start: float, length: float, from_hz: float, to_hz: float, wave: int, gain: float, duty: float, fade: float) -> void:
	var first := int(start * rate)
	var count := mini(int(length * rate), samples.size() - first)
	if count <= 0:
		return
	var attack := maxf(0.004 * rate, 1.0)
	var release := maxf(0.012 * rate, 1.0)
	var phase := 0.0
	var held := randf_range(-1.0, 1.0)
	var slide := to_hz - from_hz
	for i in count:
		var t := float(i) / count
		phase += (from_hz + slide * t) / rate
		var value := 0.0
		if wave == NOISE:
			if phase >= 1.0:
				phase -= 1.0
				held = randf_range(-1.0, 1.0)
			value = held
		else:
			phase -= floorf(phase)
			if wave == SQUARE:
				value = 1.0 if phase < duty else -1.0
			elif wave == TRIANGLE:
				value = 4.0 * absf(phase - 0.5) - 1.0
			else:
				value = 2.0 * phase - 1.0
		var level := minf(i / attack, 1.0) * minf((count - i) / release, 1.0) * pow(1.0 - t, fade)
		samples[first + i] += value * gain * level


func _stream(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
