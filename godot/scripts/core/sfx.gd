extends Node
## Sound: recorded effects (CC0 / CC BY, see assets/sfx/CREDITS.txt), the engine loop, and music.
## Every stream is loaded once at start-up, so nothing ever decodes or stalls in the middle of a fight.
## World sounds play on a fixed pool of 3D voices placed where the sound happens: Godot pans and fades them
## against the camera. When the pool is busy the quietest, oldest voice is reused instead of piling up more.

const DIR := "res://assets/sfx/"
const BANKS := {
	"gun": ["gun_1", "gun_2", "gun_3", "gun_4"],
	"gun_heavy": ["gun_heavy_1", "gun_heavy_2", "gun_heavy_3"],
	"gun_light": ["gun_light_1", "gun_light_2", "gun_light_3"],
	"boom_small": ["boom_small"], "boom_rocket": ["boom_rocket"], "boom_big": ["boom_car"],
	"launch": ["launch"], "launch_heavy": ["launch_heavy"],
}
const ONESHOTS := ["click", "confirm", "denied", "purchase", "ready", "ability_end", "crunch", "hit", "hurt", "pickup",
	"powerup", "flame", "railgun", "alarm", "wind", "streak", "count", "count_go", "win", "lose", "incoming", "incoming_hit", "boom_nuke",
	"ab_smoke", "ab_dash", "ab_toxic", "ab_riptide", "ab_zap", "ab_charge", "ab_roar", "ab_cannon", "ab_shield"]
## Engine recording per kind of vehicle: sports cars, jeeps, the monster truck, and the tracked/armoured machines.
const ENGINE_CLASS := {"venom": "sport", "toxic": "sport", "ghost": "jeep", "megalodon": "jeep", "siren": "jeep",
	"rex": "truck", "reaper": "tank", "titan": "tank", "colossus": "tank", "wraith": "sport"}
const WORLD_VOICES := 28
const UI_VOICES := 8
const GUN_VOICES := 10

var streams := {}
var _world: Array[AudioStreamPlayer3D] = []
var _world_t: Array[float] = []
var _ui: Array[AudioStreamPlayer] = []
var _ui_i := 0
var _engine_layers: Array[AudioStreamPlayer] = []
var _engine_class := "jeep"
var _engine_on := false
var _gear := 1
var _rpm := 0.0
var _load_amt := 0.0
var _shift_t := 0.0
var _music: AudioStreamPlayer
var _music_id := ""
var _guns_playing := 0
var _now := 0.0
var _boom_times: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for list in BANKS.values():
		for n in list:
			_load(n)
	for n in ONESHOTS:
		_load(n)
	for k in ENGINES:
		for l in ENGINES[k].layers:
			var s := _load("eng_%s_%s" % [k, l[0]])
			if s is AudioStreamOggVorbis:
				s.loop = true
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 140.0
		p.unit_size = 18.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_world.append(p)
		_world_t.append(-99.0)
	for i in UI_VOICES:
		var u := AudioStreamPlayer.new()
		u.bus = "SFX"
		add_child(u)
		_ui.append(u)
	for i in 3:
		var e := AudioStreamPlayer.new()
		e.bus = "SFX"
		add_child(e)
		_engine_layers.append(e)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_settings()


func _process(dt: float) -> void:
	_now += dt


func _load(n: String) -> AudioStream:
	for ext in [".ogg", ".mp3", ".wav"]:
		var path: String = DIR + n + ext
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			streams[n] = s
			return s
	push_warning("missing sound " + n)
	return null


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		for name in ["SFX", "Music"]:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")
	# a soft compressor and a hard limiter on the master keep stacked explosions loud but never clipping
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 4.0
	comp.attack_us = 3000.0
	comp.release_ms = 180.0
	AudioServer.add_bus_effect(0, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)


func apply_settings() -> void:
	var st: Dictionary = Save.state
	var v: Dictionary = st.volume
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.001, v.master)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(max(0.001, v.sfx)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not st.sound)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(max(0.001, v.music * 0.8)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not st.music)


# ---------- playback ----------

