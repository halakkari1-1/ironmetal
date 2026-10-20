class_name FX
extends Node3D
## Visual effects on GPU particles: the simulation runs on the graphics chip, so a screen full of explosions,
## fire and smoke costs the processor almost nothing. Explosion and fire use pre-rendered simulations
## (Unity Labs VFX flipbooks, CC0) played frame by frame on each particle.
##
## Every one-shot effect is built once into a small pool when the match loads and is only moved and restarted
## when it plays, so nothing is created, compiled or loaded in the middle of a fight.

const DIR := "res://assets/vfx/"
## Explosion size classes: every blast uses the nearest pre-built size.
const SIZES := [0.6, 1.0, 1.6, 2.6]
const POOL := {0.6: 4, 1.0: 6, 1.6: 4, 2.6: 1}

var _tex := {}
var _mat_cache := {}
var _blasts := {}            # size -> Array of effect roots
var _blast_i := {}
var _small := {}             # name -> {"items": Array, "i": int}
var _lights: Array[OmniLight3D] = []
var _light_t: Array[float] = []
var _light_i := 0
var _decals: Array[Decal] = []
var _decal_t: Array[float] = []
var _decal_i := 0
var _rings: Array = []       # {node, t, radius}
var _lines: Array = []       # {node, t, life}
var fx_k := 1.0


func setup() -> void:
	fx_k = Quality.tier.fx
	for s in SIZES:
		_blasts[s] = []
		_blast_i[s] = 0
		for i in max(1, int(round(POOL[s] * (0.75 + 0.25 * fx_k)))):
			_blasts[s].append(_make_blast(s))
	_pool("spark", 14, func(): return _emitter(_spark_spec(8)))
	_pool("spark_big", 6, func(): return _emitter(_spark_spec(16)))
	_pool("dust", 8, func(): return _emitter({"tex": "puff", "amount": 4, "life": 1.0, "size": [1.2, 4.0], "vel": [0.6, 1.8], "dir": Vector3.UP, "spread": 70.0,
		"colors": [Color(0.58, 0.5, 0.4, 0.35), Color(0.58, 0.5, 0.4, 0)], "damping": 1.0}))
	_pool("heal", 3, func(): return _emitter({"tex": "glow", "add": true, "amount": 24, "life": 0.8, "size": [0.9, 0.2], "vel": [3.0, 6.0], "dir": Vector3.UP, "spread": 10.0,
		"shape_r": 1.6, "colors": [Color(0.35, 1.0, 0.45, 1), Color(0.15, 1.0, 0.35, 0)]}))
	_pool("smoke_burst", 3, func(): return _emitter({"tex": "cloud", "h": 8, "v": 8, "amount": 18, "life": 3.2, "size": [3.0, 8.0], "vel": [0.3, 1.5], "dir": Vector3.UP,
		"spread": 80.0, "shape_r": 6.0, "colors": [Color(0.75, 0.75, 0.73, 0.7), Color(0.7, 0.7, 0.68, 0)], "damping": 0.6, "gravity": Vector3(0, 0.05, 0)}))
	_pool("wave", 3, func(): return _emitter({"tex": "puff", "amount": 46, "life": 0.7, "size": [1.2, 4.0], "vel": [18.0, 28.0], "dir": Vector3.BACK, "spread": 25.0,
		"colors": [Color(0.55, 0.75, 0.95, 0.6), Color(0.7, 0.85, 1.0, 0)], "damping": 2.0, "gravity": Vector3(0, -4, 0), "shape_r": 1.5}))
	_pool("zap", 4, func(): return _emitter({"tex": "glow", "add": true, "amount": 10, "life": 0.14, "size": [0.6, 0.1], "vel": [3.0, 7.0], "dir": Vector3.UP, "spread": 180.0,
		"shape_r": 1.0, "colors": [Color(0.6, 0.85, 1, 1), Color(0.3, 0.5, 1, 0)]}))
	for i in 3:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 26.0
		l.omni_attenuation = 1.5
		l.light_color = Color(1, 0.62, 0.3)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_t.append(0.0)
	var scorch: Texture2D = load(DIR + "scorch.png")
	for i in 24:
		var d := Decal.new()
		d.texture_albedo = scorch
		d.size = Vector3(1, 2, 1)
		d.visible = false
		d.cull_mask = 1
		add_child(d)
		_decals.append(d)
		_decal_t.append(0.0)


