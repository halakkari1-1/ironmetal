class_name LobbyYard
extends Node3D
## The 3D pieces of the lobby yard, standing in the painting (assets/ui/lobby.jpg) over their painted
## versions: the outpost on the left, the flood lights along the fence, the cliffs, the towers on them, the
## bridge, and the platform the car stands on. Each covers its painted twin; what has no model (the sky, the
## moon, the wet floor, the fence and the far city) stays painted, and a slice of the painting stood up along
## the fence hides the feet of the far pieces the way the painted fence would.
##
## Every piece is placed from the painting itself: the pixel where it stands, how many pixels tall it is there,
## and how far away it is. The camera that painted the picture is known (Showroom solves it from the ring), so
## a pixel and a distance give a point in the world, and a pixel height gives the size. The game's camera
## matches the painting exactly, so each piece lands on its spot whatever the screen.
##
## Light and colour are tuned to the painting: cold moonlight from behind on the right, the flood lights'
## sodium orange, the glow of the fires under the towers, fog that fades the far pieces into the haze, and
## lit windows that flicker. On the low and medium tiers the pieces use 1024 px maps and coarser meshes.

const DIR := "res://assets/lobby/"

## at: painting pixel (full painting size) under the middle of the piece's base; h: the piece's height in
## painting pixels; dist: metres from the camera along the view (0 = where that pixel meets the ground);
## yaw: degrees; tint: colour multiplier; emit: glow of the warm bright spots; light: a warm light (the fires
## and glowing mist of the canyon) [height as a fraction of the piece's height, energy, how far in front of it
## (fraction of its height), reach (fraction of its height)]; smoke: a smoke column from this height.
const PIECES := [
	{"mesh": "cliffs", "maps": "cliffs", "at": Vector2(820, 800), "h": 300.0, "dist": 75.0, "yaw": 8.0, "tint": Color(0.42, 0.36, 0.34), "emit": 0.0, "rough": 0.85, "light": [0.05, 14.0, 0.35, 1.4]},
	{"mesh": "cliffs", "maps": "cliffs", "at": Vector2(1540, 805), "h": 250.0, "dist": 120.0, "yaw": -25.0, "tint": Color(0.42, 0.36, 0.34), "emit": 0.0, "rough": 0.85, "light": [0.05, 20.0, 0.4, 1.4]},
	{"mesh": "cliffs", "maps": "cliffs", "at": Vector2(2560, 805), "h": 380.0, "dist": 62.0, "yaw": 30.0, "tint": Color(0.42, 0.36, 0.34), "emit": 0.0, "rough": 0.85, "light": [0.1, 14.0, 0.45, 1.4]},
	{"mesh": "foundry", "maps": "foundry", "at": Vector2(1495, 575), "h": 520.0, "dist": 160.0, "yaw": 0.0, "tint": Color(0.8, 0.72, 0.7), "emit": 6.0, "emit_lum": 0.3, "light": [0.12, 20.0, 0.3, 1.0], "smoke": 0.9},
	{"mesh": "foundry", "maps": "foundry", "at": Vector2(2440, 470), "h": 380.0, "dist": 110.0, "yaw": 35.0, "tint": Color(0.8, 0.72, 0.7), "emit": 6.0, "emit_lum": 0.3, "light": [0.12, 14.0, 0.3, 1.0]},
	{"mesh": "bridge", "maps": "bridge", "at": Vector2(2075, 705), "h": 210.0, "dist": 85.0, "yaw": 12.0, "tint": Color(0.8, 0.7, 0.66), "emit": 3.0},
	{"mesh": "outpost", "maps": "outpost", "at": Vector2(-20, 905), "h": 1100.0, "dist": 0.0, "yaw": 125.0, "tint": Color(0.85, 0.78, 0.74), "emit": 2.0, "light": [0.45, 1.5]},
	{"mesh": "beacon1", "maps": "beacon", "at": Vector2(422, 835), "h": 235.0, "dist": 0.0, "yaw": -20.0, "tint": Color(0.9, 0.85, 0.8), "emit": 4.0, "emit_lum": 0.4, "lamp": 0.9},
	{"mesh": "beacon1", "maps": "beacon", "at": Vector2(852, 832), "h": 165.0, "dist": 0.0, "yaw": 15.0, "tint": Color(0.9, 0.85, 0.8), "emit": 4.0, "emit_lum": 0.4, "lamp": 0.9},
	{"mesh": "beacon3", "maps": "beacon", "at": Vector2(2492, 858), "h": 150.0, "dist": 0.0, "yaw": -35.0, "tint": Color(0.9, 0.85, 0.8), "emit": 4.0, "emit_lum": 0.4, "lamp": 0.9},
	{"mesh": "beacon4", "maps": "beacon", "at": Vector2(330, 880), "h": 70.0, "dist": 0.0, "yaw": 40.0, "tint": Color(0.9, 0.85, 0.8), "emit": 4.0, "emit_lum": 0.4, "lamp": 0.85},
]

