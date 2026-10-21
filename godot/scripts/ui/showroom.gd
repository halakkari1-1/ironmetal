class_name Showroom
extends Node3D
## The lobby: the car on a glowing ring platform in the middle of a city street (the "street city 7" scene,
## dasy444 on Sketchfab), at night: the street darkened and wet, lamps and burning drums close by, fires and
## smoke rising behind the blocks, under a night sky drawn by a shader (moving clouds, stars, the moon, the
## glow of the fires). The whole street is real 3D, so the camera can circle the car. Drag anywhere free of buttons to turn the view; left alone, it
## drifts round slowly. set_focus() slides the car sideways on screen (a lens shift) to keep it clear of panels.

const RADIUS := 5.0          # the glowing ring, metres
const CAM_DIST := 11.5
const CAM_FOV := 46.0

var blocks: Callable         # main: is there UI under this screen point? (then a drag isn't for the camera)
var _cam: Camera3D
var _car: Node3D
var _car_id := ""
var _ring_light: OmniLight3D
var _ring_mat: StandardMaterial3D
var _t := 0.0
var _scenes := {}
var _focus_px := -1.0
var _env: WorldEnvironment
var _fx: FX
var _yaw := 0.55
var _pitch := 0.16
var _yaw_v := 0.0
var _idle := 99.0
var _drag_id := -2
var _drag_last := Vector2.ZERO
var _drag_moved := 0.0
var _flicker: Array = []      # [light, base energy, phase]
var _lamps: Array = []
var _rng := RandomNumberGenerator.new()


const SKY := """
shader_type sky;
uniform vec3 moon_dir = vec3(0.55, 0.42, -0.72);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; } return v; }

void sky() {
	vec3 d = EYEDIR;
	float el = d.y;
	float az = atan(d.x, d.z);
	vec3 md = normalize(moon_dir);
	float mdot = max(dot(d, md), 0.0);
	// the fires of the city light the bottom of the sky, stronger in some directions
	float fire = 0.55 + 0.45 * (0.5 + 0.5 * sin(az * 2.0 + 0.8)) * (0.6 + 0.4 * sin(az * 5.0 + 2.1));
	vec3 hor = vec3(0.50, 0.17, 0.05) * fire;
	vec3 mid = vec3(0.06, 0.05, 0.09);
	vec3 zen = vec3(0.010, 0.016, 0.040);
	vec3 col = mix(hor, mid, smoothstep(0.0, 0.22, el));
	col = mix(col, zen, smoothstep(0.2, 0.75, el));
	// stars
	if (el > 0.05) {
		vec3 sp = floor(d * 420.0);
		float s = hash3(sp);
		col += vec3(0.85, 0.9, 1.0) * step(0.9975, s) * smoothstep(0.08, 0.45, el) * (0.5 + 0.5 * sin(TIME * 2.0 + s * 80.0));
	}
	// moon: the disc, a few darker seas, a halo
	float disc = smoothstep(0.99935, 0.99955, mdot);
	vec2 mp = (d.xy - md.xy) * 220.0;
	float seas = 0.82 + 0.18 * noise(mp * 0.9);
	vec3 moon = vec3(1.7, 1.65, 1.5) * disc * seas;
	vec3 halo = vec3(0.35, 0.38, 0.5) * (pow(mdot, 600.0) * 0.8 + pow(mdot, 40.0) * 0.18);
	// clouds on a sky dome, drifting; lit orange from the fires below and silver near the moon
	float cover = 0.0;
	vec3 ccol = vec3(0.0);
	if (el > -0.03) {
		vec2 uv = d.xz / (el + 0.16);
		float n = fbm(uv * 0.9 + vec2(TIME * 0.010, TIME * 0.0035));
		float n2 = fbm(uv * 2.4 - vec2(TIME * 0.016, 0.0));
		cover = smoothstep(0.43, 0.8, n * 0.8 + n2 * 0.3) * smoothstep(-0.03, 0.1, el);
		float low = 1.0 - smoothstep(0.0, 0.4, el);
		ccol = mix(vec3(0.055, 0.05, 0.065), vec3(0.42, 0.17, 0.07) * fire, low * 0.85);
		ccol += vec3(0.32, 0.34, 0.45) * pow(mdot, 8.0) * (0.4 + 0.6 * n2);
	}
	col = mix(col + halo, ccol, cover * 0.9) + moon * (1.0 - cover * 0.75);
	if (el < 0.0) {
		col = mix(col, hor * 0.35, smoothstep(0.0, -0.06, el));
	}
	COLOR = col;
}
"""


