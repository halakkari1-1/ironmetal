extends Node
## Graphics quality. Each tier sets the 3D render height (the same sharpness on every screen size, whatever its
## pixel count), anti-aliasing, shadows, glow and effect density.
##
## "auto" picks the tier for the phone and keeps adjusting it, in both directions:
## - it remembers the tier that suited this phone (saved), so every match starts there instead of at the top;
## - the first seconds of a match (loading hitches) are not counted;
## - it steps down when the game cannot hold 50 frames a second (or the 30 cap) for a few seconds;
## - it steps back up when the graphics chip has clear room to spare for a while.
## A 90 or 120 frame cap never pushes the quality down by itself: dropping detail only to chase 120 would make
## the game look worse on the very phones that run it best.

const TIERS := {
	"high": {"height": 900, "msaa": Viewport.MSAA_2X, "shadow": 2048, "shadow_dist": 90.0, "splits": 2, "glow": true, "fx": 1.0},
	"medium": {"height": 760, "msaa": Viewport.MSAA_2X, "shadow": 2048, "shadow_dist": 70.0, "splits": 1, "glow": true, "fx": 0.8},
	"low": {"height": 620, "msaa": Viewport.MSAA_DISABLED, "shadow": 1024, "shadow_dist": 50.0, "splits": 1, "glow": false, "fx": 0.55},
}
const ORDER := ["high", "medium", "low"]
const FPS_CHOICES := [30, 60, 90, 120]
const WARMUP := 4.0        # seconds at the start of a match that are not judged
const DOWN_AFTER := 3.0    # seconds below the floor before stepping down
const UP_AFTER := 15.0     # seconds with room to spare before stepping up

signal changed

var tier_id := "high"
var tier: Dictionary = TIERS.high
var fps_now := 0.0         # measured, for the on-screen counter
var _acc := 0.0
var _frames := 0
var _low_secs := 0.0
var _good_secs := 0.0
var _warm := 0.0
var _auto := true
var _ups := 0              # times stepped up this session: stop after bouncing, never oscillate
var _judging := false      # set by sample() while a match is running past its warm-up
var _counter: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_viewport().size_changed.connect(_apply)
	apply_setting()


func apply_setting() -> void:
	var g: String = Save.state.get("graphics", "auto")
	_auto = g == "auto"
	tier_id = Save.state.get("auto_tier", "high") if _auto else g
	if not TIERS.has(tier_id):
		tier_id = "high"
	tier = TIERS[tier_id]
	Engine.max_fps = int(Save.state.get("fps", 60))
	_show_counter(bool(Save.state.get("show_fps", false)))
	_apply()


## The small frame counter at the top of the screen (settings: Frame counter).
func _show_counter(on: bool) -> void:
	if on and _counter == null:
		var layer := CanvasLayer.new()
		layer.layer = 120
		add_child(layer)
		_counter = Label.new()
		_counter.add_theme_font_size_override("font_size", 18)
		_counter.add_theme_color_override("font_color", Color(0.75, 1.0, 0.6))
		_counter.add_theme_constant_override("outline_size", 5)
		_counter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_counter.position = Vector2(560, 58)
		layer.add_child(_counter)
	if _counter:
		_counter.get_parent().visible = on


## Called when a match starts loading: the warm-up begins again and counting starts fresh.
func match_begin() -> void:
	_warm = 0.0
	_low_secs = 0.0
	_good_secs = 0.0
	_acc = 0.0
	_frames = 0


## Applies the tier to the main viewport. Scenes with their own lights read `tier` and listen to `changed`.
func _apply() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR   # FSR is Forward+ only; the game runs on Mobile
	var h: float = max(1.0, vp.get_visible_rect().size.y)
	var win_h := float(DisplayServer.window_get_size().y) if DisplayServer.get_name() != "headless" else h
	vp.scaling_3d_scale = clamp(tier.height / max(win_h, 1.0), 0.5, 1.0)
	vp.msaa_3d = tier.msaa
	RenderingServer.directional_shadow_atlas_set_size(tier.shadow, true)
	changed.emit()


func _process(dt: float) -> void:
	_acc += dt
	_frames += 1
	if _acc >= 0.5:
		fps_now = _frames / _acc
		if _counter and _counter.is_visible_in_tree():
			_counter.text = "%d FPS · %s" % [roundi(fps_now), tier_id.to_upper()]
		if _judging:
			_judge(_acc)
		_acc = 0.0
		_frames = 0
	_judging = false


## Called every frame during a match.
func sample(dt: float) -> void:
	_warm += dt
	_judging = _auto and _warm > WARMUP


func _judge(span: float) -> void:
	var cap: float = Engine.max_fps if Engine.max_fps > 0 else 60.0
	var floor_fps: float = min(cap, 60.0) * 0.83          # 50 at 60 and above, 25 at 30
	if fps_now < floor_fps:
		_low_secs += span
		_good_secs = 0.0
	else:
		_low_secs = max(0.0, _low_secs - span * 0.5)
		# room to spare: the frame rate holds its cap and the graphics chip is busy for under 55% of each frame
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		var budget: float = 1000.0 / min(cap, 60.0)
		if fps_now >= min(cap, 60.0) * 0.95 and gpu_ms > 0.0 and gpu_ms < budget * 0.55:
			_good_secs += span
		else:
			_good_secs = 0.0
	var i := ORDER.find(tier_id)
	if _low_secs >= DOWN_AFTER and i < ORDER.size() - 1:
		_set_auto_tier(ORDER[i + 1])
	elif _good_secs >= UP_AFTER and i > 0 and _ups < 2:
		_ups += 1
		_set_auto_tier(ORDER[i - 1])


func _set_auto_tier(id: String) -> void:
	_low_secs = 0.0
	_good_secs = 0.0
	_warm = WARMUP - 1.5   # give the new tier a moment before judging it
	tier_id = id
	tier = TIERS[id]
	Save.state.auto_tier = id
	Save.write()
	_apply()
