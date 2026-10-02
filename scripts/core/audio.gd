extends Node
## Audio: recorded CC0 foley (Kenney: footsteps, blades, shields, doors, coins, interface) where
## available; everything else - animals, voices, weather and ambience beds, and the lute
## "minstrel" music - is synthesised at load (cached to user:// after the first run).

const RATE := 22050
const CACHE := "user://sfx_cache_v2/"
const SOUNDS := "res://sounds/"
## sound name -> recorded variations in res://sounds (loaded directly; the folder is not imported)
const RECORDED := {
	"step_grass": ["footstep_grass_000", "footstep_grass_001", "footstep_grass_002", "footstep_grass_003", "footstep_grass_004"],
	"step_stone": ["footstep_concrete_000", "footstep_concrete_001", "footstep_concrete_002", "footstep_concrete_003", "footstep_concrete_004"],
	"step_wood": ["footstep_wood_000", "footstep_wood_001", "footstep_wood_002", "footstep_wood_003", "footstep_wood_004"],
	"step_snow": ["footstep_snow_000", "footstep_snow_001", "footstep_snow_002", "footstep_snow_003", "footstep_snow_004"],
	"step_sand": ["footstep_carpet_000", "footstep_carpet_001", "footstep_carpet_002", "footstep_carpet_003", "footstep_carpet_004"],
	"hit_flesh": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002", "impactPunch_medium_003", "impactPunch_medium_004"],
	"hit_metal": ["impactMetal_heavy_000", "impactMetal_heavy_001", "impactMetal_heavy_002", "impactMetal_heavy_003", "impactMetal_heavy_004"],
	"block": ["impactWood_heavy_000", "impactWood_heavy_001", "impactWood_heavy_002", "impactWood_heavy_003", "impactWood_heavy_004"],
	"door_open": ["doorOpen_1", "doorOpen_2"],
	"door_close": ["doorClose_1", "doorClose_2", "doorClose_3", "doorClose_4"],
	"chest": ["creak1", "creak2", "creak3"],
	"coin": ["handleCoins", "handleCoins2"],
	"unsheathe": ["drawKnife1", "drawKnife2", "drawKnife3"],
	"sheathe": ["beltHandle1", "beltHandle2"],
	"skin": ["knifeSlice", "knifeSlice2"],
	"ui_click": ["click_001"],
	"ui_hover": ["tick_001"],
	"ui_open": ["open_001"],
	"ui_close": ["close_001"],
	"ui_coin": ["handleCoins"],
	"hoof_hard": ["impactWood_light_000", "impactWood_light_001", "impactWood_light_002", "impactWood_light_003"],
	"hoof_soft": ["impactSoft_medium_000", "impactSoft_medium_001", "impactSoft_medium_002", "impactSoft_medium_003"],
	"whoosh": ["cloth1", "cloth2", "cloth3", "cloth4"],
	"parry": ["impactMetal_light_000", "impactMetal_light_001", "impactMetal_light_002"],
	"hit_heavy": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002"],
	"item_pick": ["handleSmallLeather", "handleSmallLeather2"],
	"item_drop": ["dropLeather"],
	"equip": ["metalClick"],
	"ui_book_open": ["bookOpen"],
	"ui_book_close": ["bookClose"],
	"ui_page": ["bookFlip1", "bookFlip2", "bookFlip3"],
}
## loudness matching for the recordings (dB, measured offline: mean level matched to the
## synthesised set, peaks kept under -1 dB); files not listed play as they are
const RECORDED_GAIN := {"beltHandle1": 2.3, "beltHandle2": 3.2, "click_001": 0.4, "close_001": -4.2, "confirmation_001": -7.7, "creak1": 5.7, "creak2": 6.0, "creak3": 3.7, "doorClose_1": -1.0, "doorClose_2": 0.8, "doorClose_3": -4.9, "doorClose_4": -1.0, "doorOpen_1": -1.0, "doorOpen_2": -1.0, "drawKnife1": 23.3, "drawKnife2": 21.9, "drawKnife3": 10.4, "handleCoins": -1.0, "handleCoins2": 9.7, "knifeSlice": 0.3, "knifeSlice2": -1.0, "metalLatch": -1.0,
	"cloth1": 2.5, "cloth2": 6.9, "cloth3": 9.1, "cloth4": 13.6, "handleSmallLeather": 10.6, "handleSmallLeather2": 15.5, "bookOpen": 10.5,
	"bookFlip2": 7.3, "bookFlip3": 3.6, "metalClick": 5.9, "impactMetal_light_002": 0.4, "dropLeather": -0.9, "bookClose": -1.0, "bookFlip1": -1.0, "open_001": -4.2, "tick_001": -0.2, "footstep_snow_001": -1.3, "footstep_snow_002": -1.2, "impactPunch_medium_000": -0.8, "impactPunch_medium_001": -1.1}

