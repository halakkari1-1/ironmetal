class_name Showroom
extends Node3D
## The lobby yard, built in 3D all the way round so the camera can circle the car: a wet asphalt yard with the
## car on a glowing ring platform, barriers, drums and lamp posts close by, container stacks and a ruined
## bridge further out, and a burning city on the horizon, under a night sky drawn by a shader (moving clouds,
## stars, the moon, the glow of the fires). Drag anywhere free of buttons to turn the view; left alone, it
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
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
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
	_yard()
	_bridge()
	_city()
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
	plane.size = Vector2(900, 900)
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = mat
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


func _prop(name: String, x: float, z: float, ry: float, s := 1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.mesh("prop_" + name)
	mi.material_override = Kit.material
	mi.scale = Vector3.ONE * Arena.PS * s
	mi.rotation.y = ry
	mi.position = Vector3(x, 0, z)
	if Quality.tier_id == "low":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _at(ang: float, dist: float) -> Vector2:
	return Vector2(sin(ang), cos(ang)) * dist


## Close by: barriers, drums and crates in loose groups, lamp posts; then container stacks with gaps between
## them so the city shows through.
func _yard() -> void:
	var groups := [["barrier", 0.4], ["drums", 1.3], ["crates", 2.0], ["barrier", 2.7], ["tarpDrums", 3.5], ["dumpster", 4.3], ["cylinders", 5.1], ["barrier", 5.8]]
	for gp in groups:
		var a: float = gp[1] + (_r() - 0.5) * 0.2
		var p := _at(a, 12.5 + _r() * 4)
		_prop(gp[0], p.x, p.y, a + PI / 2 + (_r() - 0.5) * 0.6)
		if gp[0] == "barrier":
			var p2 := _at(a + 0.2, 13.0 + _r() * 2)
			_prop("barrier", p2.x, p2.y, a + PI / 2 + (_r() - 0.5) * 0.3)
	for i in 4:
		var a := i * TAU / 4 + 0.8
		var p := _at(a, 10.5)
		_lamp(Vector3(p.x, 0, p.y))
	var cm := Kit.solid_material
	for i in 7:
		var a := i * TAU / 7 + 0.3 + (_r() - 0.5) * 0.25
		var dist := 34 + _r() * 14
		var p := _at(a, dist)
		var stack := 1 + int(_r() * 3)
		for k in stack:
			var mi := MeshInstance3D.new()
			mi.mesh = Kit.container(int(_r() * 3))
			mi.material_override = cm
			mi.scale = Vector3.ONE * 1.5
			mi.rotation.y = a + PI / 2 + (_r() - 0.5) * 0.3 + k * 0.08
			mi.position = Vector3(p.x, k * 3.9, p.y) + Vector3(_r() - 0.5, 0, _r() - 0.5)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		if _r() < 0.45:   # a burning drum by some of them
			var f := _fx.flame_emitter(1.0, 4)
			f.global_position = Vector3(p.x, 0.2, p.y) + Vector3(cos(a), 0, -sin(a)) * 4
			f.emitting = true
			_fire_light(f.global_position + Vector3.UP * 1.5, 1.4, 9)


func _lamp(pos: Vector3) -> void:
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.14
	cyl.height = 6.5
	post.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.11, 0.1)
	pm.metallic = 0.6
	pm.roughness = 0.5
	post.material_override = pm
	post.position = pos + Vector3(0, 3.25, 0)
	add_child(post)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.18, 0.35)
	head.mesh = box
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1, 0.8, 0.5)
	hm.emission_enabled = true
	hm.emission = Color(1, 0.72, 0.4)
	hm.emission_energy_multiplier = 5.0
	head.material_override = hm
	head.position = pos + Vector3(0, 6.5, 0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.7, 0.42)
	l.light_energy = 1.6
	l.omni_range = 14
	l.position = pos + Vector3(0, 6.2, 0)
	add_child(l)


func _fire_light(pos: Vector3, energy: float, rng_: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.5, 0.18)
	l.light_energy = energy
	l.omni_range = rng_
	l.position = pos
	add_child(l)
	_flicker.append([l, energy, _r() * 10])


