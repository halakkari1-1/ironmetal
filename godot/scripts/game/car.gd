class_name Car
extends Node3D
## One vehicle in a match: its model (scaled to its real length), weapon mount points, effects attached to it,
## and its state. Movement, weapons and AI live in Match; this node only looks after itself.

var data: Dictionary
var stats: Dictionary
var is_player := false   # the car driven on this device (camera, HUD, engine sound)
var human := false       # driven by a person, here or on another device (no AI, no difficulty scaling)
var nid := 0             # network id: the same car has the same nid on every device
var peer := 0            # multiplayer peer driving it (0: a bot)
var pname := ""          # player name; bots use the car's name
var team := 0            # 0: every car for itself
var color := Color.WHITE
var model: Node3D

# state
var x := 0.0
var z := 0.0
var heading := 0.0
var speed := 0.0
var kx := 0.0          # knockback velocity
var kz := 0.0
var y := 0.0           # wreck tumble
var vy := 0.0
var rx := 0.0
var rz := 0.0
var srx := 0.0
var srz := 0.0
var steer_s := 0.0
var hp := 100.0
var max_hp := 100.0
var alive := true
var lives := 3
var respawn_t := 0.0
var invuln := 0.0
var throttle := 0.0
var steer := 0.0
var firing := false
var gun_cd := 0.0
var rocket_cd := 0.0
var rockets := 6
var special_cd := 2.0
var special_t := 0.0
var special_on := ""
var power: Dictionary = {}
var kills := 0
var last_hit := -99.0
var last_attacker: Car = null
var last_cause := ""
var muzzle_i := 0
var death_t := 0.0
var rammed := {}
var dmg_mul := 1.0
var slow_t := 0.0
var jam_t := 0.0
var skid_t := 0.0
var skid_spin := 0.0
var hide_t := 0.0
var spin_t := 0.0
var bounty := false
var dmg_dealt := 0.0     # damage this car has done to others this match (for the MVP card)
var ai: Dictionary = {}

# shape
var dims := Vector3(2.4, 2.0, 5.2)   # width, height, length
var rad := 1.2
var half_len := 1.5
var hit_r := 2.1
var muzzles: Array[Vector3] = []
var rocket_muzzle := Vector3.ZERO
var roof := Vector3.ZERO

# attached effects
var crown: Node3D
var bubble: MeshInstance3D
var smoke_fx: GPUParticles3D
var fire_fx: GPUParticles3D
var dust_fx: GPUParticles3D
var trail_fx: GPUParticles3D
var flash: MeshInstance3D
var _flash_t := 0.0
var _materials: Array = []


func setup(car_data: Dictionary, scene: PackedScene) -> void:
	data = car_data
	_fit_model(scene)
	var spec: Dictionary = data.model
	var pt := func(p: Array) -> Vector3: return Vector3(p[0] * dims.x / 2, p[1] * dims.y, p[2] * dims.z / 2)
	for m in spec.muzzles:
		muzzles.append(pt.call(m))
	rocket_muzzle = pt.call(spec.rocket)
	rad = clamp(min(dims.x, dims.z) / 2 * 0.92, 0.85, 1.7)
	half_len = max(0.4, max(dims.x, dims.z) / 2 - rad)
	hit_r = rad + half_len * 0.6 + 0.35
	roof = Vector3(0, dims.y * 0.97, -dims.z * 0.12)
	_make_flash()
	if data.special.id == "shield":
		bubble = MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = max(dims.z, dims.x) * 0.62
		sp.height = sp.radius * 2
		sp.radial_segments = 24
		sp.rings = 12
		bubble.mesh = sp
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.5, 0.85, 1.0, 0.22)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		bubble.material_override = m
		bubble.position.y = dims.y * 0.45
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bubble.visible = false
		add_child(bubble)


## Instances the model and scales it to the car's real length. Meshy models face -X, so their length is along X.
func _fit_model(scene: PackedScene) -> void:
	model = scene.instantiate()
	add_child(model)
	var box := _aabb(model)
	var s: float = data.model.length / box.size.x
	model.scale = Vector3.ONE * s
	model.rotation.y = PI / 2
	var c := box.get_center()
	model.position = Vector3(-c.z * s, -box.position.y * s, c.x * s)
	dims = Vector3(box.size.z * s, box.size.y * s, box.size.x * s)
	_rig(s)
	if data.has("pbr"):
		var mat := pbr_material(data)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for i in (mi as MeshInstance3D).get_surface_override_material_count():
				(mi as MeshInstance3D).set_surface_override_material(i, mat)
	_materials.clear()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_materials.append(mi)


