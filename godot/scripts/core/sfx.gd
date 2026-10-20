extends Node
## Sound: recorded effects (CC0, see assets/sfx/CREDITS.txt), the engine loop, and music.
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
	"powerup", "flame", "railgun", "alarm", "wind", "streak", "count", "count_go", "win", "lose", "incoming", "strike",
	"ab_smoke", "ab_dash", "ab_toxic", "ab_riptide", "ab_zap", "ab_charge", "ab_roar", "ab_cannon", "ab_shield"]
const WORLD_VOICES := 28
const UI_VOICES := 8
const GUN_VOICES := 10

var streams := {}
var _world: Array[AudioStreamPlayer3D] = []
var _world_t: Array[float] = []
var _ui: Array[AudioStreamPlayer] = []
var _ui_i := 0
var _engine: AudioStreamPlayer
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
	for c in Data.CARS:
		var s := _load("engine_" + c.id)
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
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	add_child(_engine)
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


## "Wheeeew... boom": the falling whistle, offset so it ends on impact `secs` from now.
func incoming(secs: float, pos: Vector3, vol := 1.0) -> void:
	var s: AudioStream = streams.get("incoming")
	if s == null:
		return
	var len := s.get_length()
	play_at("incoming", pos, vol * 0.9, 1.0, len - min(len, secs))


# ---------- engine ----------

func engine_start(car_id: String) -> void:
	var s: AudioStream = streams.get("engine_" + car_id)
	if s == null:
		return
	_engine.stream = s
	_engine.volume_db = linear_to_db(0.5)
	_engine.play()


func engine_set(throttle: float, speed_frac: float) -> void:
	if not _engine.playing:
		return
	var target := 0.75 + speed_frac * 0.95 + throttle * 0.12
	_engine.pitch_scale = lerp(_engine.pitch_scale, target, 0.15)
	_engine.volume_db = linear_to_db(0.42 + throttle * 0.25)


func engine_stop() -> void:
	_engine.stop()


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