var painting_size := Vector2(2576, 1448)
var ring_px := Vector2(1732, 976)     # where the world's origin (the ring's centre) is in the painting
var focal_px := 2313.0                 # the painting camera's focal length, in painting pixels
var cam_pos := Vector3.ZERO
var cam_basis := Basis()
var platform_top := 0.0
var hi := true
var _lamps: Array[OmniLight3D] = []
var _lamp_base: Array[float] = []
var _ring_mat: StandardMaterial3D
var _matte: ShaderMaterial
var _matte_args := []
var _tier := ""
const LOD_BIAS := {"high": 1.0, "medium": 0.5, "low": 0.25}   # coarser meshes sooner on the lower tiers
const FENCE_PX := 828.0      # painting row where the yard's far fence meets the ground
const FENCE_H := 4.0         # metres of painted fence, barricades and haze that hide what stands behind them
var _t := 0.0
static var _meshes := {}
const LAYER := 2   # render layer of the yard's pieces: the car's warm key light leaves them alone


## The painting camera: where the painting's ring sits, its ellipse and the lens (the same numbers Showroom uses).
func setup(img_size: Vector2, ring: Vector2, ring_a: float, ring_b: float, focal: float, radius: float) -> void:
	painting_size = img_size
	ring_px = ring * img_size
	focal_px = focal * img_size.x
	var tilt := asin(clamp((ring_b * img_size.y) / (ring_a * img_size.x), 0.02, 0.9))
	var dist := radius * focal / ring_a
	cam_pos = Vector3(0, dist * sin(tilt), dist * cos(tilt))
	cam_basis = Basis.from_euler(Vector3(-tilt, 0, 0))
	_build()
	Quality.changed.connect(_tier_changed)


## The tier changed (settings, or auto quality): rebuild with the maps and detail of the new one.
func _tier_changed() -> void:
	if (Quality.tier_id == "high") == hi and Quality.tier_id == _tier:
		return
	for c in get_children():
		remove_child(c)
		c.free()
	release()                 # let the old tier's meshes go
	_lamps.clear()
	_lamp_base.clear()
	_ring_mat = null
	_matte = null
	_build()
	if _matte_args.size():
		set_matte(_matte_args[0], _matte_args[1], _matte_args[2])


## The ray from the painting camera through a painting pixel (world space, not normalised: its depth is 1).
func ray(px: Vector2) -> Vector3:
	var d := Vector3((px.x - ring_px.x) / focal_px, -(px.y - ring_px.y) / focal_px, -1.0)
	return cam_basis * d


## The point a painting pixel shows at this depth (metres along the view), or on the ground when depth is 0.
func point(px: Vector2, depth: float) -> Vector3:
	var r := ray(px)
	if depth <= 0.0:
		return cam_pos + r * (cam_pos.y / max(-r.y, 0.0005))
	return cam_pos + r * depth


## Lets the meshes go (the lobby is closing for a match).
static func release() -> void:
	_meshes.clear()


## The full mesh on the high tier; on medium and low the lighter one made by tools/models/lobby_lods.gd.
static func mesh(id: String, full := true) -> Mesh:
	var lo := "%slo/%s.res" % [DIR, id]
	if not full and ResourceLoader.exists(lo):
		if not _meshes.has(lo):
			_meshes[lo] = load(lo)
		return _meshes[lo]
	if not _meshes.has(id):
		var scene: Node = (load(DIR + id + ".glb") as PackedScene).instantiate()
		var mi: Array = scene.find_children("*", "MeshInstance3D", true, false)
		_meshes[id] = (mi[0] as MeshInstance3D).mesh
		scene.free()
	return _meshes[id]