# ---------- wheels and suspension ----------
# The models are single meshes, so the wheels are cut out of them once per car (every triangle inside a
# wheel's cylinder) and hung on their own pivots: they spin with the speed, the front pair steers, and the
# body rides on a spring of its own: it squats when accelerating, dives when braking, leans in turns, and
# shakes over rough ground and hits.

static var _split := {}        # car id -> {"body": [ArrayMesh per mesh node], "wheels": [{mesh, center, front}]}

var _body: Array = []          # [MeshInstance3D, its resting transform]
var _wheels: Array = []        # [{node, front}]
var _spin := 0.0
var _model_scale := 1.0
var _pivot := Vector3.ZERO     # suspension pivot, model space
var _sp := Vector3.ZERO        # pitch, roll, heave (heave in metres)
var _sv := Vector3.ZERO
var _last_speed := 0.0
var _bump := 0.0


func _rig(s: float) -> void:
	_body.clear()
	_wheels.clear()
	_model_scale = s
	_sp = Vector3.ZERO
	_sv = Vector3.ZERO
	var spec: Array = Data.WHEELS.get(data.id, [])
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if spec.size() and not _split.has(data.id):
		_split[data.id] = _cut(meshes, spec, model)
	var cut: Dictionary = _split.get(data.id, {})
	for i in meshes.size():
		var mi: MeshInstance3D = meshes[i]
		if cut.has("body"):
			mi.mesh = cut.body[i]
		_body.append([mi, mi.transform])
	for w in cut.get("wheels", []):
		var node := MeshInstance3D.new()
		node.mesh = w.mesh
		node.position = w.center
		model.add_child(node)
		_wheels.append({"node": node, "front": w.front})
	var ys: Array = spec.map(func(w): return w[1])
	_pivot = Vector3(0, ys.min() if ys.size() else 0.0, 0)


static func _root_xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D()
	var cur := n
	while cur != root and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Splits each mesh into the body and one mesh per wheel (both sides), wheel vertices centred on their hub.
static func _cut(meshes: Array, spec: Array, model: Node) -> Dictionary:
	var hubs: Array = []
	for w in spec:
		for side in [1.0, -1.0]:
			hubs.append({"x": w[0], "y": w[1], "r": w[2] * 1.04, "zin": w[3] * 0.96, "zout": w[4] * 1.15 + 0.02, "side": side,
				"center": Vector3(w[0], w[1], side * (w[3] + w[4]) / 2.0), "front": w[0] < 0.0, "tris": {}})
	var bodies: Array = []
	for mi_ in meshes:
		var mi: MeshInstance3D = mi_
		var xf := _root_xf(mi, model)
		var body := ArrayMesh.new()
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var mat: Material = mi.get_active_material(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array(range(v.size()))
			var pv := PackedVector3Array()
			pv.resize(v.size())
			for k in v.size():
				pv[k] = xf * v[k]
			var keep := PackedInt32Array()
			var per_hub: Array = []
			for h in hubs:
				per_hub.append(PackedInt32Array())
			for t in range(0, idx.size(), 3):
				var c := (pv[idx[t]] + pv[idx[t + 1]] + pv[idx[t + 2]]) / 3.0
				var hit := -1
				for hi in hubs.size():
					var h: Dictionary = hubs[hi]
					var az: float = c.z * h.side
					if az >= h.zin and az <= h.zout and Vector2(c.x - h.x, c.y - h.y).length() < h.r:
						hit = hi
						break
				if hit < 0:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					per_hub[hit].append_array([idx[t], idx[t + 1], idx[t + 2]])
			var barr := arr.duplicate()
			barr[Mesh.ARRAY_INDEX] = keep
			body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, barr)
			body.surface_set_material(body.get_surface_count() - 1, mat)
			for hi in hubs.size():
				if per_hub[hi].size() == 0:
					continue
				hubs[hi].tris[[mi, si]] = [arr, per_hub[hi], xf, mat]
		bodies.append(body)
	var wheels: Array = []
	for h in hubs:
		if h.tris.is_empty():
			continue
		var wm := ArrayMesh.new()
		for key in h.tris:
			var pack: Array = h.tris[key]
			wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _wheel_arrays(pack[0], pack[1], pack[2], h.center))
			wm.surface_set_material(wm.get_surface_count() - 1, pack[3])
		wheels.append({"mesh": wm, "center": h.center, "front": h.front})
	return {"body": bodies, "wheels": wheels}