var sfx := {}              # name -> Array of AudioStream variations
var sfx_gain := {}         # name -> Array of per-variation gain (dB)
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _ui: AudioStreamPlayer
var _amb := {}             # name -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_pb: AudioStreamGeneratorPlayback
var _ready_flag := false
var _rng := RandomNumberGenerator.new()
# minstrel state
var _voices: Array = []
var _note_t := 0.0
var _beat := 0.0
var _mode: Array = [0, 2, 3, 5, 7, 9, 10]
var _root_hz := 146.83
var _degree := 0
var _phrase_left := 0
var _playing := false
var _rest_t := 25.0
var _tempo := 84.0
var _style := "lute"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 99
	for i in 28:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 70.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)


# ------------------------------------------------------------------ public API
func generate_all() -> void:
	if _ready_flag:
		return
	DirAccess.make_dir_recursive_absolute(CACHE)
	var defs := _defs()
	for name in defs:
		var arr: Array = _recorded(name)
		if not arr.is_empty():
			sfx[name] = arr
			var gl := []
			for f in RECORDED[name]:
				gl.append(float(RECORDED_GAIN.get(f, 0.0)))
			sfx_gain[name] = gl
			continue
		for v in int(defs[name][1]):
			var path := CACHE + "%s_%d.wav" % [name, v]
			var st: AudioStreamWAV = null
			if FileAccess.file_exists(path):
				st = AudioStreamWAV.load_from_file(path)
			if st == null:
				_rng.seed = hash(name) + v * 7919
				var data: PackedFloat32Array = (defs[name][0] as Callable).call(v)
				st = _to_wav(data, bool(defs[name][2]))
				st.save_to_wav(path)
			arr.append(st)
		sfx[name] = arr
	_ready_flag = true


func _recorded(name: String) -> Array:
	var out := []
	for f in RECORDED.get(name, []):
		var st := AudioStreamOggVorbis.load_from_file(SOUNDS + String(f) + ".ogg")
		if st:
			out.append(st)
	return out


func footstep(pos: Vector3, surface: String, sprint: bool) -> void:
	play_at("step_" + surface, pos, -10.0 if not sprint else -6.0, 1.0 + randf_range(-0.08, 0.08))


func play_at(name: String, pos: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if not sfx.has(name):
		return
	var arr: Array = sfx[name]
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	var i := randi() % arr.size()
	p.stream = arr[i]
	var g: float = sfx_gain[name][i] if sfx_gain.has(name) else 0.0
	p.volume_db = vol + g + linear_to_db(maxf(float(Game.settings.sfx_volume), 0.001))
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.global_position = pos
	p.play()


func ui(name: String) -> void:
	if not sfx.has("ui_" + name):
		return
	_ui.stream = sfx["ui_" + name][0]
	var g: float = sfx_gain["ui_" + name][0] if sfx_gain.has("ui_" + name) else 0.0
	_ui.volume_db = -8.0 + g + linear_to_db(maxf(float(Game.settings.sfx_volume), 0.001))
	_ui.play()


func voice(gender: String, pos: Vector3) -> void:
	play_at("voice_" + ("f" if gender == "f" else "m"), pos, -4.0)


func start_ambience() -> void:
	generate_all()
	for n in ["amb_wind", "amb_rain", "amb_forest", "amb_night", "amb_river", "amb_fire", "amb_tavern", "amb_ocean"]:
		if _amb.has(n) or not sfx.has(n):
			continue
		var a := AudioStreamPlayer.new()
		a.stream = sfx[n][0]
		a.volume_db = -80.0
		add_child(a)
		a.play()
		_amb[n] = a
	if _music == null:
		_music = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.25
		_music.stream = gen
		_music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM    # browsers play other sounds as samples; music is generated
		add_child(_music)
		_music.play()
		_music_pb = _music.get_stream_playback()


# ------------------------------------------------------------------ ambience mix
func _process(delta: float) -> void:
	if _amb.is_empty() or Game.player_ref == null or Game.world_ref == null or Game.world_ref.atmosphere == null:
		_fill_music(delta)
		return
	var pl: Player = Game.player_ref
	var p := pl.global_position
	var atm: Atmosphere = Game.world_ref.atmosphere
	var night := Game.is_night()
	var b := WorldData.biome_at(p.x, p.z)
	var water := false
	for o in [Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 12), Vector3(0, 0, -12), Vector3.ZERO]:
		if WorldData.water_depth_at(p.x + o.x, p.z + o.z) > 0.3 and WorldData.water_level_at(p.x + o.x, p.z + o.z) > 0.5:
			water = true
	var ocean := WorldData.water_level_at(p.x, p.z) < 0.5 and b in [WorldData.Biome.BEACH, WorldData.Biome.OCEAN]
	var in_tavern := pl.indoors and _near_tavern(p)
	var fire: bool = Game.world_ref.call("fire_near", p, 9.0)
	var wind := float(atm.params.wind)
	var amb_vol := float(Game.settings.sfx_volume) * (0.25 if pl.indoors else 1.0)
	var targets := {
		"amb_wind": clampf(0.15 + wind * 0.8 + (0.3 if b in [WorldData.Biome.SNOW, WorldData.Biome.MOUNTAIN, WorldData.Biome.TUNDRA] else 0.0), 0, 1) * amb_vol,
		"amb_rain": (float(atm.params.precip) if atm.precip_kind == "rain" else 0.0) * amb_vol,
		"amb_forest": (0.7 if b in [WorldData.Biome.FOREST, WorldData.Biome.PLAINS] and not night and float(atm.params.precip) < 0.3 else 0.0) * amb_vol,
		"amb_night": (0.6 if night and b in [WorldData.Biome.FOREST, WorldData.Biome.PLAINS, WorldData.Biome.DESERT] else 0.0) * amb_vol,
		"amb_river": (0.8 if water else 0.0) * amb_vol,
		"amb_fire": 0.8 * float(Game.settings.sfx_volume) if fire else 0.0,
		"amb_tavern": 0.7 * float(Game.settings.sfx_volume) if in_tavern else 0.0,
		"amb_ocean": (0.8 if ocean else 0.0) * amb_vol,
	}
	for k in targets:
		var a: AudioStreamPlayer = _amb[k]
		var cur := db_to_linear(a.volume_db)
		var t: float = targets[k]
		cur = lerpf(cur, t, 1.0 - exp(-delta * 1.2))
		a.volume_db = linear_to_db(maxf(cur, 0.0001))
	_style = "oud" if b == WorldData.Biome.DESERT else ("jig" if in_tavern else ("frost" if b in [WorldData.Biome.TUNDRA, WorldData.Biome.SNOW] else "lute"))
	_fill_music(delta)