func _process(dt: float) -> void:
	for i in _lights.size():
		if _light_t[i] > 0:
			_light_t[i] -= dt
			_lights[i].light_energy *= exp(-dt * 9.0)
			if _light_t[i] <= 0:
				_lights[i].visible = false
	for i in _decals.size():
		if _decal_t[i] > 0:
			_decal_t[i] -= dt
			if _decal_t[i] < 8:
				_decals[i].modulate.a = max(0.0, _decal_t[i] / 8.0)
			if _decal_t[i] <= 0:
				_decals[i].visible = false
	for r in _rings:
		if r.t >= 0:
			r.t += dt
			var k: float = r.t / 0.45
			r.node.scale = Vector3.ONE * (1 + k * r.radius)
			(r.node.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1 - k)
			if k >= 1:
				r.t = -1.0
				r.node.visible = false
	for l in _lines:
		if l.t > 0:
			l.t -= dt
			(l.node.material_override as StandardMaterial3D).albedo_color.a = l.alpha * max(0.0, l.t / l.life)
			if l.t <= 0:
				l.node.visible = false


# ---------- building blocks ----------

func _texture(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := DIR + name + (".png" if ResourceLoader.exists(DIR + name + ".png") else ".webp")
		_tex[name] = load(path)
	return _tex[name]


func _draw_material(spec: Dictionary) -> StandardMaterial3D:
	var key := "%s|%s|%d|%d|%s" % [spec.tex, spec.get("add", false), spec.get("h", 1), spec.get("v", 1), spec.get("shaded", false)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(spec.tex)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if spec.get("shaded", false) else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if spec.get("add", false) else BaseMaterial3D.BLEND_MODE_MIX
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR  # no mipmaps: neighbouring flipbook cells never bleed
	m.disable_receive_shadows = true
	if spec.get("h", 1) > 1:
		m.particles_anim_h_frames = spec.h
		m.particles_anim_v_frames = spec.v
		m.particles_anim_loop = spec.get("loop", false)
	if spec.get("emission", 0.0) > 0.0:
		m.emission_enabled = true
		m.emission = Color(1, 0.6, 0.3) * spec.emission
	_mat_cache[key] = m
	return m


## Builds one GPU particle emitter from a compact description.
## size: [start, end] metres. vel: [min, max] m/s along dir with spread degrees. colors: start..end.
func _emitter(spec: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = max(1, int(spec.amount))
	p.lifetime = spec.life
	p.one_shot = not spec.get("continuous", false)
	p.explosiveness = 0.0 if spec.get("continuous", false) else spec.get("burst", 1.0)
	p.randomness = 0.5
	p.emitting = false
	p.local_coords = spec.get("local", false)
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 80, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH if not spec.get("add", false) else GPUParticles3D.DRAW_ORDER_INDEX
	var pm := ParticleProcessMaterial.new()
	pm.lifetime_randomness = spec.get("life_rand", 0.35)
	pm.direction = spec.get("dir", Vector3.UP)
	pm.spread = spec.get("spread", 180.0)
	pm.initial_velocity_min = spec.vel[0]
	pm.initial_velocity_max = spec.vel[1]
	pm.gravity = spec.get("gravity", Vector3.ZERO)
	pm.damping_min = spec.get("damping", 0.0)
	pm.damping_max = spec.get("damping", 0.0) * 1.3
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -spec.get("spin", 30.0)
	pm.angular_velocity_max = spec.get("spin", 30.0)
	var s0: float = spec.size[0]
	var s1: float = spec.size[1]
	var top: float = max(s0, s1)
	pm.scale_min = top * 0.8
	pm.scale_max = top * 1.15
	var curve := Curve.new()
	curve.add_point(Vector2(0, s0 / top))
	curve.add_point(Vector2(0.35, lerp(s0, s1, 0.75) / top))
	curve.add_point(Vector2(1, s1 / top))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	var cols: Array = spec.colors
	grad.set_color(0, cols[0])
	grad.set_color(1, cols[cols.size() - 1])
	if cols.size() == 3:
		grad.add_point(0.4, cols[1])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	if spec.has("shape_r"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = spec.shape_r
	if spec.has("ring"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = spec.ring
		pm.emission_ring_inner_radius = spec.ring * 0.7
		pm.emission_ring_height = 0.2
	if spec.get("h", 1) > 1:
		var frames: int = spec.h * spec.v
		var speed: float = spec.get("anim_loops", 1.0)
		if spec.has("fps"):
			speed = spec.fps * spec.life / frames
		pm.anim_speed_min = speed
		pm.anim_speed_max = speed
		if spec.get("loop", false):
			pm.anim_offset_min = 0.0
			pm.anim_offset_max = 1.0
	if spec.get("radial", 0.0) > 0.0:
		pm.radial_velocity_min = spec.radial * 0.7
		pm.radial_velocity_max = spec.radial
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, spec.get("aspect", 1.0))
	quad.material = _draw_material(spec)
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _pool(name: String, n: int, make: Callable) -> void:
	var items: Array = []
	for i in n:
		items.append(make.call())
	_small[name] = {"items": items, "i": 0}


func _fire_pool(name: String, pos: Vector3, basis := Basis()) -> GPUParticles3D:
	var pool: Dictionary = _small[name]
	var p: GPUParticles3D = pool.items[pool.i]
	pool.i = (pool.i + 1) % pool.items.size()
	p.global_transform = Transform3D(basis, pos)
	p.restart()
	return p


func _spark_spec(n: int) -> Dictionary:
	return {"tex": "glow", "add": true, "amount": n, "life": 0.3, "size": [0.28, 0.06], "vel": [4.0, 9.0], "dir": Vector3.UP, "spread": 80.0,
		"gravity": Vector3(0, -24, 0), "colors": [Color(1.6, 1.2, 0.6, 1), Color(1, 0.4, 0.1, 0)]}


## One explosion of a given size class: flash, the main simulated blast with secondary bursts, fire billows,
## a lingering smoke column, a ground dust ring and sparks.
func _make_blast(s: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var k := s
	var parts := [
		{"tex": "glow", "add": true, "amount": 1, "life": 0.12, "size": [5 * k, 11 * k], "vel": [0.0, 0.0], "colors": [Color(2, 1.5, 1, 0.7), Color(1, 0.4, 0.1, 0)], "y": 1.6 * k},
		{"tex": "explosion_big" if s >= 1.2 else "explosion", "h": 5, "v": 5, "amount": 1, "life": 1.5 * max(1.0, k * 0.9), "size": [7.5 * k, 10.5 * k], "vel": [1.0, 1.4],
			"spread": 5.0, "colors": [Color(1.35, 1.3, 1.25, 1), Color(1, 1, 1, 0.85)], "y": 1.6 * k, "life_rand": 0.1},
		{"tex": "explosion", "h": 5, "v": 5, "amount": int(2 + k * 2), "life": 1.3, "size": [4.5 * k, 7 * k], "vel": [1.5, 3.0], "spread": 70.0,
			"colors": [Color(1.3, 1.25, 1.2, 1), Color(1, 1, 1, 0.7)], "shape_r": 2.0 * k, "y": 1.4 * k, "burst": 0.85},
		{"tex": "fireball", "h": 8, "v": 8, "amount": int(6 * k * fx_k) + 2, "life": 0.65, "size": [2.0 * k, 4.3 * k], "vel": [4.0 * k, 9.0 * k], "spread": 75.0,
			"gravity": Vector3(0, 2, 0), "damping": 2.4, "colors": [Color(1.3, 1.05, 0.85, 0.9), Color(0.9, 0.35, 0.12, 0)], "y": 0.8},
		{"tex": "smoke", "h": 8, "v": 8, "amount": int(6 * k * fx_k) + 2, "life": 4.2, "size": [6.0 * k, 15.0 * k], "vel": [2.0, 4.5], "spread": 25.0,
			"gravity": Vector3(0, 0.4, 0), "damping": 0.6, "colors": [Color(0.24, 0.22, 0.2, 0.85), Color(0.35, 0.34, 0.33, 0)], "y": 2.2 * k, "shape_r": 1.0 * k, "burst": 0.7},
		{"tex": "disc", "h": 16, "v": 4, "aspect": 2.0, "amount": 8, "life": 1.1, "size": [2.5 * k, 6.5 * k], "vel": [10.0 * k, 16.0 * k], "dir": Vector3(1, 0.05, 0), "spread": 180.0,
			"damping": 3.0, "colors": [Color(0.62, 0.55, 0.47, 0.7), Color(0.6, 0.53, 0.45, 0)], "y": 0.6, "flat": true},
		{"tex": "glow", "add": true, "amount": int(30 * k * fx_k) + 6, "life": 0.9, "size": [0.32, 0.08], "vel": [12.0 * k, 30.0 * k], "spread": 70.0,
			"gravity": Vector3(0, -26, 0), "damping": 0.6, "colors": [Color(1.8, 1.3, 0.6, 1), Color(1, 0.3, 0.05, 0)], "y": 0.5},
	]
	for spec in parts:
		var e := _emitter(spec)
		remove_child(e)
		root.add_child(e)
		e.position.y = spec.get("y", 0.0)
		if spec.get("flat", false):
			var pm: ParticleProcessMaterial = e.process_material
			pm.spread = 180.0
			pm.flatness = 1.0
	return root


# ---------- effects used by the game ----------

func explosion(pos: Vector3, size := 1.0) -> void:
	var best: float = SIZES[0]
	for s in SIZES:
		if abs(s - size) < abs(best - size):
			best = s
	var list: Array = _blasts[best]
	var root: Node3D = list[_blast_i[best]]
	_blast_i[best] = (_blast_i[best] + 1) % list.size()
	root.global_position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = randf() * TAU
	for e in root.get_children():
		(e as GPUParticles3D).restart()
	light(Vector3(pos.x, 4, pos.z), 6.0 * size)
	scorch(pos, 4.5 * size)


func spark(pos: Vector3, big := false) -> void:
	_fire_pool("spark_big" if big else "spark", pos)


func dust(pos: Vector3) -> void:
	_fire_pool("dust", Vector3(pos.x, 0.4, pos.z))


func heal(pos: Vector3) -> void:
	_fire_pool("heal", Vector3(pos.x, 1.0, pos.z))


func smoke_burst(pos: Vector3) -> void:
	_fire_pool("smoke_burst", Vector3(pos.x, 1.2, pos.z))


func zap(pos: Vector3) -> void:
	_fire_pool("zap", pos)


## Megalodon's surge: spray rolling forward along the heading.
func wave(pos: Vector3, heading: float) -> void:
	_fire_pool("wave", pos + Vector3(sin(heading), 0.5, cos(heading)) * 2.0, Basis(Vector3.UP, heading))


func light(pos: Vector3, energy: float, color := Color(1, 0.62, 0.3)) -> void:
	var l := _lights[_light_i]
	_light_t[_light_i] = 0.35
	_light_i = (_light_i + 1) % _lights.size()
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.visible = true


func scorch(pos: Vector3, r: float) -> void:
	var d := _decals[_decal_i]
	_decal_t[_decal_i] = 40.0
	_decal_i = (_decal_i + 1) % _decals.size()
	d.global_position = Vector3(pos.x, 0.0, pos.z)
	d.rotation.y = randf() * TAU
	d.size = Vector3(r * 2, 2.0, r * 2)
	d.modulate.a = 1.0
	d.visible = true


## Expanding shock ring on the ground.
func ring(pos: Vector3, radius: float, color: Color) -> void:
	var r: Dictionary = {}
	for item in _rings:
		if item.t < 0:
			r = item
			break
	if r.is_empty():
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.75
		torus.outer_radius = 1.0
		torus.rings = 40
		torus.ring_segments = 6
		mi.mesh = torus
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		r = {"node": mi, "t": -1.0, "radius": 1.0}
		_rings.append(r)
	r.node.global_position = Vector3(pos.x, 0.6, pos.z)
	(r.node.material_override as StandardMaterial3D).albedo_color = Color(color, 0.9)
	r.node.scale = Vector3.ONE
	r.node.visible = true
	r.t = 0.0
	r.radius = radius


## A flat strip on the ground or a beam between two points, fading out over `life`.
func line(a: Vector3, b: Vector3, width: float, color: Color, life: float, alpha := 0.7) -> void:
	var l: Dictionary = {}
	for item in _lines:
		if item.t <= 0:
			l = item
			break
	if l.is_empty():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		l = {"node": mi, "t": 0.0, "life": 1.0, "alpha": 1.0}
		_lines.append(l)
	var mid := (a + b) / 2
	var len := a.distance_to(b)
	var node: MeshInstance3D = l.node
	node.global_transform = Transform3D(Basis.looking_at((b - a).normalized() if len > 0.01 else Vector3.FORWARD, Vector3.UP if abs((b - a).normalized().y) < 0.99 else Vector3.RIGHT), mid)
	node.scale = Vector3(width, width * 0.2 if a.y < 0.3 else width, len)
	(node.material_override as StandardMaterial3D).albedo_color = Color(color, alpha)
	node.visible = true
	l.t = life
	l.life = life
	l.alpha = alpha


# ---------- continuous emitters (attached by the game) ----------

## Thick dark smoke rolling off a damaged car or wreck.
func burn_emitter() -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "smoke", "h": 8, "v": 8, "amount": 10, "life": 2.8, "size": [1.6, 8.0], "vel": [2.0, 3.8], "spread": 12.0,
		"gravity": Vector3(0, 0.25, 0), "damping": 0.5, "colors": [Color(0.17, 0.16, 0.15, 0.8), Color(0.3, 0.29, 0.28, 0)], "shape_r": 0.5})


## Licking flames: the looped fire simulation.
func flame_emitter(k := 1.0, amount := 6) -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "flame", "h": 16, "v": 4, "aspect": 2.0, "loop": true, "fps": 26.0, "add": true, "amount": amount, "life": 0.8,
		"size": [2.6 * k, 3.2 * k], "vel": [0.6, 1.4], "spread": 15.0, "gravity": Vector3(0, 0.5, 0), "colors": [Color(1.1, 0.8, 0.5, 0.85), Color(0.9, 0.4, 0.2, 0)],
		"shape_r": 0.5 * k, "spin": 5.0})


## A smoke column drifting off a burning tower or chimney.
func tower_smoke_emitter(big := true) -> GPUParticles3D:
	var k := 1.0 if big else 0.4
	return _emitter({"continuous": true, "tex": "smoke", "h": 8, "v": 8, "amount": max(4, int(10 * fx_k * k)), "life": 8.0 * (0.7 + 0.3 * k), "size": [12.0 * k, 36.0 * k],
		"vel": [3.0, 5.0], "spread": 10.0, "gravity": Vector3(1.4, 0.2, 0.3), "damping": 0.25, "colors": [Color(0.14, 0.13, 0.12, 0.75), Color(0.3, 0.29, 0.28, 0)],
		"shape_r": 2.0 * k})


func dust_emitter() -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "puff", "amount": 14, "life": 1.1, "size": [1.2, 4.0], "vel": [0.5, 1.6], "spread": 60.0,
		"colors": [Color(0.6, 0.52, 0.42, 0.28), Color(0.6, 0.52, 0.42, 0)], "damping": 1.0, "shape_r": 0.6})