## A compact copy of just these triangles, moved into model space around the hub.
static func _wheel_arrays(arr: Array, tri: PackedInt32Array, xf: Transform3D, center: Vector3) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var idx := PackedInt32Array()
	for k in tri:
		if not remap.has(k):
			remap[k] = order.size()
			order.append(k)
		idx.append(remap[k])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nv := PackedVector3Array()
	for k in order:
		nv.append(xf * v[k] - center)
	out[Mesh.ARRAY_VERTEX] = nv
	var nb := xf.basis.orthonormalized()
	if arr[Mesh.ARRAY_NORMAL]:
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var nn := PackedVector3Array()
		for k in order:
			nn.append((nb * n[k]).normalized())
		out[Mesh.ARRAY_NORMAL] = nn
	if arr[Mesh.ARRAY_TANGENT]:
		var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		var nt := PackedFloat32Array()
		for k in order:
			var t3 := (nb * Vector3(tg[k * 4], tg[k * 4 + 1], tg[k * 4 + 2])).normalized()
			nt.append_array([t3.x, t3.y, t3.z, tg[k * 4 + 3]])
		out[Mesh.ARRAY_TANGENT] = nt
	for slot in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
		if arr[slot]:
			var src = arr[slot]
			var dst = src.duplicate()
			dst.resize(order.size())
			for i in order.size():
				dst[i] = src[order[i]]
			out[slot] = dst
	out[Mesh.ARRAY_INDEX] = idx
	return out


## Called every frame by the match (and the showroom): speed in m/s, steering -1..1.
func animate(dt: float, spd: float, steer_amt: float, airborne := false) -> void:
	if dt <= 0.0:
		return
	var accel: float = clamp((spd - _last_speed) / dt, -60.0, 60.0)
	_last_speed = spd
	if alive and not airborne:
		var r_m: float = 0.15 * _model_scale
		if not _wheels.is_empty():
			r_m = float(Data.WHEELS[data.id][0][2]) * _model_scale
		_spin = wrapf(_spin + spd * dt / max(r_m, 0.05), -PI * 64, PI * 64)
		var steer_a: float = steer_amt * 0.42
		for w in _wheels:
			var n: MeshInstance3D = w.node
			n.rotation = Vector3(0, steer_a if w.front else 0.0, _spin)
	# body on its spring: pitch (squat / dive), roll (lean in turns), heave (bumps)
	var fast: float = clamp(abs(spd) / 30.0, 0.0, 1.0)
	var want := Vector3(clamp(-accel * 0.0022, -0.05, 0.05), clamp(-steer_amt * fast * 0.045, -0.05, 0.05), 0.0)
	if not alive:
		want = Vector3.ZERO
	_bump -= dt
	if alive and _bump <= 0 and abs(spd) > 3:   # rough ground: little kicks, more often the faster you go
		_bump = randf_range(0.08, 0.35) / (0.4 + fast)
		_sv.z += randf_range(-0.25, 0.25) * fast
		_sv.y += randf_range(-0.04, 0.04) * fast
	var k := 90.0
	var c := 11.0
	_sv += ((want - _sp) * k - _sv * c) * dt
	_sp += _sv * dt
	_sp.x = clamp(_sp.x, -0.09, 0.09)
	_sp.y = clamp(_sp.y, -0.09, 0.09)
	_sp.z = clamp(_sp.z, -0.12, 0.12)
	# in model space: length along x (front at -x), lateral z; pitch turns about z, roll about x
	var t := Transform3D(Basis(Vector3(0, 0, 1), _sp.x) * Basis(Vector3(1, 0, 0), _sp.y), Vector3.ZERO)
	var pv := Transform3D(Basis(), _pivot)
	var susp := Transform3D(Basis(), Vector3(0, _sp.z / _model_scale, 0)) * pv * t * pv.affine_inverse()
	for b in _body:
		(b[0] as MeshInstance3D).transform = susp * (b[1] as Transform3D)