func material(maps: String, p: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/ui/lobby_prop.gdshader")
	var base := DIR + ("" if hi else "lo/") + maps + "_"
	m.set_shader_parameter("albedo_tex", load(base + "albedo.jpg"))
	m.set_shader_parameter("normal_tex", load(base + "normal.jpg"))
	m.set_shader_parameter("orm_tex", load(base + "orm.jpg"))
	var t: Color = p.get("tint", Color.WHITE)
	m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	m.set_shader_parameter("emit", float(p.get("emit", 0.0)))
	m.set_shader_parameter("emit_lum", float(p.get("emit_lum", 0.5)))
	m.set_shader_parameter("rough_min", float(p.get("rough", 0.35)))
	return m


func _build() -> void:
	_tier = Quality.tier_id
	hi = _tier == "high"
	var fx := FX.new()
	add_child(fx)
	for p in PIECES:
		var mesh_: Mesh = mesh(p.mesh, hi)
		var box := mesh_.get_aabb()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_
		mi.material_override = material(p.maps, p)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = LAYER    # out of reach of the lights that are there for the car
		mi.lod_bias = LOD_BIAS.get(_tier, 1.0)
		# size: the piece's height in pixels at its depth; place: its base centre on the pixel
		var base := point(p.at, p.dist)
		var depth: float = (cam_basis.inverse() * (base - cam_pos)).z * -1.0
		var s: float = float(p.h) / focal_px * depth / box.size.y
		mi.scale = Vector3.ONE * s
		mi.rotation.y = deg_to_rad(p.yaw)
		var foot := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
		mi.position = base - mi.basis * foot   # the basis already carries the scale
		add_child(mi)
		var height: float = box.size.y * s
		if p.has("light"):
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.5, 0.2)
			var lt: Array = p.light
			l.omni_range = height * (lt[3] if lt.size() > 3 else 0.9)
			l.light_energy = lt[1]
			l.light_cull_mask = LAYER
			# in front of the piece (its half width, plus a share of its height), towards the camera
			var front: float = max(box.size.x, box.size.z) * s * 0.5 + height * (lt[2] if lt.size() > 2 else 0.25)
			var toward := Vector3(cam_pos.x - base.x, 0, cam_pos.z - base.z).normalized()
			l.position = base + Vector3(0, height * lt[0], 0) + toward * front
			add_child(l)
			_lamps.append(l)
			_lamp_base.append(l.light_energy)
		if p.has("lamp"):   # a flood light: its lamp head shines on the yard
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.58, 0.25)
			l.omni_range = 14.0
			l.omni_attenuation = 1.4
			l.light_energy = 2.4
			l.position = base + Vector3(0, height * p.lamp, 0) + (cam_pos - base).normalized() * 0.6
			add_child(l)
			_lamps.append(l)
			_lamp_base.append(l.light_energy)
			var glow := MeshInstance3D.new()   # the bright lens of the lamp, seen from the camera
			var q := QuadMesh.new()
			q.size = Vector2.ONE * height * 0.45
			glow.mesh = q
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			gm.albedo_texture = FX.new()._texture("glow")
			gm.albedo_color = Color(1.0, 0.7, 0.4, 1.0)
			gm.disable_fog = true
			glow.material_override = gm
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.position = l.position
			add_child(glow)
		if p.has("smoke"):
			var sm := fx.tower_smoke_emitter(true)
			sm.position = base + Vector3(0, height * p.smoke, 0)
			sm.emitting = true   # the effects node already holds it
	_platform()
	_fence()


## The fence line along the far edge of the yard, as a screen-matched slice of the painting (lobby_matte).
func _fence() -> void:
	var at := point(Vector2(ring_px.x, FENCE_PX), 0.0)
	var wall := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(600.0, FENCE_H)
	wall.mesh = q
	wall.position = Vector3(0, FENCE_H * 0.5, at.z)
	_matte = ShaderMaterial.new()
	_matte.shader = load("res://scripts/ui/lobby_matte.gdshader")
	wall.material_override = _matte
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)


## Showroom tells where the painting sits on screen (it moves with the screen shape and the panels).
func set_matte(tex: Texture2D, rect: Rect2, screen: Vector2) -> void:
	_matte_args = [tex, rect, screen]
	if _matte:
		_matte.set_shader_parameter("painting", tex)
		_matte.set_shader_parameter("rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
		_matte.set_shader_parameter("screen", screen)


## The car's platform: the round deck painted in the yard, as a model, with the glowing ring on it.
func _platform() -> void:
	var m := mesh("platform")
	var box := m.get_aabb()
	var r := 5.57                                   # the painted deck's outer edge, in metres
	var s: float = r * 2.0 / max(box.size.x, box.size.z)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material("platform", {"tint": Color(0.75, 0.7, 0.68), "emit": 0.0})
	mi.scale = Vector3(s, s * 0.45, s)
	mi.layers = LAYER | 1
	mi.position = -Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5) * mi.scale
	add_child(mi)
	platform_top = box.size.y * s * 0.45
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 4.93
	tm.outer_radius = 5.07
	tm.rings = 96
	tm.ring_segments = 6
	ring.mesh = tm
	ring.scale = Vector3(1, 0.35, 1)
	ring.position.y = platform_top + 0.01
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.5, 0.18)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.45, 0.12)
	_ring_mat.emission_energy_multiplier = 3.0
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	for i in _lamps.size():   # sodium lamps and fires breathe, each on its own rhythm
		var k := float(i) * 1.7
		_lamps[i].light_energy = _lamp_base[i] * (0.86 + 0.1 * sin(_t * (0.9 + 0.13 * k) + k) + 0.04 * sin(_t * (6.0 + k)))
	if _ring_mat:
		_ring_mat.albedo_color = Color(1.0, 0.5, 0.18) * (0.85 + 0.15 * sin(_t * 2.2))