## Rocket exhaust: a hot core and a fading smoke trail.
func trail_emitter(big := false) -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "puff", "amount": 40 if big else 28, "life": 1.3, "size": [0.9, 3.6 if big else 2.8], "vel": [0.3, 1.0], "spread": 180.0,
		"colors": [Color(1.4, 1.0, 0.6, 0.7), Color(0.6, 0.58, 0.55, 0.45), Color(0.45, 0.44, 0.42, 0)], "damping": 1.0})


func beacon_emitter() -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "puff", "amount": 24, "life": 3.0, "size": [1.2, 5.0], "vel": [5.0, 8.0], "spread": 8.0, "gravity": Vector3(0.3, -0.5, 0),
		"damping": 0.4, "colors": [Color(0.25, 0.5, 1, 0.75), Color(0.5, 0.65, 0.9, 0)]})


func toxic_emitter(r: float) -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "cloud", "h": 8, "v": 8, "amount": int(26 * fx_k) + 6, "life": 2.0, "size": [2.4, 5.5], "vel": [0.3, 1.0], "spread": 80.0,
		"shape_r": r * 0.8, "damping": 0.6, "colors": [Color(0.45, 1.25, 0.3, 0.55), Color(0.3, 0.8, 0.15, 0)]})


func fire_zone_emitter(r: float) -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "flame", "h": 16, "v": 4, "aspect": 2.0, "loop": true, "fps": 26.0, "add": true, "amount": int(r * 2.5) + 4, "life": 0.8,
		"size": [1.6, 2.4], "vel": [0.6, 1.4], "spread": 15.0, "shape_r": r * 0.8, "colors": [Color(1.1, 0.8, 0.5, 0.85), Color(0.9, 0.4, 0.2, 0)]})