func _ready() -> void:
	Kit.init()
	_rng.seed = 7
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	sm.shader = sh
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.3, 0.38)
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true          # a thin haze: the city fades into the glow instead of ending sharply
	env.fog_light_color = Color(0.2, 0.09, 0.05)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	_env = WorldEnvironment.new()
	_env.environment = env
	add_child(_env)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.1
	_cam.far = 900
	add_child(_cam)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.7, 1.0)
	moon.light_energy = 0.6
	moon.rotation = Vector3(deg_to_rad(-42), deg_to_rad(145), 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 30
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(moon)
	var fire_fill := DirectionalLight3D.new()      # the burning city's glow, low and warm
	fire_fill.light_color = Color(1.0, 0.5, 0.22)
	fire_fill.light_energy = 0.55
	fire_fill.rotation = Vector3(deg_to_rad(-10), deg_to_rad(-40), 0)
	add_child(fire_fill)
	_fx = FX.new()
	add_child(_fx)
	_fx.setup()
	_ground()
	_platform()
	_street()
	_fires()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _r() -> float:
	return _rng.randf()


# ---------- the yard ----------

func _ground() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var rough := NoiseTexture2D.new()          # puddles: patches of near-mirror ground between rougher asphalt
	rough.noise = noise
	rough.width = 512
	rough.height = 512
	rough.seamless = true
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	cr.colors = PackedColorArray([Color(0.3, 0.3, 0.3), Color(0.36, 0.36, 0.36), Color(0.75, 0.75, 0.75), Color(0.88, 0.88, 0.88)])
	rough.color_ramp = cr
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/kit/ground_concrete.jpg")
	mat.albedo_color = Color(0.17, 0.16, 0.16)
	mat.roughness_texture = rough
	mat.roughness = 1.0
	mat.metallic_specular = 0.45
	mat.uv1_scale = Vector3(60, 60, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)  # beyond the street model
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = mat
	g.position.y = -0.3
	add_child(g)


func _platform() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS + 1.6
	disc.bottom_radius = RADIUS + 1.9
	disc.height = 0.24
	disc.radial_segments = 64
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.09, 0.085, 0.08)
	dm.metallic = 0.45
	dm.roughness = 0.5
	var d := MeshInstance3D.new()
	d.mesh = disc
	d.material_override = dm
	d.position.y = 0.12 - 0.12
	add_child(d)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(1, 0.45, 0.15)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1, 0.38, 0.1)
	_ring_mat.emission_energy_multiplier = 2.5
	for rr in [[RADIUS, 0.09], [RADIUS + 1.45, 0.035]]:
		var t := TorusMesh.new()
		t.inner_radius = rr[0] - rr[1]
		t.outer_radius = rr[0] + rr[1]
		t.rings = 96
		t.ring_segments = 6
		var ring := MeshInstance3D.new()
		ring.mesh = t
		ring.material_override = _ring_mat
		ring.position.y = 0.13
		ring.scale = Vector3(1, 0.5, 1)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	_ring_light = OmniLight3D.new()
	_ring_light.light_color = Color(1, 0.45, 0.15)
	_ring_light.omni_range = 11
	_ring_light.light_energy = 1.6
	_ring_light.position = Vector3(0, 0.7, 0)
	add_child(_ring_light)


const STREET := "res://assets/lobby/street.glb"
const STREET_SCALE := 6.0
const STREET_SPOT := Vector3(-2.6, 0.0, 3.0)   # the platform's place in the street model (middle of the road)


## The street, scaled up round the platform. Its daylight photo textures are darkened for night; the road is
## made wet so it shines with the lamps and fires; every surface is drawn from both sides (the far blocks are
## single cards).
func _street() -> void:
	var scene: PackedScene = load(STREET)
	var st: Node3D = scene.instantiate()
	st.scale = Vector3.ONE * STREET_SCALE
	st.position = -STREET_SPOT * STREET_SCALE + Vector3(0, -0.02, 0)
	add_child(st)
	var done := {}
	for mi in st.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box: AABB = m.mesh.get_aabb()
		var flat: bool = box.size.y * m.global_transform.basis.get_scale().y < 0.7 * STREET_SCALE and m.name.begins_with("Plane")
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i)
			if not (src is BaseMaterial3D):
				continue
			var key := str(src.get_instance_id()) + ("w" if flat else "")
			if not done.has(key):
				var mat: BaseMaterial3D = src.duplicate()
				mat.albedo_color = mat.albedo_color * Color(0.5, 0.48, 0.5)
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.metallic = 0.0
				if flat:     # wet road and pavement
					mat.roughness = 0.32
					mat.metallic_specular = 0.6
				else:
					mat.roughness = 0.9
					mat.metallic_specular = 0.3
				done[key] = mat
			m.set_surface_override_material(i, done[key])
	var i := 0
	for z in [-38.0, -22.0, -6.0, 10.0, 26.0, 42.0]:   # both kerbs, staggered; two of them failing
		var x := -11.0 if i % 2 == 0 else 11.0
		_lamp(Vector3(x, 0, z), Vector3(-x, 0, 0), i == 1 or i == 4)
		i += 1
	for p in [Vector3(-8.5, 0, -16.0), Vector3(9.5, 0, 17.0), Vector3(7.0, 0, -20.0)]:   # burning drums in the road
		var f := _fx.flame_emitter(1.0, 4)
		f.global_position = p + Vector3(0, 0.4, 0)
		f.emitting = true
		_fire_light(p + Vector3.UP * 1.6, 1.6, 12)


