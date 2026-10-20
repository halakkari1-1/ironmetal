extends Node
## Graphics quality. Each tier sets the 3D render resolution (upscaled with FSR), shadows, glow and effect density.
## "auto" starts high and steps down only if the frame rate cannot hold the target for a few seconds,
## so a phone that keeps up never loses detail and one that cannot never stutters for long.

const TIERS := {
	"high": {"scale": 0.9, "msaa": Viewport.MSAA_2X, "shadow": 2048, "shadow_dist": 90.0, "glow": true, "fx": 1.0},
	"medium": {"scale": 0.78, "msaa": Viewport.MSAA_2X, "shadow": 2048, "shadow_dist": 70.0, "glow": true, "fx": 0.8},
	"low": {"scale": 0.66, "msaa": Viewport.MSAA_DISABLED, "shadow": 1024, "shadow_dist": 50.0, "glow": false, "fx": 0.55},
}
const ORDER := ["high", "medium", "low"]

signal changed

var tier_id := "high"
var tier: Dictionary = TIERS.high
var _acc := 0.0
var _frames := 0
var _low_secs := 0.0
var _auto := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_setting()


func apply_setting() -> void:
	var g: String = Save.state.get("graphics", "auto")
	_auto = g == "auto"
	tier_id = "high" if _auto else g
	tier = TIERS[tier_id]
	Engine.max_fps = int(Save.state.get("fps", 60))
	_apply()


## Applies the tier to the main viewport. Scenes with their own lights read `tier` when they build.
func _apply() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = tier.scale
	vp.msaa_3d = tier.msaa
	vp.fsr_sharpness = 0.35
	RenderingServer.directional_shadow_atlas_set_size(tier.shadow, true)
	changed.emit()


## Called every frame during a match in auto mode.
func sample(dt: float) -> void:
	if not _auto:
		return
	_acc += dt
	_frames += 1
	if _acc < 1.0:
		return
	var fps := _frames / _acc
	_acc = 0.0
	_frames = 0
	var target: float = Engine.max_fps if Engine.max_fps > 0 else 60.0
	if fps < target * 0.8:
		_low_secs += 1.0
	else:
		_low_secs = max(0.0, _low_secs - 0.5)
	if _low_secs >= 3.0:
		_low_secs = 0.0
		var i := ORDER.find(tier_id)
		if i < ORDER.size() - 1:
			tier_id = ORDER[i + 1]
			tier = TIERS[tier_id]
			_apply()
