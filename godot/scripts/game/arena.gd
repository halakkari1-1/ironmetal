class_name Arena
extends Node3D
## Builds an arena: sky, sun, ground, the concrete barrier walls, cover props with collision shapes,
## explosive barrels, storage tanks, and the district around it — a continuous street front of warehouses
## with ruined towers and wrecked works packed edge to edge behind, so the square is closed in on every side.

const PS := 1.5   # prop scale: kit props are true-to-life, game cars are a bit oversized
const BS := 1.7   # landmark building scale
const WS := 1.6   # wall (jersey barrier) scale
## Building models around the arena (assets/buildings/<id>.glb). tall: ruined tower; otherwise wide works.
const SKYLINE := [
	{"id": "skyscraper", "tall": true}, {"id": "spire", "tall": true}, {"id": "ascent", "tall": true},
	{"id": "refinery", "tall": false}, {"id": "foundry", "tall": false},
]

var map: Dictionary
var half := 66.0
var obstacles: Array = []   # {kind:"box"|"circle", x, z, hw, hd, rot | r, h, barrel?, hp?, node?, index?}
var spawns: Array = []      # {x, z, heading}
var pickup_spots: Array = []
var stacks: Array = []      # smoke columns: {pos, big}
var blazes: Array = []      # fires in the buildings: Vector3
var sun: DirectionalLight3D
var env: Environment
var barrel_mm: MultiMeshInstance3D

var _rng := RandomNumberGenerator.new()
var _instances := {}        # prop name -> [Transform3D]
var _barrels: Array = []


func R() -> float:
	return _rng.randf()


func build(m: Dictionary) -> void:
	Kit.init()
	map = m
	half = m.size / 2.0
	_rng.seed = hash(m.id) + int(m.size) * 13
	var prof := OS.has_environment("IM_PROFILE")
	var t0 := Time.get_ticks_usec()
	for step in [_environment, _walls, _district, _atmosphere, _terrain, _layout, _ground, _flush_props, func(): _flush_district(true)]:
		step.call()
		if prof:
			print("TEST arena %s %d ms" % [str(step.get_method()), (Time.get_ticks_usec() - t0) / 1000])
			t0 = Time.get_ticks_usec()
	for i in 10:   # room for a full multiplayer match
		var a := float(i) / 10.0 * TAU + PI / 2
		var sr := half * 0.72
		spawns.append({"x": cos(a) * sr, "z": sin(a) * sr, "heading": atan2(-cos(a), -sin(a))})
	for i in 6:
		var a := float(i) / 6.0 * TAU + 0.4
		var d := half * (0.42 if i % 2 else 0.25)
		pickup_spots.append({"x": cos(a) * d, "z": sin(a) * d, "type": "ammo" if i % 2 else "health"})


# ---------- sky, light ----------