func _near_tavern(p: Vector3) -> bool:
	var s = Game.world_ref.settlements
	if s == null:
		return false
	for info in s.infos:
		if (info.center as Vector3).distance_to(p) > 200.0:
			continue
		for bd in info.buildings:
			if bd.type == "tavern" and (bd.center as Vector3).distance_to(p) < 8.0:
				return true
	return false


func lightning(distance: float) -> void:
	await get_tree().create_timer(distance / 343.0).timeout
	if sfx.has("thunder"):
		_ui.stream = sfx.thunder[randi() % sfx.thunder.size()]
		_ui.volume_db = lerpf(0.0, -14.0, clampf(distance / 2500.0, 0, 1)) + linear_to_db(maxf(float(Game.settings.sfx_volume), 0.001))
		_ui.play()


# ------------------------------------------------------------------ minstrel (Karplus-Strong lute)
func _fill_music(delta: float) -> void:
	if _music_pb == null:
		return
	var frames := _music_pb.get_frames_available()
	if frames <= 0:
		return
	var vol := float(Game.settings.music_volume) * 0.32
	if not _playing:
		_rest_t -= delta
		if _rest_t <= 0.0:
			_start_piece()
	var buf := PackedVector2Array()
	buf.resize(frames)
	var spb := 60.0 / _tempo / 2.0     # eighth notes
	for i in frames:
		if _playing:
			_note_t -= 1.0 / RATE
			if _note_t <= 0.0:
				_next_note()
				_note_t += spb * (2.0 if _rng.randf() < 0.3 else 1.0)
		var s := 0.0
		for v in _voices:
			var line: PackedFloat32Array = v.buf
			var n: int = v.n
			var idx: int = v.i
			var nxt := (idx + 1) % n
			var out := line[idx]
			line[idx] = (out + line[nxt]) * 0.5 * float(v.damp)
			v.i = nxt
			s += out * float(v.amp)
		buf[i] = Vector2(s, s) * vol
	_music_pb.push_buffer(buf)
	for k in range(_voices.size() - 1, -1, -1):
		_voices[k].life -= delta
		if _voices[k].life <= 0.0:
			_voices.remove_at(k)


