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
var dust_fx: GPUParticles3D       # dust kicked up behind the left rear wheel...
var dust_fx2: GPUParticles3D      # ...and the right one
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
var _track: Dictionary = {}    # tracked machines: {path, len, shoes (MultiMeshInstance3D), offset}


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
	_track = {}
	if Data.TRACKS.has(data.id):
		_build_tracks(Data.TRACKS[data.id])


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
		if not _track.is_empty() and abs(spd) > 0.05:
			_track.offset = fposmod(float(_track.offset) + spd * dt / max(_model_scale, 0.01), float(_track.shape.len))
			_update_tracks()
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


# ---------- tracks ----------
# The tracked machines' belts are one piece with the rest of the model, so they can't turn. Instead a belt is
# laid over each one (a dark band following the belt's path, a little proud of it) with track shoes that run
# round it at the vehicle's speed: still on the ground, sliding along the top, round the sprockets.

const SHOE_PITCH := 0.042      # model units between shoes

static var _track_cache := {}  # car id -> {path, cum, len, belt mesh}


static func _track_path(spec: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in spec.pulleys:
		for k in 40:
			var a := TAU * k / 40.0
			pts.append(Vector2(p[0] + p[2] * cos(a), p[1] + p[2] * sin(a)))
	var hull := Geometry2D.convex_hull(pts)
	hull.remove_at(hull.size() - 1)   # closed: drop the repeated first point
	# run so the bottom stretch goes towards +x (the back): shoes there then stay put on the ground
	var lo := 0
	for i in hull.size():
		if hull[i].y < hull[lo].y:
			lo = i
	if hull[(lo + 1) % hull.size()].x < hull[lo].x:
		hull.reverse()
	# resample evenly
	var out := PackedVector2Array()
	var n := hull.size()
	var step := 0.006
	for i in n:
		var a := hull[i]
		var b := hull[(i + 1) % n]
		var segs: int = max(1, int(ceil(a.distance_to(b) / step)))
		for k in segs:
			out.append(a.lerp(b, float(k) / segs))
	return out


static func _track_shape(spec: Dictionary) -> Dictionary:
	var path := _track_path(spec)
	var n := path.size()
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	for i in n:
		cum[i + 1] = cum[i] + path[i].distance_to(path[(i + 1) % n])
	var h: float = spec.thick * 0.5
	var hide_y: float = spec.get("hide_above", 9.0)
	var hide_x: float = spec.get("hide_x_max", -9.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var zi: float = spec.zin * side
		var zo: float = spec.zout * side
		for i in n:
			var a := path[i]
			var b := path[(i + 1) % n]
			var m := (a + b) * 0.5
			if m.y > hide_y and m.x < hide_x:
				continue
			var t := (b - a).normalized()
			var nrm := Vector2(t.y, -t.x)   # outward for a counter-clockwise loop seen from +z
			if (m - _centre(spec)).dot(nrm) < 0:
				nrm = -nrm
			var ao := a + nrm * h
			var bo := b + nrm * h
			var ai := a - nrm * h
			var bi := b - nrm * h
			var N := Vector3(nrm.x, nrm.y, 0)
			_quad(st, Vector3(ao.x, ao.y, zi), Vector3(bo.x, bo.y, zi), Vector3(bo.x, bo.y, zo), Vector3(ao.x, ao.y, zo), N)        # tread face
			_quad(st, Vector3(ai.x, ai.y, zo), Vector3(bi.x, bi.y, zo), Vector3(bi.x, bi.y, zi), Vector3(ai.x, ai.y, zi), -N)       # inner face
			_quad(st, Vector3(ao.x, ao.y, zo), Vector3(bo.x, bo.y, zo), Vector3(bi.x, bi.y, zo), Vector3(ai.x, ai.y, zo), Vector3(0, 0, side))   # outer side
			_quad(st, Vector3(ai.x, ai.y, zi), Vector3(bi.x, bi.y, zi), Vector3(bo.x, bo.y, zi), Vector3(ao.x, ao.y, zi), Vector3(0, 0, -side))  # inner side
	var belt := st.commit()
	return {"path": path, "cum": cum, "len": cum[n], "belt": belt}


static func _centre(spec: Dictionary) -> Vector2:
	var c := Vector2.ZERO
	for p in spec.pulleys:
		c += Vector2(p[0], p[1])
	return c / spec.pulleys.size()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# both windings, so the face shows whichever way it is seen (cheap and the belt is thin)
	for tri in [[a, b, c], [a, c, d], [a, c, b], [a, d, c]]:
		for v in tri:
			st.set_normal(n)
			st.add_vertex(v)


static var _belt_mat: StandardMaterial3D
static var _shoe_mat: StandardMaterial3D


func _build_tracks(spec: Dictionary) -> void:
	if not _track_cache.has(data.id):
		_track_cache[data.id] = _track_shape(spec)
	var shape: Dictionary = _track_cache[data.id]
	if _belt_mat == null:
		_belt_mat = StandardMaterial3D.new()
		_belt_mat.albedo_color = Color(0.075, 0.07, 0.065)
		_belt_mat.metallic = 0.5
		_belt_mat.roughness = 0.7
		_shoe_mat = StandardMaterial3D.new()
		_shoe_mat.albedo_color = Color(0.24, 0.225, 0.21)
		_shoe_mat.metallic = 0.85
		_shoe_mat.roughness = 0.38
	var belt := MeshInstance3D.new()
	belt.mesh = shape.belt
	belt.material_override = _belt_mat
	model.add_child(belt)
	var count := int(shape.len / SHOE_PITCH)
	var box := BoxMesh.new()
	box.size = Vector3(SHOE_PITCH * 0.55, spec.thick * 0.55, spec.zout - spec.zin + 0.012)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = count * 2
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shoe_mat
	model.add_child(mmi)
	_track = {"shape": shape, "spec": spec, "mm": mm, "count": count, "pitch": shape.len / count, "offset": 0.0,
		"zmid": (spec.zin + spec.zout) * 0.5, "h": spec.thick * 0.5 + spec.thick * 0.2}
	_update_tracks()


## Places the shoes along the belt for the current offset; the ones under the fenders are hidden (scaled to 0).
func _update_tracks() -> void:
	var tr := _track
	var shape: Dictionary = tr.shape
	var path: PackedVector2Array = shape.path
	var cum: PackedFloat32Array = shape.cum
	var L: float = shape.len
	var n := path.size()
	var spec: Dictionary = tr.spec
	var hide_y: float = spec.get("hide_above", 9.0)
	var hide_x: float = spec.get("hide_x_max", -9.0)
	var c := _centre(spec)
	var mm: MultiMesh = tr.mm
	var j := 0   # walks the path along with the shoes (they come in order of s)
	var s0: float = fposmod(tr.offset, tr.pitch)
	for k in tr.count:
		var s: float = s0 + k * tr.pitch
		while j < n - 1 and cum[j + 1] < s:
			j += 1
		var a := path[j]
		var b := path[(j + 1) % n]
		var f: float = clamp((s - cum[j]) / max(cum[j + 1] - cum[j], 1e-6), 0.0, 1.0)
		var p := a.lerp(b, f)
		var t := (b - a).normalized()
		var nrm := Vector2(t.y, -t.x)
		if (p - c).dot(nrm) < 0:
			nrm = -nrm
		var hidden := p.y > hide_y and p.x < hide_x
		var q: Vector2 = p + nrm * float(tr.h)
		var bx := Vector3(t.x, t.y, 0)
		var by := Vector3(nrm.x, nrm.y, 0)
		var basis := Basis(bx, by, bx.cross(by))
		if hidden:
			basis = basis.scaled(Vector3.ZERO)
		mm.set_instance_transform(k, Transform3D(basis, Vector3(q.x, q.y, tr.zmid)))
		mm.set_instance_transform(k + tr.count, Transform3D(basis, Vector3(q.x, q.y, -float(tr.zmid))))


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
	dust_fx2 = fx.dust_emitter()
	for e in [smoke_fx, fire_fx, dust_fx, dust_fx2]:
		e.get_parent().remove_child(e)
		add_child(e)
	smoke_fx.position = Vector3(0, dims.y * 0.7, dims.z * 0.2)
	fire_fx.position = Vector3(0, dims.y * 0.55, dims.z * 0.25)
	# just behind each rear wheel (or the back of each track), low to the ground
	dust_fx.position = Vector3(dims.x * 0.36, 0.25, -dims.z * 0.42)
	dust_fx2.position = Vector3(-dims.x * 0.36, 0.25, -dims.z * 0.42)


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
	dust_fx2.emitting = dust_fx.emitting


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
