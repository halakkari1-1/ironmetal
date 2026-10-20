class_name Kit
extends RefCounted
## The environment kit (post-apocalypse kitbash by Oleg Ushenok, Fab Standard licence): props, the landmark
## building, and procedural pieces (containers, warehouse blocks, tanks, barrels) whose faces sample regions of
## the kit's texture atlas. Everything shares one material, so the whole arena draws with few state changes.

const DIR := "res://assets/kit/"
## Atlas regions in 1024-px image coordinates (x0, y0, x1, y1).
const ATLAS := {
	"corrugated": [252, 2, 498, 246], "corrugated2": [504, 2, 752, 246], "shutter": [4, 4, 244, 248], "doors": [760, 30, 1020, 250],
	"plate": [2, 262, 250, 508], "concrete": [504, 262, 752, 508], "rust_panel": [204, 512, 312, 618], "grey_plate": [196, 784, 308, 1020],
	"red_panel": [568, 868, 662, 1018],
}

static var material: BaseMaterial3D
static var solid_material: BaseMaterial3D  # same atlas without alpha cut-outs (big flat walls)
static var meta: Dictionary
static var _meshes := {}
static var _cache := {}


static func init() -> void:
	if material:
		return
	var f := FileAccess.open(DIR + "meta.json", FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	material = ORMMaterial3D.new()
	material.albedo_texture = load(DIR + "kit_albedo.png")
	material.normal_enabled = true
	material.normal_texture = load(DIR + "kit_normal_2048.jpg")
	material.orm_texture = load(DIR + "kit_orm_2048.jpg")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	solid_material = material.duplicate()
	solid_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	solid_material.cull_mode = BaseMaterial3D.CULL_BACK


## Mesh of a kit prop or the landmark building ("building_lod0").
static func mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var scene: PackedScene = load(DIR + name + ".glb")
	var root := scene.instantiate()
	var found: Mesh = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	root.free()
	_meshes[name] = found
	return found


static func prop_size(name: String, scale := 1.0) -> Vector3:
	var s: Array = meta.props[name].size
	return Vector3(s[0], s[1], s[2]) * scale


# ---------- atlas-textured procedural pieces ----------

static func _region_uv(r: Array) -> Rect2:
	return Rect2(r[0] / 1024.0, r[1] / 1024.0, (r[2] - r[0]) / 1024.0, (r[3] - r[1]) / 1024.0)


## A quad grid on one face; every panel shows the whole atlas region, so textures tile without stretching.
static func _face(st: SurfaceTool, origin: Vector3, u: Vector3, v: Vector3, n: Vector3, w: float, h: float, pw: float, ph: float, region: Array) -> void:
	var r := _region_uv(region)
	var nu: int = max(1, roundi(w / pw))
	var nv: int = max(1, roundi(h / ph))
	var cw := w / nu
	var ch := h / nv
	for i in nu:
		for j in nv:
			var a0 := i * cw
			var b0 := j * ch
			var p := [origin + u * a0 + v * b0, origin + u * (a0 + cw) + v * b0, origin + u * (a0 + cw) + v * (b0 + ch), origin + u * a0 + v * (b0 + ch)]
			# image v grows downward: the bottom of the panel samples the bottom of the region
			var t := [Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y)]
			_tri(st, [p[0], p[1], p[2]], [n, n, n], [t[0], t[1], t[2]], n)
			_tri(st, [p[0], p[2], p[3]], [n, n, n], [t[0], t[2], t[3]], n)


