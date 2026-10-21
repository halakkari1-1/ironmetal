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
	_environment()
	_ground()
	_walls()
	_district()
	_layout()
	_flush_props()
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
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = map.sky_top
	sky_mat.sky_horizon_color = map.horizon
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = map.ground.darkened(0.4)
	sky_mat.ground_horizon_color = map.horizon
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = map.horizon
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = Quality.tier.glow
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = map.sun
	sun.light_energy = 1.6
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-38), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = Quality.tier.shadow_dist
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)


# ---------- ground ----------

func _ground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ground/dirt_albedo.jpg")
	mat.albedo_color = map.ground.lerp(Color(0.62, 0.6, 0.58), 0.35)
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/ground/dirt_normal.png")
	mat.normal_scale = 0.8
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(map.size * 4 / 14.0, map.size * 4 / 14.0, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plane := PlaneMesh.new()
	plane.size = Vector2(map.size * 4, map.size * 4)
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	if map.concrete > 0:
		var tex: Texture2D = load("res://assets/kit/ground_concrete.jpg")
		var cm := StandardMaterial3D.new()
		cm.albedo_texture = tex
		cm.albedo_color = Color(0.78, 0.75, 0.71)
		cm.roughness = 0.92
		var size: float = map.size * map.concrete
		cm.uv1_scale = Vector3(size / 15.0, size / 15.0, 1)
		var cp := PlaneMesh.new()
		cp.size = Vector2(size, size)
		var slab := MeshInstance3D.new()
		slab.mesh = cp
		slab.material_override = cm
		slab.position.y = 0.02
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slab)


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
	var tints := [Color(1, 1, 1), Color("c8d8e8"), Color("f0c8b8"), Color("d8e0c0"), Color("e8d8b0")]
	var mesh := Kit.container(1 if R() < 0.5 else 0)
	for level in (2 if stack else 1):
		var mat: BaseMaterial3D = Kit.solid_material.duplicate()
		mat.albedo_color = tints[int(R() * tints.size())]
		_mesh(mesh, mat, Vector3(x, level * 3.3, z), ry + ((R() - 0.5) * 0.25 if level else 0.0))
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
	var walls := [Kit.ATLAS.corrugated, Kit.ATLAS.corrugated2, Kit.ATLAS.concrete, Kit.ATLAS.rust_panel, Kit.ATLAS.grey_plate]
	var fronts := [Kit.ATLAS.shutter, Kit.ATLAS.doors]
	var edge := half + 1.7
	var D1 := 14.0
	# Row 1: a continuous street front pressed against the barriers, so the arena reads as a walled square.
	# Each side merges into one mesh (one draw call) and gets an occluder that hides what stands behind it.
	for side in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var span := half + D1 + 2 if side < 2 else half
		var u := -span
		while u < span:
			var w: float = min(span - u, 9 + R() * 11)
			if w < 3:
				break
			var d := D1 - R() * 3
			var h := 10 + R() * 9
			var mid := u + w / 2
			var dist := edge + d / 2
			var xz := _side_point(side, mid, dist)
			var ry := _side_rot(side)
			var wall: Array = walls[int(R() * walls.size())]
			var front: Array = fronts[int(R() * fronts.size())] if R() < 0.5 else wall
			st.append_from(Kit.block(w, h, d, wall, Kit.ATLAS.grey_plate, front), 0, Transform3D(Basis(Vector3.UP, ry), Vector3(xz.x, 0, xz.y)))
			if R() < 0.5:
				var w2 := w * (0.4 + R() * 0.4)
				var h2 := 3 + R() * 7
				var back := Vector3(sin(ry), 0, cos(ry)) * -d * 0.15
				st.append_from(Kit.block(w2, h2, d * 0.6, walls[int(R() * walls.size())], Kit.ATLAS.plate, walls[0]), 0,
					Transform3D(Basis(Vector3.UP, ry), Vector3(xz.x, h, xz.y) + back))
			u += w
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = Kit.solid_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_occluder(_side_point(side, 0, edge + D1 / 2), _side_rot(side), Vector3(span * 2, 9, D1 * 0.8))
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
	for i in 8:
		var a := float(i) / 8.0 * TAU + PI / 2
		if Vector2(x - cos(a) * sr, z - sin(a) * sr).length() < r + 7:
			return false
	if Vector2(x, z).length() < r + 5:
		return false
	for o in obstacles:
		var orad: float = o.get("r", Vector2(o.get("hw", 0), o.get("hd", 0)).length())
		if Vector2(o.x - x, o.z - z).length() <= r + orad + 7.5:
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