## Non-positional sound (UI, the player's own feedback).
func play(n: String, vol := 1.0, pitch := 1.0) -> void:
	var s: AudioStream = streams.get(n)
	if s == null:
		return
	var p := _ui[_ui_i]
	_ui_i = (_ui_i + 1) % _ui.size()
	p.stream = s
	p.volume_db = linear_to_db(max(0.001, vol))
	p.pitch_scale = pitch
	p.play()


## A sound in the world. Returns the voice used (or null when skipped).
func play_at(n: String, pos: Vector3, vol := 1.0, pitch := 1.0, offset := 0.0) -> AudioStreamPlayer3D:
	var s: AudioStream = streams.get(n)
	if s == null:
		return null
	var best := -1
	var best_t := INF
	for i in _world.size():
		if not _world[i].playing:
			best = i
			break
		if _world_t[i] < best_t:
			best_t = _world_t[i]
			best = i
	var p := _world[best]
	p.stream = s
	p.global_position = pos
	p.volume_db = linear_to_db(max(0.001, vol))
	p.pitch_scale = pitch
	_world_t[best] = _now
	p.play(max(0.0, offset))
	return p


func bank_at(bank: String, pos: Vector3, vol := 1.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var list: Array = BANKS[bank]
	return play_at(list[randi() % list.size()], pos, vol, pitch * randf_range(0.95, 1.05))


## Machine gun: the calibre picks the recording; the number of guns heard at once is capped.
func gun(pos: Vector3, calibre: float, vol := 1.0) -> void:
	if _guns_playing >= GUN_VOICES:
		return
	var bank := "gun_heavy" if calibre < 0.88 else ("gun_light" if calibre > 1.1 else "gun")
	var p := bank_at(bank, pos, vol * 0.9, calibre if bank == "gun" else 1.0)
	if p:
		_guns_playing += 1
		get_tree().create_timer(0.2, true, false, true).timeout.connect(func(): _guns_playing -= 1)


## Explosion sized like the blast; at most three start within a third of a second.
func explosion(pos: Vector3, size := 1.0) -> void:
	_boom_times = _boom_times.filter(func(t): return _now - t < 0.35)
	if _boom_times.size() >= 3:
		return
	_boom_times.append(_now)
	var bank := "boom_small" if size < 0.65 else ("boom_rocket" if size < 1.3 else "boom_big")
	bank_at(bank, pos, 1.1, randf_range(0.92, 1.04))


func rocket(pos: Vector3, heavy := false, vol := 1.0) -> void:
	bank_at("launch_heavy" if heavy else "launch", pos, vol)


## Red-zone shell: the falling whistle, started so it ends on impact `secs` from now.
func incoming(secs: float, pos: Vector3, vol := 1.0) -> void:
	var s: AudioStream = streams.get("incoming")
	if s == null:
		return
	var len := s.get_length()
	play_at("incoming", pos, vol, 1.0, len - min(len, secs))


## The big blast of a red-zone shell or a mini nuke.
func nuke_blast(pos: Vector3, vol := 1.2) -> void:
	_boom_times.append(_now)
	play_at("boom_nuke", pos, vol)


## An enemy rocket about to hit the player: whoosh and blast in one recording, its blast 0.34 s in.
const INCOMING_HIT_AT := 0.34


func incoming_hit(pos: Vector3, vol := 1.0) -> void:
	_boom_times.append(_now)
	play_at("incoming_hit", pos, vol)


# ---------- engine ----------
# Each class has constant-pitch loops recorded at a few engine speeds ("layers": name, its pitch in Hz along
# the tracked harmonic, and the engine pitch where it plays alone). A simulated rev counter and gearbox set
# the engine pitch; the nearest layers crossfade and are re-pitched to it, so the engine climbs through the
# gears, drops on each shift, idles steadily when stopped and revs when the throttle is pressed standing still.
# Offline copy of this model for listening tests: sim.py next to the sound build scripts.

const ENGINES := {
	"sport": {"layers": [["low", 73.1, 70.0], ["mid", 141.1, 145.0], ["high", 218.9, 230.0]], "idle": 66.0, "top": 265.0,
		"gears": [0.13, 0.27, 0.44, 0.62, 0.81, 1.0]},
	"jeep": {"layers": [["low", 152.8, 140.0], ["high", 156.2, 290.0]], "idle": 132.0, "top": 320.0,
		"gears": [0.16, 0.34, 0.55, 0.77, 1.0]},
	"truck": {"layers": [["low", 38.0, 38.0], ["mid", 46.6, 52.0], ["high", 89.2, 95.0]], "idle": 37.0, "top": 112.0,
		"gears": [0.18, 0.38, 0.6, 0.8, 1.0]},
	"tank": {"layers": [["loop", 1.0, 1.0]], "idle": 0.82, "top": 1.45, "gears": [0.25, 0.5, 0.75, 1.0]},
}


func engine_start(car_id: String) -> void:
	_engine_class = ENGINE_CLASS.get(car_id, "jeep")
	var layers: Array = ENGINES[_engine_class].layers
	for i in _engine_layers.size():
		var p := _engine_layers[i]
		p.stop()
		if i < layers.size():
			p.stream = streams.get("eng_%s_%s" % [_engine_class, layers[i][0]])
			p.volume_db = -60.0
			p.play(randf() * 0.4)
	_gear = 1
	_rpm = 0.0
	_load_amt = 0.0
	_shift_t = 0.0
	_engine_on = true


## throttle -1..1 and speed as a fraction of top speed (negative when reversing); called once a frame.
func engine_set(throttle: float, speed_frac: float, dt: float) -> void:
	if not _engine_on or dt <= 0.0:
		return
	var c: Dictionary = ENGINES[_engine_class]
	var b: Array = c.gears
	var sp: float = min(abs(speed_frac), 1.2)
	var th: float = abs(throttle)
	if sp > 0.05 and signf(throttle) != signf(speed_frac):
		th = 0.0                                       # pressing against the motion is braking, not accelerating
	while _gear < b.size() and sp > b[_gear - 1]:
		_gear += 1
		_shift_t = 0.16
	while _gear > 1 and sp < float(b[_gear - 2]) * 0.85:
		_gear -= 1
	var lo: float = b[_gear - 2] if _gear > 1 else 0.0
	var frac: float = clamp((sp - lo) / (float(b[_gear - 1]) - lo), 0.0, 1.15)
	var target: float = (0.06 + 0.94 * frac) if _gear == 1 else (0.4 + 0.6 * frac)
	if sp < 0.1 and th > 0.1:
		target = max(target, 0.62 * th)
	if th < 0.1:
		target *= 0.9
	_shift_t -= dt
	var rate := 4.0 if target < _rpm else 1.6
	_rpm += clamp(target - _rpm, -rate * dt, rate * dt)
	_load_amt += (th - _load_amt) * min(1.0, dt * 8.0)
	var f: float = c.idle * pow(c.top / c.idle, _rpm)
	var vol: float = (0.45 + 0.35 * _load_amt + 0.2 * _rpm) * (0.7 if _shift_t > 0.0 else 1.0) * 0.62
	var layers: Array = c.layers
	var lf := log(f)
	for i in layers.size():
		var w := 1.0
		if layers.size() > 1:
			var at := log(float(layers[i][2]))
			if lf < at:
				w = 1.0 if i == 0 else max(0.0, 1.0 - (at - lf) / (at - log(float(layers[i - 1][2]))))
			else:
				w = 1.0 if i == layers.size() - 1 else max(0.0, 1.0 - (lf - at) / (log(float(layers[i + 1][2])) - at))
		var p := _engine_layers[i]
		p.pitch_scale = clamp(f / float(layers[i][1]), 0.3, 3.0)
		p.volume_db = linear_to_db(max(sqrt(w) * vol, 0.0005))


func engine_stop() -> void:
	_engine_on = false
	for p in _engine_layers:
		p.stop()


# ---------- music ----------

func music(id: String) -> void:
	if id == _music_id and _music.playing:
		return
	_music_id = id
	var path := "res://assets/music/lobby.mp3" if id == "lobby" else "res://assets/sfx/music_match.ogg"
	var s = load(path)
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
	_music.stream = s
	_music.volume_db = 0.0 if id == "lobby" else -6.0
	_music.play()


func music_stop() -> void:
	_music_id = ""
	_music.stop()