func _start_piece() -> void:
	_playing = true
	_phrase_left = _rng.randi_range(48, 96)
	match _style:
		"oud":
			_mode = [0, 1, 4, 5, 7, 8, 10]     # phrygian dominant
			_root_hz = 130.81
			_tempo = 76.0
		"jig":
			_mode = [0, 2, 4, 5, 7, 9, 10]     # mixolydian
			_root_hz = 196.0
			_tempo = 132.0
		"frost":
			_mode = [0, 2, 3, 5, 7, 8, 10]     # aeolian
			_root_hz = 110.0
			_tempo = 60.0
		_:
			_mode = [0, 2, 3, 5, 7, 9, 10] if not Game.is_night() else [0, 2, 3, 5, 7, 8, 10]
			_root_hz = 146.83
			_tempo = 84.0 if not Game.is_night() else 66.0
	_degree = 0


func _next_note() -> void:
	if _phrase_left <= 0:
		_playing = false
		_rest_t = _rng.randf_range(40.0, 110.0)
		return
	_phrase_left -= 1
	_beat += 1.0
	# melody: random walk on the mode, gravitating home at phrase ends
	var step: int = [-2, -1, -1, 1, 1, 2, 0, 3, -3][_rng.randi() % 9]
	if int(_beat) % 16 == 15:
		step = -_degree
	_degree = clampi(_degree + step, -3, 9)
	if _rng.randf() < 0.82:
		_pluck(_hz(_degree + 7), 0.55, 0.996 if _style != "oud" else 0.993)
	if int(_beat) % 4 == 0:
		_pluck(_hz(0), 0.42, 0.997)
		if _rng.randf() < 0.5:
			_pluck(_hz(4), 0.25, 0.997)


func _hz(deg: int) -> float:
	var octave := floori(float(deg) / 7.0)
	var d := posmod(deg, 7)
	return _root_hz * pow(2.0, octave + float(_mode[d]) / 12.0)


func _pluck(hz: float, amp: float, damp: float) -> void:
	if _voices.size() >= 6:
		_voices.remove_at(0)
	var n := maxi(int(RATE / hz), 2)
	var line := PackedFloat32Array()
	line.resize(n)
	for i in n:
		line[i] = _rng.randf_range(-1.0, 1.0)
	# soften the attack a little (pick position)
	for i in range(1, n):
		line[i] = (line[i] + line[i - 1]) * 0.5
	_voices.append({"buf": line, "n": n, "i": 0, "amp": amp, "damp": damp, "life": 3.0})


# ------------------------------------------------------------------ synthesis
func _to_wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for x in data:
		peak = maxf(peak, absf(x))
	var g := 0.89 / peak
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(secs * RATE))
	return b


## Biquad band-pass applied in place.
func _bandpass(x: PackedFloat32Array, f: float, q: float) -> void:
	var w0 := TAU * f / RATE
	var alpha := sin(w0) / (2.0 * q)
	var b0 := alpha
	var b2 := -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var xi := x[i]
		var y := (b0 * xi + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = y
		x[i] = y


func _lowpass(x: PackedFloat32Array, f: float) -> void:
	var a := 1.0 - exp(-TAU * f / RATE)
	var y := 0.0
	for i in x.size():
		y += (x[i] - y) * a
		x[i] = y


func _noise(x: PackedFloat32Array, amp := 1.0) -> void:
	for i in x.size():
		x[i] += _rng.randf_range(-amp, amp)


func _env(x: PackedFloat32Array, attack: float, decay: float) -> void:
	for i in x.size():
		var t := float(i) / RATE
		var e := minf(t / maxf(attack, 0.0001), 1.0) * exp(-maxf(t - attack, 0.0) / decay)
		x[i] *= e


func _tone(x: PackedFloat32Array, f0: float, f1: float, amp: float, decay: float, shape := "sine", start := 0.0, vib := 0.0) -> void:
	var ph := 0.0
	var s := int(start * RATE)
	for i in range(s, x.size()):
		var t := float(i - s) / RATE
		var k := float(i - s) / maxf(x.size() - s, 1)
		var f := lerpf(f0, f1, k) * (1.0 + vib * sin(t * 37.0))
		ph += TAU * f / RATE
		var v := sin(ph)
		match shape:
			"saw": v = fposmod(ph / TAU, 1.0) * 2.0 - 1.0
			"square": v = 1.0 if sin(ph) > 0.0 else -1.0
		x[i] += v * amp * exp(-t / decay)


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, at: float, gain := 1.0) -> void:
	var s := int(at * RATE)
	for i in b.size():
		if s + i < a.size():
			a[s + i] += b[i] * gain


func _loop_fade(x: PackedFloat32Array, secs: float) -> void:
	var n := mini(int(secs * RATE), x.size() / 3)
	var L := x.size()
	for i in n:
		var t := float(i) / n
		x[i] = x[i] * t + x[L - n + i] * (1.0 - t)
	x.resize(L - n)