## A hit or a hard landing jolts the body.
func jolt(strength: float) -> void:
	_sv.z -= strength * 0.8
	_sv.x += randf_range(-1, 1) * strength * 0.15
	_sv.y += randf_range(-1, 1) * strength * 0.15


## Hands the current (wrecked) model over to be left behind and builds a fresh one in its place.
func swap_model(scene: PackedScene) -> Node3D:
	var old := model
	remove_child(old)
	_fit_model(scene)
	return old


func attach_fx(fx: FX) -> void:
	smoke_fx = fx.burn_emitter()
	fire_fx = fx.flame_emitter(0.8, 5)
	dust_fx = fx.dust_emitter()
	for e in [smoke_fx, fire_fx, dust_fx]:
		e.get_parent().remove_child(e)
		add_child(e)
	smoke_fx.position = Vector3(0, dims.y * 0.7, dims.z * 0.2)
	fire_fx.position = Vector3(0, dims.y * 0.55, dims.z * 0.25)
	dust_fx.position = Vector3(0, 0.3, -dims.z * 0.45)


## Muzzle flash: a fireball frame flashed on a camera-facing quad for a few hundredths of a second.
func _make_flash() -> void:
	flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	flash.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/vfx/glow.png")
	m.albedo_color = Color(2.2, 1.6, 0.8)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	flash.material_override = m
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	add_child(flash)


func show_flash(local: Vector3) -> void:
	flash.position = local + Vector3(0, 0, 0.6)
	flash.scale = Vector3.ONE * randf_range(0.8, 1.3)
	flash.visible = true
	_flash_t = 0.05


func _process(dt: float) -> void:
	if _flash_t > 0:
		_flash_t -= dt
		if _flash_t <= 0:
			flash.visible = false


## Updates the damage smoke, fire and the dust trail from the car's state.
func update_fx(map_dusty: bool) -> void:
	var dmg := hp / max_hp if alive else 0.0
	smoke_fx.emitting = dmg < 0.4 or (not alive and death_t < 8)
	fire_fx.emitting = dmg < 0.2 or (not alive and death_t < 5)
	dust_fx.emitting = alive and abs(speed) > (8.0 if map_dusty else 12.0)


static var _pbr := {}


## Cars delivered as a bare mesh plus full-size texture maps (albedo, normal, roughness/metal) get one shared
## material built from them.
static func pbr_material(d: Dictionary) -> StandardMaterial3D:
	if _pbr.has(d.id):
		return _pbr[d.id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(d.pbr.albedo)
	m.normal_enabled = true
	m.normal_texture = load(d.pbr.normal)
	m.normal_scale = 1.0
	var orm: Texture2D = load(d.pbr.orm)
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0
	m.metallic_texture = orm
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.metallic = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_pbr[d.id] = m
	return m


func label() -> String:
	return pname if pname != "" else data.name


func world_point(local: Vector3) -> Vector3:
	return Vector3(x, 0, z) + local.rotated(Vector3.UP, heading)


func forward() -> Vector3:
	return Vector3(sin(heading), 0, cos(heading))


## Blackens a destroyed car.
func wreck() -> void:
	for mi in _materials:
		var m: MeshInstance3D = mi
		for i in m.get_surface_override_material_count():
			var base: Material = m.get_active_material(i)
			if base is BaseMaterial3D:
				var c: BaseMaterial3D = base.duplicate()
				c.albedo_color = c.albedo_color * Color(0.2, 0.18, 0.17)
				c.emission_enabled = false
				m.set_surface_override_material(i, c)


func restore() -> void:
	for mi in _materials:
		var m: MeshInstance3D = mi
		for i in m.get_surface_override_material_count():
			m.set_surface_override_material(i, pbr_material(data) if data.has("pbr") else null)


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var t := Transform3D()
		var cur: Node = m
		while cur != n and cur is Node3D:
			t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var bb := t * m.mesh.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out
