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
	_materials.clear()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_materials.append(mi)


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
			m.set_surface_override_material(i, null)


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
