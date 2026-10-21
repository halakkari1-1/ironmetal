class_name Showroom
extends Node3D
## The lobby: a painted night yard behind, with the selected car standing live in 3D on the glowing ring.
## The camera is solved from the painted ring (its centre and how flat its ellipse is), with a lens shift so
## the car lands exactly on the ring at any screen shape. The car's shadow falls on an invisible catcher plane.

const IMG := "res://assets/ui/lobby.jpg"
const IMG_W := 2576.0
const IMG_H := 1448.0
const RING := Vector2(0.6724, 0.674)   # ring centre in the image (0..1)
const RING_A := 0.2686                 # half-width of the ring ellipse, fraction of image width
const RING_B := 0.0622                 # half-height, fraction of image height
const FOCAL := 0.898                   # focal length in image widths
const RADIUS := 5.0                    # the ring's radius in metres

var _bg: TextureRect
var _layer: CanvasLayer
var _cam: Camera3D
var _car: Node3D
var _car_id := ""
var _turn := 0.0
var _ring_light: OmniLight3D
var _t := 0.0
var _scenes := {}
var _focus_px := -1.0   # where the ring (and the car) should sit across the screen; < 0 = default
var _env: WorldEnvironment


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -10
	add_child(_layer)
	_bg = TextureRect.new()
	_bg.texture = load(IMG)
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_layer.add_child(_bg)
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.5)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	_env = WorldEnvironment.new()
	_env.environment = env
	add_child(_env)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.near = 0.05
	_cam.far = 200
	add_child(_cam)
	var key := DirectionalLight3D.new()           # moonlight from the upper right of the painting
	key.light_color = Color(0.7, 0.75, 1.0)
	key.light_energy = 1.1
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(140), 0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40
	add_child(key)
	var warm := DirectionalLight3D.new()          # warm lamps from the yard
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 0.9
	warm.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-60), 0)
	add_child(warm)
	_ring_light = OmniLight3D.new()
	_ring_light.light_color = Color(1, 0.45, 0.15)
	_ring_light.omni_range = 9
	_ring_light.light_energy = 1.5
	add_child(_ring_light)
	var catcher := MeshInstance3D.new()           # receives the car's shadow, otherwise invisible
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	catcher.mesh = plane
	var cm := StandardMaterial3D.new()
	cm.shadow_to_opacity = true
	cm.albedo_color = Color(0, 0, 0, 0.75)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	catcher.material_override = cm
	catcher.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(catcher)
	get_viewport().size_changed.connect(_layout)
	_layout()


func activate(on: bool) -> void:
	visible = on
	_layer.visible = on
	# only one WorldEnvironment may be active: hand the sky back to the arena while a match runs
	if on and _env.get_parent() == null:
		add_child(_env)
	elif not on and _env.get_parent() != null:
		remove_child(_env)
	if on:
		_cam.make_current()
		_layout()


## Fits the painting to the screen (cover), then solves the camera so the ground ring matches it.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var cover: float = max(vp.x / IMG_W, vp.y / IMG_H)
	var target: float = _focus_px if _focus_px >= 0 else 0.64 * vp.x
	# zoom the painting in (up to 40%) when that is the only way to slide the ring to the target spot
	var need: float = max(target / RING.x, (vp.x - target) / (1.0 - RING.x)) / IMG_W
	var sc: float = clamp(need, cover, cover * 1.4)
	var dw := IMG_W * sc
	var dh := IMG_H * sc
	var ox: float = clamp(target - RING.x * dw, vp.x - dw, 0.0)
	var oy := (vp.y - dh) / 2
	_bg.position = Vector2(ox, oy)
	_bg.size = Vector2(dw, dh)
	var cx := ox + RING.x * dw
	var cy := oy + RING.y * dh
	var f := FOCAL * dw                                    # focal length in screen pixels
	var tilt := asin(clamp((RING_B * dh) / (RING_A * dw), 0.02, 0.9))  # flatter ellipse = lower camera
	var dist := RADIUS * f / (RING_A * dw)
	_cam.position = Vector3(0, dist * sin(tilt), dist * cos(tilt))
	_cam.rotation = Vector3(-tilt, 0, 0)
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = vp.y / f * _cam.near
	_cam.frustum_offset = Vector2(-(cx - vp.x / 2) / f * _cam.near, (cy - vp.y / 2) / f * _cam.near)
	_ring_light.position = Vector3(0, 0.6, 0)


## Slides the car to a spot across the screen (in canvas pixels), clear of the panels a screen shows.
func set_focus(px: float) -> void:
	if abs(px - _focus_px) < 0.5:
		return
	_focus_px = px
	_layout()


func show_car(id: String) -> void:
	if id == _car_id:
		return
	_car_id = id
	if _car:
		_car.queue_free()
	if not _scenes.has(id):
		_scenes[id] = load("res://assets/cars/%s.glb" % id)
	var c := Car.new()
	c.data = Data.car(id)
	c._fit_model(_scenes[id])
	var fit: float = min(1.0, RADIUS * 1.75 / c.dims.z)
	c.scale = Vector3.ONE * fit
	_car = c
	add_child(c)
	_turn = -0.6


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if _car:
		_turn += dt * 0.25
		_car.rotation.y = _turn
	_ring_light.light_energy = 1.4 + sin(_t * 2.2) * 0.35