func _environment() -> void:
	var sk: Dictionary = map.sky
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://scripts/game/sky.gdshader")
	sky_mat.set_shader_parameter("top_color", map.sky_top)
	sky_mat.set_shader_parameter("horizon_color", map.horizon)
	sky_mat.set_shader_parameter("ground_color", map.ground.darkened(0.6))
	sky_mat.set_shader_parameter("sun_color", map.sun)
	sky_mat.set_shader_parameter("stars", sk.stars)
	sky_mat.set_shader_parameter("moon", sk.moon)
	sky_mat.set_shader_parameter("sun_size", 0.03 if sk.moon > 0 else 0.016)
	sky_mat.set_shader_parameter("halo", 0.18 if sk.moon > 0 else 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = sk.ambient
	env.ambient_light_energy = sk.ambient_energy * 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.2
	env.tonemap_white = 6.0
	env.glow_enabled = Quality.tier.glow
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.05
	env.adjustment_brightness = 1.06
	# a light distance haze in the horizon colour: depth, and it softens the district
	env.fog_enabled = false   # fog turns the premultiplied fire sprites into glowing boxes on some renderers
	env.fog_light_color = map.horizon.lerp(map.sky_top, 0.35)
	env.fog_light_energy = 0.8
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = map.sun
	sun.light_energy = sk.sun_energy
	sun.rotation = Vector3(deg_to_rad(-sk.elev), deg_to_rad(sk.az), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = Quality.tier.shadow_dist
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 0.8
	sun.shadow_opacity = 0.7   # shadows soft enough that nothing disappears in them
	sun.light_angular_distance = 0.4
	add_child(sun)
	_clouds(sk)


## The moving cloud deck: an inside-out dome far out, drawn over the sky.
func _clouds(sk: Dictionary) -> void:
	var dome := SphereMesh.new()
	dome.radius = 700.0
	dome.height = 1400.0
	dome.radial_segments = 32
	dome.rings = 16
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/game/clouds.gdshader")
	m.set_shader_parameter("noise_tex", load("res://assets/arena/cloud_noise.png"))
	m.set_shader_parameter("lit_color", sk.cloud_lit)
	m.set_shader_parameter("shade_color", sk.cloud_shade)
	m.set_shader_parameter("cover", sk.cover)
	m.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	m.set_shader_parameter("opacity", 0.75 if sk.stars > 0.5 else 0.92)
	var mi := MeshInstance3D.new()
	mi.mesh = dome
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 100.0
	add_child(mi)


# ---------- searchlights and ground fires ----------
# Searchlights on poles behind the walls sweep the arena in two colours; each has a visible beam (an additive
# cone that fades along its length, the cheap stand-in for volumetric light on phones). Small fires burn on the
# ground around the edge with a flickering light; the match puts the flames and smoke on them (ground_fires).

var ground_fires: Array = []    # Vector3
var _lights: Array = []         # {light, beam, base_yaw, phase, kind}
var _t := 0.0


func _atmosphere() -> void:
	var sk: Dictionary = map.sky
	var cols: Array = sk.search
	var night: bool = sk.stars > 0.5
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var n := 4 if Quality.tier_id != "low" else 2
	for i in n:
		var c: Vector2 = corners[i] * (half - 2.5)
		var pole := _mesh(_pole_mesh(), Kit.solid_material, Vector3(c.x, 0, c.y))
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var head := Node3D.new()
		head.position = Vector3(c.x, 14.0, c.y)
		add_child(head)
		var sl := SpotLight3D.new()
		sl.light_color = cols[i % 2]
		sl.light_energy = 16.0 if night else 8.0
		sl.spot_range = 110.0
		sl.spot_angle = 17.0
		sl.spot_attenuation = 0.6
		sl.shadow_enabled = false
		head.add_child(sl)
		var beam := MeshInstance3D.new()
		beam.mesh = _beam_mesh(92.0, 92.0 * tan(deg_to_rad(17.0)))
		var bm := ShaderMaterial.new()
		bm.shader = _beam_shader()
		bm.set_shader_parameter("color", cols[i % 2])
		bm.set_shader_parameter("strength", 0.22 if night else 0.07)
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(beam)
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.7
		lm.height = 1.4
		lamp.mesh = lm
		var em := StandardMaterial3D.new()
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.albedo_color = (cols[i % 2] as Color) * 3.0
		lamp.material_override = em
		head.add_child(lamp)
		var yaw := atan2(-c.x, -c.y)
		_lights.append({"node": head, "base_yaw": yaw, "phase": R() * TAU, "speed": 0.25 + R() * 0.2, "kind": "search"})
	# fires on the ground, out of the way along the walls
	var count: int = int(sk.fires * Quality.tier.fx) if Quality.tier_id != "low" else 2
	var lit := 0
	for k in count:
		var side := int(R() * 4)
		var p := _side_point(side, (R() * 2 - 1) * (half - 12), half - 4.0 - R() * 3)
		var pos := Vector3(p.x, 0.0, p.y)
		ground_fires.append(pos)
		obstacles.append({"kind": "circle", "x": pos.x, "z": pos.z, "r": 1.4, "h": 0.6})
		add_prop("drums", pos.x + 1.6, pos.z + 0.4, R() * TAU, 0.8, false)
		if lit < 4:
			lit += 1
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.55, 0.2)
			ol.light_energy = 4.5 if night else 2.2
			ol.omni_range = 13.0
			ol.position = pos + Vector3(0, 2.0, 0)
			ol.shadow_enabled = false
			add_child(ol)
			_lights.append({"node": ol, "phase": R() * 10, "base": ol.light_energy, "kind": "fire"})


func _process(dt: float) -> void:
	_t += dt
	for l in _lights:
		if l.kind == "search":
			# a slow sweep left and right of the arena centre, and a gentle nod
			var n: Node3D = l.node
			n.rotation = Vector3(-0.36 + 0.1 * sin(_t * l.speed * 0.7 + l.phase), l.base_yaw + 0.55 * sin(_t * l.speed + l.phase), 0)
		else:
			var f := 0.75 + 0.25 * sin(_t * 13.0 + l.phase) * sin(_t * 7.3 + l.phase * 2.0) + 0.1 * sin(_t * 31.0 + l.phase)
			(l.node as OmniLight3D).light_energy = l.base * f


func _pole_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.25
	m.bottom_radius = 0.4
	m.height = 14.0
	m.radial_segments = 8
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	var out := ArrayMesh.new()
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += 7.0
	arr[Mesh.ARRAY_VERTEX] = v
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## A cone along -z (the light's direction) from the lamp to `length`, open at the far end.
func _beam_mesh(length: float, radius: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * 0.5, sin(a0) * 0.5, 0)
		var p1 := Vector3(cos(a1) * 0.5, sin(a1) * 0.5, 0)
		var q0 := Vector3(cos(a0) * radius, sin(a0) * radius, -length)
		var q1 := Vector3(cos(a1) * radius, sin(a1) * radius, -length)
		for v in [[p0, 0.0], [q0, 1.0], [q1, 1.0], [p0, 0.0], [q1, 1.0], [p1, 0.0]]:
			st.set_uv(Vector2(0, v[1]))
			st.add_vertex(v[0])
	return st.commit()


static var _beam_sh: Shader


func _beam_shader() -> Shader:
	if _beam_sh == null:
		_beam_sh = Shader.new()
		_beam_sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color;
uniform float strength = 0.3;
void fragment() {
	// bright near the lamp, fading out along the beam; soft at the edges seen side-on
	float along = 1.0 - UV.y;
	float edge = pow(abs(dot(NORMAL, VIEW)), 2.5);
	ALBEDO = color * strength * along * along * edge;
}
"""
	return _beam_sh


# ---------- terrain: hills and jump ramps ----------
# The driving is on a height field: a few broad, low hills (gaussian mounds) and jump ramps (wedges that rise
# towards a lip with a sheer back). height_at() is what the cars follow; the ground mesh is built from the hills,
# each ramp has its own mesh. Cars leave the ground when it falls away faster than gravity can pull them down,
# so a fast run up a ramp throws them into the air.

var hills: Array = []       # {x, z, h, s}
var ramps: Array = []       # {x, z, fx, fz, L, W, H}
var _reserved: Array = []   # [x, z, r]: kept clear of props

const RAMP_L := 8.0
const RAMP_W := 6.5
const RAMP_H := 2.3


func height_at(x: float, z: float) -> float:
	var h := 0.0
	for m in hills:
		var dx: float = x - m.x
		var dz: float = z - m.z
		var d2 := dx * dx + dz * dz
		if d2 < m.cut:
			h += m.h * exp(-d2 / (2.0 * m.s * m.s))
	for r in ramps:
		var dx: float = x - r.x
		var dz: float = z - r.z
		var u: float = dx * r.fx + dz * r.fz
		var v: float = -dx * r.fz + dz * r.fx
		if abs(v) <= r.W * 0.5 and abs(u) <= r.L * 0.5:
			h = max(h, r.H * (u + r.L * 0.5) / r.L)
	return h


## Where each map's landmark buildings stand (kept free of hills and ramps).
func _landmark_spots() -> Array:
	match map.id:
		"scrapyard": return [[-half * 0.42, -half * 0.05, 20.0]]
		"refinery": return [[half * 0.45, -half * 0.42, 20.0]]
		"dustbowl": return [[half * 0.5, half * 0.48, 20.0]]
		"shanty": return [[0.0, -half * 0.36, 20.0], [-half * 0.38, half * 0.3, 20.0], [half * 0.4, half * 0.28, 20.0]]
	return [[0.0, 0.0, 28.0]]


func _terrain() -> void:
	for q in _landmark_spots():
		_reserved.append(q)
	var n_hills := 4
	var n_ramps := 3 if map.size >= 140 else 2
	var k := 0
	var tries := 0
	while k < n_hills and tries < 300:
		tries += 1
		var a := R() * TAU
		var d := half * (0.3 + R() * 0.5)
		var x := cos(a) * d
		var z := sin(a) * d
		var sg := 6.0 + R() * 4.0
		if _clear(x, z, sg * 1.3):
			var hh := 1.1 + R() * 1.0
			hills.append({"x": x, "z": z, "h": hh, "s": sg, "cut": pow(sg * 3.2, 2)})
			_reserved.append([x, z, sg * 1.5])
			k += 1
	k = 0
	tries = 0
	while k < n_ramps and tries < 900:
		tries += 1
		var loose := tries > 450   # crowded maps: settle for a shorter run-up
		var x := (R() * 2 - 1) * half * 0.75
		var z := (R() * 2 - 1) * half * 0.75
		var ang := R() * TAU
		var fx := sin(ang)
		var fz := cos(ang)
		# the ramp itself, its run-up and its landing all need open ground
		var ok := _clear(x, z, 5.0 if loose else 6.0) and _clear(x - fx * 14, z - fz * 14, 2.5 if loose else 4.0) \
			and _clear(x + fx * 18, z + fz * 18, 4.0 if loose else 6.0)
		if not ok:
			continue
		for r in ramps:
			if Vector2(r.x - x, r.z - z).length() < 30:
				ok = false
		if not ok:
			continue
		ramps.append({"x": x, "z": z, "fx": fx, "fz": fz, "L": RAMP_L, "W": RAMP_W, "H": RAMP_H})
		for p in [[0.0, 6.0], [-14.0, 4.0], [18.0, 6.0]]:
			_reserved.append([x + fx * p[0], z + fz * p[0], p[1]])
		# the sheer back face stops cars driving into it from behind (cars flying off the lip pass over it)
		obstacles.append({"kind": "box", "x": x + fx * (RAMP_L * 0.5 + 0.35), "z": z + fz * (RAMP_L * 0.5 + 0.35),
			"hw": RAMP_W * 0.5, "hd": 0.35, "rot": ang, "h": RAMP_H, "ramp": true})
		_ramp_mesh(ramps[-1], ang)
		k += 1


static var _ramp_mat: StandardMaterial3D


func _ramp_mesh(r: Dictionary, ang: float) -> void:
	if _ramp_mat == null:
		_ramp_mat = StandardMaterial3D.new()
		_ramp_mat.albedo_texture = load("res://assets/arena/ramp_albedo.png")
		_ramp_mat.normal_enabled = true
		_ramp_mat.normal_texture = load("res://assets/arena/ramp_normal.png")
		_ramp_mat.metallic = 0.55
		_ramp_mat.roughness = 0.5
		_ramp_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var L: float = r.L
	var W: float = r.W
	var H: float = r.H
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-W / 2, 0, -L / 2)
	var b := Vector3(W / 2, 0, -L / 2)
	var c := Vector3(W / 2, H, L / 2)
	var d := Vector3(-W / 2, H, L / 2)
	var nt := Vector3(0, L, -H).normalized()
	# top: hazard band (v = 0) at the lip
	_tri3(st, [a, c, b], [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)], nt)
	_tri3(st, [a, d, c], [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)], nt)
	# sides and back, plain plate from the middle of the texture
	var e := Vector3(W / 2, 0, L / 2)
	var f := Vector3(-W / 2, 0, L / 2)
	_tri3(st, [b, c, e], [Vector2(0, 0.6), Vector2(1, 0.3), Vector2(1, 0.6)], Vector3.RIGHT)
	_tri3(st, [a, f, d], [Vector2(0, 0.6), Vector2(1, 0.6), Vector2(1, 0.3)], Vector3.LEFT)
	_tri3(st, [e, c, d], [Vector2(1, 0.62), Vector2(1, 0.4), Vector2(0, 0.4)], Vector3.BACK)
	_tri3(st, [e, d, f], [Vector2(1, 0.62), Vector2(0, 0.4), Vector2(0, 0.62)], Vector3.BACK)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ramp_mat
	mi.position = Vector3(r.x, 0, r.z)
	mi.rotation.y = ang
	add_child(mi)


func _tri3(st: SurfaceTool, p: Array, uv: Array, n: Vector3) -> void:
	# wound to face along n
	var order := [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(n)
		st.set_uv(uv[i])
		st.add_vertex(p[i])


# ---------- ground ----------
# One shader for the whole floor: tiled dirt with large-scale light and dark patches, the concrete square on maps
# that have one, and a detail map baked for each arena from stamps: cracks, tyre tracks and scorch marks (darker),
# oil (black and glossy) and puddles (dark and mirror-smooth, they pick up the sky and the lights).

const DETAIL_PX := 1024


func _ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/game/ground.gdshader")
	var fl: Dictionary = map.floor
	var base := "res://assets/ground/%s_" % fl.tex
	mat.set_shader_parameter("dirt_albedo", load(base + "color.jpg"))
	mat.set_shader_parameter("dirt_normal", load(base + "normal.jpg"))
	mat.set_shader_parameter("dirt_rough", load(base + "rough.jpg"))
	mat.set_shader_parameter("concrete_tex", load("res://assets/ground/concrete047a_color.jpg"))
	mat.set_shader_parameter("tint", Color.WHITE.lerp(map.ground, 0.15) * float(fl.bright))
	mat.set_shader_parameter("tile", 1.0 / float(fl.tile))
	mat.set_shader_parameter("concrete_half", map.size * map.concrete * 0.5)
	mat.set_shader_parameter("arena_half", half)
	var maps := _detail_maps()
	mat.set_shader_parameter("grime_map", maps[0])
	mat.set_shader_parameter("wet_map", maps[1])
	mat.set_shader_parameter("water_map", maps[2])
	# the far ground: one big flat plane
	var plane := PlaneMesh.new()
	plane.size = Vector2(map.size * 4, map.size * 4)
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = mat
	g.position.y = -0.03
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	# the arena floor: a grid lifted over the hills
	var ext := half + 6.0
	var step := 1.6
	var n := int(ceil(ext * 2 / step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -ext + i * step
			var z := -ext + j * step
			var h := 0.0
			for m in hills:
				var d2: float = pow(x - m.x, 2) + pow(z - m.z, 2)
				h += m.h * exp(-d2 / (2.0 * m.s * m.s))
			hs[j * (n + 1) + i] = h
	for j in n + 1:
		for i in n + 1:
			var h0 := hs[j * (n + 1) + i]
			var hx := hs[j * (n + 1) + min(i + 1, n)] - hs[j * (n + 1) + max(i - 1, 0)]
			var hz := hs[min(j + 1, n) * (n + 1) + i] - hs[max(j - 1, 0) * (n + 1) + i]
			st.set_normal(Vector3(-hx / (2 * step), 1, -hz / (2 * step)).normalized())
			st.add_vertex(Vector3(-ext + i * step, h0, -ext + j * step))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 2)
			st.add_index(a + n + 1)
	var floor := MeshInstance3D.new()
	floor.mesh = st.commit()
	floor.material_override = mat
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor)


## Bakes the three detail masks for this arena (grime, oil, water) from the stamp images.
func _detail_maps() -> Array:
	var out := []
	var size := float(map.size)
	var px_per_m := DETAIL_PX / size
	var layers := [
		[["crack_0", "crack_1", "crack_2", "crack_3"], 26, [7.0, 14.0]],
		[["oil_0", "oil_1", "oil_2"], 12, [2.0, 4.5]],
		[["puddle_0", "puddle_1", "puddle_2"], 7, [4.0, 8.0]],
	]
	var stamps := {}
	for li in 3:
		var img := Image.create(DETAIL_PX, DETAIL_PX, false, Image.FORMAT_LA8)
		img.fill(Color(0, 0, 0, 1))
		var spec: Array = layers[li]
		var count: int = spec[1]
		for k in count + (10 if li == 0 else 0):
			var name: String = spec[0][int(R() * spec[0].size())]
			var meters: float = lerp(float(spec[2][0]), float(spec[2][1]), R())
			if li == 0 and k >= count:   # tyre tracks and old scorch marks go on the grime layer too
				name = ["tyre_0", "tyre_1", "scorch_ground"][k % 3]
				meters = 16.0 if name.begins_with("tyre") else 7.0
			var x := (R() * 2 - 1) * (half - 4)
			var z := (R() * 2 - 1) * (half - 4)
			if li == 2 and abs(height_at(x, z)) > 0.05:
				continue   # no puddles on hills or ramps
			_stamp(img, _stamp_image(stamps, name), x, z, meters * px_per_m)
		img.generate_mipmaps()   # no shimmer in the distance
		var tex := ImageTexture.create_from_image(img)
		out.append(tex)
	return out


func _stamp_image(cache: Dictionary, name: String) -> Image:
	if not cache.has(name):
		var img: Image = load("res://assets/arena/%s.png" % name).get_image()
		img.decompress()
		img.convert(Image.FORMAT_LA8)   # the stamps are white with the mask in alpha
		cache[name] = img
	return cache[name]


func _stamp(dst: Image, src: Image, x: float, z: float, px: float) -> void:
	var s: Image = src.duplicate()
	var ratio := float(s.get_height()) / s.get_width()
	s.resize(max(4, int(px)), max(4, int(px * ratio)), Image.INTERPOLATE_BILINEAR)
	if R() < 0.5:
		s.rotate_90(CLOCKWISE)
	if R() < 0.5:
		s.flip_x()
	if R() < 0.5:
		s.flip_y()
	var u := int((x / map.size + 0.5) * DETAIL_PX - s.get_width() / 2.0)
	var v := int((z / map.size + 0.5) * DETAIL_PX - s.get_height() / 2.0)
	dst.blend_rect(s, Rect2i(0, 0, s.get_width(), s.get_height()), Vector2i(u, v))


# ---------- helpers ----------

func add_prop(name: String, x: float, z: float, ry := 0.0, s := 1.0, collide := true) -> void:
	if not collide and Quality.tier_id == "low":
		return
	if not _instances.has(name):
		_instances[name] = []
	var b := Basis(Vector3.UP, ry).scaled(Vector3.ONE * PS * s)
	_instances[name].append(Transform3D(b, Vector3(x, 0, z)))
	if not collide:
		return
	var sz := Kit.prop_size(name, PS * s)
	var hw := sz.x / 2 * 0.94
	var hd := sz.z / 2 * 0.94
	if abs(hw - hd) < 0.3 * max(hw, hd):
		obstacles.append({"kind": "circle", "x": x, "z": z, "r": (hw + hd) / 2, "h": sz.y})
	else:
		obstacles.append({"kind": "box", "x": x, "z": z, "hw": hw, "hd": hd, "rot": ry, "h": sz.y})


func _flush_props() -> void:
	for name in _instances:
		var list: Array = _instances[name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Kit.mesh("prop_" + name)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = Kit.material
		if Quality.tier_id != "high" and name != "barrier":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if _barrels.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Kit.barrel()
		mm.instance_count = _barrels.size()
		for i in _barrels.size():
			mm.set_instance_transform(i, _barrels[i])
		barrel_mm = MultiMeshInstance3D.new()
		barrel_mm.multimesh = mm
		var bm: BaseMaterial3D = Kit.solid_material.duplicate()
		bm.albedo_color = Color(1.15, 0.92, 0.85)
		barrel_mm.material_override = bm
		add_child(barrel_mm)


## A destroyed barrel collapses its instance to nothing.
func hide_barrel(o: Dictionary) -> void:
	if barrel_mm:
		barrel_mm.multimesh.set_instance_transform(o.index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, ry := 0.0, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = ry
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func barrel(x: float, z: float) -> void:
	obstacles.append({"kind": "circle", "x": x, "z": z, "r": 0.85, "h": 1.8, "barrel": true, "hp": 15.0, "index": _barrels.size()})
	_barrels.append(Transform3D(Basis(Vector3.UP, R() * TAU), Vector3(x, 0, z)))


func tank(x: float, z: float, r: float, h: float) -> void:
	var node := _mesh(Kit.panel_cylinder(r, h, Kit.ATLAS.plate), Kit.solid_material, Vector3(x, 0, z))
	var stripe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r + 0.04
	cyl.bottom_radius = r + 0.04
	cyl.height = 0.6
	cyl.cap_top = false
	cyl.cap_bottom = false
	stripe.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("c9951f")
	sm.roughness = 0.7
	stripe.material_override = sm
	stripe.position = Vector3(0, h * 0.72, 0)
	node.add_child(stripe)
	obstacles.append({"kind": "circle", "x": x, "z": z, "r": r, "h": h + r * 0.35, "node": node, "tank": true})


func container(x: float, z: float, ry: float, stack := false) -> void:
	for level in (2 if stack else 1):
		_put_container(Vector3(x, level * CONT_H, z), ry + ((R() - 0.5) * 0.25 if level else 0.0))
	obstacles.append({"kind": "box", "x": x, "z": z, "hw": 3.9, "hd": 1.55, "rot": ry, "h": 6.6 if stack else 3.3})


func landmark(x: float, z: float, ry: float) -> void:
	var lod0 := _mesh(Kit.mesh("building_lod0"), Kit.material, Vector3(x, 0, z), ry)
	lod0.scale = Vector3.ONE * BS
	var fp: Dictionary = Kit.meta.building.footprint
	var cx: float = (fp.min[0] + fp.max[0]) / 2 * BS
	var cz: float = (fp.min[2] + fp.max[2]) / 2 * BS
	var c := cos(ry)
	var s := sin(ry)
	obstacles.append({"kind": "box", "x": x + cx * c + cz * s, "z": z - cx * s + cz * c,
		"hw": (fp.max[0] - fp.min[0]) / 2 * BS, "hd": (fp.max[2] - fp.min[2]) / 2 * BS, "rot": ry,
		"h": Kit.meta.building.lod0.size[1] * BS, "building": true})


# ---------- boundary ----------

func _walls() -> void:
	var bs := Kit.prop_size("barrier", WS)
	var n := ceili(map.size / (bs.x * 0.98))
	for i in n:
		var p: float = -half + (i + 0.5) * (map.size / n)
		for w in [[p, -half, 0.0], [p, half, PI], [-half, p, PI / 2], [half, p, -PI / 2]]:
			if not _instances.has("barrier"):
				_instances["barrier"] = []
			var b := Basis(Vector3.UP, w[2] + (R() - 0.5) * 0.06).scaled(Vector3.ONE * WS)
			_instances["barrier"].append(Transform3D(b, Vector3(w[0], 0, w[1])))


# ---------- the district beyond the walls ----------

func _district() -> void:
	var edge := half + 1.7
	var D1 := 14.0
	# Row 1, pressed against the barriers: stacks of coloured shipping containers and piles of burnt-out wrecks,
	# heaped at random. Every container and every wreck model is one draw call (instanced).
	var wreck_share: float = {"scrapyard": 0.55, "refinery": 0.2, "dustbowl": 0.4, "shanty": 0.45, "outpost": 0.3}.get(map.id, 0.35)
	if Quality.tier_id == "low":
		wreck_share *= 0.4   # wrecks are the heaviest part of the wall; low-end phones get mostly containers
	for side in 4:
		var span := half + D1 + 2 if side < 2 else half
		var u := -span
		while u < span - 4:
			var wreck := R() < wreck_share
			var seg: float = min(span - u, (10.0 + R() * 8.0) if wreck else (CONT_L + 0.6) * (1 + int(R() * 3)))
			if wreck:
				_wreck_pile(side, u, seg, edge)
			else:
				_container_stacks(side, u, seg, edge)
			u += seg + R() * 1.5
		_occluder(_side_point(side, 0, edge + D1 / 2), _side_rot(side), Vector3(span * 2, 5, D1 * 0.6))
	_flush_district()
	_skyline(edge, D1)


func _skyline(edge: float, D1: float) -> void:
	# Rows 2 and 3: building models packed edge to edge, alternating towers and works, overlapping slightly so
	# no sky shows between them. Each building is its own instance (frustum culled, automatic LOD).
	var kinds: Array = []
	for k in SKYLINE:
		var scene: PackedScene = load("res://assets/buildings/%s.glb" % k.id)
		var probe := scene.instantiate()
		var box := _aabb(probe)
		probe.free()
		kinds.append({"id": k.id, "tall": k.tall, "scene": scene, "box": box})
	var tall := kinds.filter(func(k): return k.tall)
	var wide := kinds.filter(func(k): return not k.tall)
	var turn := 0
	var rows := 2 if Quality.tier_id != "low" else 1
	for row in rows:
		var row_start := edge + D1 + 3.0 + row * 46.0
		for side in 4:
			var span := half + D1 + 30.0 + row * 46.0
			var u := -span + (0.0 if row == 0 else 12.0)
			while u < span:
				var list: Array = tall if (turn % 2 == 0 or row == 1) else wide
				var kind: Dictionary = list[(turn / 2) % list.size()]
				turn += 1
				var hgt: float = (58 + R() * 24 + row * 10) if kind.tall else (36 + R() * 10)
				var size: Vector3 = kind.box.size
				var sc := hgt / size.y
				var quarter := int(R() * 4)
				var along := (size.z if quarter % 2 else size.x) * sc
				var deep := (size.x if quarter % 2 else size.z) * sc
				var mid := u + along / 2
				var dist := row_start + deep / 2
				var xz := _side_point(side, mid, dist)
				_building(kind, sc, quarter * PI / 2 + (R() - 0.5) * 0.12, Vector3(xz.x, 0, xz.y), hgt, deep, row == 0)
				u += along * 0.82  # slight overlap: never a gap
	# corner towers close the four corners
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var kind: Dictionary = tall[(cx + 1 + (cz + 1) / 2) % tall.size()]
			var hgt := 70 + R() * 15
			var sc: float = hgt / kind.box.size.y
			var p: Vector3 = Vector3(cx, 0, cz) * (edge + D1 + 3 + max(kind.box.size.x, kind.box.size.z) * sc / 2)
			_building(kind, sc, R() * TAU, p, hgt, max(kind.box.size.x, kind.box.size.z) * sc, true)


# ---------- containers and wrecks ----------

const CONT_L := 7.8
const CONT_W := 3.1
const CONT_H := 3.3
const CONT_COLORS := [Color("b13a2c"), Color("2f5f9e"), Color("3f7f4a"), Color("d9782a"), Color("d8b23a"), Color("2f8a8c"),
	Color("d6d3c8"), Color("7a2a32"), Color("4a4f8a"), Color("c45a2a")]
const WRECK_IDS := ["ghost", "venom", "toxic", "megalodon", "siren", "rex", "colossus", "wraith", "titan", "reaper"]

static var _cont_mesh: ArrayMesh
static var _cont_mat: StandardMaterial3D
static var _wreck_meshes := {}
static var _wreck_mat: ShaderMaterial
var _cont_xf: Array = []     # [Transform3D, Color]
var _wreck_xf := {}          # id -> [Transform3D]


## Shipping container, origin at ground centre, long axis along X: corrugated sides, the doors on the +X end.
static func container_mesh() -> ArrayMesh:
	if _cont_mesh:
		return _cont_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var X := CONT_L / 2
	var Z := CONT_W / 2
	var H := CONT_H
	var quads := [
		# corners (counter-clockwise seen from outside), uv rect, normal
		[[Vector3(-X, 0, Z), Vector3(X, 0, Z), Vector3(X, H, Z), Vector3(-X, H, Z)], [0.0, 0.75], Vector3.BACK],
		[[Vector3(X, 0, -Z), Vector3(-X, 0, -Z), Vector3(-X, H, -Z), Vector3(X, H, -Z)], [0.0, 0.75], Vector3.FORWARD],
		[[Vector3(X, 0, Z), Vector3(X, 0, -Z), Vector3(X, H, -Z), Vector3(X, H, Z)], [0.75, 1.0], Vector3.RIGHT],
		[[Vector3(-X, 0, -Z), Vector3(-X, 0, Z), Vector3(-X, H, Z), Vector3(-X, H, -Z)], [0.0, 0.2], Vector3.LEFT],
		[[Vector3(-X, H, Z), Vector3(X, H, Z), Vector3(X, H, -Z), Vector3(-X, H, -Z)], [0.0, 0.75], Vector3.UP],
	]
	for q in quads:
		var p: Array = q[0]
		var u0: float = q[1][0]
		var u1: float = q[1][1]
		var uv := [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(q[2])
			st.set_uv(uv[idx])
			st.add_vertex(p[idx])
	st.generate_tangents()
	_cont_mesh = st.commit()
	_cont_mat = StandardMaterial3D.new()
	_cont_mat.albedo_texture = load("res://assets/arena/container_albedo.png")
	_cont_mat.normal_enabled = true
	_cont_mat.normal_texture = load("res://assets/arena/container_normal.png")
	_cont_mat.vertex_color_use_as_albedo = true
	_cont_mat.roughness = 0.62
	_cont_mat.metallic = 0.35
	_cont_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _cont_mesh


func _put_container(pos: Vector3, ry: float, col := Color(-1, 0, 0)) -> void:
	if col.r < 0:
		col = CONT_COLORS[int(R() * CONT_COLORS.size())]
	col = col * (0.85 + R() * 0.25)
	col.a = 1.0
	_cont_xf.append([Transform3D(Basis(Vector3.UP, ry), pos), col])


## Two rows of container stacks along the wall, one to four high, a little skewed; now and then one turned
## across the stack or perched crooked on top.
func _container_stacks(side: int, u0: float, seg: float, edge: float) -> void:
	var ry := _side_rot(side) + PI / 2
	var n: int = max(1, int(seg / (CONT_L + 0.5)))
	for row in 2:
		for i in n:
			var along := u0 + (i + 0.5) * seg / n + (R() - 0.5) * 0.8
			var dist := edge + 2.0 + row * (CONT_W + 0.4) + R() * 0.3
			var hmax := (2 if row == 0 else 4)
			var levels := 1 + int(R() * hmax)
			var base := _side_point(side, along, dist)
			for lv in levels:
				var jitter := (R() - 0.5) * (0.08 if lv == 0 else 0.16)
				var off := Vector2((R() - 0.5) * 0.5, 0) if lv > 0 else Vector2.ZERO
				_put_container(Vector3(base.x + off.x, lv * CONT_H, base.y + off.y), ry + jitter)
			if R() < 0.18:   # one dropped crooked on top
				_put_container(Vector3(base.x, levels * CONT_H, base.y), ry + PI / 2 + (R() - 0.5) * 0.6)


static func wreck_mesh(id: String) -> Mesh:
	if not _wreck_meshes.has(id):
		_wreck_meshes[id] = load("res://assets/wrecks/wreck_%s.obj" % id)
	if _wreck_mat == null:
		_wreck_mat = ShaderMaterial.new()
		_wreck_mat.shader = load("res://scripts/game/wreck.gdshader")
	return _wreck_meshes[id]


## A heap of burnt cars: a bottom layer at all angles, a second layer tipped over on them, a few on top, some
## upside down. They are the game's own cars, charred and squashed.
var wreck_spots: Array = []   # pile centres (for tests and screenshots)


func _wreck_pile(side: int, u0: float, seg: float, edge: float) -> void:
	var c := _side_point(side, u0 + seg / 2, edge + 6.0)
	wreck_spots.append(Vector3(c.x, 0, c.y))
	var layers := [[5 + int(R() * 3), 0.0, 0.15], [3 + int(R() * 2), 1.5, 0.45], [1 + int(R() * 2), 2.9, 0.7]]
	for L in layers:
		for i in L[0]:
			var along := u0 + R() * seg
			var dist: float = edge + 2.5 + R() * 8.5 * (1.0 - float(L[1]) / 6.0)
			var p := _side_point(side, along, dist)
			var id: String = WRECK_IDS[int(R() * WRECK_IDS.size())]
			var tilt: float = L[2]
			var flip := PI if (L[1] > 0 and R() < 0.3) else 0.0
			var b := Basis.from_euler(Vector3((R() - 0.5) * tilt * 2 + flip, R() * TAU, (R() - 0.5) * tilt * 2))
			var sc := 2.8 + R() * 0.3
			b = b * Basis.from_scale(Vector3(sc, sc * (0.7 + R() * 0.2), sc))
			if not _wreck_xf.has(id):
				_wreck_xf[id] = []
			var paint: Color = [Color("8a2a22"), Color("2c4a6e"), Color("4a5a2e"), Color("6a6a66"), Color("a0742a"), Color("3a3a3a")][int(R() * 6)]
			_wreck_xf[id].append([Transform3D(b, Vector3(p.x, L[1] + 0.9, p.y)), paint])


func _flush_district(shadows := false) -> void:
	if _cont_xf.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = container_mesh()
		mm.instance_count = _cont_xf.size()
		for i in _cont_xf.size():
			mm.set_instance_transform(i, _cont_xf[i][0])
			mm.set_instance_color(i, _cont_xf[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _cont_mat
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_cont_xf.clear()
	for id in _wreck_xf:
		var list: Array = _wreck_xf[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = wreck_mesh(id)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _wreck_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_wreck_xf.clear()


func _building(kind: Dictionary, sc: float, ry: float, pos: Vector3, hgt: float, deep: float, front_row: bool) -> void:
	var node: Node3D = kind.scene.instantiate()
	var box: AABB = kind.box
	var c := (box.get_center() * Vector3(1, 0, 1)) * sc
	node.scale = Vector3.ONE * sc
	node.rotation.y = ry
	node.position = pos - c.rotated(Vector3.UP, ry) + Vector3(0, -box.position.y * sc - 1.2, 0)  # sunk a little
	for mi in node.find_children("*", "GeometryInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	if front_row:
		_occluder(Vector2(pos.x, pos.z), ry, Vector3(box.size.x, box.size.y, box.size.z) * sc * 0.6, hgt * 0.3)
	# smoke off the broken top, fires in the floors facing the arena
	var fx_k: float = Quality.tier.fx
	if R() < 0.55 * fx_k + 0.2:
		stacks.append({"pos": Vector3(pos.x + (R() - 0.5) * deep * 0.3, hgt * 0.95, pos.z + (R() - 0.5) * deep * 0.3), "big": true})
	var toward := atan2(-pos.x, -pos.z)
	for k in (2 if kind.tall else 1):
		if R() < 0.6 * fx_k:
			var fy := hgt * (0.3 + R() * 0.45 if kind.tall else 0.35 + R() * 0.3)
			var sw := (R() - 0.5) * 0.6
			blazes.append(Vector3(pos.x + sin(toward + sw) * deep * 0.45, fy, pos.z + cos(toward + sw) * deep * 0.45))


func _occluder(xz: Vector2, ry: float, size: Vector3, y := 0.0) -> void:
	var oc := OccluderInstance3D.new()
	var box := BoxOccluder3D.new()
	box.size = size
	oc.occluder = box
	oc.position = Vector3(xz.x, y + size.y / 2, xz.y)
	oc.rotation.y = ry
	add_child(oc)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var bb: AABB = (m.transform * m.mesh.get_aabb()) if m.get_parent() == n else _global_aabb(m, n)
		out = bb if first else out.merge(bb)
		first = false
	return out


func _global_aabb(m: MeshInstance3D, root: Node) -> AABB:
	var t := Transform3D()
	var cur: Node = m
	while cur != root and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t * m.mesh.get_aabb()


func _side_point(side: int, along: float, dist: float) -> Vector2:
	match side:
		0: return Vector2(along, -dist)
		1: return Vector2(along, dist)
		2: return Vector2(-dist, along)
	return Vector2(dist, along)


## Rotation that turns a block's front (+Z) to face the arena.
func _side_rot(side: int) -> float:
	return [0.0, PI, PI / 2, -PI / 2][side]


# ---------- the floor plan of each map ----------

func _clear(x: float, z: float, r: float) -> bool:
	if abs(x) > half - r - 3 or abs(z) > half - r - 3:
		return false
	var sr := half * 0.72
	for i in 10:   # the spawn points (build() puts ten round the ring)
		var a := float(i) / 10.0 * TAU + PI / 2
		if Vector2(x - cos(a) * sr, z - sin(a) * sr).length() < r + 7:
			return false
	if Vector2(x, z).length() < r + 5:
		return false
	for o in obstacles:
		var orad: float = o.get("r", Vector2(o.get("hw", 0), o.get("hd", 0)).length())
		if Vector2(o.x - x, o.z - z).length() <= r + orad + 7.5:
			return false
	for q in _reserved:
		if Vector2(q[0] - x, q[1] - z).length() <= r + q[2]:
			return false
	return true


func _place(count: int, r: float, fn: Callable) -> void:
	var k := 0
	var tries := 0
	while k < count and tries < 500:
		tries += 1
		var x := (R() * 2 - 1) * half
		var z := (R() * 2 - 1) * half
		if _clear(x, z, r):
			fn.call(x, z)
			k += 1


func _quarter() -> float:
	return floorf(R() * 4) * PI / 2 + (R() - 0.5) * 0.25


func _cluster(x: float, z: float, main: String, extras: Array) -> void:
	add_prop(main, x, z, _quarter())
	var ms := Kit.prop_size(main, PS)
	for e in extras:
		var a := R() * TAU
		var d: float = max(ms.x, ms.z) / 2 + 1.1 + R() * 0.8
		add_prop(e, x + cos(a) * d, z + sin(a) * d, _quarter(), 1.0, false)


func _layout() -> void:
	match map.id:
		"scrapyard":
			landmark(-half * 0.42, -half * 0.05, PI / 2)
			_place(7, 5, func(x, z): container(x, z, _quarter(), R() < 0.4))
			_place(5, 3, func(x, z): _cluster(x, z, "dumpster", ["boxes", "jugCrate"]))
			_place(4, 3, func(x, z): _cluster(x, z, "tarpDrums", ["crates"]))
			_place(3, 3, func(x, z): _cluster(x, z, "cage", ["boxes"]))
			_place(4, 2.5, func(x, z): _cluster(x, z, "cart", ["jugCrate"]))
			_place(3, 2.5, func(x, z): add_prop("shelf", x, z, _quarter()))
			_place(4, 2, func(x, z): add_prop("drums", x, z, _quarter()))
			_place(6, 1.5, func(x, z):
				barrel(x, z)
				if R() < 0.6: barrel(x + 1.8, z + 0.5))
			_place(3, 1, func(x, z): add_prop("pole", x, z, R() * TAU))
		"refinery":
			landmark(half * 0.45, -half * 0.42, 0)
			_place(4, 7, func(x, z): tank(x, z, 4 + R() * 2.2, 8 + R() * 5))
			_place(4, 5, func(x, z): container(x, z, _quarter(), R() < 0.3))
			_place(4, 3, func(x, z): _cluster(x, z, "waterTank", ["cylinder", "cylinder"]))
			_place(3, 3, func(x, z): _cluster(x, z, "tankStand", ["compressor"]))
			_place(4, 2.5, func(x, z): _cluster(x, z, "gasCart", ["cylinders"]))
			_place(3, 2, func(x, z): add_prop("cylCart", x, z, _quarter()))
			_place(9, 2.5, func(x, z):
				barrel(x, z)
				barrel(x + 1.75, z)
				barrel(x + 0.88, z + 1.5))
			_place(3, 1, func(x, z): add_prop("pole", x, z, R() * TAU))
		"dustbowl":
			var rock: BaseMaterial3D = Kit.solid_material.duplicate()
			rock.albedo_color = Color(1.35, 1.08, 0.78)
			_place(11, 4, func(x, z):
				var r := 2 + R() * 2.4
				var h := 5 + R() * 9
				_mesh(Kit.panel_cylinder(r, h, Kit.ATLAS.concrete, 7, 6, 2, false), rock, Vector3(x, 0, z), R() * TAU)
				obstacles.append({"kind": "circle", "x": x, "z": z, "r": r, "h": h}))
			landmark(half * 0.5, half * 0.48, -PI * 0.75)
			_place(5, 5, func(x, z):
				var along := R() < 0.5
				var k := 3 + int(R() * 3)
				var s := Kit.prop_size("barrier", WS).x
				for i in k:
					var o := (i - k / 2.0) * s
					add_prop("barrier", x + (o if along else 0.0), z + (0.0 if along else o), (0.0 if along else PI / 2) + (R() - 0.5) * 0.15, WS / PS))
			_place(3, 2.5, func(x, z): _cluster(x, z, "tarpDrums", ["drums"]))
			_place(5, 1.5, func(x, z):
				barrel(x, z)
				barrel(x + 1.8, z + 0.4))
			_place(3, 5, func(x, z): container(x, z, _quarter() + 0.3, false))
		"shanty":
			landmark(0, -half * 0.36, 0)
			landmark(-half * 0.38, half * 0.3, PI * 0.66)
			landmark(half * 0.4, half * 0.28, -PI * 0.66)
			_place(6, 5, func(x, z): container(x, z, _quarter(), R() < 0.5))
			_place(5, 3, func(x, z): _cluster(x, z, "dumpster", ["crates", "boxes"]))
			_place(4, 3, func(x, z): _cluster(x, z, "cage", ["jugCrate"]))
			_place(4, 2.5, func(x, z): _cluster(x, z, "tarpDrums", ["boxes"]))
			_place(3, 2, func(x, z): add_prop("shelf", x, z, _quarter()))
			_place(4, 1, func(x, z): add_prop("pole", x, z, R() * TAU))
			_place(6, 1.5, func(x, z):
				barrel(x, z)
				if R() < 0.5: barrel(x + 1.8, z))
		_:  # outpost: a fortified building in the middle, a ring of barriers with gaps
			landmark(0, 0, R() * TAU)
			var ring_r := 20.0
			var s := Kit.prop_size("barrier", WS).x
			var count := int(TAU * ring_r / s)
			for i in count:
				if i % 7 == 0 or i % 7 == 1:
					continue
				var a := float(i) / count * TAU
				add_prop("barrier", cos(a) * ring_r, sin(a) * ring_r, -a + PI / 2, WS / PS)
			for p in [[0.4, 13.0, "tankStand"], [2.2, 13.5, "gasCart"], [3.6, 13.0, "waterTank"], [5.1, 13.5, "cage"]]:
				add_prop(p[2], cos(p[0]) * p[1], sin(p[0]) * p[1], p[0])
			_place(5, 5, func(x, z): container(x, z, _quarter(), R() < 0.35))
			_place(4, 3, func(x, z): _cluster(x, z, "dumpster", ["boxes"]))
			_place(3, 2.5, func(x, z): _cluster(x, z, "cart", ["cylinders"]))
			_place(7, 1.5, func(x, z):
				barrel(x, z)
				if R() < 0.6: barrel(x + 1.8, z + 0.4))
			_place(4, 1, func(x, z): add_prop("pole", x, z, R() * TAU))