## A broken road bridge on pillars, its lamps still burning, crossing behind the yard as in the old painting.
func _bridge() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ang := -0.55
	var dir := Vector3(cos(ang), 0, -sin(ang))
	var centre := Vector3(sin(ang), 0, cos(ang)) * 95
	var length := 240.0
	var deck := 22.0
	var segs := 10
	for i in segs:
		if i == 6:
			continue   # the collapsed span
		var u := -length / 2 + (i + 0.5) * length / segs
		var p := centre + dir * u
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
		st.append_from(Kit.block(9, 2.2, length / segs + 0.2, Kit.ATLAS.concrete, Kit.ATLAS.grey_plate, Kit.ATLAS.concrete), 0, Transform3D(basis, p + Vector3(0, deck, 0)))
		st.append_from(Kit.block(3.2, deck, 3.2, Kit.ATLAS.concrete, Kit.ATLAS.concrete, Kit.ATLAS.concrete), 0, Transform3D(basis, p - dir * length / segs * 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Kit.solid_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bulb := SphereMesh.new()
	bulb.radius = 0.35
	bulb.height = 0.7
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(3.0, 1.6, 0.6)
	bulb.material = bm
	mm.mesh = bulb
	var lamps: Array = []
	var u := -length / 2 + 6
	while u < length / 2:
		if abs(u - (-length / 2 + 6.5 * length / segs)) > length / segs * 0.6:
			for side in [-1, 1]:
				lamps.append(centre + dir * u + Vector3(dir.z, 0, -dir.x) * 4.2 * side + Vector3(0, deck + 2.6, 0))
		u += 12
	mm.instance_count = lamps.size()
	for i in lamps.size():
		mm.set_instance_transform(i, Transform3D(Basis(), lamps[i]))
	var lm := MultiMeshInstance3D.new()
	lm.multimesh = mm
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lm)


## The burning city: ruined towers and works all round the horizon, smoke from their tops, fires in them.
func _city() -> void:
	var kinds: Array = []
	for k in Arena.SKYLINE:
		var scene: PackedScene = load("res://assets/buildings/%s.glb" % k.id)
		var probe := scene.instantiate()
		var box := Car.new()._aabb(probe)
		probe.free()
		kinds.append({"tall": k.tall, "scene": scene, "box": box})
	var low := Quality.tier_id == "low"
	var n := 12 if low else 18
	var fx_k: float = Quality.tier.fx
	for i in n:
		var kind: Dictionary = kinds[i % kinds.size()]
		var a := i * TAU / n + (_r() - 0.5) * 0.2
		var dist := 265 + _r() * 75
		var hgt: float = (70 + _r() * 45) if kind.tall else (38 + _r() * 18)
		var box: AABB = kind.box
		var sc: float = hgt / box.size.y
		var node: Node3D = kind.scene.instantiate()
		var p := _at(a, dist)
		var c := (box.get_center() * Vector3(1, 0, 1)) * sc
		var ry := _r() * TAU
		node.scale = Vector3.ONE * sc
		node.rotation.y = ry
		node.position = Vector3(p.x, -box.position.y * sc - 1.5, p.y) - c.rotated(Vector3.UP, ry)
		for mi in node.find_children("*", "GeometryInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		if _r() < 0.5 + 0.3 * fx_k:
			var sm := _fx.tower_smoke_emitter(true)
			sm.global_position = Vector3(p.x, hgt * 0.92, p.y)
			sm.emitting = true
		if not low and _r() < 0.75 * fx_k:
			var toward := atan2(-p.x, -p.y)
			var r := (box.size.x + box.size.z) * 0.25 * sc
			var fpos := Vector3(p.x + sin(toward) * r, hgt * (0.25 + _r() * 0.4), p.y + cos(toward) * r)
			var f := _fx.flame_emitter(4.5, 8)
			f.global_position = fpos
			f.emitting = true
			_fire_light(fpos + Vector3(sin(toward), 0, cos(toward)) * 8, 5.0, 60)


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
	for f in _flicker:
		var l: OmniLight3D = f[0]
		l.light_energy = f[1] * (0.8 + 0.2 * sin(_t * 9.0 + f[2]) * sin(_t * 5.3 + f[2] * 2.0))