const SOUND_SPECS := {
	"step_grass": 4, "step_stone": 4, "step_wood": 4, "step_snow": 4, "step_sand": 3, "step_water": 3, "swing": 3, "hit_flesh": 3, "hit_metal": 3,
	"block": 2, "door_open": 2, "door_close": 2, "chest": 1, "coin": 2, "drink": 1, "unsheathe": 1, "sheathe": 1, "whistle": 1, "hoof": 3,
	"growl": 2, "howl": 2, "bite": 2, "quack": 2, "honk": 2, "cow": 1, "sheep": 1, "pig": 1, "hen": 1, "dog": 1, "donkey": 1, "alpaca": 1,
	"skin": 1, "portcullis": 1, "thunder": 3, "ui_click": 1, "ui_hover": 1, "ui_open": 1, "ui_close": 1, "ui_coin": 1, "voice_m": 4, "voice_f": 4,
	"amb_wind": 1, "amb_rain": 1, "amb_forest": 1, "amb_night": 1, "amb_river": 1, "amb_fire": 1, "amb_tavern": 1, "amb_ocean": 1,
	"neigh": 2, "snort": 2, "hoof_hard": 1, "hoof_soft": 1, "whoosh": 1, "parry": 1, "hit_heavy": 1, "item_pick": 1, "item_drop": 1, "equip": 1,
	"ui_book_open": 1, "ui_book_close": 1, "ui_page": 1,
}


func _defs() -> Dictionary:
	var d := {}
	for n in SOUND_SPECS:
		d[n] = [_gen.bind(n), SOUND_SPECS[n], n.begins_with("amb_")]
	return d


