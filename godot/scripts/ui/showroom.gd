class_name Showroom
extends Node3D
## The lobby: a painted backdrop, with the car standing live in 3D on the glowing ring painted in it.
## The camera is solved from the painted ring (its centre and how flat its ellipse is), with a lens shift so
## the car lands exactly on the ring at any screen shape. The car's shadow falls on an invisible catcher plane.
## Backdrops: the night yard (the lobby), and the harbour of the Azure Wraith offer, which comes alive: drifting
## clouds, twinkling city lights, rippling water, a pulsing ring, and fireworks over the skyline.

const RADIUS := 5.0                    # the ring's radius in metres
## img: the painting; ring: its centre (fraction of the image); a / b: the ring ellipse's half-width and
## half-height (fractions of image width / height); focal: lens focal length in image widths; fit: car length
## as a fraction of the ring's diameter.
const BACKDROPS := {
	"yard": {"img": "res://assets/ui/lobby.jpg", "w": 2576.0, "h": 1448.0, "ring": Vector2(0.6724, 0.674), "a": 0.2686, "b": 0.0622, "focal": 0.898, "fit": 0.875,
		"shader": "res://scripts/ui/yard.gdshader"},
	"harbor": {"img": "res://assets/ui/offers/harbor.jpg", "w": 1672.0, "h": 941.0, "ring": Vector2(0.6926, 0.661), "a": 0.2703, "b": 0.0659, "focal": 0.898, "fit": 0.86, "alive": true,
		"shader": "res://scripts/ui/harbor.gdshader", "fireworks": true},
}

var IMG_W := 2576.0
var IMG_H := 1448.0
var RING := Vector2(0.6724, 0.674)
var RING_A := 0.2686
var RING_B := 0.0622
var FOCAL := 0.898
var _backdrop := ""
var _fit := 0.875
var _alive_mat: ShaderMaterial
var _fireworks: Fireworks

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
var blocks: Callable        # main: is there UI under this screen point? (then a drag isn't for the car)
var _drag_id := -2
var _drag_last := Vector2.ZERO
var _spin_v := 0.0
var _idle := 99.0


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -10
	add_child(_layer)
	_bg = TextureRect.new()
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
	set_backdrop("yard")


## Switches the painting behind the car (and the ring the camera is solved from).
func set_backdrop(id: String) -> void:
	if id == _backdrop:
		return
	_backdrop = id
	var b: Dictionary = BACKDROPS[id]
	_bg.texture = load(b.img)
	IMG_W = b.w
	IMG_H = b.h
	RING = b.ring
	RING_A = b.a
	RING_B = b.b
	FOCAL = b.focal
	_fit = b.fit
	# every backdrop is a living painting: its own shader animates it (clouds, lights, ring)
	var mat := ShaderMaterial.new()
	mat.shader = load(b.shader)
	mat.set_shader_parameter("noise_tex", load("res://assets/arena/cloud_noise.png"))
	_bg.material = mat
	if b.get("fireworks", false):
		if _fireworks == null:
			_fireworks = Fireworks.new()
			_bg.add_child(_fireworks)
		_fireworks.active = true
	elif _fireworks:
		_fireworks.active = false
	if _car:   # refit the car for this ring
		var id_ := _car_id
		_car_id = ""
		show_car(id_)
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
	var fit: float = RADIUS * 2.0 * _fit / c.dims.z
	if not BACKDROPS[_backdrop].get("alive", false):
		fit = min(1.0, fit)   # the lobby never blows a car up; the offer shows it filling the ring as in its art
	c.scale = Vector3.ONE * fit
	_car = c
	add_child(c)
	_turn = -0.6


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	_idle += dt
	if _car:
		if _drag_id == -2:
			if abs(_spin_v) > 0.02:      # a flick keeps it turning, slowing down
				_turn += _spin_v * dt
				_spin_v *= exp(-dt * 2.5)
			elif _idle > 3.0:            # left alone: back to the slow turn
				_turn += dt * 0.25 * min(1.0, (_idle - 3.0) / 1.5)
		_car.rotation.y = _turn
	_ring_light.light_energy = 1.4 + sin(_t * 2.2) * 0.35


## Drag anywhere free of buttons to turn the car round and look at it from every side.
func _input(e: InputEvent) -> void:
	if not visible or _car == null:
		return
	var pos := Vector2.ZERO
	var idx := -1
	var pressed := false
	var released := false
	if e is InputEventScreenTouch:
		idx = e.index
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif (e is InputEventScreenDrag and e.index == _drag_id) or (e is InputEventMouseMotion and _drag_id == -1 and (e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		var d: Vector2 = e.position - _drag_last
		_drag_last = e.position
		var k := d.x / get_viewport().get_visible_rect().size.x * 5.0
		_turn += k
		_spin_v = k / max(get_process_delta_time(), 0.008)
		_idle = 0.0
		return
	if pressed and _drag_id == -2:
		if blocks.is_valid() and blocks.call(pos):
			return
		_drag_id = idx
		_drag_last = pos
		_spin_v = 0.0
		_idle = 0.0
	elif released and idx == _drag_id:
		_drag_id = -2