## Adds one triangle; the winding is chosen from `facing` so the triangle is front-facing on that side.
static func _tri(st: SurfaceTool, p: Array, n: Array, uv: Array, facing: Vector3) -> void:
	var order := [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(facing) > 0.0:
		order = [0, 2, 1]
	for k in order:
		st.set_normal(n[k])
		st.set_uv(uv[k])
		st.add_vertex(p[k])


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_tangents()
	return st.commit()


## Shipping container, origin at ground centre, long axis along X.
static func container(variant := 0) -> ArrayMesh:
	var key := "container%d" % variant
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 7.8
	var H := 3.3
	var W := 3.1
	var X := L / 2
	var Z := W / 2
	var side: Array = ATLAS.corrugated2 if variant else ATLAS.corrugated
	_face(st, Vector3(-X, 0, Z), Vector3.RIGHT, Vector3.UP, Vector3.BACK, L, H, 2.6, H, side)
	_face(st, Vector3(X, 0, -Z), Vector3.LEFT, Vector3.UP, Vector3.FORWARD, L, H, 2.6, H, side)
	_face(st, Vector3(X, 0, Z), Vector3.FORWARD, Vector3.UP, Vector3.RIGHT, W, H, W, H, ATLAS.doors)
	_face(st, Vector3(-X, 0, -Z), Vector3.BACK, Vector3.UP, Vector3.LEFT, W, H, W, H, side)
	_face(st, Vector3(-X, H, Z), Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, L, W, 2.6, W, ATLAS.plate)
	_cache[key] = _finish(st)
	return _cache[key]


## Warehouse block (no floor) with panelled walls and a roof, origin at ground centre, front facing +Z.
static func block(w: float, h: float, d: float, walls: Array, roof: Array, front: Array, panel := 4.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var X := w / 2
	var Z := d / 2
	_face(st, Vector3(-X, 0, Z), Vector3.RIGHT, Vector3.UP, Vector3.BACK, w, h, panel, panel, front)
	_face(st, Vector3(X, 0, -Z), Vector3.LEFT, Vector3.UP, Vector3.FORWARD, w, h, panel, panel, walls)
	_face(st, Vector3(X, 0, Z), Vector3.FORWARD, Vector3.UP, Vector3.RIGHT, d, h, panel, panel, walls)
	_face(st, Vector3(-X, 0, -Z), Vector3.BACK, Vector3.UP, Vector3.LEFT, d, h, panel, panel, walls)
	_face(st, Vector3(-X, h, Z), Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, w, d, panel * 1.5, panel * 1.5, roof)
	return _finish(st)


## Cylinder wall made of separate panels, each showing the full atlas region (tanks, chimneys).
static func panel_cylinder(r: float, h: float, region: Array, panel_w := 6.0, panel_h := 5.0, segs_per := 4, cap := true) -> ArrayMesh:
	var key := "cyl%.2f|%.2f|%s|%s" % [r, h, str(region), cap]
	if _cache.has(key):
		return _cache[key]
	var rr := _region_uv(region)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var panels: int = max(3, roundi(TAU * r / panel_w))
	var rows: int = max(1, roundi(h / panel_h))
	var segs := panels * segs_per
	var rh := h / rows
	for i in segs:
		var a0 := float(i) / segs * TAU
		var a1 := float(i + 1) / segs * TAU
		var k := i % segs_per
		var ua := rr.position.x + float(k) / segs_per * rr.size.x
		var ub := rr.position.x + float(k + 1) / segs_per * rr.size.x
		for j in rows:
			var y0 := j * rh
			var y1 := y0 + rh
			var P := func(a: float, y: float) -> Vector3: return Vector3(sin(a) * r, y, cos(a) * r)
			var N := func(a: float) -> Vector3: return Vector3(sin(a), 0, cos(a))
			var q := [[P.call(a0, y0), N.call(a0), Vector2(ua, rr.end.y)], [P.call(a1, y0), N.call(a1), Vector2(ub, rr.end.y)],
				[P.call(a1, y1), N.call(a1), Vector2(ub, rr.position.y)], [P.call(a0, y1), N.call(a0), Vector2(ua, rr.position.y)]]
			var out: Vector3 = N.call((a0 + a1) / 2)
			for tri in [[0, 1, 2], [0, 2, 3]]:
				_tri(st, [q[tri[0]][0], q[tri[1]][0], q[tri[2]][0]], [q[tri[0]][1], q[tri[1]][1], q[tri[2]][1]], [q[tri[0]][2], q[tri[1]][2], q[tri[2]][2]], out)
	if cap:  # a shallow cone roof
		var gp := _region_uv(ATLAS.grey_plate)
		var top := Vector3(0, h + r * 0.35, 0)
		for i in segs:
			var a0 := float(i) / segs * TAU
			var a1 := float(i + 1) / segs * TAU
			var p0 := Vector3(sin(a0) * r * 1.02, h, cos(a0) * r * 1.02)
			var p1 := Vector3(sin(a1) * r * 1.02, h, cos(a1) * r * 1.02)
			var n := (p1 - p0).cross(top - p0).normalized()
			if n.y < 0:
				n = -n
			_tri(st, [p0, top, p1], [n, n, n], [Vector2(gp.position.x, gp.end.y), gp.get_center(), gp.end], n)
	_cache[key] = _finish(st)
	return _cache[key]


## Explosive fuel barrel: low-poly cylinder whose side samples the red painted panel.
static func barrel() -> ArrayMesh:
	if _cache.has("barrel"):
		return _cache.barrel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var r := 0.75
	var h := 1.8
	var red := _region_uv(ATLAS.red_panel)
	var grey := _region_uv(ATLAS.grey_plate)
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		var u0 := red.position.x + float(i) / seg * red.size.x
		var u1 := red.position.x + float(i + 1) / seg * red.size.x
		var v := [[Vector3(sin(a0) * r, 0, cos(a0) * r), Vector2(u0, red.end.y), a0], [Vector3(sin(a1) * r, 0, cos(a1) * r), Vector2(u1, red.end.y), a1],
			[Vector3(sin(a1) * r, h, cos(a1) * r), Vector2(u1, red.position.y), a1], [Vector3(sin(a0) * r, h, cos(a0) * r), Vector2(u0, red.position.y), a0]]
		var nn := func(a: float) -> Vector3: return Vector3(sin(a), 0, cos(a))
		var out: Vector3 = nn.call((a0 + a1) / 2)
		for tri in [[0, 1, 2], [0, 2, 3]]:
			_tri(st, [v[tri[0]][0], v[tri[1]][0], v[tri[2]][0]], [nn.call(v[tri[0]][2]), nn.call(v[tri[1]][2]), nn.call(v[tri[2]][2])], [v[tri[0]][1], v[tri[1]][1], v[tri[2]][1]], out)
		var cp := [Vector3(0, h, 0), Vector3(sin(a0) * r, h, cos(a0) * r), Vector3(sin(a1) * r, h, cos(a1) * r)]
		var cuv := []
		for p in cp:
			cuv.append(grey.position + grey.size * Vector2(0.5 + p.x / (2 * r), 0.5 + p.z / (2 * r)))
		_tri(st, cp, [Vector3.UP, Vector3.UP, Vector3.UP], cuv, Vector3.UP)
	_cache.barrel = _finish(st)
	return _cache.barrel