func _gen(v: int, n: String) -> PackedFloat32Array:
	var x: PackedFloat32Array
	match n:
		"step_grass":
			x = _buf(0.12)
			_noise(x)
			_bandpass(x, 2600.0 + v * 400.0, 0.8)
			_env(x, 0.004, 0.035)
			var y := _buf(0.12)
			_tone(y, 90.0, 60.0, 0.6, 0.03)
			_mix(x, y, 0.0)
		"step_stone":
			x = _buf(0.1)
			_noise(x)
			_bandpass(x, 4200.0 + v * 600.0, 2.0)
			_env(x, 0.001, 0.012)
			var y := _buf(0.1)
			_tone(y, 140.0, 110.0, 0.8, 0.025)
			_mix(x, y, 0.0)
		"step_wood":
			x = _buf(0.16)
			_noise(x)
			var a := x.duplicate()
			_bandpass(x, 320.0 + v * 30.0, 6.0)
			_bandpass(a, 760.0, 5.0)
			_mix(x, a, 0.0, 0.6)
			_env(x, 0.002, 0.05)
		"step_snow":
			x = _buf(0.2)
			for i in x.size():
				x[i] = _rng.randf_range(-1, 1) * (1.0 if _rng.randf() < 0.3 else 0.2)
			_lowpass(x, 3000.0)
			_env(x, 0.02, 0.06)
		"step_sand":
			x = _buf(0.16)
			_noise(x)
			_lowpass(x, 1800.0)
			_env(x, 0.01, 0.05)
		"step_water":
			x = _buf(0.3)
			_noise(x)
			_bandpass(x, 1400.0 + v * 300.0, 1.2)
			_env(x, 0.005, 0.09)
			var y := _buf(0.3)
			_tone(y, 500.0, 900.0, 0.2, 0.05, "sine", 0.03)
			_mix(x, y, 0.0)
		"swing":
			x = _buf(0.32)
			var lp := 0.0
			for i in x.size():
				var k := float(i) / x.size()
				lp += (_rng.randf_range(-1, 1) - lp) * (1.0 - exp(-TAU * lerpf(500.0, 2600.0, k) / RATE))
				x[i] = lp * sin(k * PI)
		"hit_flesh":
			x = _buf(0.2)
			_noise(x)
			_lowpass(x, 700.0)
			_env(x, 0.002, 0.05)
			var y := _buf(0.2)
			_tone(y, 110.0, 60.0, 1.0, 0.06)
			_mix(x, y, 0.0)
		"hit_metal":
			x = _buf(0.9)
			for f in [523.0, 1309.0, 2093.0, 3301.0, 4400.0]:
				_tone(x, f * (1.0 + v * 0.03), f * 0.99, 0.3, 0.25 + 0.4 / (f / 500.0))
			var nz := _buf(0.9)
			_noise(nz, 0.6)
			_env(nz, 0.0005, 0.01)
			_mix(x, nz, 0.0)
		"block":
			x = _buf(0.6)
			for f in [420.0, 980.0, 1720.0]:
				_tone(x, f, f * 0.98, 0.35, 0.18)
			var nz := _buf(0.6)
			_noise(nz)
			_lowpass(nz, 900.0)
			_env(nz, 0.001, 0.04)
			_mix(x, nz, 0.0, 1.2)
		"door_open", "chest":
			x = _buf(0.9)
			_tone(x, 180.0, 260.0, 0.4, 2.0, "saw", 0.0, 0.08)
			_bandpass(x, 900.0, 3.0)
			var nz := _buf(0.9)
			_noise(nz, 0.3)
			_bandpass(nz, 1200.0, 4.0)
			_mix(x, nz, 0.0)
			_env(x, 0.05, 0.6)
			if n == "chest":
				var th := _buf(0.4)
				_noise(th)
				_lowpass(th, 500.0)
				_env(th, 0.001, 0.08)
				_mix(x, th, 0.45)
		"door_close":
			x = _buf(0.4)
			_noise(x)
			_lowpass(x, 400.0)
			_env(x, 0.002, 0.07)
			var c := _buf(0.2)
			_noise(c)
			_bandpass(c, 3000.0, 3.0)
			_env(c, 0.001, 0.01)
			_mix(x, c, 0.12, 0.6)
		"coin", "ui_coin":
			x = _buf(0.6)
			for k in 3:
				var y := _buf(0.4)
				_tone(y, 3200.0 + k * 700.0 + v * 200.0, 3150.0 + k * 700.0, 0.4, 0.09)
				_mix(x, y, k * 0.07)
		"drink":
			x = _buf(0.9)
			for k in 3:
				var y := _buf(0.25)
				_tone(y, 240.0, 120.0, 0.6, 0.06)
				_mix(x, y, 0.1 + k * 0.25)
		"unsheathe", "sheathe":
			x = _buf(0.5 if n == "unsheathe" else 0.35)
			_noise(x)
			_bandpass(x, 5200.0 if n == "unsheathe" else 3600.0, 2.0)
			for i in x.size():
				x[i] *= sin(float(i) / x.size() * PI)
		"whistle":
			x = _buf(1.0)
			_tone(x, 1900.0, 2500.0, 0.6, 1.5, "sine", 0.0, 0.01)
			var y := _buf(0.45)
			_tone(y, 2500.0, 1800.0, 0.6, 1.0)
			_mix(x, y, 0.55)
			_env(x, 0.03, 0.8)
		"neigh":
			# a whinny: a sharp rise, then a long quavering fall
			x = _buf(1.5)
			var phn := 0.0
			for i in x.size():
				var t := float(i) / RATE
				var f := (1150.0 + v * 70.0 if t < 0.12 else lerpf(1380.0 + v * 60.0, 470.0, clampf((t - 0.12) / 1.25, 0.0, 1.0))) * (1.0 + 0.055 * sin(t * TAU * 11.0) * clampf(t * 4.0, 0.0, 1.0))
				phn += TAU * f / RATE
				var sg := sin(phn) + 0.55 * sin(phn * 2.0) + 0.3 * sin(phn * 3.0) + 0.15 * sin(phn * 4.0)
				x[i] = sg * minf(t / 0.04, 1.0) * clampf((1.5 - t) / 0.4, 0.0, 1.0) * 0.4
			var yn := _buf(1.5)
			_noise(yn, 0.3)
			_bandpass(yn, 1700.0, 1.2)
			_env(yn, 0.02, 0.5)
			_mix(x, yn, 0.0)
		"snort":
			x = _buf(0.7)
			_noise(x)
			_bandpass(x, 650.0 + v * 180.0, 1.1)
			for i in x.size():
				var t := float(i) / RATE
				x[i] *= (0.55 + 0.45 * sin(t * TAU * 38.0)) * minf(t / 0.03, 1.0) * exp(-t / 0.2) * 1.6
		"hoof":
			x = _buf(0.25)
			for k in 2:
				var y := _buf(0.12)
				_noise(y)
				_bandpass(y, 260.0 + k * 500.0, 4.0)
				_env(y, 0.001, 0.03)
				_mix(x, y, k * 0.07)
		"growl":
			x = _buf(1.4)
			_noise(x)
			_lowpass(x, 260.0)
			for i in x.size():
				x[i] *= 0.6 + 0.4 * sin(float(i) / RATE * TAU * 23.0)
			var y := _buf(1.4)
			_tone(y, 70.0, 55.0, 0.6, 2.0, "saw")
			_lowpass(y, 300.0)
			_mix(x, y, 0.0)
			_env(x, 0.15, 0.9)
		"howl":
			x = _buf(2.8)
			var ph := 0.0
			for i in x.size():
				var t := float(i) / RATE
				var f := (420.0 + v * 30.0 + 300.0 * sin(clampf(t / 2.4, 0, 1) * PI) - t * 40.0) * (1.0 + 0.012 * sin(t * 31.0))
				ph += TAU * f / RATE
				x[i] = (sin(ph) + 0.3 * sin(ph * 2.0) + 0.1 * sin(ph * 3.0)) * sin(clampf(t / 2.8, 0, 1) * PI)
		"bite":
			x = _buf(0.2)
			_noise(x)
			_bandpass(x, 1800.0, 1.5)
			_env(x, 0.001, 0.03)
		"quack", "honk", "hen", "pig", "dog":
			var cfg: Array = {"quack": [2, 0.15, 320.0, 280.0, "square", 1100.0, 0.18], "honk": [2, 0.28, 260.0, 240.0, "saw", 800.0, 0.3],
				"hen": [4, 0.08, 620.0, 560.0, "square", 1500.0, 0.15], "pig": [3, 0.15, 160.0, 120.0, "saw", 500.0, 0.18], "dog": [2, 0.14, 420.0, 300.0, "saw", 900.0, 0.22]}[n]
			x = _buf(0.9)
			for k in int(cfg[0]):
				var y := _buf(cfg[1])
				_tone(y, cfg[2] + k * 10.0, cfg[3], 0.7, 0.2, cfg[4])
				if n in ["pig", "dog"]:
					_noise(y, 0.35)
				_bandpass(y, cfg[5], 2.0)
				_env(y, 0.004, cfg[1] * 0.4)
				_mix(x, y, k * cfg[6])
		"cow", "sheep", "alpaca":
			x = _buf(1.5 if n == "cow" else 0.8)
			_tone(x, {"cow": 110.0, "sheep": 310.0, "alpaca": 520.0}[n], {"cow": 95.0, "sheep": 290.0, "alpaca": 480.0}[n], 0.8, 3.0, "saw" if n != "alpaca" else "sine", 0.0, 0.05 if n == "sheep" else 0.0)
			var a := x.duplicate()
			_bandpass(x, {"cow": 400.0, "sheep": 950.0, "alpaca": 900.0}[n], 2.0)
			_bandpass(a, 900.0, 3.0)
			_mix(x, a, 0.0, 0.4)
			_env(x, 0.15, 0.6 if n == "cow" else 0.3)
		"donkey":
			x = _buf(1.6)
			for k in 4:
				var y := _buf(0.35)
				_tone(y, 900.0 if k % 2 == 0 else 320.0, 860.0 if k % 2 == 0 else 300.0, 0.6, 0.3, "saw")
				_bandpass(y, 1000.0, 1.5)
				_mix(x, y, k * 0.35)
		"skin":
			x = _buf(0.6)
			for k in 4:
				var y := _buf(0.12)
				_noise(y)
				_bandpass(y, 1200.0, 1.0)
				_env(y, 0.003, 0.04)
				_mix(x, y, k * 0.12)
		"portcullis":
			x = _buf(2.2)
			for k in 40:
				var y := _buf(0.05)
				_tone(y, _rng.randf_range(1800.0, 4200.0), 1500.0, 0.2, 0.02)
				_mix(x, y, _rng.randf_range(0.0, 2.0))
			var nz := _buf(2.2)
			_noise(nz)
			_lowpass(nz, 120.0)
			_mix(x, nz, 0.0, 0.6)
		"thunder":
			x = _buf(5.0)
			var b := 0.0
			for i in x.size():
				b = b * 0.996 + _rng.randf_range(-1, 1) * 0.06
				x[i] = b
			_lowpass(x, 300.0)
			for i in x.size():
				var t := float(i) / RATE
				x[i] *= exp(-t / 1.6) * (0.6 + 0.4 * sin(t * 3.7) * sin(t * 1.3))
			var c := _buf(0.3)
			_noise(c)
			_env(c, 0.001, 0.05)
			_mix(x, c, 0.0, 0.8)
		"ui_click", "ui_hover":
			x = _buf(0.06)
			_tone(x, 1400.0 if n == "ui_click" else 2200.0, 900.0 if n == "ui_click" else 2000.0, 0.5 if n == "ui_click" else 0.15, 0.02)
		"ui_open", "ui_close":
			x = _buf(0.3)
			_noise(x)
			_bandpass(x, 900.0 if n == "ui_open" else 600.0, 1.0)
			for i in x.size():
				x[i] *= sin(float(i) / x.size() * PI) * 0.6
		"voice_m", "voice_f":
			x = _babble((115.0 if n == "voice_m" else 210.0) + v * 14.0)
		"amb_wind":
			x = _buf(12.0)
			var b := 0.0
			for i in x.size():
				b = b * 0.995 + _rng.randf_range(-1, 1) * 0.1
				x[i] = b * (0.6 + 0.4 * sin(float(i) / RATE * 0.5) * sin(float(i) / RATE * 0.23))
			_lowpass(x, 700.0)
			_loop_fade(x, 2.0)
		"amb_rain":
			x = _buf(8.0)
			_noise(x, 0.5)
			_lowpass(x, 5000.0)
			for k in 900:
				var y := _buf(0.02)
				_tone(y, _rng.randf_range(2000, 6000), 1500.0, 0.3, 0.004)
				_mix(x, y, _rng.randf_range(0.0, 7.9))
			_loop_fade(x, 1.0)
		"amb_forest":
			x = _buf(14.0)
			_noise(x, 0.04)
			_lowpass(x, 500.0)
			for k in 26:
				var f := _rng.randf_range(2400.0, 4600.0)
				var at := _rng.randf_range(0.0, 13.0)
				for m in _rng.randi_range(2, 6):
					var z := _buf(0.09)
					_tone(z, f, f * _rng.randf_range(0.7, 1.3), 0.3, 0.04)
					_mix(x, z, at + m * 0.08)
			_loop_fade(x, 1.0)
		"amb_night":
			x = _buf(10.0)
			for i in x.size():
				var t := float(i) / RATE
				x[i] = sin(TAU * 4400.0 * t) * maxf(sin(TAU * 18.0 * t), 0.0) * (0.5 + 0.5 * sin(t * 1.7)) * 0.15
			for k in 3:
				var y := _buf(0.9)
				_tone(y, 390.0, 370.0, 0.5, 0.3)
				_mix(x, y, _rng.randf_range(0, 9.0))
			_loop_fade(x, 1.0)
		"amb_river":
			x = _buf(10.0)
			_noise(x)
			_bandpass(x, 700.0, 0.6)
			var y := _buf(10.0)
			_noise(y)
			_bandpass(y, 2400.0, 1.5)
			for i in y.size():
				y[i] *= 0.5 + 0.5 * sin(float(i) / RATE * 7.0 + sin(float(i) / RATE * 1.3) * 3.0)
			_mix(x, y, 0.0, 0.5)
			_loop_fade(x, 1.5)
		"amb_fire":
			x = _buf(8.0)
			_noise(x, 0.2)
			_lowpass(x, 300.0)
			for k in 260:
				var y := _buf(0.03)
				_noise(y)
				_bandpass(y, _rng.randf_range(1500, 5000), 2.0)
				_env(y, 0.001, 0.006)
				_mix(x, y, _rng.randf_range(0.0, 7.9), _rng.randf_range(0.3, 1.0))
			_loop_fade(x, 1.0)
		"amb_tavern":
			x = _buf(12.0)
			for k in 30:
				_mix(x, _babble(_rng.randf_range(100.0, 230.0)), _rng.randf_range(0.0, 11.0), 0.35)
			for k in 6:
				var c := _buf(0.3)
				_tone(c, 2900.0, 2800.0, 0.3, 0.08)
				_mix(x, c, _rng.randf_range(0, 11.0))
			_lowpass(x, 2500.0)
			_loop_fade(x, 1.5)
		"amb_ocean":
			x = _buf(16.0)
			_noise(x)
			_lowpass(x, 900.0)
			for i in x.size():
				var t := float(i) / RATE
				x[i] *= 0.25 + 0.75 * pow(maxf(sin(t * TAU / 8.0), 0.0), 2.0)
			_loop_fade(x, 2.0)
		_:
			x = _buf(0.1)
	return x


## Murmured speech: formant-filtered syllables ("Simlish").
func _babble(pitch: float) -> PackedFloat32Array:
	var x := _buf(1.1)
	var t := 0.0
	var formants := [[730.0, 1090.0], [270.0, 2290.0], [530.0, 1840.0], [570.0, 840.0], [300.0, 870.0]]
	while t < 0.95:
		var dur := _rng.randf_range(0.08, 0.18)
		var y := _buf(dur)
		_tone(y, pitch * _rng.randf_range(0.95, 1.12), pitch * _rng.randf_range(0.85, 1.0), 0.6, 1.0, "saw")
		var f: Array = formants[_rng.randi() % formants.size()]
		var a := y.duplicate()
		_bandpass(y, f[0], 4.0)
		_bandpass(a, f[1], 6.0)
		_mix(y, a, 0.0, 0.6)
		for i in y.size():
			y[i] *= sin(float(i) / y.size() * PI)
		_mix(x, y, t)
		t += dur + _rng.randf_range(0.0, 0.05)
	return x