func smoke_trail_emitter() -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "cloud", "h": 8, "v": 8, "amount": 30, "life": 3.0, "size": [2.5, 7.0], "vel": [0.2, 1.0], "spread": 90.0,
		"shape_r": 2.0, "damping": 0.5, "colors": [Color(0.75, 0.75, 0.73, 0.65), Color(0.7, 0.7, 0.68, 0)]})


func color_trail_emitter(c: Color) -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "glow", "add": true, "amount": 30, "life": 0.35, "size": [1.4, 0.3], "vel": [0.0, 0.8], "spread": 180.0,
		"shape_r": 0.4, "colors": [Color(c, 1), Color(c * Color(0.6, 0.4, 0.8), 0)]})


func sand_emitter() -> GPUParticles3D:
	return _emitter({"continuous": true, "tex": "puff", "amount": 90, "life": 1.8, "size": [4.0, 11.0], "vel": [14.0, 22.0], "dir": Vector3(1, 0, 0.35), "spread": 12.0,
		"shape_r": 26.0, "colors": [Color(0.78, 0.62, 0.44, 0.35), Color(0.75, 0.6, 0.42, 0)]})


## Debris chunks, a short burst with gravity; ground collision comes from the floor collider in the match.
func debris_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 4.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0, -30, 0)
	pm.angular_velocity_min = -400
	pm.angular_velocity_max = 400
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.3
	pm.collision_friction = 0.6
	pm.collision_use_scale = true
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.18, 0.4)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.17, 0.155, 0.14)
	m.metallic = 0.7
	m.roughness = 0.5
	mesh.material = m
	p.draw_pass_1 = mesh
	add_child(p)
	return p