## Fires and smoke rising behind the blocks all round, lighting the sky and the building tops orange.
func _fires() -> void:
	var fx_k: float = Quality.tier.fx
	var n := 9 if Quality.tier_id != "low" else 5
	for i in n:
		var a := i * TAU / n + 0.3 + (_r() - 0.5) * 0.3
		var dist := 120.0 + _r() * 60.0
		var p := _at(a, dist)
		var base := Vector3(p.x, 0, p.y)
		if _r() < 0.75:
			var f := _fx.flame_emitter(9.0 + _r() * 5.0, 10)
			f.global_position = base + Vector3(0, 6, 0)
			f.emitting = true
			_fire_light(base + Vector3(0, 25, 0) - base.normalized() * 30.0, 6.0, 110)
		if _r() < 0.6 + 0.3 * fx_k:
			var sm := _fx.tower_smoke_emitter(true)
			sm.global_position = base + Vector3(0, 30 + _r() * 30, 0)
			sm.scale = Vector3.ONE * 2.0
			sm.emitting = true


func _at(ang: float, dist: float) -> Vector2:
	return Vector2(sin(ang), cos(ang)) * dist


## A street lamp leaning over the road: a bright head, a spotlight throwing a warm pool on the wet road, and a
## soft beam of light in the air beneath it. Some of them are failing and flicker.
func _lamp(pos: Vector3, toward: Vector3, flicker := false) -> void:
	var arm_dir := Vector3(toward.x, 0, toward.z).normalized()
	var h := 7.5
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.1, 0.095, 0.09)
	pm.metallic = 0.6
	pm.roughness = 0.45
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.16
	cyl.height = h
	post.mesh = cyl
	post.material_override = pm
	post.position = pos + Vector3(0, h / 2, 0)
	add_child(post)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.12, 0.12, 2.4)
	arm.mesh = ab
	arm.material_override = pm
	var head_pos := pos + arm_dir * 2.2 + Vector3(0, h - 0.1, 0)
	arm.position = pos + arm_dir * 1.1 + Vector3(0, h, 0)
	arm.rotation.y = atan2(arm_dir.x, arm_dir.z)
	add_child(arm)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.55, 0.16, 0.9)
	head.mesh = hb
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1, 0.85, 0.6)
	hm.emission_enabled = true
	hm.emission = Color(1, 0.75, 0.42)
	hm.emission_energy_multiplier = 9.0
	head.material_override = hm
	head.position = head_pos
	head.rotation.y = arm.rotation.y
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1, 0.72, 0.42)
	spot.light_energy = 14.0
	spot.spot_range = 22.0
	spot.spot_angle = 52.0
	spot.spot_attenuation = 0.6
	spot.spot_angle_attenuation = 1.6
	spot.position = head_pos - Vector3(0, 0.15, 0)
	spot.rotation = Vector3(-PI / 2, 0, 0)
	add_child(spot)
	var beam := MeshInstance3D.new()        # the light hanging in the damp air under the lamp
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3
	cone.bottom_radius = 4.6
	cone.height = h - 0.3
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	var bm := ShaderMaterial.new()
	bm.shader = _beam_shader()
	beam.material_override = bm
	beam.position = head_pos - Vector3(0, (h - 0.3) / 2 + 0.1, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_lamps.append({"spot": spot, "head": hm, "beam": bm, "flicker": flicker, "on": 1.0, "next": _r() * 3.0, "phase": _r() * 10.0})


static var _beam: Shader


static func _beam_shader() -> Shader:
	if _beam:
		return _beam
	_beam = Shader.new()
	_beam.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float level = 1.0;
void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 2.0);   // fades out at the cone's silhouette
	float down = smoothstep(1.0, 0.0, UV.y) * 0.85 + 0.15;   // brightest by the lamp
	float fade_floor = smoothstep(0.0, 0.08, UV.y) ;
	ALBEDO = vec3(1.0, 0.68, 0.36) * 0.26 * edge * level * (1.0 - UV.y * 0.75) * fade_floor;
}
"""
	return _beam


## Failing lamps: mostly on, then a stutter of short drop-outs, now and then dark for a moment.
func _update_lamps(dt: float) -> void:
	for L in _lamps:
		var lvl := 1.0
		if L.flicker:
			L.next -= dt
			if L.next <= 0:
				L.on = 0.08 if L.on > 0.5 else 1.0
				L.next = randf_range(0.03, 0.12) if L.on < 0.5 else (randf_range(0.05, 0.25) if randf() < 0.6 else randf_range(1.0, 3.5))
			lvl = L.on * (0.9 + 0.1 * sin(_t * 60.0 + L.phase))
		L.spot.light_energy = 14.0 * lvl
		L.head.emission_energy_multiplier = 9.0 * lvl
		L.beam.set_shader_parameter("level", lvl)



func _fire_light(pos: Vector3, energy: float, rng_: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.5, 0.18)
	l.light_energy = energy
	l.omni_range = rng_
	l.position = pos
	add_child(l)
	_flicker.append([l, energy, _r() * 10])


# ---------- camera ----------

func activate(on: bool) -> void:
	visible = on
	set_process_input(on)
	for p in find_children("*", "GPUParticles3D", true, false):   # nothing burns here while a match runs
		var gp := p as GPUParticles3D
		if not on and gp.emitting:
			gp.set_meta("lobby_on", true)
			gp.emitting = false
		elif on and gp.get_meta("lobby_on", false):
			gp.emitting = true
	if on and _env.get_parent() == null:
		add_child(_env)
	elif not on and _env.get_parent() != null:
		remove_child(_env)
	if on:
		_cam.make_current()
		_layout()


## Slides the car to a spot across the screen (in canvas pixels), clear of the panels a screen shows.
func set_focus(px: float) -> void:
	if abs(px - _focus_px) < 0.5:
		return
	_focus_px = px
	_layout()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var px: float = _focus_px if _focus_px >= 0 else 0.64 * vp.x
	var py := 0.6 * vp.y
	_cam.size = 2.0 * _cam.near * tan(deg_to_rad(CAM_FOV) / 2.0)
	var k := _cam.size / vp.y
	_cam.frustum_offset = Vector2(-(px - vp.x / 2) * k, (py - vp.y / 2) * k)
	_place_cam()


func _place_cam() -> void:
	var dist := CAM_DIST
	if _car:
		dist *= clamp((_car as Car).dims.z * _car.scale.x / 5.6, 0.85, 1.3)
	var look := Vector3(0, 1.0, 0)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * dist
	_cam.position = look + off
	_cam.look_at(look, Vector3.UP)


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
	c.position.y = 0.0
	c.rotation.y = -0.6
	_car = c
	add_child(c)
	_place_cam()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	var pressed := false
	var released := false
	var idx := -1
	var pos := Vector2.ZERO
	if e is InputEventScreenTouch:
		idx = e.index
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		idx = -1
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif (e is InputEventScreenDrag and e.index == _drag_id) or (e is InputEventMouseMotion and _drag_id == -1 and (e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		var d: Vector2 = e.position - _drag_last
		_drag_last = e.position
		_drag_moved += d.length()
		var vp := get_viewport().get_visible_rect().size
		var dy := d.x / vp.x * 3.4
		_yaw -= dy
		_yaw_v = -dy / max(get_process_delta_time(), 0.008)
		_pitch = clamp(_pitch + d.y / vp.y * 1.2, 0.05, 0.55)
		_idle = 0.0
		_place_cam()
		return
	if pressed and _drag_id == -2:
		if blocks.is_valid() and blocks.call(pos):
			return
		_drag_id = idx
		_drag_last = pos
		_drag_moved = 0.0
		_yaw_v = 0.0
	elif released and idx == _drag_id:
		_drag_id = -2


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	_idle += dt
	if _drag_id == -2:
		if abs(_yaw_v) > 0.01:   # a flick keeps turning and slows down
			_yaw += _yaw_v * dt
			_yaw_v *= exp(-dt * 3.0)
			_place_cam()
		elif _idle > 4.0:        # left alone: drift round slowly
			_yaw += dt * 0.09 * min(1.0, (_idle - 4.0) / 2.0)
			_place_cam()
	_ring_light.light_energy = 1.5 + sin(_t * 2.2) * 0.35
	_ring_mat.emission_energy_multiplier = 2.4 + sin(_t * 2.2) * 0.5
	_update_lamps(dt)
	for f in _flicker:
		var l: OmniLight3D = f[0]
		l.light_energy = f[1] * (0.8 + 0.2 * sin(_t * 9.0 + f[2]) * sin(_t * 5.3 + f[2] * 2.0))
