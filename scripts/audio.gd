extends Node
## All sounds and the ambient score are synthesized locally; no licensed audio is used.

const SAMPLE_RATE: int = 22050
var _jump_enabled: bool = true
var _sfx_enabled: bool = true
var _music_enabled: bool = true
var _players: Dictionary = {}
var _music: AudioStreamPlayer
var _ready_audio: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var definitions: Dictionary = {
		"jump": [390.0, 760.0, 0.085, -19.0],
		"land": [180.0, 100.0, 0.08, -23.0],
		"coin": [1046.5, 1568.0, 0.17, -19.0],
		"hit": [155.0, 45.0, 0.30, -14.0],
		"record": [523.25, 1046.5, 0.54, -18.0],
		"level": [659.25, 1318.5, 0.68, -17.0],
		"button": [520.0, 680.0, 0.055, -25.0],
		"eat": [410.0, 180.0, 0.075, -25.0],
		"quake": [45.0, 29.0, 0.45, -21.0],
		"electric": [1300.0, 180.0, 0.50, -22.0]
	}
	for sound_name: String in definitions:
		var definition: Array = definitions[sound_name]
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Sound_" + sound_name
		player.max_polyphony = 4
		player.volume_db = float(definition[3])
		player.stream = _tone(sound_name, float(definition[0]), float(definition[1]), float(definition[2]))
		add_child(player)
		_players[sound_name] = player
	_music = AudioStreamPlayer.new()
	_music.name = "AmbientScore"
	_music.volume_db = -28.0
	_music.stream = _ambient_score()
	add_child(_music)
	_ready_audio = true
	var progress: Node = get_node_or_null("/root/Progress")
	if progress != null:
		_music_enabled = bool(progress.data["settings"]["music"])
		_sfx_enabled = bool(progress.data["settings"]["sfx"])
		_jump_enabled = bool(progress.data["settings"].get("jump_sfx", true))
	if _music_enabled:
		_music.play()

func play_sound(sound_name: String) -> void:
	if sound_name in ["jump", "land"] and not _jump_enabled:
		return
	if _sfx_enabled and _players.has(sound_name):
		var player: AudioStreamPlayer = _players[sound_name]
		player.play()

func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not _ready_audio:
		return
	if enabled and not _music.playing:
		_music.play()
	elif not enabled:
		_music.stop()

func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled
	if not enabled:
		for player: AudioStreamPlayer in _players.values():
			player.stop()

func set_jump_enabled(enabled: bool) -> void:
	_jump_enabled = enabled
	if not enabled:
		for key: String in ["jump", "land"]:
			if _players.has(key):
				_players[key].stop()

func _wav(samples: PackedByteArray, sample_count: int, loop: bool = false) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = samples
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream

func _tone(sound_name: String, initial: float, final: float, seconds: float) -> AudioStreamWAV:
	var count: int = int(seconds * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 430
	for index: int in count:
		var t: float = float(index) / float(SAMPLE_RATE)
		var fraction: float = t / seconds
		var frequency: float = lerpf(initial, final, fraction)
		if sound_name == "coin":
			frequency = initial if fraction < 0.42 else final
		elif sound_name in ["record", "level"]:
			var steps: Array[float] = [1.0, 1.25, 1.5, 2.0]
			frequency = initial * steps[mini(3, int(fraction * 4.0))]
		phase += TAU * frequency / float(SAMPLE_RATE)
		var envelope: float = minf(1.0, t / 0.008) * pow(maxf(0.0, 1.0 - fraction), 1.5)
		var value: float = sin(phase) * 0.73 + sin(phase * 2.0) * 0.17
		if sound_name == "hit":
			value = value * 0.4 + rng.randf_range(-0.6, 0.6)
		elif sound_name == "quake":
			value = sin(phase) * 0.7 + sin(phase * 0.47) * 0.2 + rng.randf_range(-0.12, 0.12)
		elif sound_name == "electric":
			var pulse := 0.45 + 0.55 * absf(sin(t * 83.0))
			value = (sin(phase) * 0.30 + signf(sin(phase * 0.51)) * 0.23 + rng.randf_range(-0.3, 0.3)) * pulse
		bytes.encode_s16(index * 2, int(clampf(value * envelope, -1.0, 1.0) * 26000.0))
	return _wav(bytes, count)

func _ambient_score() -> AudioStreamWAV:
	# Four gentle, low-pass-sounding pentatonic pads. Every edge fades to avoid clicks.
	var seconds: float = 16.0
	var count: int = int(seconds * SAMPLE_RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	var roots: Array[float] = [130.8128, 164.8138, 146.8324, 195.9977]
	var melody: Array[float] = [523.2511, 659.2551, 783.9909, 659.2551, 587.3295, 523.2511, 783.9909, 1046.5023]
	for index: int in count:
		var t: float = float(index) / float(SAMPLE_RATE)
		var chord_position: float = fmod(t, 4.0)
		var root_note: float = roots[mini(3, int(t / 4.0))]
		var envelope: float = sin(PI * chord_position / 4.0)
		var value: float = (sin(TAU * root_note * t) * 0.27 + sin(TAU * root_note * 1.5 * t) * 0.13 + sin(TAU * root_note * 2.0 * t) * 0.08) * envelope
		var note_position: float = fmod(t, 2.0)
		var note_envelope: float = minf(1.0, note_position / 0.03) * exp(-note_position * 2.4)
		value += sin(TAU * melody[mini(7, int(t / 2.0))] * t) * note_envelope * 0.14
		var edge_fade: float = minf(1.0, minf(t, seconds - t) * 3.0)
		bytes.encode_s16(index * 2, int(clampf(value * edge_fade, -1.0, 1.0) * 27000.0))
	return _wav(bytes, count, true)

func _exit_tree() -> void:
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	for player: AudioStreamPlayer in _players.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_players.clear()
